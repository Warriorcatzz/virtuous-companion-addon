-- Run from virtuous-addon with a Lua 5.1 interpreter.
strtrim = function(value) return (value:gsub("^%s+", ""):gsub("%s+$", "")) end
GetNormalizedRealmName = function() return "CAMWOWEU4Realm7PvE" end
GetRealmName = function() return "Eastern Plaguelands" end
Enum = { ClubType = { Guild = 1, Character = 2 } }

local function region(parent)
  local self = { parent = parent, anchors = {}, shown = true, scripts = {}, color = { 1, 1, 1, 1 } }
  function self:ClearAllPoints() self.anchors = {} end
  function self:SetPoint(point, relative, relativePoint, x, y)
    if type(relative) == "number" then x, y, relative, relativePoint = relative, relativePoint, self.parent, point end
    for index, anchor in ipairs(self.anchors) do if anchor[1] == point then table.remove(self.anchors, index); break end end
    table.insert(self.anchors, { point, relative, relativePoint, x or 0, y or 0 })
  end
  function self:GetPoint(index) return unpack(self.anchors[index]) end
  function self:GetNumPoints() return #self.anchors end
  function self:SetText(value) self.text = value end
  function self:SetWidth(value) self.width = value end
  function self:SetSize(width, height) self.width, self.height = width, height end
  function self:SetJustifyH() end
  function self:SetWordWrap() end
  function self:EnableMouse() end
  function self:SetScript(event, callback) self.scripts[event] = callback end
  function self:HookScript(event, callback)
    local previous = self.scripts[event]
    self.scripts[event] = function(...) if previous then previous(...) end; callback(...) end
  end
  function self:Show() self.shown = true end
  function self:Hide() self.shown = false end
  function self:IsShown() return self.shown end
  function self:GetTextColor() return unpack(self.color) end
  function self:SetTextColor(...) self.color = { ... } end
  function self:CreateFontString() return region(self) end
  return self
end
CreateFrame = function(_, _, parent) return region(parent) end
hooksecurefunc = function(object, method, callback)
  local original = object[method]
  object[method] = function(...)
    local result = { original(...) }
    callback(...)
    return unpack(result)
  end
end

local Virtuous = {}
VirtuousAddonDB = { discordRoster = {
  { wowName = "Main", discordName = "Discord Name" },
  { wowName = "Main Lastname", discordName = "Discord Name" },
  { wowName = "Alt", discordName = "Name |cffff0000Text" },
  { wowName = "Duplicate", discordName = "One" },
  { wowName = "duplicate", discordName = "Two" },
} }
assert(loadfile("DiscordRoster.lua"))("VirtuousCompanion", Virtuous)
Virtuous:RebuildDiscordRoster()
assert(Virtuous:DiscordNameForCharacter("MAIN-EasternPlaguelands") == "Discord Name")
assert(Virtuous:DiscordNameForCharacter("MAIN-CAMWOWEU4Realm7PvE") == "Discord Name")
assert(Virtuous:DiscordNameForCharacter("Main  Lastname-EasternPlaguelands") == "Discord Name")
assert(Virtuous:DiscordNameForCharacter("Main-OtherRealm") == "")
assert(Virtuous:DiscordNameForCharacter("Unknown") == "")
assert(Virtuous:DiscordNameForCharacter("Duplicate") == "")

local list = region()
list.expandedDisplay = true
list.club = { clubType = Enum.ClubType.Guild }
list.columnInfo = { { attribute = "name" }, { attribute = "memberNote" } }
function list:GetSelectedClubInfo() return self.club end
function list:GetGuildColumnIndex() return self.extraColumn end
list.ColumnDisplay = region(list)
local noteHeader = region(list.ColumnDisplay)
function noteHeader:GetID() return 2 end
list.ColumnDisplay.columnHeaders = {}
function list.ColumnDisplay.columnHeaders:EnumerateActive()
  local returned = false
  return function() if not returned then returned = true; return noteHeader end end
end
function list.ColumnDisplay:LayoutColumns()
  noteHeader:ClearAllPoints()
  noteHeader:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 300, 1)
  noteHeader:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -28, 1)
end
list.ScrollBox = region(list)
list.ScrollBox.rows = {}
function list.ScrollBox:ForEachFrame(callback) for _, row in ipairs(self.rows) do callback(row) end end
function list:RefreshLayout() self.ColumnDisplay:LayoutColumns() end
function list:RefreshListDisplay() end
local function makeRow(name)
  local row = region(list.ScrollBox)
  row.expanded = true
  row.member = { name = name }
  row.Rank = region(row)
  row.Note = region(row)
  row.Note:SetPoint("LEFT", row.Rank, "RIGHT", 8, 0)
  row.Note:SetPoint("RIGHT", row, "RIGHT", -4, 0)
  function row:GetMemberInfo() return self.member end
  function row:RefreshExpandedColumns() end
  function row:UpdatePresence() end
  table.insert(list.ScrollBox.rows, row)
  return row
end
local row = makeRow("Main")
list:RefreshLayout()
Virtuous:InstallDiscordRoster({ MemberList = list })
assert(list.ColumnDisplay.VirtuousDiscordHeader.text == "Discord")
assert(row.VirtuousDiscordName.text == "Discord Name")
GameTooltip = {
  IsOwned = function() return false end,
  SetOwner = function() end,
  SetText = function(_, ...)
    assert(select("#", ...) == 1, "Tooltip text cannot receive gsub's second return value as a color")
  end,
  AddLine = function() end,
  Show = function() end,
}
row.scripts.OnEnter()
local _, _, _, originalRight = noteHeader:GetPoint(2)
list:RefreshLayout()
local _, _, _, repeatedRight = noteHeader:GetPoint(2)
assert(originalRight == repeatedRight, "Repeated native layouts must not keep shrinking Note")

row.member = { name = "Unknown" }
row:RefreshExpandedColumns()
assert(row.VirtuousDiscordName.text == "", "Reused rows must clear the previous member")
row.member = { name = "Main Lastname-EasternPlaguelands" }
row:RefreshExpandedColumns()
assert(row.VirtuousDiscordName.text == "Discord Name", "Full roleplay names and displayed realms resolve")
row.member = nil
row:RefreshExpandedColumns()
assert(not row.VirtuousDiscordName:IsShown(), "Invitation/section headers have no Discord name")
row.member = { name = "Alt" }
row:RefreshExpandedColumns()
assert(row.VirtuousDiscordName.text == "Name ||cffff0000Text", "Names cannot inject WoW markup")
row.Note.color = { 0.5, 0.5, 0.5, 1 }
row:UpdatePresence()
assert(row.VirtuousDiscordName.color[1] == 0.5, "Offline styling follows the native row")

list.expandedDisplay = false
list:RefreshLayout()
assert(not row.VirtuousDiscordName:IsShown())
assert(not list.ColumnDisplay.VirtuousDiscordHeader:IsShown())
local _, rightRelative = row.Note:GetPoint(2)
assert(rightRelative == row, "Chat restores the native Note anchors")
list.expandedDisplay = true
list.club.clubType = Enum.ClubType.Character
list:RefreshLayout()
assert(not row.VirtuousDiscordName:IsShown(), "Other communities are not labelled")
list.club.clubType = Enum.ClubType.Guild
list.extraColumn = 1
list:RefreshLayout()
assert(not row.VirtuousDiscordName:IsShown(), "Native extra-column views keep their layout")
list.extraColumn = nil
list:RefreshLayout()
local lateRow = makeRow("Main")
list.ScrollBox.scripts.OnUpdate(list.ScrollBox, 0.2)
assert(lateRow.VirtuousDiscordName.text == "Discord Name", "Scrolling discovers newly allocated rows")

VirtuousAddonDB.discordRoster = {}
Virtuous:RebuildDiscordRoster()
list:RefreshListDisplay()
assert(lateRow.VirtuousDiscordName.text == "", "An empty sync clears stale links")
local originalHeader = list.ColumnDisplay.VirtuousDiscordHeader
Virtuous:InstallDiscordRoster({ MemberList = list })
assert(list.ColumnDisplay.VirtuousDiscordHeader == originalHeader, "Installation is idempotent")

-- New and old payloads replace the persisted directory; absent data clears it.
function Virtuous:Notify() end
assert(loadfile("Bridge.lua"))("VirtuousCompanion", Virtuous)
VirtuousAddonDB.outbox = {}
VirtuousAddonDB.tickets = {}
VirtuousAddonDB.raids = {}
VirtuousDesktopInbox = { protocol = 1, generatedAt = "new", discordRoster = { { wowName = "Main", discordName = "Renamed" } } }
Virtuous:ConsumeDesktopInbox()
assert(Virtuous:DiscordNameForCharacter("Main") == "Renamed")
VirtuousDesktopInbox = { protocol = 1, generatedAt = "old-server" }
Virtuous:ConsumeDesktopInbox()
assert(Virtuous:DiscordNameForCharacter("Main") == "")
print("Discord roster: mapping, headers, scrolling, native layouts and inbox checks passed")
