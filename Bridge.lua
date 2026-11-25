local _, Virtuous = ...

local function asSet(values)
  local result = {}
  if type(values) == "table" then
    for _, value in pairs(values) do result[tostring(value)] = true end
  end
  return result
end

function Virtuous:ConsumeDesktopInbox()
  if type(VirtuousDesktopInbox) ~= "table" or VirtuousDesktopInbox.protocol ~= 1 then return end
  if VirtuousDesktopInbox.generatedAt ~= nil and VirtuousAddonDB.lastSyncAt == VirtuousDesktopInbox.generatedAt then
    VirtuousDesktopInbox = nil
    return
  end
  local acknowledged = asSet(VirtuousDesktopInbox.acknowledgedEventIds)
  local remaining = {}
  for _, event in ipairs(VirtuousAddonDB.outbox) do
    if not acknowledged[tostring(event.id)] then table.insert(remaining, event) end
  end
  VirtuousAddonDB.outbox = remaining
  if type(VirtuousDesktopInbox.tickets) == "table" then VirtuousAddonDB.tickets = VirtuousDesktopInbox.tickets end
  if type(VirtuousDesktopInbox.raids) == "table" then VirtuousAddonDB.raids = VirtuousDesktopInbox.raids end
  if type(VirtuousDesktopInbox.characters) == "table" then VirtuousAddonDB.characters = VirtuousDesktopInbox.characters end
  -- Replace the whole directory, including an empty snapshot, to clear old links.
  VirtuousAddonDB.discordRoster = type(VirtuousDesktopInbox.discordRoster) == "table" and VirtuousDesktopInbox.discordRoster or {}
  if self.RebuildDiscordRoster then self:RebuildDiscordRoster() end
  VirtuousAddonDB.officerTools = type(VirtuousDesktopInbox.officerTools) == "table" and VirtuousDesktopInbox.officerTools or { authorized = false, entries = {} }
  if VirtuousDesktopInbox.cursor ~= nil then VirtuousAddonDB.cursor = VirtuousDesktopInbox.cursor end
  VirtuousAddonDB.lastSyncAt = VirtuousDesktopInbox.generatedAt
  VirtuousAddonDB.notices = type(VirtuousDesktopInbox.notices) == "table" and VirtuousDesktopInbox.notices or {}
  VirtuousDesktopInbox = nil
  self:Notify(string.format("Sync imported: %d ticket(s), %d raid(s), %d action(s) still pending.", #VirtuousAddonDB.tickets, #VirtuousAddonDB.raids, #VirtuousAddonDB.outbox))
  for index, notice in ipairs(VirtuousAddonDB.notices) do
    if index > 3 then break end
    self:Notify("Sync notice: " .. tostring(notice))
  end
end

function Virtuous:SyncSummary()
  local last = VirtuousAddonDB.lastSyncAt or "Never"
  return string.format("Last helper sync: %s", tostring(last))
end
