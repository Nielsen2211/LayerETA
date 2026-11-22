-- LayerETA: viser hvilket lag du er paa, og skifter lag med et klik. Ingen hosting.
-- Samme stil som LevelETA og GoldETA. Koden er skrevet fra bunden.
--
-- Saadan virker et skift i WoW Forever: du skifter lag ved at joine en gruppe, hvor lederen staar i
-- samme zone paa et andet lag. De fleste hosts koerer LayerSwap (eller Bulo / Simple Layer, som taler
-- samme "sprog"), saa LayerETA sender en anmodning i det format, de svarer paa:
--   * laget laeses fra en NPC's GUID: Creature-0-<server>-<instans>-<zoneUID>-... Laget er <server>,
--     og id'et der sendes er "<server>-<zoneUID>"
--   * LayerETA sender aldrig selv beskeder til nogen. Anmodningen laegges i din chatboks til layer-kanalen,
--     og du sender den selv med Enter:
--       inv layer <LS <zone map id> not <dit lag-id> <x>,<y>>
--   * en host paa et andet lag inviterer. En host paa dit eget lag svarer "same", andre brugere "heard ..."
--   * efter joinet flytter spillet dig (SHARD_TRANSFER), og LayerETA forlader gruppen igen lidt efter
local ADDON = "LayerETA"
local PATH = "Interface\\AddOns\\LayerETA\\"
local TEX = PATH .. "Textures\\"
local F_SEMI = PATH .. "Fonts\\Inter-SemiBold.ttf"
local F_BOLD = PATH .. "Fonts\\Inter-Bold.ttf"

local PREFIX = "LayerSwap"   -- det prefix hosts lytter paa
local BOOK_TTL = 7 * 86400   -- kendte hosts huskes en uge og spoerges foerst
local ASK_TTL = 60           -- saa laenge venter et klik paa en invite
local NO_MOVE_LEAVE = 8      -- joinet, men ikke flyttet efter saa mange sekunder: forlad gruppen (no move used)
local COOLDOWN = 5
local DB

local LOC = {
  en = { movedNew = "Moved to another layer", left = "%d of 10 swaps left this hour", wait = "No swaps left: wait %s", fewLeft = "%d swaps left this hour.", blindSub = "Layers can't be told apart on Forever", layer = "Layer", unknown = "Target an NPC", swap = "Swap", stop = "Stop", back = "Back to %s", seen = "Layers here", goingTo = "Looking for %s",
    needNpc = "Target or mouse over an NPC first, so your layer is known.", inGroup = "You are in a group. Leave it to swap layer.",
    inInstance = "No layers in here. Swap layer works in the open world.", pressEnter = "Press Enter to send your request", sent = "Asking, waiting for an invite", joinChan = "Join the layer channel first: type /join layer",
    asking = "Asking %d players", heard = "Waiting, %d heard", nobody = "Found nobody to ask. Try again in a moment.", noSearch = "The player search is not available on this client.", asked = "Asked %d players",
    askedAll = "Everyone here was asked already. Click again to ask more.", noAnswer = "No host answered. Try again in a moment.",
    invited = "Invited by %s", joined = "Joined, waiting for the move", moved = "Moved to %s", leaving = "Leaving in %ds",
    notMoved = "%s is on your layer. Left the group.", whoFail = "The player search did not start. Try again in a moment.",
    stopped = "Stopped", hint = "Click: open or close  ·  Drag: move", acceptHint = "Accept the invite from %s", locked = "Window locked", unlocked = "Window unlocked",
    help = "/leta: show or hide  ·  /leta swap  ·  /leta lock  ·  /leta debug  ·  /leta leave <seconds>  ·  /leta da|en" },
  da = { movedNew = "Flyttet til et andet lag", left = "%d af 10 skift tilbage denne time", wait = "Ingen skift tilbage: vent %s", fewLeft = "%d skift tilbage denne time.", blindSub = "Lag kan ikke skelnes på Forever", layer = "Lag", unknown = "Målret en NPC", swap = "Skift", stop = "Stop", back = "Tilbage til %s", seen = "Lag her", goingTo = "Leder efter %s",
    needNpc = "Målret eller hold musen over en NPC først, så dit lag er kendt.", inGroup = "Du er i en gruppe. Forlad den for at skifte lag.",
    inInstance = "Ingen lag herinde. Skift lag virker ude i verden.", pressEnter = "Tryk Enter for at sende din anmodning", sent = "Spørger, venter på en invitation", joinChan = "Gå ind i layer-kanalen først: skriv /join layer",
    asking = "Spørger %d spillere", heard = "Venter, %d har hørt", nobody = "Fandt ingen at spørge. Prøv igen om lidt.", noSearch = "Spillerssøgningen virker ikke på denne klient.", asked = "Spurgte %d spillere",
    askedAll = "Alle her er allerede spurgt. Klik igen for at spørge flere.", noAnswer = "Ingen host svarede. Prøv igen om lidt.",
    invited = "Inviteret af %s", joined = "Joinet, venter på skiftet", moved = "Flyttet til %s", leaving = "Forlader om %ds",
    notMoved = "%s er på dit lag. Forlod gruppen.", whoFail = "Søgningen startede ikke. Prøv igen om lidt.",
    stopped = "Stoppet", hint = "Klik: åbn eller luk  ·  Træk: flyt", acceptHint = "Acceptér invitationen fra %s", locked = "Vinduet er låst", unlocked = "Vinduet er låst op",
    help = "/leta: vis eller skjul  ·  /leta swap  ·  /leta lock  ·  /leta debug  ·  /leta leave <sekunder>  ·  /leta da|en" },
}
local function T(k) return (LOC[(DB and DB.lang) or "en"] or LOC.en)[k] end

local defaults = { lang = "en", open = false, hidden = false, locked = false, leaveDelay = 4, scale = 1 }

-- Forever skjuler nogle vaerdier for addons ("secret values"): dem roerer vi ikke
local function secret(v) return type(issecretvalue) == "function" and issecretvalue(v) or false end
local function str(v) return not secret(v) and type(v) == "string" and v ~= "" end
local function short(name) return str(name) and (string.match(name, "^([^%-]+)") or name) or nil end

-- ---------- zone og lag ----------
local ZONE_TYPE = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
local function zoneMap()  -- zonens map id (ens for alle klienter); en hule eller bygning taeller som zonen
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo) then return nil end
  local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
  if not ok or secret(id) or type(id) ~= "number" then return nil end
  for _ = 1, 6 do
    local okI, info = pcall(C_Map.GetMapInfo, id)
    if not okI or type(info) ~= "table" then return id end
    if info.mapType == ZONE_TYPE or not info.parentMapID or info.parentMapID == 0 then return id end
    if (info.mapType or 0) < ZONE_TYPE then return id end
    id = info.parentMapID
  end
  return id
end
local function mapPos(zone)
  if not (zone and C_Map and C_Map.GetPlayerMapPosition) then return nil end
  local ok, pos = pcall(C_Map.GetPlayerMapPosition, zone, "player")
  if not ok or secret(pos) or type(pos) ~= "table" then return nil end
  local x, y = pos.x, pos.y
  if type(pos.GetXY) == "function" then local okX, a, b = pcall(pos.GetXY, pos); if okX then x, y = a, b end end
  if type(x) == "number" and type(y) == "number" and x > 0 and y > 0 then return x, y end
end

local lastShard    -- when the game last said it moved us (SHARD_TRANSFER)
local blind = true -- true: the game hides which layer you are on (Forever since 20 Nov 2026); false once a GUID shows one
local target       -- laget du vil tilbage til, naar du klikker en linje i listen
local cur          -- {id = "6843-8", key = "6843", at = tid}
local swap         -- det igangvaerende skift
local refresh
-- Lag faar et bogstav i den raekkefoelge, du ser dem i en zone (A, B, C ...). Det er kun dit eget navn for
-- laget: andre addons bruger deres egne bogstaver, saa server-nummeret vises ved siden af.
local function letter(key)
  if not (DB and key) then return "?" end
  local zone = tostring(zoneMap() or 0)
  DB.letters = DB.letters or {}
  local z = DB.letters[zone]
  if not z or (z.day ~= date("%j")) then z = { n = 0, day = date("%j"), k = {} }; DB.letters[zone] = z end  -- nye bogstaver hver dag
  if not z.k[key] then z.n = z.n + 1; z.k[key] = z.n end
  local n = z.k[key]
  return n <= 26 and string.char(64 + n) or tostring(n)
end
-- historik: de lag du har vaeret paa i denne zone, med klokkeslet for skiftet
local HIST_MAX = 6
local function noteLeft(key, id)   -- kaldes naar du forlader et lag: det er dét lag, der kommer paa listen
  if not (DB and key) then return end
  local zone = tostring(zoneMap() or 0)
  DB.hist = DB.hist or {}
  local h = DB.hist[zone]
  if type(h) ~= "table" then h = {}; DB.hist[zone] = h end
  for i = #h, 1, -1 do if type(h[i]) ~= "table" or h[i].key == key then table.remove(h, i) end end
  table.insert(h, 1, { key = key, id = id, t = time() })   -- tidspunktet er, da du forlod laget
  for i = #h, HIST_MAX + 1, -1 do h[i] = nil end
end
local function histFor()
  if not DB then return {} end
  local z = DB.hist and DB.hist[tostring(zoneMap() or 0)]
  return type(z) == "table" and z or {}
end

local function histId(key)   -- hele id'et ("6843-1753") for et lag i listen, som LayerSwap's "want" skal bruge
  for _, item in ipairs(histFor()) do
    if type(item) == "table" and item.key == key and type(item.id) == "string" then return item.id end
  end
end

local function layerKey(id) return type(id) == "string" and (string.match(id, "^(%d+)%-") or id) or nil end

local function setStatus(text, secs)
  DB._status, DB._statusUntil = text, secs and (GetTime() + secs) or nil
  if refresh then refresh() end
end

local onMoved
local swapsLeft, waitText
local function observe(unit)
  if not UnitGUID then return end
  local ok, guid = pcall(UnitGUID, unit)
  if not ok or not str(guid) then return end
  local kind, _, server, _, zoneUID = strsplit("-", guid)
  if (kind ~= "Creature" and kind ~= "Vehicle") or not server or not zoneUID then return end
  -- Forever, since the hotfix of 20 November 2026: the game hides the realm in every GUID (0), so no
  -- addon can tell one layer from another any more. Then LayerETA shows no layer and asks for none.
  if server == "0" or server == "" then blind = true; return end
  blind = false
  if type(UnitPlayerControlled) == "function" then  -- totems og pets baerer id'et fra det sted, de blev lavet
    local okP, pc = pcall(UnitPlayerControlled, unit)
    if okP and not secret(pc) and pc == true then return end
  end
  local id = server .. "-" .. zoneUID
  local key = layerKey(id)
  local old, oldId = cur and cur.key, cur and cur.id
  cur = { id = id, key = key, at = GetTime() }
  if old ~= key then
    if old then noteLeft(old, oldId) end
    if swap and swap.joinedAt and swap.fromKey and key ~= swap.fromKey then onMoved() end
    refresh()
  end
end

-- ---------- ten moves an hour ----------
-- The game moves a character to another layer at most ten times an hour on Forever. LayerETA counts
-- the moves of each character (also across a login), and once they are used up the button waits.
local HOUR, PER_HOUR = 3600, 10
local function charKey()
  local n, r = UnitName and UnitName("player"), GetRealmName and GetRealmName()
  return (str(n) and n or "?") .. "-" .. (str(r) and r or "")
end
local function moves()
  DB.moves = DB.moves or {}
  local list = DB.moves[charKey()] or {}
  local now, keep = time(), {}
  for _, t in ipairs(list) do if now - t < HOUR then keep[#keep + 1] = t end end
  DB.moves[charKey()] = keep
  return keep
end
swapsLeft = function() return math.max(0, PER_HOUR - #moves()) end
waitText = function()
  local list = moves()
  if #list < PER_HOUR then return "0:00" end
  local secs = math.max(0, HOUR - (time() - list[1]))
  return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end
local function noteMove()
  local list = moves()
  list[#list + 1] = time()
  local left = swapsLeft()
  if left == 3 then print("|cffffd24aLayerETA|r: " .. string.format(T("fewLeft"), left)) end
end

-- ---------- huskeliste: hvem er spurgt, og hvem er hosts ----------
local function prune()
  local now = time()
  for n, e in pairs(DB.book) do if type(e) ~= "table" or now - (e.at or 0) > BOOK_TTL then DB.book[n] = nil end end
end

-- ---------- gruppen ----------
local function leaveGroup()
  local leave = (C_PartyInfo and C_PartyInfo.LeaveParty) or LeaveParty
  if leave and IsInGroup and IsInGroup() then pcall(leave) end
end

local function endSwap(text, secs)
  swap = nil
  if Who and Who.pending then Who.pending = nil end
  setStatus(text, secs or 12)
end

onMoved = function()
  if not swap or swap.moved then return end
  noteMove()
  if target and cur and cur.key ~= target then
    -- flyttet, men ikke til det lag du ville tilbage til: bliv staaende og lad brugeren klikke igen
    swap.moved = true
    swap.leaveAt = GetTime() + math.max(0, DB.leaveDelay or 4)
    refresh()
    return
  end
  if target and cur and cur.key == target then target = nil end
  swap.moved = true
  local delay = math.max(0, DB.leaveDelay or 4)
  swap.leaveAt = GetTime() + delay
  refresh()
end


-- ---------- soegningen: find spillerne i zonen, og hvisk anmodningen til dem ----------
-- Saadan goer LayerSwap paa Forever: den skriver ikke i layer-kanalen, men laver en who-soegning
-- efter spillerne i din zone og sender anmodningen som en skjult addon-besked til hver af dem.
-- Spillets egen who-liste (group finder) aabner sig selv, naar et svar kommer ind, saa den bliver
-- koblet fra imens og koblet til igen bagefter. Du ser den aldrig.
local Who = { WAIT = 6, BURST = 8, BURST_WAIT = 1, ROUNDS = 25, MAX = 49, LATE = 30, sentTo = {}, muted = {} }
Who.LISTS = { "LFGWhoListFrame", "FriendsFrame", "WhoFrame" }

local function zoneName(map)
  if not (map and C_Map and C_Map.GetMapInfo) then return nil end
  local ok, info = pcall(C_Map.GetMapInfo, map)
  local name = ok and type(info) == "table" and info.name
  return str(name) and name or nil
end

local function me()
  local n = UnitName and UnitName("player")
  return str(n) and n or nil
end

function Who.ready()
  local f = C_FriendList
  return type(f) == "table" and type(f.SendWho) == "function" and type(f.GetNumWhoResults) == "function"
    and type(f.GetWhoInfo) == "function" and C_ChatInfo ~= nil and type(C_ChatInfo.SendAddonMessage) == "function"
end

function Who.hush()   -- tag WHO_LIST_UPDATE fra spillets egne lister, saa de ikke popper op
  for _, name in ipairs(Who.LISTS) do
    local fr = _G[name]
    if type(fr) == "table" and not Who.muted[name] and type(fr.IsEventRegistered) == "function" then
      local okR, reg = pcall(fr.IsEventRegistered, fr, "WHO_LIST_UPDATE")
      local okV, seen = pcall(fr.IsVisible, fr)
      -- har du selv listen aabne, roerer vi den ikke
      if okR and reg == true and okV and seen ~= true and pcall(fr.UnregisterEvent, fr, "WHO_LIST_UPDATE") then
        Who.muted[name] = fr
      end
    end
  end
end

function Who.release(p)
  if p and Who.flight ~= p then return end
  Who.flight = nil
  for name, fr in pairs(Who.muted) do pcall(fr.RegisterEvent, fr, "WHO_LIST_UPDATE"); Who.muted[name] = nil end
  if C_FriendList and type(C_FriendList.SetWhoToUi) == "function" then
    for _, name in ipairs(Who.LISTS) do   -- har du selv en liste aabne, skal svarene blive der
      local fr = _G[name]
      if type(fr) == "table" and type(fr.IsVisible) == "function" and select(2, pcall(fr.IsVisible, fr)) == true then return end
    end
    pcall(C_FriendList.SetWhoToUi, false)
  end
end

function Who.ask(line)
  if not Who.ready() then return false end
  local map = zoneMap()
  local zname = zoneName(map)
  local now = GetTime()
  for name, at in pairs(Who.sentTo) do if now - at > 60 then Who.sentTo[name] = nil end end
  local p = { line = line, at = now, zone = zname, sent = 0, rounds = 0, queue = {} }
  Who.pending, Who.flight = p, p
  Who.hush()
  if type(C_FriendList.SetWhoToUi) == "function" then pcall(C_FriendList.SetWhoToUi, true) end
  local origin = (Enum and Enum.SocialWhoOrigin and Enum.SocialWhoOrigin.Social) or 1
  local text = zname and ((str(WHO_TAG_ZONE) and WHO_TAG_ZONE or "z-") .. '"' .. zname .. '"') or ""
  local ok = false
  if map and not Who.noMap then
    ok = pcall(C_FriendList.SendWho, text, origin, { classIDs = {}, raceIDs = {}, uiMapIDs = { map } })
    if not ok then Who.noMap = true end   -- klienten tager ikke kort-filteret: zonens navn alene herefter
  end
  if not ok then ok = pcall(C_FriendList.SendWho, text, origin) end
  if not ok then Who.pending = nil; Who.release(p); return false end
  if C_Timer and C_Timer.After then C_Timer.After(Who.LATE, function() Who.release(p) end) end
  return true
end

function Who.send(p)   -- en byge hvisk ad gangen: klienten spaerrer, hvis vi sender for mange paa en gang
  if Who.pending ~= p then return end
  -- er du allerede inviteret, stopper vi. Ellers inviterer de naeste hosts forgaeves.
  if not swap or swap.inviter then Who.pending = nil; return end
  p.rounds = p.rounds + 1
  local n = 0
  while #p.queue > 0 and n < Who.BURST do
    local name = p.queue[1]
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, p.line, "WHISPER", name)
    if ok and not secret(res) and res == 3 then break end   -- 3: for hurtigt, navnet venter til naeste runde
    table.remove(p.queue, 1)
    n = n + 1
    if ok and not secret(res) and res == 0 then
      p.sent = p.sent + 1
      Who.sentTo[name] = GetTime()
      if swap then swap.asked = p.sent end
    end
  end
  if swap then refresh() end
  if #p.queue > 0 and p.rounds < Who.ROUNDS and C_Timer and C_Timer.After then
    C_Timer.After(Who.BURST_WAIT, function() Who.send(p) end)
  else
    Who.pending = nil
  end
end

function Who.results()
  local p = Who.pending
  if not p or p.names then Who.release(Who.flight); return end
  local okN, n = pcall(C_FriendList.GetNumWhoResults)
  if not okN or secret(n) or type(n) ~= "number" then n = 0 end
  local mine, here, far, seen = me(), {}, {}, {}
  for i = 1, math.min(n, Who.MAX) do
    local ok, info = pcall(C_FriendList.GetWhoInfo, i)
    local name = (ok and type(info) == "table" and not secret(info)) and info.fullName or nil
    if str(name) and not seen[name] then
      seen[name] = true
      if short(name) ~= mine and name ~= mine and not Who.sentTo[name] then
        local area = type(info) == "table" and info.area
        if p.zone and str(area) and area == p.zone then here[#here + 1] = name else far[#far + 1] = name end
      end
    end
  end
  Who.release(p)
  p.names = true
  -- kendte hosts foerst, saa dem i din egen zone, saa resten
  local book, rest = {}, {}
  for _, name in ipairs(here) do
    if DB.book and DB.book[short(name) or ""] then book[#book + 1] = name else rest[#rest + 1] = name end
  end
  for _, name in ipairs(book) do p.queue[#p.queue + 1] = name end
  for _, name in ipairs(rest) do p.queue[#p.queue + 1] = name end
  for _, name in ipairs(far) do p.queue[#p.queue + 1] = name end
  if #p.queue == 0 then Who.pending = nil; if swap then setStatus(T("nobody"), 8) end; return end
  Who.send(p)
end

-- ---------- klik: skift lag ----------
-- LayerETA sender aldrig selv noget til andre spillere. Knappen laegger anmodningen i din chatboks,
-- rettet mod layer-kanalen, og du sender den selv med Enter (eller dropper den med Escape).
local lastClick = -100
local function requestSwap()
  local now = GetTime()
  if swap then endSwap(T("stopped"), 5); return end  -- samme knap stopper
  if now - lastClick < COOLDOWN then return end
  if IsInInstance and select(1, IsInInstance()) then setStatus(T("inInstance"), 8); return end
  if IsInGroup and IsInGroup() then setStatus(T("inGroup"), 8); return end
  if swapsLeft() <= 0 then setStatus(string.format(T("wait"), waitText()), 8); return end
  if not Who.ready() then setStatus(T("noSearch"), 10); return end
  lastClick = now
  local zone = zoneMap()
  local parts = { "<LS" }
  if zone then parts[#parts + 1] = tostring(zone) end
  -- LayerSwap's eget format: "want <id>" beder om netop det lag, "not <id>" om alt andet end det.
  -- Flere "not" betyder, at en host paa et af dem springer dig over, saa du ikke lander samme sted igen.
  local want = target and histId(target) or nil
  if want then
    parts[#parts + 1] = "want " .. want
  elseif cur then
    parts[#parts + 1] = "not " .. cur.id
    for _, item in ipairs(histFor()) do
      if type(item) == "table" and type(item.id) == "string" and item.key ~= cur.key then
        parts[#parts + 1] = "not " .. item.id
      end
    end
  end
  local x, y = mapPos(zone)
  if zone and x then parts[#parts + 1] = string.format("%.1f,%.1f", x * 100, y * 100) end
  local line = "inv layer " .. table.concat(parts, " ") .. ">"

  -- Intet gaar i layer-kanalen. Anmodningen sendes som en skjult addon-besked til de spillere,
  -- soegningen finder i din zone, praecis som LayerSwap goer det.
  if not Who.ask(line) then setStatus(T("noSearch"), 10); return end

  local s = { at = now, zone = zone, fromKey = cur and cur.key, heard = 0 }
  swap = s
  refresh()
  C_Timer.After(ASK_TTL, function()
    if swap == s and not s.inviter then endSwap(T("noAnswer")) end
  end)
end

-- ---------- svar fra hosts ----------
local function onNote(text, sender)
  if not str(text) or not str(sender) then return end
  local name = short(sender)
  if text == "same" then  -- en host paa vores eget lag
    DB.book[name] = { at = time(), host = true }
    if swap then swap.heard = swap.heard + 1; refresh() end
  else
    local _, layer, _, flag = string.match(text, "^heard ([^|]*)|([^|]*)|([^|]*)|([^|]*)")
    if layer then
      DB.book[name] = { at = time(), host = flag == "h" or nil, layer = layer ~= "-" and layer or nil }
      if swap then swap.heard = swap.heard + 1; refresh() end
    end
  end
end

local function onInvite(name)
  local s = swap
  if not s or s.inviter or GetTime() - s.at > ASK_TTL + 30 then return end  -- kun invites vi selv har bedt om
  s.inviter = str(name) and name or "?"
  Who.pending = nil   -- stop de resterende hvisk: en host har taget den
  if str(name) then DB.book[short(name)] = { at = time(), host = true } end
  -- acceptér selv; kan klienten ikke det, beder vi dig trykke
  local ok = AcceptGroup and pcall(AcceptGroup)
  if ok then
    if StaticPopup_Hide then pcall(StaticPopup_Hide, "PARTY_INVITE") end
  else
    s.manual = true
  end
  refresh()
end

-- ---------- vindue ----------
local function fs(parent, font, size)
  local t = parent:CreateFontString(nil, "OVERLAY")
  t:SetFont(font, size, ""); t:SetShadowOffset(1, -1); t:SetShadowColor(0, 0, 0, 0.6)
  return t
end
local W = 150  -- samme bredde lukket og aaben; vinduet folder kun ud nedad
local f = CreateFrame("Frame", "LayerETAFrame", UIParent)
f:SetSize(W, 40); f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -220, -520)
f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true); f:RegisterForDrag("LeftButton")
if f.SetToplevel then f:SetToplevel(true) end
f:SetScript("OnDragStart", function(self) self._drag = true; if not DB.locked then self:StartMoving() end end)
f:SetScript("OnMouseUp", function(self, button)  -- klik folder ud, klik igen folder sammen
  if self._drag then self._drag = nil; return end
  if button == "LeftButton" and DB then DB.open = not DB.open; refresh() end
end)
f:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:AddLine("LayerETA", 1, 0.82, 0.3)
  GameTooltip:AddLine(T("hint"), 0.6, 0.6, 0.6); GameTooltip:Show()
end)
f:SetScript("OnLeave", function() GameTooltip:Hide() end)
f:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local l, t = self:GetLeft(), self:GetTop()
  if l and t then self:ClearAllPoints(); self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t); DB.point = { l, t } end
end)
do
  local function part(name, p1, p2)
    local t = f:CreateTexture(nil, "BACKGROUND")
    t:SetTexture(TEX .. name); t:SetTexCoord(0, 520 / 1024, 0, 40 / 64)
    return t
  end
  local top = part("PanelTop"); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(20)
  local bot = part("PanelBottom"); bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT"); bot:SetHeight(20)
  local mid = part("PanelMid"); mid:SetPoint("TOPLEFT", top, "BOTTOMLEFT"); mid:SetPoint("BOTTOMRIGHT", bot, "TOPRIGHT")
end
-- toppen (altid synlig): logo, "Layer A" og en linje under
-- Mark er logoet uden ring: ringen aeder for meget ved denne stoerrelse
local mIcon = f:CreateTexture(nil, "ARTWORK"); mIcon:SetSize(26, 26); mIcon:SetPoint("TOPLEFT", 8, -8); mIcon:SetTexture(TEX .. "Mark")
local mTop = fs(f, F_BOLD, 12); mTop:SetPoint("TOPLEFT", 40, -8); mTop:SetTextColor(0.91, 0.92, 0.94)
local mSub = fs(f, F_SEMI, 10); mSub:SetPoint("TOPLEFT", 40, -23); mSub:SetTextColor(0.55, 0.58, 0.64)
mSub:SetWidth(W - 48); mSub:SetJustifyH("LEFT"); if mSub.SetWordWrap then mSub:SetWordWrap(false) end

-- det udfoldede: liste over lag i denne zone, status og en lille knap
local sep = f:CreateTexture(nil, "ARTWORK"); sep:SetHeight(1); sep:SetColorTexture(1, 1, 1, 0.06)
sep:SetPoint("TOPLEFT", 12, -40); sep:SetPoint("TOPRIGHT", -12, -40)
local hLabel = fs(f, F_SEMI, 9); hLabel:SetPoint("TOPLEFT", 12, -46); hLabel:SetTextColor(0.42, 0.45, 0.52)

-- en linje pr lag: bogstavet til venstre, klokkeslettet til hoejre. Klik paa en linje leder efter det lag igen.
local ROW_H, rows = 15, {}
for i = 1, HIST_MAX do
  local r = CreateFrame("Button", nil, f)
  r:SetHeight(ROW_H); r:SetPoint("TOPLEFT", 10, -(58 + (i - 1) * ROW_H)); r:SetPoint("TOPRIGHT", -10, -(58 + (i - 1) * ROW_H))
  local hl = r:CreateTexture(nil, "BACKGROUND"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.05); hl:Hide()
  local lt = fs(r, F_BOLD, 11); lt:SetPoint("LEFT", 4, 0)
  local tt = fs(r, F_SEMI, 10); tt:SetPoint("RIGHT", -2, 0); tt:SetTextColor(0.45, 0.48, 0.55)
  r.hl, r.lt, r.tt = hl, lt, tt
  r:SetScript("OnEnter", function(self) self.hl:Show() end)
  r:SetScript("OnLeave", function(self) self.hl:Hide() end)
  r:SetScript("OnClick", function(self)
    if not self.key or (cur and self.key == cur.key) then return end
    if target == self.key and not swap then target = nil; refresh(); return end
    target = self.key
    if swap then endSwap(nil, 1) end
    requestSwap()
  end)
  rows[i] = r
end

local status = fs(f, F_SEMI, 10); status:SetPoint("TOPLEFT", 12, -47); status:SetPoint("TOPRIGHT", -12, -47)
status:SetJustifyH("LEFT"); status:SetTextColor(0.75, 0.78, 0.84)
if status.SetWordWrap then status:SetWordWrap(true) end

-- knappen: en lille fyldt guld-pille med moerk tekst. Lysere under musen, trykkes lidt ned ved klik,
-- og bliver graa ("Stop"), mens et skift er i gang.
local BTN_W = 86
local btn = CreateFrame("Button", nil, f)
btn:SetSize(BTN_W, 22); btn:SetPoint("BOTTOM", 0, 10)
local bbg = btn:CreateTexture(nil, "BACKGROUND"); bbg:SetAllPoints(); bbg:SetTexture(TEX .. "Button"); bbg:SetTexCoord(0, 240 / 256, 0, 48 / 64)
local btxt = btn:CreateFontString(nil, "OVERLAY"); btxt:SetFont(F_BOLD, 11, ""); btxt:SetPoint("CENTER")
local function paintBtn()
  local stop, over = btn.stop, btn.over
  if stop then
    bbg:SetVertexColor(over and 0.34 or 0.26, over and 0.36 or 0.28, over and 0.42 or 0.33)
    btxt:SetTextColor(0.91, 0.92, 0.94); btxt:SetShadowOffset(1, -1); btxt:SetShadowColor(0, 0, 0, 0.6)
  else
    bbg:SetVertexColor(1, over and 0.88 or 0.8, over and 0.5 or 0.33)
    btxt:SetTextColor(0.1, 0.08, 0.03); btxt:SetShadowOffset(0, 0)
  end
end
btn:SetScript("OnEnter", function() btn.over = true; paintBtn() end)
btn:SetScript("OnLeave", function() btn.over = false; paintBtn(); btxt:SetPoint("CENTER", 0, 0) end)
btn:SetScript("OnMouseDown", function() btxt:SetPoint("CENTER", 0, -1) end)
btn:SetScript("OnMouseUp", function() btxt:SetPoint("CENTER", 0, 0) end)
-- Venstreklik skifter, og har du valgt et lag i listen, er det dét lag, den beder om.
-- Hoejreklik glemmer det valgte lag, saa knappen beder om et hvilket som helst lag igen.
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btn:SetScript("OnClick", function(_, button)
  if button == "RightButton" then
    if not swap then target = nil; refresh() end
    return
  end
  requestSwap()
end)
paintBtn()

local full = { sep, hLabel, status, btn }
refresh = function()
  if not DB then return end
  if DB.hidden then f:Hide(); return end
  f:Show()
  if f._scale ~= DB.scale then f._scale = DB.scale; f:SetScale(DB.scale) end
  local s, text = swap, nil
  if s then
    if s.moved then
      text = (cur and string.format(T("moved"), T("layer") .. " " .. letter(cur.key)) or T("movedNew")) .. ". " .. string.format(T("leaving"), math.max(0, math.ceil((s.leaveAt or 0) - GetTime())))
    elseif s.joinedAt then text = T("joined")
    elseif s.inviter then text = string.format(s.manual and T("acceptHint") or T("invited"), s.inviter)
    elseif s.heard > 0 then text = string.format(T("heard"), s.heard)
    elseif target then text = string.format(T("goingTo"), letter(target))
    elseif s.asked and s.asked > 0 then text = string.format(T("asked"), s.asked)
    else text = T("searching") end
  elseif DB._status and (not DB._statusUntil or GetTime() < DB._statusUntil) then
    text = DB._status
  end
  local open = DB.open and true or false
  if f._open ~= open then
    f._open = open
    for _, x in ipairs(full) do x:SetShown(open) end
    if not open then for _, r in ipairs(rows) do r:Hide() end end
  end
  mTop:SetText(blind and "LayerETA" or (T("layer") .. " " .. (cur and letter(cur.key) or "?")))
  if cur then mTop:SetTextColor(0.62, 0.82, 1) else mTop:SetTextColor(0.91, 0.92, 0.94) end
  local h = 40
  if open then
    mSub:SetText(blind and string.format(T("left"), swapsLeft()) or (cur and "LayerETA" or T("unknown")))
    hLabel:SetText(T("seen"))
    -- listen: de lag du har vaeret paa i denne zone, nyeste oeverst
    local hist, list = histFor(), {}
    for _, item in ipairs(hist) do
      if type(item) == "table" and not (cur and item.key == cur.key) then list[#list + 1] = item end
    end
    local n = 0
    for i, r in ipairs(rows) do
      local item = list[i]
      if item then
        n = i
        r.key = item.key
        r.lt:SetText(letter(item.key))
        if target == item.key then r.lt:SetTextColor(1, 0.82, 0.32) else r.lt:SetTextColor(0.75, 0.78, 0.84) end
        r.tt:SetText(date("%H:%M", item.t))
        r:Show()
      else
        r.key = nil; r:Hide()
      end
    end
    hLabel:SetShown(n > 0)
    local y = (n > 0) and (58 + n * ROW_H + 4) or 46
    status:ClearAllPoints()
    status:SetPoint("TOPLEFT", 12, -y); status:SetPoint("TOPRIGHT", -12, -y)
    status:SetText(text or "")
    local stop = (s and not s.joinedAt) and true or false
    local used = not s and swapsLeft() <= 0
    btxt:SetText(stop and T("stop") or (used and ("Wait " .. waitText())) or (target and string.format(T("back"), letter(target)) or T("swap")))
    btn:SetWidth(math.max(BTN_W, (btxt:GetStringWidth() or 40) + 26))
    if btn.stop ~= stop then btn.stop = stop; paintBtn() end
    h = y + 22 + 10
    if text then h = h + math.max(11, status:GetStringHeight() or 11) + 6 end
  else
    mSub:SetText(text or (blind and string.format(T("left"), swapsLeft())) or (cur and "LayerETA") or T("unknown"))
  end
  if f._h ~= h then f._h = h; f:SetHeight(h) end
end

-- ---------- haendelser ----------
local E = CreateFrame("Frame")
for _, ev in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED", "NAME_PLATE_UNIT_ADDED",
  "ZONE_CHANGED_NEW_AREA", "CHAT_MSG_ADDON", "PARTY_INVITE_REQUEST", "GROUP_JOINED", "GROUP_LEFT",
  "SHARD_TRANSFER", "GROUP_ROSTER_UPDATE", "WHO_LIST_UPDATE" }) do pcall(E.RegisterEvent, E, ev) end

E:SetScript("OnEvent", function(_, ev, a1, a2, a3, a4)
  if ev == "ADDON_LOADED" then
    if a1 ~= ADDON then return end
    LayerETADB = LayerETADB or {}
    DB = LayerETADB
    for k, v in pairs(defaults) do if DB[k] == nil then DB[k] = v end end
    if DB.leaveDelay == 20 then DB.leaveDelay = 4 end   -- den gamle standard var for lang
    DB.asked, DB.book = nil, DB.book or {}
    DB._status, DB._statusUntil = nil, nil
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
    if DB.point then f:ClearAllPoints(); f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", DB.point[1], DB.point[2]) end
    prune()
    return
  end
  if not DB then return end
  if ev == "PLAYER_ENTERING_WORLD" then refresh()
  elseif ev == "UPDATE_MOUSEOVER_UNIT" then observe("mouseover")
  elseif ev == "PLAYER_TARGET_CHANGED" then observe("target")
  elseif ev == "NAME_PLATE_UNIT_ADDED" then if str(a1) then observe(a1) end
  elseif ev == "ZONE_CHANGED_NEW_AREA" then
    if not swap then target = nil end
    cur = nil; observe("target"); refresh()  -- laget er zonens: laes det igen i den nye zone
  elseif ev == "SHARD_TRANSFER" then
    lastShard = GetTime()
    -- spillet har flyttet os: det gamle lag gaelder ikke mere, laes det nye fra en NPC
    cur = nil
    if swap and swap.joinedAt then onMoved() end
    observe("target"); observe("mouseover"); refresh()
  elseif ev == "CHAT_MSG_ADDON" then
    if not secret(a1) and a1 == PREFIX and not secret(a3) and a3 == "WHISPER" then onNote(a2, a4) end
  elseif ev == "WHO_LIST_UPDATE" then Who.results()
  elseif ev == "PARTY_INVITE_REQUEST" then onInvite(a1)
  elseif ev == "GROUP_JOINED" or ev == "GROUP_ROSTER_UPDATE" then
    local s = swap
    if s and s.inviter and not s.joinedAt and IsInGroup and IsInGroup() then
      s.joinedAt, s.manual = GetTime(), nil
      refresh()
    end
  elseif ev == "GROUP_LEFT" then
    if swap and swap.joinedAt then endSwap(swap.moved and (cur and string.format(T("moved"), T("layer") .. " " .. letter(cur.key)) or T("movedNew")) or nil, 10) end
  end
end)

-- et tik i sekundet, kun mens et skift er i gang
C_Timer.NewTicker(1, function()
  local s = swap
  if not s then
    if DB and DB._statusUntil and GetTime() > DB._statusUntil then DB._status, DB._statusUntil = nil, nil; refresh() end
    -- the Wait timer on the button, and the swaps that come back after an hour
    if DB and swapsLeft() < PER_HOUR and math.floor(GetTime()) % 5 == 0 then refresh() end
    return
  end
  local now = GetTime()
  if s.joinedAt then
    -- mens vi venter paa flytningen, laeser vi laget igen hvert sekund fra alt omkring dig.
    -- Ellers opdager vi foerst skiftet, naar du selv peger paa en NPC.
    if not s.moved then
      observe("target"); observe("mouseover")
      if C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        if ok and type(plates) == "table" then
          for _, pl in ipairs(plates) do
            local unit = type(pl) == "table" and (pl.namePlateUnitToken or (pl.UnitFrame and pl.UnitFrame.unit))
            if str(unit) then observe(unit) end
          end
        end
      end
    end
    if s.moved then
      if now >= (s.leaveAt or 0) then
        local key = cur and cur.key
        swap = nil; leaveGroup(); setStatus(key and string.format(T("moved"), T("layer") .. " " .. letter(key)) or T("movedNew"), 15)
      else refresh() end
    elseif now - s.joinedAt > NO_MOVE_LEAVE then
      local who = s.inviter or "?"
      swap = nil; leaveGroup(); setStatus(string.format(T("notMoved"), who), 15)
    end
  end
end)

SLASH_LAYERETA1 = "/leta"
SLASH_LAYERETA2 = "/layereta"
SlashCmdList.LAYERETA = function(msg)
  if not DB then return end
  msg = string.lower(msg or "")
  if msg == "swap" then requestSwap()
  elseif msg == "lock" then DB.locked = not DB.locked; print("|cffffd24aLayerETA|r: " .. T(DB.locked and "locked" or "unlocked"))
  elseif msg == "debug" then
    print("|cffffd24aLayerETA|r debug:")
    print("  player search: " .. tostring(Who.ready()) .. "   asking now: " .. tostring(Who.pending ~= nil))
    print("  your layer: " .. (blind and "hidden by the game (realm 0 in GUIDs)" or (cur and (cur.id .. " = " .. letter(cur.key)) or "unknown, target an NPC")))
    print("  swaps left this hour: " .. swapsLeft() .. "   last move seen: " .. (lastShard and string.format("%ds ago", GetTime() - lastShard) or "none"))
    print("  zone map id: " .. tostring(zoneMap()))
    print("  in a group: " .. tostring(IsInGroup and IsInGroup()) .. "   in an instance: " .. tostring(IsInInstance and select(1, IsInInstance())))
    print("  swap running: " .. tostring(swap ~= nil) .. "   want back to: " .. tostring(target))
    print("  whispers sent in the last ask: " .. tostring(swap and swap.asked or 0))
  elseif msg == "da" or msg == "en" then DB.lang = msg; refresh()
  elseif string.match(msg, "^leave%s+%d+") then DB.leaveDelay = math.min(120, tonumber(string.match(msg, "%d+")) or 4)
  elseif msg == "help" or msg == "?" then print("|cffffd24aLayerETA|r: " .. T("help"))
  else DB.hidden = not DB.hidden; refresh() end
end
