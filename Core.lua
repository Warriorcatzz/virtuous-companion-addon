local addonName, Virtuous = ...
_G.Virtuous = Virtuous

local PROTOCOL = 1
local MAX_OUTBOX = 100

local function now()
  return time and time() or 0
end

local function trimmed(value)
  return strtrim(tostring(value or ""))
end

local function playerIdentity()
  local name, realm = UnitName("player")
  if GetNormalizedRealmName then realm = GetNormalizedRealmName() or realm end
  return {
    guid = UnitGUID("player"),
    name = name,
    realm = realm or "",
    faction = UnitFactionGroup and UnitFactionGroup("player") or nil,
  }
end

local function makeId()
  VirtuousAddonDB.sequence = (VirtuousAddonDB.sequence or 0) + 1
  local guid = (UnitGUID("player") or "unknown"):gsub("[^%w%-]", "")
  return table.concat({ guid, tostring(now()), tostring(VirtuousAddonDB.sequence) }, ":")
end

function Virtuous:InitializeDatabase()
  if type(VirtuousAddonDB) ~= "table" then VirtuousAddonDB = {} end
  VirtuousAddonDB.protocol = PROTOCOL
  VirtuousAddonDB.outbox = type(VirtuousAddonDB.outbox) == "table" and VirtuousAddonDB.outbox or {}
  VirtuousAddonDB.tickets = type(VirtuousAddonDB.tickets) == "table" and VirtuousAddonDB.tickets or {}
  VirtuousAddonDB.raids = type(VirtuousAddonDB.raids) == "table" and VirtuousAddonDB.raids or {}
  VirtuousAddonDB.characters = type(VirtuousAddonDB.characters) == "table" and VirtuousAddonDB.characters or {}
  VirtuousAddonDB.discordRoster = type(VirtuousAddonDB.discordRoster) == "table" and VirtuousAddonDB.discordRoster or {}
  VirtuousAddonDB.officerTools = type(VirtuousAddonDB.officerTools) == "table" and VirtuousAddonDB.officerTools or { authorized = false, entries = {} }
  VirtuousAddonDB.notices = type(VirtuousAddonDB.notices) == "table" and VirtuousAddonDB.notices or {}
  VirtuousAddonDB.sequence = tonumber(VirtuousAddonDB.sequence) or 0
  VirtuousAddonDB.character = playerIdentity()
end

function Virtuous:CurrentCharacter()
  local player = UnitName("player")
  if not player then return nil end
  for _, character in ipairs(VirtuousAddonDB.characters or {}) do
    if tostring(character.wowName or character.name or ""):lower() == tostring(player):lower() then return character end
  end
  return nil
end

function Virtuous:QueueEvent(eventType, payload)
  if #VirtuousAddonDB.outbox >= MAX_OUTBOX then return false, "The local queue is full. Use /reload so Virtuous Companion can upload it, then reload again after sync." end
  local event = {
    id = makeId(),
    type = eventType,
    createdAt = now(),
    character = playerIdentity(),
    payload = payload,
  }
  table.insert(VirtuousAddonDB.outbox, event)
  VirtuousAddonDB.lastQueuedAt = now()
  self:Notify("Action queued. Use /reload to export it; Virtuous Companion uploads it automatically.")
  if self.Refresh then self:Refresh() end
  return true, event.id
end

function Virtuous:QueueMaterialTicket(materials, purpose, bis, notes)
  materials, purpose, bis, notes = trimmed(materials), trimmed(purpose), trimmed(bis), trimmed(notes)
  if materials == "" then return false, "List the items and quantities you need." end
  if purpose == "" then return false, "Tell the guild bank what the materials are for." end
  if #materials > 1000 or #purpose > 1000 or #bis > 1000 or #notes > 1000 then return false, "Each field must be 1,000 characters or fewer." end
  local character = self:CurrentCharacter()
  if not character then return false, "Synchronise once and link this character on virtuous.dk first." end
  return self:QueueEvent("ticket.material.create", {
    characterId = character.id,
    materials = materials,
    purpose = purpose,
    bis = bis,
    notes = notes,
  })
end

function Virtuous:QueueAbsenceTicket(firstDate, lastDate, reason)
  firstDate, lastDate, reason = trimmed(firstDate), trimmed(lastDate), trimmed(reason)
  if not firstDate:match("^%d%d%d%d%-%d%d%-%d%d$") or not lastDate:match("^%d%d%d%d%-%d%d%-%d%d$") then return false, "Use YYYY-MM-DD for both dates." end
  if lastDate < firstDate then return false, "The end date must be on or after the start date." end
  if reason == "" then return false, "Add a reason for the absence." end
  if #reason > 1000 then return false, "The reason must be 1,000 characters or fewer." end
  return self:QueueEvent("ticket.absence.create", { firstDate = firstDate, lastDate = lastDate, reason = reason })
end

function Virtuous:QueueTicketReply(ticket, message)
  message = trimmed(message)
  if type(ticket) ~= "table" or not ticket.id or (ticket.kind ~= "material" and ticket.kind ~= "absence") then return false, "That ticket is not available." end
  if message == "" then return false, "Write a reply first." end
  if #message > 1000 then return false, "The reply must be 1,000 characters or fewer." end
  return self:QueueEvent("ticket.reply", { ticketKind = ticket.kind, ticketId = tostring(ticket.id), message = message })
end

function Virtuous:QueueRaidSignup(raid, action, raidRole)
  if type(raid) ~= "table" or not raid.id then return false, "That raid is not available." end
  for _, event in ipairs(VirtuousAddonDB.outbox or {}) do
    if event.type == "raid.signup" and event.payload and tostring(event.payload.eventId) == tostring(raid.id) then
      return false, "A signup change for this raid is already waiting to synchronise."
    end
  end
  if action == "withdraw" then return self:QueueEvent("raid.signup", { eventId = raid.id, action = "withdraw" }) end
  if not raid.signupCharacterId then return false, "No Main character is assigned to this raid team in the database." end
  local feral = raid.signupClassName == "Druid" and raid.signupSpec == "Feral Combat"
  if feral and raidRole ~= "Tank" and raidRole ~= "Melee" then return false, "Choose Tank or Melee for your Feral character." end
  return self:QueueEvent("raid.signup", {
    eventId = raid.id,
    action = "signup",
    characterId = raid.signupCharacterId,
    raidRole = feral and raidRole or "",
  })
end

function Virtuous:Notify(message)
  local prefix = "|cffa873ffVirtuous Companion:|r "
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(prefix .. tostring(message)) end
end

function Virtuous:PendingCount()
  return VirtuousAddonDB and #VirtuousAddonDB.outbox or 0
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, arg)
  if event == "ADDON_LOADED" and arg == addonName then
    Virtuous:InitializeDatabase()
    if Virtuous.ConsumeDesktopInbox then Virtuous:ConsumeDesktopInbox() end
  elseif event == "PLAYER_LOGIN" then
    VirtuousAddonDB.character = playerIdentity()
    if Virtuous.CreateWindow then Virtuous:CreateWindow() end
  end
end)
