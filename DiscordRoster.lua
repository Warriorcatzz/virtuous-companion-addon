local _, Virtuous = ...
local COLUMN_WIDTH = 108
local discordNames = {}

local function key(value)
  return strtrim(tostring(value or "")):gsub("%s+", " "):lower()
end

local function plainText(value)
  -- Discord names are text, not WoW colour codes, textures, or hyperlinks.
  return tostring(value or ""):gsub("[%c]", " "):gsub("|", "||")
end

function Virtuous:RebuildDiscordRoster()
  discordNames = {}
  for _, entry in ipairs(VirtuousAddonDB.discordRoster or {}) do
    local name = key(entry.wowName)
    local discordName = strtrim(tostring(entry.discordName or ""))
    if name ~= "" and discordName ~= "" then
      if discordNames[name] and discordNames[name] ~= discordName then
        discordNames[name] = false
      elseif discordNames[name] == nil then
        discordNames[name] = discordName
      end
    end
  end
end

function Virtuous:DiscordNameForCharacter(value)
  local name, realm = tostring(value or ""):match("^([^-]+)%-(.+)$")
  if realm then
    local normalizedRealm = GetNormalizedRealmName and GetNormalizedRealmName() or ""
    local displayRealm = GetRealmName and GetRealmName() or ""
    local realmKey = key(realm):gsub("[%s%-]", "")
    if realmKey ~= key(normalizedRealm):gsub("[%s%-]", "") and realmKey ~= key(displayRealm):gsub("[%s%-]", "") then return "" end
  end
  return discordNames[key(name or value)] or ""
end

local function enabled(memberList)
  local club = memberList.GetSelectedClubInfo and memberList:GetSelectedClubInfo()
  -- The narrow chat list and native profession/achievement views keep their
  -- original layout. Forever's normal roster has room beside the note.
  return memberList.expandedDisplay and club and club.clubType == Enum.ClubType.Guild
    and (not memberList.GetGuildColumnIndex or memberList:GetGuildColumnIndex() == nil)
end

local function points(region)
  local result = {}
  for index = 1, region:GetNumPoints() do result[index] = { region:GetPoint(index) } end
  return result
end

local function restoreNote(row)
  if not row.VirtuousNotePoints then return end
  local reserved = false
  for index = 1, row.Note:GetNumPoints() do
    local _, relative = row.Note:GetPoint(index)
    if relative == row.VirtuousDiscordName then reserved = true end
  end
  -- A native layout update may already have replaced our anchors.
  if reserved then
    row.Note:ClearAllPoints()
    for _, point in ipairs(row.VirtuousNotePoints) do row.Note:SetPoint(unpack(point)) end
  end
  row.VirtuousNotePoints = nil
end

local function refreshRow(memberList, row)
  if not row.Note or not row.GetMemberInfo then return end
  local member = row:GetMemberInfo()
  local visible = enabled(memberList) and row.expanded and member and not row.isInvitation
  if not visible then
    if row.VirtuousDiscordName then row.VirtuousDiscordName:SetText(""); row.VirtuousDiscordName:Hide() end
    restoreNote(row)
    return
  end
  if not row.VirtuousDiscordName then
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    text:SetSize(COLUMN_WIDTH - 8, 16)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    row.VirtuousDiscordName = text
  end
  restoreNote(row)
  row.VirtuousNotePoints = points(row.Note)
  row.Note:ClearAllPoints()
  row.Note:SetPoint("LEFT", row.Rank, "RIGHT", 8, 0)
  row.Note:SetPoint("RIGHT", row.VirtuousDiscordName, "LEFT", -8, 0)
  row.VirtuousDiscordName:SetText(plainText(Virtuous:DiscordNameForCharacter(member.name)))
  row.VirtuousDiscordName:SetTextColor(row.Note:GetTextColor())
  row.VirtuousDiscordName:Show()
end

local function refreshHeader(memberList, nativeLayout)
  local display = memberList.ColumnDisplay
  local header = display.VirtuousDiscordHeader
  if not enabled(memberList) then if header then header:Hide() end; return end
  if not display.columnHeaders then return end
  local noteIndex
  for index, info in ipairs(memberList.columnInfo or {}) do
    if info.attribute == "memberNote" then noteIndex = index; break end
  end
  if not noteIndex then return end
  local note
  for candidate in display.columnHeaders:EnumerateActive() do
    if candidate:GetID() == noteIndex then note = candidate; break end
  end
  if not note then return end
  if nativeLayout or display.VirtuousNoteHeader ~= note then
    display.VirtuousNoteHeader = note
    display.VirtuousHeaderPoints = points(note)
  end
  if not display.VirtuousHeaderPoints then return end
  if not header then
    header = CreateFrame("Button", nil, display, "ColumnDisplayButtonTemplate")
    header:SetText("Discord")
    header:SetScript("OnClick", nil)
    header:EnableMouse(false)
    header:SetWidth(COLUMN_WIDTH)
    display.VirtuousDiscordHeader = header
  end
  note:ClearAllPoints()
  header:ClearAllPoints()
  for _, point in ipairs(display.VirtuousHeaderPoints) do
    if point[1] == "BOTTOMRIGHT" or point[1] == "RIGHT" or point[1] == "TOPRIGHT" then
      header:SetPoint(unpack(point))
      note:SetPoint(point[1], point[2], point[3], point[4] - COLUMN_WIDTH + 2, point[5])
    else note:SetPoint(unpack(point)) end
  end
  header:Show()
end

function Virtuous:InstallDiscordRoster(guildFrame)
  local memberList = guildFrame and guildFrame.MemberList
  if not memberList or memberList.VirtuousDiscordInstalled or not hooksecurefunc then return end
  if not memberList.ColumnDisplay or not memberList.ScrollBox or not memberList.ScrollBox.ForEachFrame then return end
  memberList.VirtuousDiscordInstalled = true
  self:RebuildDiscordRoster()
  local function refreshRows()
    memberList.ScrollBox:ForEachFrame(function(row)
      if row.RefreshExpandedColumns and not row.VirtuousDiscordHooked then
        row.VirtuousDiscordHooked = true
        hooksecurefunc(row, "RefreshExpandedColumns", function() refreshRow(memberList, row) end)
        if row.UpdatePresence then hooksecurefunc(row, "UpdatePresence", function() refreshRow(memberList, row) end) end
        row:HookScript("OnEnter", function()
          if not row.VirtuousDiscordName or not row.VirtuousDiscordName:IsShown() then return end
          local member = row:GetMemberInfo()
          local name = member and Virtuous:DiscordNameForCharacter(member.name) or ""
          if name == "" then return end
          if not GameTooltip:IsOwned(row) then
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:SetText((plainText(member.name)))
          end
          GameTooltip:AddLine("Discord: " .. plainText(name), 1, 1, 1)
          GameTooltip:Show()
        end)
      end
      refreshRow(memberList, row)
    end)
  end
  hooksecurefunc(memberList.ColumnDisplay, "LayoutColumns", function() refreshHeader(memberList, true) end)
  hooksecurefunc(memberList, "RefreshLayout", function() refreshHeader(memberList); refreshRows() end)
  hooksecurefunc(memberList, "RefreshListDisplay", refreshRows)
  -- New pooled rows can be created while scrolling without a list refresh.
  -- Discover them without replacing Blizzard's initializer or scrolling code.
  local elapsed = 0
  memberList.ScrollBox:HookScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < 0.1 then return end
    elapsed = 0
    refreshRows()
  end)
  refreshHeader(memberList, true)
  refreshRows()
end
