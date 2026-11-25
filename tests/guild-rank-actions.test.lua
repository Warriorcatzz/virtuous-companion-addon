-- Run from virtuous-addon with Lua 5.1. Rank changes are mocked; click dispatch
-- uses the unmodified Forever client sources cached in ../.tools.
local methods = {}
function methods:GetAttribute(prefix, name, suffix)
  if not name then return self.attributes[prefix] end
  for _, key in ipairs({ prefix .. name .. suffix, "*" .. name .. suffix, prefix .. name .. "*", "*" .. name .. "*", name .. suffix, prefix .. name, name }) do
    if self.attributes[key] ~= nil then return self.attributes[key] end
  end
end
function methods:SetAttribute(name, value) self.attributes[name] = value end
function methods:SetScript(name, callback)
  assert(name ~= "OnClick", "Addon code must preserve Blizzard's inherited click handler")
  self.scripts[name] = callback
end
function methods:HookScript(name, callback)
  local previous = self.scripts[name]
  self.scripts[name] = function(...) if previous then previous(...) end; callback(...) end
end
function methods:RegisterForClicks(...) self.clicks = { ... } end
function methods:Hide() if self.scripts.OnHide then self.scripts.OnHide(self) end end
function methods:IsProtected() return false end
CopyTable = function(value) local copy = {}; for key, child in pairs(value) do copy[key] = child end; return copy end
GetFrameMetatable = function() return { __index = methods } end
IsShiftKeyDown = function() return false end
IsControlKeyDown = function() return false end
IsAltKeyDown = function() return false end
SpellCanTargetItem = function() return false end
SpellCanTargetItemID = function() return false end
forceinsecure = function() error("Rank actions cannot use custom insecure handlers") end
local fixtureRoot = os.getenv("VIRTUOUS_WOW_UI_FIXTURES") or "../.tools"
assert(loadfile(fixtureRoot .. "/wow-forever-SecureTemplates.lua"))()
local xml = assert(io.open(fixtureRoot .. "/wow-forever-SecureTemplates.xml")):read("*a")
local template = assert(xml:match('<Button name="InsecureActionButtonTemplate"(.-)</Button>'))
assert(not template:find("SecureFrameTemplate", 1, true))
local clickSource = assert(template:match("<OnClick>(.-)</OnClick>"))
local nativeClick = assert(loadstring("return function(self, button, down) " .. clickSource .. " end"))()

local function scenario(useKeyDown)
  local state = { commands = {}, notices = {}, timers = {}, refreshes = 0, inTemplate = false }
  local Virtuous = {}
  function Virtuous:Notify(message) table.insert(state.notices, message) end
  function Virtuous:Refresh() state.refreshes = state.refreshes + 1 end
  assert(loadfile("GuildRanks.lua"))("VirtuousCompanion", Virtuous)
  VirtuousAddonDB = { officerTools = { authorized = true } }
  local member = { "Horace Alder-EasternPlaguelands", "Raider", 4 }
  member[17] = "Player-123-HORACE"
  state.member = member
  GetNumGuildMembers = function() return 1, 0, 0 end
  GetGuildRosterInfo = function() return unpack(member, 1, 17) end
  GuildControlGetRankName = function(index)
    return ({ "Guild Master", "Guild Officer", "Officer", "Loot Council", "Raider", "Trial", "Social", "Alt", "Newcomer" })[index]
  end
  InCombatLockdown = function() return false end
  CanGuildPromote = function() return true end
  CanGuildDemote = function() return true end
  GetCVarBool = function(name) return name == "ActionButtonUseKeyDown" and useKeyDown or false end
  C_Timer = { After = function(delay, callback) table.insert(state.timers, { delay, callback }) end }
  local function forbidden() error("Addon Lua must never call a protected rank API directly") end
  GuildPromote, GuildDemote, RunMacroText = forbidden, forbidden, forbidden
  C_GuildInfo = {
    GuildRoster = function() end,
    IsGuildRankAssignmentAllowed = function(guid, rankOrder)
      assert(guid == member[17] and rankOrder >= 3)
      return true
    end,
    SetGuildRankOrder = forbidden, Demote = forbidden, Promote = forbidden,
  }
  C_Macro = { RunMacroText = function(text, mouseButton)
    assert(state.inTemplate, "Only the native template may execute the macro")
    assert(mouseButton == "LeftButton")
    table.insert(state.commands, text)
    if state.onCommand then state.onCommand() end
  end }
  CreateFrame = function(kind, name, parent, inherits)
    assert(kind == "Button" and inherits == "UIPanelButtonTemplate,InsecureActionButtonTemplate")
    return setmetatable({ attributes = {}, scripts = { OnClick = nativeClick } }, { __index = methods })
  end
  local button = Virtuous:CreateGuildRankActionButton({})
  button.memberName, button.fromRankIndex, button.targetRankIndex, button.expectedRank, button.promoting = member[1], 4, 5, "Trial", false
  function state:click(mouseButton, down)
    mouseButton = mouseButton or "LeftButton"
    if mouseButton ~= "LeftButton" or down then return end -- LeftButtonUp registration
    button.scripts.PreClick(button, mouseButton, down)
    state.inTemplate = true
    button.scripts.OnClick(button, mouseButton, down)
    state.inTemplate = false
    button.scripts.PostClick(button, mouseButton, down)
  end
  state.button = button
  return Virtuous, state
end

-- Either global click-edge setting still dispatches one command on mouse-up.
for _, useKeyDown in ipairs({ true, false }) do
  local Virtuous, state = scenario(useKeyDown)
  assert(not state.button:IsProtected(), "Rank actions must not protect the surrounding Companion panel")
  assert(state.button.scripts.OnClick == nativeClick)
  assert(state.button.clicks[1] == "LeftButtonUp")
  state:click("LeftButton", true)
  assert(#state.commands == 0)
  state:click("LeftButton", false)
  assert(#state.commands == 1 and state.commands[1] == "/gdemote Horace Alder-EasternPlaguelands")
  assert(state.button:GetAttribute("type") == nil and state.button:GetAttribute("macrotext") == nil)
  assert(Virtuous:GuildRankChangePending(state.member[1]))
  assert(state.notices[1]:find("Demotion requested", 1, true))
  state:click()
  assert(#state.commands == 1, "Waiting for confirmation cannot send a duplicate demotion")
  state.member[2], state.member[3] = "Trial", 5
  Virtuous:CheckPendingGuildRankChange()
  assert(not Virtuous:GuildRankChangePending())
  assert(state.notices[#state.notices]:find("is now Trial", 1, true))
  for _, timer in ipairs(state.timers) do timer[2]() end
  assert(#state.commands == 1, "Timers only refresh; they cannot change another rank")
end

local Virtuous, state = scenario(true)
state.button.targetRankIndex, state.button.expectedRank, state.button.promoting = 2, "Officer", true
state:click()
assert(state.commands[1] == "/gpromote Horace Alder-EasternPlaguelands", "Promotions also use one native command")

-- Every rejected preflight clears a previously armed command.
local function rejects(mutate)
  local Virtuous, state = scenario(true)
  state.button:SetAttribute("type", "macro")
  state.button:SetAttribute("macrotext", "/gdemote Wrong Member")
  mutate(Virtuous, state)
  state:click()
  assert(#state.commands == 0)
  assert(state.button:GetAttribute("type") == nil and state.button:GetAttribute("macrotext") == nil)
  assert(not Virtuous:GuildRankChangePending())
end
rejects(function(_, state) state.member[3] = 5 end)
rejects(function() VirtuousAddonDB.officerTools.authorized = false end)
rejects(function() InCombatLockdown = function() return true end end)
rejects(function() CanGuildDemote = function() return false end end)
rejects(function() C_GuildInfo.IsGuildRankAssignmentAllowed = function() return false end end)
rejects(function(_, state) state.button.targetRankIndex = 1 end)
rejects(function(_, state) state.member[1] = "Horace\n/gdemote Other"; state.button.memberName = state.member[1] end)

Virtuous, state = scenario(true)
assert(Virtuous:PrepareGuildRankClick(state.button, "LeftButton", false))
state.button:Hide()
assert(not Virtuous:GuildRankChangePending() and state.button:GetAttribute("macrotext") == nil)
Virtuous, state = scenario(true)
state.onCommand = function() Virtuous:GuildRankActionBlocked("VirtuousCompanion", "UNKNOWN()") end
state:click()
assert(not Virtuous:GuildRankChangePending())
assert(state.notices[1]:find("WoW blocked", 1, true))
Virtuous, state = scenario(true)
state:click()
state.timers[2][2]()
assert(not Virtuous:GuildRankChangePending())
assert(state.notices[#state.notices]:find("No rank change was confirmed", 1, true))
assert(#state.commands == 1)
print("Guild rank actions: actual Forever click dispatch, both click-edge settings, macro isolation, validation and confirmation passed")

