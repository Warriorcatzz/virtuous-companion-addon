local addonName, Virtuous = ...
local pending

local function nameKey(value)
  return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")):lower()
end

local function findMember(name, guid)
  local count = GetNumGuildMembers and tonumber((GetNumGuildMembers())) or 0
  for index = 1, count do
    local info = { GetGuildRosterInfo(index) }
    if (guid and info[17] == guid) or (not guid and nameKey(info[1]) == nameKey(name)) then
      return { name = info[1], rankName = info[2], rankIndex = info[3], guid = info[17] }
    end
  end
end

local function requestRoster()
  if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster()
  elseif GuildRoster then GuildRoster() end
end

function Virtuous:GuildRankChangePending(name)
  return pending ~= nil and (not name or nameKey(pending.name) == nameKey(name))
end

function Virtuous:CheckPendingGuildRankChange(timedOut)
  if not pending then return end
  local member = findMember(pending.name, pending.guid)
  if member and type(member.rankIndex) == "number" and member.rankIndex ~= pending.fromRankIndex then
    pending = nil
    self:Notify(string.format("Guild rank updated: %s is now %s.", member.name, member.rankName))
  elseif timedOut then
    local name = pending.name
    pending = nil
    self:Notify("No rank change was confirmed for " .. name .. ". Check WoW's error message and try again.")
  end
end

function Virtuous:GuildRankActionBlocked(source, action)
  if pending and source == addonName then
    pending = nil
    self:Notify("WoW blocked the protected guild rank command.")
    if self.Refresh then self:Refresh() end
  end
end

local function clearClick(action, cancelPending)
  if cancelPending and action.virtuousRankRequest == pending then pending = nil end
  action:SetAttribute("type", nil)
  action:SetAttribute("macrotext", nil)
  action.virtuousRankRequest = nil
end

function Virtuous:CreateGuildRankActionButton(parent)
  -- Keep Blizzard's inherited OnClick: calling it from addon Lua would taint
  -- the protected action again. This template is usable only out of combat.
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate,InsecureActionButtonTemplate")
  button:RegisterForClicks("LeftButtonUp")
  button:SetAttribute("useOnKeyDown", false)
  button:SetScript("PreClick", function(self, mouseButton, down) Virtuous:PrepareGuildRankClick(self, mouseButton, down) end)
  button:SetScript("PostClick", function(self) Virtuous:FinishGuildRankClick(self) end)
  button:HookScript("OnHide", function(self) clearClick(self, true) end)
  return button
end

function Virtuous:PrepareGuildRankClick(action, mouseButton, down)
  -- PreClick's return value cannot cancel an action. Disarm before validating.
  clearClick(action, true)
  if mouseButton ~= "LeftButton" or down then return false end
  local function reject(message)
    self:Notify(message)
    return false
  end
  if not (VirtuousAddonDB.officerTools and VirtuousAddonDB.officerTools.authorized == true) then
    return reject("Guild rank access is not available.")
  end
  if InCombatLockdown() then return reject("Guild ranks cannot be changed during combat.") end
  self:CheckPendingGuildRankChange()
  if pending then return reject("Waiting for the previous guild rank change.") end
  if not action.memberName or type(action.fromRankIndex) ~= "number" or type(action.targetRankIndex) ~= "number"
    or action.fromRankIndex < 2 or action.targetRankIndex < 2 or action.targetRankIndex > 7
    or action.fromRankIndex == action.targetRankIndex then
    return reject("That rank action is no longer available. Refresh the guild roster.")
  end
  local member = findMember(action.memberName)
  if not member or member.rankIndex ~= action.fromRankIndex then
    requestRoster()
    if self.Refresh then self:Refresh() end
    return reject("The guild roster changed. Review the refreshed rank before clicking again.")
  end
  local promoting = member.rankIndex > action.targetRankIndex
  if promoting ~= action.promoting then return reject("That rank action is no longer available.") end
  local permission
  if promoting then permission = CanGuildPromote else permission = CanGuildDemote end
  if permission and not permission() then return reject("Your guild rank does not allow that change.") end
  if GuildControlGetRankName and GuildControlGetRankName(action.targetRankIndex + 1) ~= action.expectedRank then
    return reject("Guild rank order differs. Refresh the guild rank settings first.")
  end
  local nextRankIndex = member.rankIndex + (promoting and -1 or 1)
  if member.guid and C_GuildInfo and C_GuildInfo.IsGuildRankAssignmentAllowed
    and not C_GuildInfo.IsGuildRankAssignmentAllowed(member.guid, nextRankIndex + 1) then
    return reject("WoW does not allow assigning that guild rank to " .. member.name .. ".")
  end
  if member.name:find("[%c|]") then return reject("That character name cannot be used in a guild rank command.") end
  local request = { name = member.name, guid = member.guid, fromRankIndex = member.rankIndex, promoting = promoting }
  pending = request
  action.virtuousRankRequest = request
  action:SetAttribute("macrotext", (promoting and "/gpromote " or "/gdemote ") .. member.name)
  action:SetAttribute("type", "macro")
  return true
end

function Virtuous:FinishGuildRankClick(action)
  local request = action.virtuousRankRequest
  clearClick(action)
  if not request then return false end
  if pending ~= request then return false end
  self:Notify((request.promoting and "Promotion" or "Demotion") .. " requested for " .. request.name .. ".")
  if self.Refresh then self:Refresh() end
  requestRoster()
  if C_Timer and C_Timer.After then
    for _, delay in ipairs({ 0.8, 5 }) do
      local timedOut = delay == 5
      C_Timer.After(delay, function()
        if pending ~= request then return end
        requestRoster()
        self:CheckPendingGuildRankChange(timedOut)
        if self.Refresh then self:Refresh() end
      end)
    end
  end
  return true
end
