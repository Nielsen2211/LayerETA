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
local NO_MOVE_LEAVE = 15     -- joinet, men ikke flyttet efter saa mange sekunder: forlad gruppen
local COOLDOWN = 5
local DB

local LOC = {
  en = { layer = "Layer", unknown = "Target an NPC", swap = "Swap layer", stop = "Stop",
    needNpc = "Target or mouse over an NPC first, so your layer is known.", inGroup = "You are in a group. Leave it to swap layer.",
    inInstance = "No layers in here. Swap layer works in the open world.", pressEnter = "Press Enter to send your request", joinChan = "Join the layer channel first: type /join layer",
    asking = "Asking %d players", heard = "Waiting, %d heard", nobody = "Found nobody to ask. Try again in a moment.",
    askedAll = "Everyone here was asked already. Click again to ask more.", noAnswer = "No host answered. Try again in a moment.",
    invited = "Invited by %s", joined = "Joined, waiting for the move", moved = "Moved to %s", leaving = "Leaving in %ds",
    notMoved = "%s is on your layer. Left the group.", whoFail = "The player search did not start. Try again in a moment.",
    stopped = "Stopped", hint = "Click: open or close  ·  Drag: move", acceptHint = "Accept the invite from %s", locked = "Window locked", unlocked = "Window unlocked",
    help = "/leta: show or hide  ·  /leta swap  ·  /leta lock  ·  /leta leave <seconds>  ·  /leta da|en" },
  da = { layer = "Lag", unknown = "Målret en NPC", swap = "Skift lag", stop = "Stop",
    needNpc = "Målret eller hold musen over en NPC først, så dit lag er kendt.", inGroup = "Du er i en gruppe. Forlad den for at skifte lag.",
    inInstance = "Ingen lag herinde. Skift lag virker ude i verden.", pressEnter = "Tryk Enter for at sende din anmodning", joinChan = "Gå ind i layer-kanalen først: skriv /join layer",
    asking = "Spørger %d spillere", heard = "Venter, %d har hørt", nobody = "Fandt ingen at spørge. Prøv igen om lidt.",
    askedAll = "Alle her er allerede spurgt. Klik igen for at spørge flere.", noAnswer = "Ingen host svarede. Prøv igen om lidt.",
    invited = "Inviteret af %s", joined = "Joinet, venter på skiftet", moved = "Flyttet til %s", leaving = "Forlader om %ds",
    notMoved = "%s er på dit lag. Forlod gruppen.", whoFail = "Søgningen startede ikke. Prøv igen om lidt.",
    stopped = "Stoppet", hint = "Klik: åbn eller luk  ·  Træk: flyt", acceptHint = "Acceptér invitationen fra %s", locked = "Vinduet er låst", unlocked = "Vinduet er låst op",
    help = "/leta: vis eller skjul  ·  /leta swap  ·  /leta lock  ·  /leta leave <sekunder>  ·  /leta da|en" },
}
local function T(k) return (LOC[(DB and DB.lang) or "en"] or LOC.en)[k] end

local defaults = { lang = "en", open = false, hidden = false, locked = false, leaveDelay = 20, scale = 1 }

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
local function layerKey(id) return type(id) == "string" and (string.match(id, "^(%d+)%-") or id) or nil end

local function setStatus(text, secs)
  DB._status, DB._statusUntil = text, secs and (GetTime() + secs) or nil
  if refresh then refresh() end
end

local onMoved
local function observe(unit)
  if not UnitGUID then return end
  local ok, guid = pcall(UnitGUID, unit)
  if not ok or not str(guid) then return end
  local kind, _, server, _, zoneUID = strsplit("-", guid)
  if (kind ~= "Creature" and kind ~= "Vehicle") or not server or not zoneUID then return end
  if type(UnitPlayerControlled) == "function" then  -- totems og pets baerer id'et fra det sted, de blev lavet
    local okP, pc = pcall(UnitPlayerControlled, unit)
    if okP and not secret(pc) and pc == true then return end
  end
  local id = server .. "-" .. zoneUID
  local key = layerKey(id)
  local old = cur and cur.key
  cur = { id = id, key = key, at = GetTime() }
  if old ~= key then
    if swap and swap.joinedAt and swap.fromKey and key ~= swap.fromKey then onMoved() end
    refresh()
  end
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
  setStatus(text, secs or 12)
end

onMoved = function()
  if not swap or swap.moved then return end
  swap.moved = true
  local delay = math.max(0, DB.leaveDelay or 20)
  swap.leaveAt = GetTime() + delay
  refresh()
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
  if not cur then setStatus(T("needNpc"), 8); return end
  local chan = GetChannelName and GetChannelName("layer") or 0
  if secret(chan) or type(chan) ~= "number" or chan == 0 then setStatus(T("joinChan"), 15); return end
  lastClick = now
  local zone = zoneMap()
  local parts = { "<LS" }
  if zone then parts[#parts + 1] = tostring(zone) end
  parts[#parts + 1] = "not " .. cur.id
  local x, y = mapPos(zone)
  if zone and x then parts[#parts + 1] = string.format("%.1f,%.1f", x * 100, y * 100) end
  local line = "inv layer " .. table.concat(parts, " ") .. ">"
  if not ChatFrame_OpenChat then setStatus(T("whoFail"), 8); return end
  ChatFrame_OpenChat("/" .. chan .. " " .. line)
  local s = { at = now, zone = zone, fromKey = cur.key, heard = 0 }
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
local mIcon = f:CreateTexture(nil, "ARTWORK"); mIcon:SetSize(20, 20); mIcon:SetPoint("TOPLEFT", 11, -10); mIcon:SetTexture(TEX .. "Logo")
local mTop = fs(f, F_BOLD, 12); mTop:SetPoint("TOPLEFT", 38, -8); mTop:SetTextColor(0.91, 0.92, 0.94)
local mSub = fs(f, F_SEMI, 10); mSub:SetPoint("TOPLEFT", 38, -23); mSub:SetTextColor(0.55, 0.58, 0.64)
mSub:SetWidth(W - 46); mSub:SetJustifyH("LEFT"); if mSub.SetWordWrap then mSub:SetWordWrap(false) end

-- det udfoldede: streg, status (kun naar der sker noget) og knappen
local sep = f:CreateTexture(nil, "ARTWORK"); sep:SetHeight(1); sep:SetColorTexture(1, 1, 1, 0.06)
sep:SetPoint("TOPLEFT", 12, -40); sep:SetPoint("TOPRIGHT", -12, -40)
local status = fs(f, F_SEMI, 10); status:SetPoint("TOPLEFT", 12, -47); status:SetPoint("TOPRIGHT", -12, -47)
status:SetJustifyH("LEFT"); status:SetTextColor(0.75, 0.78, 0.84)
if status.SetWordWrap then status:SetWordWrap(true) end

-- knappen: en fyldt guld-pille med moerk tekst. Lysere under musen, trykkes lidt ned ved klik,
-- og bliver graa ("Stop"), mens et skift er i gang.
local btn = CreateFrame("Button", nil, f)
btn:SetHeight(24); btn:SetPoint("BOTTOMLEFT", 12, 10); btn:SetPoint("BOTTOMRIGHT", -12, 10)
local bbg = btn:CreateTexture(nil, "BACKGROUND"); bbg:SetAllPoints(); bbg:SetTexture(TEX .. "Button"); bbg:SetTexCoord(0, 240 / 256, 0, 48 / 64)
local btxt = btn:CreateFontString(nil, "OVERLAY"); btxt:SetFont(F_BOLD, 12, ""); btxt:SetPoint("CENTER")
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
btn:SetScript("OnClick", function() requestSwap() end)
paintBtn()

local full = { sep, status, btn }
refresh = function()
  if not DB then return end
  if DB.hidden then f:Hide(); return end
  f:Show()
  if f._scale ~= DB.scale then f._scale = DB.scale; f:SetScale(DB.scale) end
  local s, text = swap, nil
  if s then
    if s.moved then
      text = string.format(T("moved"), cur and (T("layer") .. " " .. letter(cur.key)) or "?") .. ". " .. string.format(T("leaving"), math.max(0, math.ceil((s.leaveAt or 0) - GetTime())))
    elseif s.joinedAt then text = T("joined")
    elseif s.inviter then text = string.format(s.manual and T("acceptHint") or T("invited"), s.inviter)
    elseif s.heard > 0 then text = string.format(T("heard"), s.heard)
    else text = T("pressEnter") end
  elseif DB._status and (not DB._statusUntil or GetTime() < DB._statusUntil) then
    text = DB._status
  end
  local open = DB.open and true or false
  if f._open ~= open then
    f._open = open
    for _, x in ipairs(full) do x:SetShown(open) end
  end
  mTop:SetText(T("layer") .. " " .. (cur and letter(cur.key) or "?"))
  if cur then mTop:SetTextColor(0.62, 0.82, 1) else mTop:SetTextColor(0.91, 0.92, 0.94) end
  local h = 40
  if open then
    -- aaben: status staar med fuld tekst under stregen, saa linjen i toppen viser bare navnet
    mSub:SetText(cur and "LayerETA" or T("unknown"))
    status:SetText(text or "")
    local stop = (s and not s.joinedAt) and true or false
    btxt:SetText(stop and T("stop") or T("swap"))
    if btn.stop ~= stop then btn.stop = stop; paintBtn() end
    h = 40 + 8 + 24 + 10
    if text then h = h + math.max(11, status:GetStringHeight() or 11) + 6 end
  else
    mSub:SetText(text or (cur and "LayerETA") or T("unknown"))
  end
  if f._h ~= h then f._h = h; f:SetHeight(h) end
end

-- ---------- haendelser ----------
local E = CreateFrame("Frame")
for _, ev in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED", "NAME_PLATE_UNIT_ADDED",
  "ZONE_CHANGED_NEW_AREA", "CHAT_MSG_ADDON", "PARTY_INVITE_REQUEST", "GROUP_JOINED", "GROUP_LEFT",
  "SHARD_TRANSFER", "GROUP_ROSTER_UPDATE" }) do pcall(E.RegisterEvent, E, ev) end

E:SetScript("OnEvent", function(_, ev, a1, a2, a3, a4)
  if ev == "ADDON_LOADED" then
    if a1 ~= ADDON then return end
    LayerETADB = LayerETADB or {}
    DB = LayerETADB
    for k, v in pairs(defaults) do if DB[k] == nil then DB[k] = v end end
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
    cur = nil; observe("target"); refresh()  -- laget er zonens: laes det igen i den nye zone
  elseif ev == "SHARD_TRANSFER" then
    -- spillet har flyttet os: det gamle lag gaelder ikke mere, laes det nye fra en NPC
    cur = nil
    if swap and swap.joinedAt then onMoved() end
    observe("target"); observe("mouseover"); refresh()
  elseif ev == "CHAT_MSG_ADDON" then
    if not secret(a1) and a1 == PREFIX and not secret(a3) and a3 == "WHISPER" then onNote(a2, a4) end
  elseif ev == "PARTY_INVITE_REQUEST" then onInvite(a1)
  elseif ev == "GROUP_JOINED" or ev == "GROUP_ROSTER_UPDATE" then
    local s = swap
    if s and s.inviter and not s.joinedAt and IsInGroup and IsInGroup() then
      s.joinedAt, s.manual = GetTime(), nil
      refresh()
    end
  elseif ev == "GROUP_LEFT" then
    if swap and swap.joinedAt then endSwap(swap.moved and string.format(T("moved"), cur and (T("layer") .. " " .. letter(cur.key)) or "?") or nil, 10) end
  end
end)

-- et tik i sekundet, kun mens et skift er i gang
C_Timer.NewTicker(1, function()
  local s = swap
  if not s then
    if DB and DB._statusUntil and GetTime() > DB._statusUntil then DB._status, DB._statusUntil = nil, nil; refresh() end
    return
  end
  local now = GetTime()
  if s.joinedAt then
    if s.moved then
      if now >= (s.leaveAt or 0) then
        local key = cur and cur.key
        swap = nil; leaveGroup(); setStatus(string.format(T("moved"), T("layer") .. " " .. letter(key)), 15)
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
  elseif msg == "da" or msg == "en" then DB.lang = msg; refresh()
  elseif string.match(msg, "^leave%s+%d+") then DB.leaveDelay = math.min(120, tonumber(string.match(msg, "%d+")) or 20)
  elseif msg == "help" or msg == "?" then print("|cffffd24aLayerETA|r: " .. T("help"))
  else DB.hidden = not DB.hidden; refresh() end
end
