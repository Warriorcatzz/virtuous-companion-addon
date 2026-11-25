-- Run from virtuous-addon with a Lua 5.1 interpreter.
SlashCmdList = {}
local Virtuous = {}
assert(loadfile("UI.lua"))("VirtuousCompanion", Virtuous)

local function getUpvalue(fn, wanted)
  for index = 1, 100 do
    local name, value = debug.getupvalue(fn, index)
    if not name then break end
    if name == wanted then return value end
  end
  error("Missing upvalue: " .. wanted)
end

local function setUpvalue(fn, wanted, value)
  for index = 1, 100 do
    local name = debug.getupvalue(fn, index)
    if not name then break end
    if name == wanted then debug.setupvalue(fn, index, value); return end
  end
  error("Missing upvalue: " .. wanted)
end

local function region(top)
  local self = { shown = true, top = top, anchors = {} }
  function self:Hide() self.shown = false end
  function self:Show() self.shown = true end
  function self:SetShown(value) self.shown = value end
  function self:IsShown() return self.shown end
  function self:SetText(value) self.text = value end
  function self:SetEnabled(value) self.enabled = value end
  function self:SetAttribute(name, value) self[name] = value end
  function self:ClearAllPoints() self.anchors = {} end
  function self:SetPoint(...) table.insert(self.anchors, { ... }) end
  function self:GetTop() return self.top end
  function self:GetHeight() return 36 end
  return self
end

local page = { rows = {} }
for index = 1, 5 do
  local row = region()
  for _, name in ipairs({ "action", "name", "current", "expected" }) do row[name] = region() end
  page.rows[index] = row
end
for _, name in ipairs({ "summary", "empty", "warning", "pageText", "previous", "next", "header" }) do page[name] = region() end
local host = {}
local window = { pages = { officer = page }, tabs = { tickets = region(), raids = region(), officer = region() } }
function window:GetParent() return host end
local refreshOfficer = getUpvalue(Virtuous.Refresh, "refreshOfficer")
local refreshVisibility = getUpvalue(Virtuous.Refresh, "refreshTabVisibility")
local refreshSideTabs = getUpvalue(refreshVisibility, "refreshSideTabVisibility")
setUpvalue(refreshOfficer, "window", window)
VirtuousAddonDB = { officerTools = { authorized = true, entries = {} } }

-- The online/member counts are additional return values, not tonumber's base.
GetNumGuildMembers = function() return 0, 0, 0 end
refreshOfficer()
assert(page.summary.text == "Waiting for the live guild roster...")
local queried = 0
GetNumGuildMembers = function() return 150, 40, 0 end
GetGuildRosterInfo = function() queried = queried + 1 end
refreshOfficer()
assert(queried == 150, "Only the total member count controls roster iteration")
GetNumGuildMembers = function() return 150, 20, 0 end
queried = 0
refreshOfficer()
assert(queried == 150, "Online counts must not reinterpret the total in a different base")

-- Use the real refresh function with Forever's full roleplay names.
local roster = {
  { "Jag Ben-EasternPlaguelands", "Raider", 4 },
  { "Tiersa Clawford", "Newcomer", 8 },
  { "Theadred Lightwarden", "Raider", 4 },
  { "Notlinked Member", "Trial", 5 },
  { "Svennie Purple", "Officer", 2 },
  { "Svennie Orange", "Raider", 4 },
  { "Twin Light", "Social", 6 },
  { "Twin Dark", "Social", 6 },
  { "Warriorcatz Moonstalker", "Guild Master", 0 },
  { "Exact Member", "Raider", 4 },
}
GetNumGuildMembers = function() return #roster, 3, 0 end
GetGuildRosterInfo = function(index) return unpack(roster[index]) end
InCombatLockdown = function() return false end
local entries = {}
for _, entry in ipairs({
  { "Jag", "Raider" }, { "Tiersa", "Raider" }, { "Theadred", "Officer" },
  { "Missing", "Social" }, { "Svennie", "Alt" }, { "Svennie", "Officer" },
  { "Twin", "Raider" }, { "Warriorcatz", "Raider" }, { "Exact Member", "Trial" },
}) do table.insert(entries, { name = entry[1], expectedRank = entry[2] }) end
VirtuousAddonDB.officerTools.entries = entries
refreshOfficer()
assert(page.summary.text == "3 members need a rank change")
assert(page.rows[1].name.text == "Exact Member")
assert(page.rows[1].action.text == "Demote")
assert(page.rows[2].name.text == "Theadred Lightwarden")
assert(page.rows[2].current.text == "Raider" and page.rows[2].expected.text == "Officer")
assert(page.rows[3].name.text == "Tiersa Clawford")
assert(page.rows[3].action.memberName == "Tiersa Clawford")
assert(page.rows[3].action.fromRankIndex == 8 and page.rows[3].action.targetRankIndex == 4)
assert(page.rows[3].action.expectedRank == "Raider")
assert(not page.rows[4]:IsShown(), "Correct, missing, conflicting, ambiguous and leadership ranks are omitted")
assert(not page.next:IsShown(), "Only multiple pages receive paging controls")
Virtuous.GuildRankChangePending = function(_, name) return not name or name == "Tiersa Clawford" end
refreshOfficer()
assert(page.rows[3].action.text == "Waiting..." and not page.rows[3].action.enabled)
assert(page.rows[3].action.memberName == nil, "Pending rows cannot keep a clickable stale action")
Virtuous.GuildRankChangePending = nil
refreshOfficer()

roster[2][2], roster[2][3] = "Raider", 4
refreshOfficer()
assert(page.summary.text == "2 members need a rank change")
assert(not page.rows[3]:IsShown() and page.rows[3].action.memberName == nil, "A corrected member disappears and cannot retain an old action")
roster[3][2], roster[3][3] = "Officer", 2
roster[10][2], roster[10][3] = "Trial", 5
refreshOfficer()
assert(page.empty:IsShown() and not page.header:IsShown())
assert(not page.rows[1]:IsShown(), "Unresolved database entries cannot fill an otherwise empty mismatch list")

-- Exact full names remain usable even when their first-name alias collides.
table.insert(entries, { name = "Twin Light", expectedRank = "Raider" })
refreshOfficer()
assert(page.rows[1].name.text == "Twin Light")
assert(not page.rows[2]:IsShown())
table.insert(entries, { name = "Twin Light", expectedRank = "Officer" })
refreshOfficer()
assert(page.empty:IsShown(), "A conflicting exact match never falls back to an alias")

-- Pagination is based only on confirmed mismatches and clamps after changes.
roster, entries = {}, {}
for index = 1, 7 do
  table.insert(roster, { "Member" .. index, "Trial", 5 })
  table.insert(entries, { name = "Member" .. index, expectedRank = "Raider" })
end
VirtuousAddonDB.officerTools.entries = entries
refreshOfficer()
assert(page.next:IsShown() and page.pageText.text == "1 / 2")
page.issuePage = 1
refreshOfficer()
assert(page.rows[1].name.text == "Member6" and not page.rows[3]:IsShown())
for _, member in ipairs(roster) do member[2], member[3] = "Raider", 4 end
refreshOfficer()
assert(page.issuePage == 0 and not page.next:IsShown() and page.empty:IsShown())

local guild = {}
for index, name in ipairs({ "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab", "GuildPreferredPlaySettingsTab" }) do
  guild[name] = region(400 - (index - 1) * 44)
end
window.nativeTabAnchor = guild.GuildPreferredPlaySettingsTab
setUpvalue(refreshSideTabs, "guildFrameRoot", guild)
refreshSideTabs()
assert(window.tabs.officer:IsShown(), "An authorized officer receives the Guild Ranks tab")
assert(window.tabs.officer.anchors[1][5] == -44, "Tabs use the guild frame's native spacing")
assert(window.tabs.officer.anchors[1][2] == window.tabs.raids)
VirtuousAddonDB.officerTools.authorized = false
refreshSideTabs()
assert(not window.tabs.officer:IsShown(), "Unprivileged members do not receive the officer tab")
-- Content refreshes cannot leave authorized tabs at their initial hidden state.
VirtuousAddonDB.officerTools.authorized = true
window.status = region()
function Virtuous:SyncSummary() return "Test sync" end
function Virtuous:PendingCount() return 0 end
setUpvalue(Virtuous.Refresh, "refreshTicketOverview", function() error("Content unavailable") end)
local ok = pcall(function() Virtuous:Refresh() end)
assert(not ok)
assert(window.tabs.officer:IsShown(), "Tab visibility updates before page content")
print("Guild Ranks: roster counts, confirmed mismatches, unique aliases, pagination and tab visibility passed")
