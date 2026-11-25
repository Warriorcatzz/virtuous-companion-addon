local _, Virtuous = ...
local window
local anchorTabs
local guildFrameRoot
local companionHost
local hostNativeState
local nativeContentState
local companionHostWasShown
local hostReplaced = false
local activePage = "tickets"
local ticketMode = "materials"
local ticketView = "overview"
local selectedTicket = nil
local feralRole = nil

local COLORS = {
  background = { 0.025, 0.023, 0.019, 1 },
  panel = { 0.055, 0.052, 0.044, 1 },
  gold = { 1, 0.82, 0.2, 1 },
  muted = { 0.72, 0.69, 0.62, 1 },
  green = { 0.38, 0.78, 0.42, 1 },
  border = { 0.43, 0.36, 0.22, 1 },
}

local INSET_BACKDROP = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 9,
  insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

local function applyInset(frame, background)
  frame:SetBackdrop(INSET_BACKDROP)
  frame:SetBackdropColor(unpack(background or COLORS.panel))
  frame:SetBackdropBorderColor(unpack(COLORS.border))
end

local TAB_DATA = {
  tickets = { label = "Tickets", icon = "Interface\\Icons\\INV_Misc_Note_01" },
  raids = { label = "Raid signups", icon = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend" },
  officer = { label = "Guild ranks", icon = "Interface\\Icons\\INV_Misc_GroupLooking" },
}

local RANK_INDEX = { Officer = 2, ["Loot Council"] = 3, Raider = 4, Trial = 5, Social = 6, Alt = 7 }

local function rosterKey(value)
  local name = tostring(value or ""):match("^[^-]+") or ""
  return (name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")):lower()
end

local function firstNameKey(value)
  return rosterKey(value):match("^%S+") or ""
end

local function addUniqueAlias(aliases, key, record)
  if aliases[key] == nil then aliases[key] = record
  elseif aliases[key] ~= record then aliases[key] = false end
end

local function requestGuildRoster()
  if C_GuildInfo and C_GuildInfo.GuildRoster then
    pcall(C_GuildInfo.GuildRoster)
  elseif GuildRoster then
    pcall(GuildRoster)
  end
end

local function label(parent, text, x, y, template)
  local font = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
  font:SetPoint("TOPLEFT", x, y)
  font:SetText(text)
  return font
end

local function button(parent, text, width, onClick)
  local control = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  control:SetSize(width, 24)
  control:SetText(text)
  control:SetScript("OnClick", onClick)
  return control
end

local function input(parent, multiline, width, height)
  local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
  box:SetSize(width, height)
  box:SetAutoFocus(false)
  box:SetMultiLine(multiline)
  box:SetFontObject("ChatFontNormal")
  box:SetTextInsets(8, 8, 6, 6)
  applyInset(box, COLORS.background)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  return box
end

local function field(parent, title, x, y, width, height, multiline, maxLetters)
  local heading = label(parent, title, x, y, "GameFontNormalSmall")
  heading:SetTextColor(unpack(COLORS.gold))
  local box = input(parent, multiline, width, height)
  box:SetPoint("TOPLEFT", x, y - 16)
  box:SetMaxLetters(maxLetters or 1000)
  return box
end

local function ticketState(ticket)
  if ticket.state then return tostring(ticket.state) end
  if ticket.active == false then return "cancelled" end
  if ticket.closed then return "closed" end
  return "open"
end

local function ticketTitle(ticket)
  if ticket.kind == "absence" then return string.format("Absent %s to %s", tostring(ticket.first_date or "?"), tostring(ticket.last_date or "?")) end
  return ticket.character_name and ("Materials - " .. ticket.character_name) or "Material request"
end

local TERMINAL_TICKET_STATES = {
  cancelled = true, canceled = true, closed = true, complete = true,
  completed = true, denied = true, rejected = true, resolved = true,
}

local function ticketIsActive(ticket)
  if ticket.active == false or ticket.closed == true then return false end
  return not TERMINAL_TICKET_STATES[tostring(ticketState(ticket)):lower()]
end

local function rosterText(signups)
  local names = {}
  for _, signup in ipairs(signups or {}) do
    if signup.characterName then table.insert(names, signup.characterName) end
    if #names >= 5 then break end
  end
  local result = table.concat(names, ", ")
  if #(signups or {}) > #names then result = result .. string.format(" +%d", #(signups or {}) - #names) end
  return result ~= "" and result or "No signups yet"
end

local function raidTime(value)
  return tostring(value or ""):sub(1, 16):gsub("T", " ")
end

local function setTabState()
  if not window then return end
  for name, tab in pairs(window.tabs) do
    tab:SetChecked(name == activePage and window:IsShown())
  end
end

local function memberDetailFrames()
  local unique, result = {}, {}
  local function add(frame)
    if frame and frame.IsShown and not unique[frame] then unique[frame] = true; table.insert(result, frame) end
  end
  -- Add candidates individually: an array containing an early nil makes
  -- ipairs stop and previously prevented later client-specific frames from
  -- ever being detected.
  add(_G.GuildMemberDetailFrame)
  add(_G.CommunitiesFrameGuildMemberDetailFrame)
  add(guildFrameRoot and guildFrameRoot.GuildMemberDetailFrame)
  add(guildFrameRoot and guildFrameRoot.MemberDetailFrame)
  add(guildFrameRoot and guildFrameRoot.MemberList and guildFrameRoot.MemberList.GuildMemberDetailFrame)
  add(guildFrameRoot and guildFrameRoot.MemberList and guildFrameRoot.MemberList.MemberDetailFrame)
  return result
end

local function memberDetailShown()
  for _, frame in ipairs(memberDetailFrames()) do if frame:IsShown() then return true end end
  return false
end

local function refreshSideTabVisibility()
  if not window or not window.tabs then return end
  local hiddenByPopup = memberDetailShown()
  local authorized = VirtuousAddonDB.officerTools and VirtuousAddonDB.officerTools.authorized == true
  window.tabs.tickets:SetShown(not hiddenByPopup)
  window.tabs.raids:SetShown(not hiddenByPopup)
  window.tabs.officer:SetShown(not hiddenByPopup and authorized)
  anchorTabs(guildFrameRoot)
end

local NATIVE_CONTENT_KEYS = {
  "Chat",
  "MemberList",
  "ChatEditBox",
  "StreamDropdown",
  "CommunityMemberListDropdown",
  "GuildMemberListDropdown",
  "CommunitiesControlFrame",
  "GuildBenefitsFrame",
  "GuildPreferredPlaySettingsFrame",
  "GuildDetailsFrame",
  "LoadingSpinner",
  "Spinner",
}

local function restoreNativeHost()
  if not hostReplaced then return end
  for _, entry in ipairs(hostNativeState or {}) do
    if entry.shown then entry.region:Show() else entry.region:Hide() end
  end
  for _, entry in ipairs(nativeContentState or {}) do
    if entry.shown then entry.region:Show() else entry.region:Hide() end
  end
  if companionHostWasShown then companionHost:Show() else companionHost:Hide() end
  hostNativeState = nil
  nativeContentState = nil
  companionHostWasShown = nil
  hostReplaced = false
end

local function replaceNativeHost()
  if not companionHost then return end
  if not hostReplaced then
    companionHostWasShown = companionHost:IsShown()
    nativeContentState = {}
    local captured = {}
    for _, key in ipairs(NATIVE_CONTENT_KEYS) do
      local nativeFrame = guildFrameRoot and guildFrameRoot[key]
      if nativeFrame and nativeFrame ~= companionHost and nativeFrame.Hide and not captured[nativeFrame] then
        captured[nativeFrame] = true
        table.insert(nativeContentState, { region = nativeFrame, shown = nativeFrame:IsShown() })
      end
    end
    if CommunitiesFrameGuildDetailsFrame and CommunitiesFrameGuildDetailsFrame ~= companionHost and not captured[CommunitiesFrameGuildDetailsFrame] then
      table.insert(nativeContentState, { region = CommunitiesFrameGuildDetailsFrame, shown = CommunitiesFrameGuildDetailsFrame:IsShown() })
    end
    hostNativeState = {}
    for _, region in ipairs({ companionHost:GetRegions() }) do
      table.insert(hostNativeState, { region = region, shown = region:IsShown() })
      region:Hide()
    end
    for _, child in ipairs({ companionHost:GetChildren() }) do
      if child ~= window then
        table.insert(hostNativeState, { region = child, shown = child:IsShown() })
        child:Hide()
      end
    end
    hostReplaced = true
  else
    for _, entry in ipairs(hostNativeState or {}) do entry.region:Hide() end
  end
  companionHost:Show()
end

local function hideNativeGuildContent()
  if not window then return end
  local frame = guildFrameRoot
  for _, key in ipairs(NATIVE_CONTENT_KEYS) do
    local nativeFrame = frame[key]
    if nativeFrame and nativeFrame ~= companionHost and nativeFrame.Hide then nativeFrame:Hide() end
  end

  -- This frame is global on older clients instead of being exposed as a child.
  if CommunitiesFrameGuildDetailsFrame and CommunitiesFrameGuildDetailsFrame.Hide then
    CommunitiesFrameGuildDetailsFrame:Hide()
  end
end

local function suppressNativeOnShow(nativeFrame)
  if not nativeFrame or nativeFrame == window or not nativeFrame.HookScript or nativeFrame.VirtuousSuppressHook then return end
  nativeFrame.VirtuousSuppressHook = true
  nativeFrame:HookScript("OnShow", function(self)
    if window and window:IsShown() and hostReplaced then self:Hide() end
  end)
end

local function showTicketMode(mode)
  ticketMode = mode
  window.ticketSections.materials:SetShown(mode == "materials")
  window.ticketSections.absence:SetShown(mode == "absence")
  window.ticketButtons.materials:SetEnabled(mode ~= "materials")
  window.ticketButtons.absence:SetEnabled(mode ~= "absence")
  Virtuous:Refresh()
end

local function showTicketView(view)
  ticketView = (view == "form" or view == "detail") and view or "overview"
  window.ticketViews.overview:SetShown(ticketView == "overview")
  window.ticketViews.form:SetShown(ticketView == "form")
  window.ticketViews.detail:SetShown(ticketView == "detail")
  window.ticketNew:SetShown(ticketView == "overview")
  window.ticketBack:SetShown(ticketView ~= "overview")
  if ticketView == "overview" then
    window.ticketTitle:SetText("Tickets")
    window.ticketHelp:SetText("Your active requests and absence tickets.")
    Virtuous:Refresh()
  elseif ticketView == "form" then
    window.ticketTitle:SetText("New ticket")
    window.ticketHelp:SetText("Choose a material request or absence ticket.")
    showTicketMode(ticketMode)
  else
    window.ticketTitle:SetText(ticketTitle(selectedTicket or {}))
    window.ticketHelp:SetText("Status and replies from Discord, the website, and WoW.")
    Virtuous:Refresh()
  end
end

local function showPage(name)
  activePage = name
  for pageName, page in pairs(window.pages) do page:SetShown(pageName == name) end
  replaceNativeHost()
  window:Show()
  hideNativeGuildContent()
  setTabState()
  if name == "tickets" then
    showTicketView("overview")
  else
    if name == "officer" then requestGuildRoster() end
    Virtuous:Refresh()
  end
end

local function hideCompanion()
  if window then
    window:Hide()
    restoreNativeHost()
    setTabState()
  end
end

local function createTicketList(parent, kind, heading)
  local history = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  applyInset(history)
  local title = label(history, heading, 10, -10, "GameFontNormalSmall")
  title:SetTextColor(unpack(COLORS.muted))
  history.rows = {}
  history.kind = kind
  for index = 1, 4 do
    local row = CreateFrame("Button", nil, history)
    row:SetPoint("TOPLEFT", 10, -32 - ((index - 1) * 37))
    row:SetPoint("TOPRIGHT", -10, -32 - ((index - 1) * 37))
    row:SetHeight(35)
    row.title = label(row, "", 0, -1, "GameFontHighlightSmall")
    row.title:SetPoint("TOPRIGHT", 0, -1)
    row.title:SetHeight(15)
    row.title:SetJustifyH("LEFT")
    row.title:SetJustifyV("TOP")
    row.state = label(row, "", 0, -18, "GameFontNormalSmall")
    row.state:SetTextColor(unpack(COLORS.gold))
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row:SetScript("OnClick", function(self)
      if self.ticket then selectedTicket = self.ticket; showTicketView("detail") end
    end)
    history.rows[index] = row
  end
  history.empty = label(history, "No requests yet.", 10, -39, "GameFontHighlightSmall")
  history.empty:SetTextColor(unpack(COLORS.muted))
  return history
end

local function refreshTicketList(history)
  for _, row in ipairs(history.rows) do row:Hide() end
  local index = 0
  for _, ticket in ipairs(VirtuousAddonDB.tickets or {}) do
    if ticket.kind == history.kind then
      index = index + 1
      if index > #history.rows then break end
      local row = history.rows[index]
      row.ticket = ticket
      row.title:SetText(ticketTitle(ticket))
      local messages = ticket.messages or {}
      local replySummary = #messages == 1 and "1 reply" or (#messages .. " replies")
      if #messages > 0 then replySummary = replySummary .. " · last: " .. tostring(messages[#messages].author_name or "member") end
      row.state:SetText(ticketState(ticket) .. "  |  " .. replySummary)
      row:Show()
    end
  end
  history.empty:SetShown(index == 0)
end

local function refreshTicketOverview()
  if not window.ticketLists then return end
  local materials, absences = 0, 0
  for _, ticket in ipairs(VirtuousAddonDB.tickets or {}) do
    if ticketIsActive(ticket) then
      if ticket.kind == "absence" then absences = absences + 1
      elseif ticket.kind == "material" then materials = materials + 1 end
    end
  end
  window.ticketCounts.materials:SetText(tostring(materials))
  window.ticketCounts.absence:SetText(tostring(absences))
  refreshTicketList(window.ticketLists.materials)
  refreshTicketList(window.ticketLists.absence)
end

local function refreshTicketDetail()
  if not window.ticketDetail or not selectedTicket then return end
  for _, current in ipairs(VirtuousAddonDB.tickets or {}) do
    if current.kind == selectedTicket.kind and tostring(current.id) == tostring(selectedTicket.id) then selectedTicket = current; break end
  end
  local detail = window.ticketDetail
  detail.status:SetText("Status: " .. ticketState(selectedTicket) .. "  |  Ticket #" .. tostring(selectedTicket.id))
  local meta = selectedTicket.kind == "absence"
    and ("Absent " .. tostring(selectedTicket.first_date or "?") .. " to " .. tostring(selectedTicket.last_date or "?"))
    or (selectedTicket.character_name and ("Character: " .. selectedTicket.character_name) or "Guild bank material request")
  detail.meta:SetText(meta)
  local messages = selectedTicket.messages or {}
  local first = math.max(1, #messages - #detail.messages + 1)
  for index, line in ipairs(detail.messages) do
    local message = messages[first + index - 1]
    if message then
      local source = message.source == "game" and "WoW" or message.source == "website" and "Website" or "Discord"
      local content = tostring(message.content or ""):gsub("[\r\n]+", " ")
      if #content > 180 then content = content:sub(1, 177) .. "..." end
      line:SetText(string.format("|cffffd100%s (%s):|r %s", tostring(message.author_name or "Member"), source, content))
      line:Show()
    else line:Hide() end
  end
  detail.empty:SetShown(#messages == 0)
  local open = ticketIsActive(selectedTicket)
  detail.reply:SetEnabled(open)
  detail.send:SetEnabled(open)
  detail.closed:SetShown(not open)
end

local function refreshRaids()
  local page = window.pages.raids
  local needsFeralRole = false
  for _, row in ipairs(page.rows) do row:Hide() end
  page.empty:SetShown(#(VirtuousAddonDB.raids or {}) == 0)
  for index, raid in ipairs(VirtuousAddonDB.raids or {}) do
    if index > #page.rows then break end
    local row = page.rows[index]
    row.raid = raid
    row.title:SetText(tostring(raid.title or "Raid"))
    row.team:SetText(tostring(raid.teamName or raid.team or "Assigned team"))
    row.meta:SetText(raidTime(raid.startsAt) .. "  |  " .. tostring(#(raid.signups or {})) .. " signed")
    row.roster:SetText(rosterText(raid.signups))
    row.character:SetText(raid.signupCharacterName and ("Your Main: " .. raid.signupCharacterName) or "No Main assigned for this team")
    row.character:SetTextColor(unpack(raid.signupCharacterName and COLORS.green or COLORS.muted))
    if raid.mySignup then
      row.status:SetText("Signed: " .. tostring(raid.mySignup.status or "available"))
      row.action:SetText("Withdraw")
      row.action:SetEnabled(true)
    else
      row.status:SetText("Not signed")
      row.action:SetText("Sign up")
      row.action:SetEnabled(raid.signupCharacterId ~= nil)
    end
    if raid.signupClassName == "Druid" and raid.signupSpec == "Feral Combat" and not raid.mySignup then needsFeralRole = true end
    row:Show()
  end
  page.feral:SetShown(needsFeralRole)
end

local function rankLayoutValid()
  if not GuildControlGetRankName then return true end
  for name, index in pairs(RANK_INDEX) do
    if tostring(GuildControlGetRankName(index + 1) or "") ~= name then return false end
  end
  return true
end

local function refreshOfficer()
  local page = window.pages.officer
  if not page then return end
  if Virtuous.CheckPendingGuildRankChange then Virtuous:CheckPendingGuildRankChange() end
  for _, row in ipairs(page.rows) do
    row:Hide()
    row.action.memberName = nil
    row.action.promoting = nil
    row.action.fromRankIndex = nil
    row.action.targetRankIndex = nil
    row.action.expectedRank = nil
    row.action:SetAttribute("type", nil)
    row.action:SetAttribute("macrotext", nil)
  end
  local tools = VirtuousAddonDB.officerTools or {}
  if not tools.authorized then return end
  page.header:Hide()
  page.previous:Hide()
  page.next:Hide()
  page.pageText:Hide()
  page.warning:Hide()
  page.summary:Show()
  -- Ignore the additional online/mobile counts returned by the guild API.
  local totalMembers = GetNumGuildMembers and tonumber((GetNumGuildMembers())) or 0
  if totalMembers == 0 then
    page.summary:SetText("Waiting for the live guild roster...")
    page.empty:Hide()
    requestGuildRoster()
    return
  end
  local roster, rosterAliases = {}, {}
  for index = 1, totalMembers do
    local name, rankName, rankIndex = GetGuildRosterInfo(index)
    if name then
      local member = { name = name, rankName = rankName, rankIndex = rankIndex }
      roster[rosterKey(name)] = member
      addUniqueAlias(rosterAliases, firstNameKey(name), member)
    end
  end
  local database = {}
  for _, entry in ipairs(tools.entries or {}) do
    local key = rosterKey(entry.name)
    if key ~= "" then
      local existing = database[key]
      if not existing then
        database[key] = { entry = entry, ranks = { [tostring(entry.expectedRank)] = true } }
      else
        existing.ranks[tostring(entry.expectedRank)] = true
      end
    end
  end
  local databaseAliases = {}
  for key, record in pairs(database) do addUniqueAlias(databaseAliases, firstNameKey(key), record) end
  local issues = {}
  for key, record in pairs(database) do
    local rankCount = 0
    for _ in pairs(record.ranks) do rankCount = rankCount + 1 end
    local member = roster[key]
    -- Forever displays full roleplay names. A first-name fallback is safe only
    -- when it identifies one character in both complete snapshots.
    local alias = firstNameKey(key)
    if not member and databaseAliases[alias] == record then member = rosterAliases[alias] end
    local target = RANK_INDEX[record.entry.expectedRank]
    -- Guild Master/Guild Officer ranks are independent of raid-team ranks.
    if rankCount == 1 and target and member and type(member.rankIndex) == "number" and member.rankIndex >= 2
      and member.rankName and rosterKey(member.rankName) ~= ""
      and rosterKey(member.rankName) ~= rosterKey(record.entry.expectedRank) then
      table.insert(issues, { entry = record.entry, member = member, target = target })
    end
  end
  table.sort(issues, function(left, right)
    return rosterKey(left.member.name) < rosterKey(right.member.name)
  end)
  page.summary:SetText(#issues == 1 and "1 member needs a rank change" or string.format("%d members need a rank change", #issues))
  page.summary:SetShown(#issues > 0)
  page.empty:SetShown(#issues == 0)
  page.header:SetShown(#issues > 0)
  local validLayout = rankLayoutValid()
  page.warning:SetShown(not validLayout and #issues > 0)
  if not validLayout then page.summary:Hide() end
  local canPromote = not CanGuildPromote or CanGuildPromote()
  local canDemote = not CanGuildDemote or CanGuildDemote()
  local pages = math.max(1, math.ceil(#issues / #page.rows))
  page.issuePage = math.max(0, math.min(tonumber(page.issuePage) or 0, pages - 1))
  page.pageText:SetText(string.format("%d / %d", page.issuePage + 1, pages))
  page.pageText:SetShown(#issues > #page.rows)
  page.previous:SetShown(#issues > #page.rows)
  page.next:SetShown(#issues > #page.rows)
  page.previous:SetEnabled(page.issuePage > 0)
  page.next:SetEnabled(page.issuePage < pages - 1)
  local firstIssue = (page.issuePage * #page.rows) + 1
  for index = 1, #page.rows do
    local issue = issues[firstIssue + index - 1]
    if not issue then break end
    local row = page.rows[index]
    local entry = issue.entry
    local member = issue.member
    row.name:SetText(((member.name:match("^[^-]+") or member.name):gsub("|", "||")))
    row.current:SetText(tostring(member.rankName))
    row.expected:SetText(tostring(entry.expectedRank))
    row.tooltipName = member.name
    row.tooltipReason = entry.reason
    local promoting = member.rankIndex > issue.target
    local waiting = Virtuous.GuildRankChangePending and Virtuous:GuildRankChangePending()
    local waitingForMember = waiting and Virtuous:GuildRankChangePending(member.name)
    local allowed = validLayout and not waiting and not InCombatLockdown() and (promoting and canPromote or (not promoting and canDemote))
    row.action:SetText(waitingForMember and "Waiting..." or (promoting and "Promote" or "Demote"))
    row.action:SetEnabled(allowed)
    if allowed then
      row.action.memberName = member.name
      row.action.promoting = promoting
      row.action.fromRankIndex = member.rankIndex
      row.action.targetRankIndex = issue.target
      row.action.expectedRank = entry.expectedRank
    end
    row:Show()
  end
end

local function refreshTabVisibility()
  if not window then return end
  local authorized = VirtuousAddonDB.officerTools and VirtuousAddonDB.officerTools.authorized == true
  if not authorized and activePage == "officer" then activePage = "tickets"; window.pages.officer:Hide() end
  refreshSideTabVisibility()
end

function Virtuous:Refresh()
  if not window then return end
  refreshTabVisibility()
  window.status:SetText(self:SyncSummary() .. string.format("  |  %d queued locally", self:PendingCount()))
  refreshTicketOverview()
  refreshTicketDetail()
  refreshRaids()
  refreshOfficer()
end

local function visibleBlizzardTabs(frame)
  local visible = {}
  for _, tab in ipairs({ frame.ChatTab, frame.RosterTab, frame.GuildBenefitsTab, frame.GuildInfoTab, frame.GuildPreferredPlaySettingsTab }) do
    if tab and tab:IsShown() then table.insert(visible, tab) end
  end
  return visible
end

local function lastBlizzardTab(frame)
  local visible = visibleBlizzardTabs(frame)
  return visible[#visible]
end

local function blizzardTabStep(frame)
  local visible = visibleBlizzardTabs(frame)
  local last = visible[#visible]
  local previous = visible[#visible - 1]
  if last and previous then
    local lastTop, previousTop = last:GetTop(), previous:GetTop()
    if lastTop and previousTop and previousTop > lastTop then
      return previousTop - lastTop
    end
  end
  return last and (last:GetHeight() + 4) or 42
end

anchorTabs = function(frame)
  if not window then return end
  -- Blizzard changes which native buttons report themselves as shown while it
  -- refreshes pages. Capture the original last guild tab once so Companion
  -- buttons never jump when their content is selected.
  if not window.nativeTabAnchor then window.nativeTabAnchor = lastBlizzardTab(frame) end
  local previous = window.nativeTabAnchor
  -- Custom tabs need a little more breathing room than Blizzard's tightly
  -- packed native strip, especially when the checked border is visible.
  local step = blizzardTabStep(frame)
  for _, name in ipairs({ "tickets", "raids", "officer" }) do
    local tab = window.tabs[name]
    if tab:IsShown() then
      tab:ClearAllPoints()
      -- Continue Blizzard's measured top-to-top rhythm. This stays aligned
      -- across UI scales and different CommunitiesFrame template sizes.
      if previous then tab:SetPoint("TOPLEFT", previous, "TOPLEFT", 0, -step)
      else tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, -36) end
      previous = tab
    end
  end
end

local function createSideTab(frame, name)
  local data = TAB_DATA[name]
  local tab = CreateFrame("CheckButton", "VirtuousCompanion" .. name .. "Tab", frame, "CommunitiesFrameTabTemplate")
  -- Match Blizzard's own side tabs. Forcing these onto DIALOG made them draw
  -- over member context panels, dropdowns, and other native popups.
  local nativeTab = lastBlizzardTab(frame)
  tab:SetFrameStrata(nativeTab and nativeTab:GetFrameStrata() or frame:GetFrameStrata())
  -- Keep a deliberately low level as a fallback for clients whose member
  -- detail frame is not exposed under the usual global names.
  tab:SetFrameLevel(frame:GetFrameLevel() + 1)
  local icon = tab.Icon or tab.icon or tab.IconTexture
  if icon then icon:SetTexture(data.icon) end
  tab:SetScript("OnClick", function() showPage(name) end)
  tab:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Virtuous Companion")
    GameTooltip:AddLine(data.label, 1, 1, 1)
    GameTooltip:Show()
  end)
  tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return tab
end

local function loadCommunities()
  if CommunitiesFrame then return CommunitiesFrame end
  if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_Communities")
  elseif LoadAddOn then pcall(LoadAddOn, "Blizzard_Communities") end
  return CommunitiesFrame
end

function Virtuous:CreateWindow()
  if window then return true end
  local guildFrame = loadCommunities()
  if not guildFrame then return false end
  if self.InstallDiscordRoster then self:InstallDiscordRoster(guildFrame) end

  guildFrameRoot = guildFrame
  companionHost = guildFrame.GuildBenefitsFrame
  if not companionHost then return false end

  window = CreateFrame("Frame", "VirtuousCompanionGuildPanel", companionHost)
  window:SetAllPoints(companionHost)
  window:SetFrameLevel(companionHost:GetFrameLevel() + 10)
  window:EnableMouse(true)

  -- Blizzard refreshes guild pages after a tab is selected. Prevent those
  -- delayed refreshes from putting the removed native controls back underneath
  -- the Companion content. Normal tabs release the replacement on mouse-down.
  for _, key in ipairs(NATIVE_CONTENT_KEYS) do
    if guildFrame[key] ~= companionHost then suppressNativeOnShow(guildFrame[key]) end
  end
  suppressNativeOnShow(CommunitiesFrameGuildDetailsFrame)
  for _, child in ipairs({ companionHost:GetChildren() }) do suppressNativeOnShow(child) end

  window.tabs = { tickets = createSideTab(guildFrame, "tickets"), raids = createSideTab(guildFrame, "raids"), officer = createSideTab(guildFrame, "officer") }
  window.tabs.officer:Hide()
  for _, detailFrame in ipairs(memberDetailFrames()) do
    if detailFrame.HookScript and not detailFrame.VirtuousTabVisibilityHook then
      detailFrame.VirtuousTabVisibilityHook = true
      detailFrame:HookScript("OnShow", refreshSideTabVisibility)
      detailFrame:HookScript("OnHide", refreshSideTabVisibility)
    end
  end
  -- Some clients create the member-detail frame lazily, after Companion is
  -- initialized. Watch its visibility at a low frequency so those variants
  -- still hide the side tabs while the panel overlaps them.
  window.tabVisibilityWatcher = CreateFrame("Frame")
  window.tabVisibilityWatcher.elapsed = 0
  window.tabVisibilityWatcher.lastShown = false
  window.tabVisibilityWatcher:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 0.1 then return end
    self.elapsed = 0
    local shown = memberDetailShown()
    if shown ~= self.lastShown then self.lastShown = shown; refreshSideTabVisibility() end
  end)
  window.nativeTabAnchor = lastBlizzardTab(guildFrame)
  anchorTabs(guildFrame)
  for _, tab in ipairs({ guildFrame.ChatTab, guildFrame.RosterTab, guildFrame.GuildBenefitsTab, guildFrame.GuildInfoTab, guildFrame.GuildPreferredPlaySettingsTab }) do
    if tab and tab.HookScript then
      -- Release the native panes before Blizzard handles the click, so its
      -- selected guild page becomes the sole content again.
      tab:HookScript("OnMouseDown", hideCompanion)
      tab:HookScript("OnClick", hideCompanion)
    end
  end
  if guildFrame.UpdateCommunitiesTabs and hooksecurefunc then
    hooksecurefunc(guildFrame, "UpdateCommunitiesTabs", function()
      anchorTabs(guildFrame)
      if window and window:IsShown() then
        replaceNativeHost()
        hideNativeGuildContent()
      end
    end)
  end

  local brand = label(window, "VIRTUOUS COMPANION", 16, -11, "GameFontNormalSmall")
  brand:SetTextColor(unpack(COLORS.gold))
  window.status = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  window.status:SetPoint("BOTTOMLEFT", 16, 9)
  window.status:SetTextColor(unpack(COLORS.muted))

  window.pages = {}
  for _, name in ipairs({ "tickets", "raids", "officer" }) do
    local page = CreateFrame("Frame", nil, window)
    page:SetPoint("TOPLEFT", 0, -22)
    page:SetPoint("BOTTOMRIGHT", 0, 23)
    page:SetFrameLevel(205)
    window.pages[name] = page
  end

  local officer = window.pages.officer
  label(officer, "Guild ranks", 16, -7, "GameFontNormalLarge")
  local officerHelp = label(officer, "Only rank mismatches are listed. Each click changes one rank step.", 16, -30, "GameFontHighlightSmall")
  officerHelp:SetTextColor(unpack(COLORS.muted))
  officer.summary = label(officer, "Waiting for guild roster...", 16, -55, "GameFontNormal")
  officer.summary:SetTextColor(unpack(COLORS.gold))
  officer.issuePage = 0
  officer.previous = button(officer, "Prev", 54, function() officer.issuePage = math.max(0, officer.issuePage - 1); refreshOfficer() end)
  officer.previous:SetPoint("TOPRIGHT", -126, -3)
  officer.pageText = officer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  officer.pageText:SetPoint("TOPRIGHT", -70, -10)
  officer.pageText:SetWidth(52)
  officer.pageText:SetJustifyH("CENTER")
  officer.next = button(officer, "Next", 54, function() officer.issuePage = officer.issuePage + 1; refreshOfficer() end)
  officer.next:SetPoint("TOPRIGHT", -16, -3)
  officer.warning = label(officer, "Guild rank order differs. Rank changes are disabled.", 16, -55, "GameFontHighlightSmall")
  officer.warning:SetTextColor(1, 0.35, 0.25)
  officer.warning:SetWidth(540)
  officer.empty = label(officer, "No confirmed rank mismatches.", 28, -104, "GameFontHighlight")
  officer.empty:SetTextColor(unpack(COLORS.green))
  officer.header = CreateFrame("Frame", nil, officer)
  officer.header:SetPoint("TOPLEFT", 16, -80)
  officer.header:SetPoint("TOPRIGHT", -16, -80)
  officer.header:SetHeight(15)
  for _, column in ipairs({ { "CHARACTER", 10 }, { "CURRENT", 184 }, { "EXPECTED", 301 } }) do
    local heading = label(officer.header, column[1], column[2], 0, "GameFontNormalSmall")
    heading:SetTextColor(unpack(COLORS.muted))
  end
  officer.rows = {}
  for index = 1, 5 do
    local row = CreateFrame("Frame", nil, officer, "BackdropTemplate")
    row:SetPoint("TOPLEFT", 16, -98 - ((index - 1) * 37))
    row:SetPoint("TOPRIGHT", officer, "TOPRIGHT", -16, -98 - ((index - 1) * 37))
    row:SetHeight(33)
    applyInset(row)
    row.name = label(row, "", 10, -11, "GameFontHighlightSmall")
    row.name:SetWidth(166)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.current = label(row, "", 184, -11, "GameFontHighlightSmall")
    row.current:SetTextColor(unpack(COLORS.muted))
    row.current:SetWidth(90)
    row.current:SetJustifyH("LEFT")
    local arrow = label(row, ">", 280, -11, "GameFontHighlightSmall")
    arrow:SetTextColor(unpack(COLORS.muted))
    row.expected = label(row, "", 301, -11, "GameFontNormalSmall")
    row.expected:SetTextColor(unpack(COLORS.gold))
    row.expected:SetWidth(96)
    row.expected:SetJustifyH("LEFT")
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText((tostring(self.tooltipName or ""):gsub("|", "||")))
      GameTooltip:AddLine(tostring(self.tooltipReason or "Database assignment"), 1, 0.82, 0.2)
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.action = Virtuous:CreateGuildRankActionButton(row)
    row.action:SetSize(82, 24)
    row.action:SetPoint("RIGHT", -9, 0)
    officer.rows[index] = row
  end

  local rosterEvents = CreateFrame("Frame")
  rosterEvents:RegisterEvent("GUILD_ROSTER_UPDATE")
  rosterEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
  rosterEvents:RegisterEvent("ADDON_ACTION_BLOCKED")
  rosterEvents:RegisterEvent("ADDON_ACTION_FORBIDDEN")
  rosterEvents:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then Virtuous:GuildRankActionBlocked(...)
    elseif event == "GUILD_ROSTER_UPDATE" then Virtuous:CheckPendingGuildRankChange() end
    if window and window:IsShown() then refreshOfficer() end
  end)

  local tickets = window.pages.tickets
  window.ticketTitle = label(tickets, "Tickets", 16, -7, "GameFontNormalLarge")
  window.ticketHelp = label(tickets, "Your active requests and absence tickets.", 16, -30, "GameFontHighlightSmall")
  window.ticketHelp:SetTextColor(unpack(COLORS.muted))
  window.ticketNew = button(tickets, "New ticket", 108, function() showTicketView("form") end)
  window.ticketNew:SetPoint("TOPRIGHT", -16, -3)
  window.ticketBack = button(tickets, "Back to overview", 132, function() showTicketView("overview") end)
  window.ticketBack:SetPoint("TOPRIGHT", -16, -3)

  window.ticketViews = {}
  local overview = CreateFrame("Frame", nil, tickets)
  overview:SetAllPoints()
  window.ticketViews.overview = overview

  window.ticketCounts = {}
  local materialCount = CreateFrame("Frame", nil, overview, "BackdropTemplate")
  materialCount:SetPoint("TOPLEFT", 16, -58)
  materialCount:SetPoint("TOPRIGHT", overview, "TOP", -5, -58)
  materialCount:SetHeight(58)
  applyInset(materialCount)
  local materialCountLabel = label(materialCount, "ACTIVE MATERIAL REQUESTS", 12, -10, "GameFontNormalSmall")
  materialCountLabel:SetTextColor(unpack(COLORS.muted))
  window.ticketCounts.materials = label(materialCount, "0", 12, -29, "GameFontNormalLarge")
  window.ticketCounts.materials:SetTextColor(unpack(COLORS.gold))

  local absenceCount = CreateFrame("Frame", nil, overview, "BackdropTemplate")
  absenceCount:SetPoint("TOPLEFT", overview, "TOP", 5, -58)
  absenceCount:SetPoint("TOPRIGHT", -16, -58)
  absenceCount:SetHeight(58)
  applyInset(absenceCount)
  local absenceCountLabel = label(absenceCount, "ACTIVE ABSENCE TICKETS", 12, -10, "GameFontNormalSmall")
  absenceCountLabel:SetTextColor(unpack(COLORS.muted))
  window.ticketCounts.absence = label(absenceCount, "0", 12, -29, "GameFontNormalLarge")
  window.ticketCounts.absence:SetTextColor(unpack(COLORS.gold))

  window.ticketLists = {}
  window.ticketLists.materials = createTicketList(overview, "material", "YOUR MATERIAL REQUESTS")
  window.ticketLists.materials:SetPoint("TOPLEFT", 16, -126)
  window.ticketLists.materials:SetPoint("BOTTOMRIGHT", overview, "BOTTOM", -5, 8)
  window.ticketLists.absence = createTicketList(overview, "absence", "YOUR ABSENCE TICKETS")
  window.ticketLists.absence:SetPoint("TOPLEFT", overview, "TOP", 5, -126)
  window.ticketLists.absence:SetPoint("BOTTOMRIGHT", -16, 8)

  local ticketDetail = CreateFrame("Frame", nil, tickets)
  ticketDetail:SetAllPoints()
  window.ticketViews.detail = ticketDetail
  window.ticketDetail = ticketDetail
  ticketDetail.status = label(ticketDetail, "", 16, -58, "GameFontNormal")
  ticketDetail.status:SetTextColor(unpack(COLORS.gold))
  ticketDetail.meta = label(ticketDetail, "", 16, -79, "GameFontHighlightSmall")
  ticketDetail.meta:SetTextColor(unpack(COLORS.muted))
  local conversation = CreateFrame("Frame", nil, ticketDetail, "BackdropTemplate")
  conversation:SetPoint("TOPLEFT", 16, -103)
  conversation:SetPoint("BOTTOMRIGHT", -16, 85)
  applyInset(conversation)
  ticketDetail.messages = {}
  for index = 1, 4 do
    local line = label(conversation, "", 10, -10 - ((index - 1) * 40), "GameFontHighlightSmall")
    line:SetPoint("TOPRIGHT", -10, -10 - ((index - 1) * 40))
    line:SetHeight(36)
    line:SetJustifyH("LEFT")
    line:SetJustifyV("TOP")
    line:SetWordWrap(true)
    ticketDetail.messages[index] = line
  end
  ticketDetail.empty = label(conversation, "No replies yet. New Discord and website messages appear after the next helper sync.", 10, -12, "GameFontHighlightSmall")
  ticketDetail.empty:SetTextColor(unpack(COLORS.muted))
  ticketDetail.empty:SetPoint("TOPRIGHT", -10, -12)
  ticketDetail.reply = input(ticketDetail, true, 415, 48)
  ticketDetail.reply:SetPoint("BOTTOMLEFT", 16, 28)
  ticketDetail.reply:SetMaxLetters(1000)
  ticketDetail.send = button(ticketDetail, "Queue reply", 112, function()
    local ok, reason = Virtuous:QueueTicketReply(selectedTicket, ticketDetail.reply:GetText())
    if ok then ticketDetail.reply:SetText("") else Virtuous:Notify(reason) end
  end)
  ticketDetail.send:SetPoint("BOTTOMRIGHT", -16, 40)
  ticketDetail.closed = label(ticketDetail, "This ticket is closed. Reopen it in Discord to answer.", 16, -14, "GameFontNormalSmall")
  ticketDetail.closed:SetTextColor(1, 0.35, 0.25)

  local ticketForm = CreateFrame("Frame", nil, tickets)
  ticketForm:SetAllPoints()
  window.ticketViews.form = ticketForm
  window.ticketButtons = {}
  window.ticketButtons.materials = button(ticketForm, "Materials", 100, function() showTicketMode("materials") end)
  window.ticketButtons.materials:SetPoint("TOPLEFT", 16, -52)
  window.ticketButtons.absence = button(ticketForm, "Absence", 100, function() showTicketMode("absence") end)
  window.ticketButtons.absence:SetPoint("TOPLEFT", 121, -52)
  window.ticketSections = {}

  local materials = CreateFrame("Frame", nil, ticketForm)
  materials:SetAllPoints()
  window.ticketSections.materials = materials
  materials.items = field(materials, "ITEMS AND QUANTITIES", 16, -86, 520, 32, true, 1000)
  materials.purpose = field(materials, "WHAT ARE THEY FOR?", 16, -136, 520, 32, true, 1000)
  materials.bis = field(materials, "BIS / REFERENCE (OPTIONAL)", 16, -186, 520, 24, false, 1000)
  materials.notes = field(materials, "NOTES (OPTIONAL)", 16, -226, 520, 24, false, 1000)
  local materialSubmit = button(materials, "Queue request", 126, function()
    local ok, reason = Virtuous:QueueMaterialTicket(materials.items:GetText(), materials.purpose:GetText(), materials.bis:GetText(), materials.notes:GetText())
    if ok then
      materials.items:SetText(""); materials.purpose:SetText(""); materials.bis:SetText(""); materials.notes:SetText("")
      showTicketView("overview")
    else Virtuous:Notify(reason) end
  end)
  materialSubmit:SetPoint("TOPRIGHT", -16, -266)

  local absence = CreateFrame("Frame", nil, ticketForm)
  absence:SetAllPoints()
  window.ticketSections.absence = absence
  absence.firstDate = field(absence, "FIRST DAY (YYYY-MM-DD)", 16, -92, 250, 26, false, 10)
  absence.lastDate = field(absence, "LAST DAY (YYYY-MM-DD)", 286, -92, 250, 26, false, 10)
  absence.reason = field(absence, "REASON", 16, -142, 520, 66, true, 1000)
  local absenceSubmit = button(absence, "Queue absence", 126, function()
    local ok, reason = Virtuous:QueueAbsenceTicket(absence.firstDate:GetText(), absence.lastDate:GetText(), absence.reason:GetText())
    if ok then
      absence.firstDate:SetText(""); absence.lastDate:SetText(""); absence.reason:SetText("")
      showTicketView("overview")
    else Virtuous:Notify(reason) end
  end)
  absenceSubmit:SetPoint("TOPRIGHT", -16, -232)

  local raids = window.pages.raids
  label(raids, "Raid signups", 16, -7, "GameFontNormalLarge")
  local raidHelp = label(raids, "Upcoming raids are filtered by your database-assigned teams. Your assigned Main is used for signup.", 16, -30, "GameFontHighlightSmall")
  raidHelp:SetTextColor(unpack(COLORS.muted))
  raids.feral = CreateFrame("Frame", nil, raids)
  raids.feral:SetSize(226, 24)
  raids.feral:SetPoint("TOPRIGHT", -16, -5)
  label(raids.feral, "Feral role:", 0, -6, "GameFontNormalSmall")
  local tank = button(raids.feral, "Tank", 58, function() feralRole = "Tank"; Virtuous:Notify("Feral role set to Tank.") end)
  tank:SetPoint("LEFT", 70, 0)
  local melee = button(raids.feral, "Melee", 58, function() feralRole = "Melee"; Virtuous:Notify("Feral role set to Melee.") end)
  melee:SetPoint("LEFT", 133, 0)
  raids.empty = label(raids, "No upcoming raids were delivered by the last sync.", 28, -104, "GameFontHighlight")
  raids.empty:SetTextColor(unpack(COLORS.muted))
  raids.rows = {}
  for index = 1, 3 do
    local row = CreateFrame("Frame", nil, raids, "BackdropTemplate")
    row:SetPoint("TOPLEFT", 16, -62 - ((index - 1) * 88))
    row:SetPoint("TOPRIGHT", raids, "TOPRIGHT", -16, -62 - ((index - 1) * 88))
    row:SetHeight(82)
    applyInset(row)
    row.title = label(row, "", 12, -8, "GameFontHighlight")
    row.team = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.team:SetPoint("TOPRIGHT", -12, -9)
    row.team:SetTextColor(unpack(COLORS.gold))
    row.meta = label(row, "", 12, -29, "GameFontNormalSmall")
    row.meta:SetTextColor(unpack(COLORS.muted))
    row.character = label(row, "", 12, -49, "GameFontHighlightSmall")
    row.roster = label(row, "", 245, -49, "GameFontHighlightSmall")
    row.roster:SetWidth(230)
    row.roster:SetJustifyH("LEFT")
    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.status:SetPoint("BOTTOMRIGHT", -101, 12)
    row.status:SetTextColor(unpack(COLORS.green))
    row.action = button(row, "Sign up", 82, function()
      local action = row.raid and row.raid.mySignup and "withdraw" or "signup"
      local ok, reason = Virtuous:QueueRaidSignup(row.raid, action, feralRole)
      if not ok then Virtuous:Notify(reason) end
    end)
    row.action:SetPoint("BOTTOMRIGHT", -10, 8)
    raids.rows[index] = row
  end

  window:Hide()
  showTicketView("overview")
  self:Refresh()
  return true
end

function Virtuous:Toggle()
  if not self:CreateWindow() then self:Notify("The Guild & Communities window is not available in this client."); return end
  local guildFrame = window:GetParent()
  if not guildFrame:IsShown() and ToggleGuildFrame then ToggleGuildFrame() end
  showPage(activePage)
end

SLASH_VIRTUOUS1 = "/virtuous"
SLASH_VIRTUOUS2 = "/vt"
SlashCmdList.VIRTUOUS = function() Virtuous:Toggle() end
