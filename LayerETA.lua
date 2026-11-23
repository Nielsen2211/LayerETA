-- LayerETA 4: one click to another layer.
-- Part of the ETA family (LevelETA, GoldETA, CraftETA ...). All code here is our own.
-- Copyright (c) 2026 Rasmus. All Rights Reserved.
--
-- How it works
--   * In WoW you change layer by joining a group whose leader stands on another layer in the same
--     zone. The game then moves you (SHARD_TRANSFER) and you can leave again.
--   * LayerETA users help each other: anyone can turn on "Host for others". Hosts sit in a hidden
--     LayerETA channel. A click on Swap sends one short request there, and a host in your zone
--     invites you. Requests and answers use LayerETA's own message format (see Net below).
--   * The click also asks players who host with LayerSwap for an invite (LayerSwapAsk.lua, our own
--     code that only sends their request line). /leta others turns that off.
--   * Optionally the click also writes "inv" in the public layer channel, if you have joined it,
--     so any player hosting there can invite you too.
--   * Since 20 Nov 2026 Forever hides which layer anyone is on, so no host knows if it stands on
--     your layer. LayerETA finds out after the join from how the game marks the host in your group,
--     and remembers hosts that turned out to share your layer, so they are skipped next time.

local _, ns = ...
local NAME = "LayerETA"
local DIR = "Interface\\AddOns\\LayerETA\\"
local IMG = DIR .. "Textures\\"
local FONT_SEMI = DIR .. "Fonts\\Inter-SemiBold.ttf"
local FONT_BOLD = DIR .. "Fonts\\Inter-Bold.ttf"

local cfg   -- saved settings (LayerETADB)
local paint -- redraws the box, set further down

-- ===================================================================================== text ==
local TEXT = {
  en = {
    title = "LayerETA", swap = "Swap", stop = "Stop", waitBtn = "Wait %s",
    quota = "%d of 10 swaps left this hour", quotaLow = "Only %d swaps left this hour.",
    hostLabel = "Host for others", hosting = "Hosting", hostCount = "Hosting · %d invited",
    looking = "Looking for a host", lookingN = "Looking for a host (%d hosts online)", invitedBy = "Invited by %s",
    acceptIt = "Accept the invite from %s", inGroupWait = "In %s's group, waiting for the move",
    moved = "Moved to another layer", leavingIn = "Moved. Leaving the group in %ds",
    sameLayer = "%s is on your layer. Left the group.", refused = "The game did not move you. Your 10 swaps this hour may be used.",
    noHost = "No host answered. Try again in a little while.", stopped = "Stopped",
    notHere = "Swapping works in the open world, not in here.", grouped = "Leave your group first.",
    fighting = "Not during combat. Try again in a few seconds.", spent = "No swaps left this hour. Wait %s.",
    noRoute = "No way to ask: the LayerETA channel is not ready and you are not in the layer channel (/join layer).",
    lsOn = "Swap also asks other hosts in your zone for an invite.", lsOff = "Swap no longer asks other hosts in your zone.", lsAsked = "Looking for a host (asked %d players)",
    hint = "Click: open or close  ·  Drag: move", locked = "Box locked", unlocked = "Box unlocked",
    hostNowOn = "You now invite LayerETA users in your zone who want another layer.", hostNowOff = "You no longer host.",
    chanOn = "Swap also writes \"inv\" in the layer channel.", chanOff = "Swap no longer writes in the layer channel.",
    help = "/leta: show or hide  ·  /leta swap  ·  /leta host  ·  /leta channel  ·  /leta others  ·  /leta lock  ·  /leta leave <seconds>  ·  /leta debug  ·  /leta da|en",
  },
  da = {
    title = "LayerETA", swap = "Skift", stop = "Stop", waitBtn = "Vent %s",
    quota = "%d af 10 skift tilbage denne time", quotaLow = "Kun %d skift tilbage denne time.",
    hostLabel = "Host for andre", hosting = "Hoster", hostCount = "Hoster · %d inviteret",
    looking = "Leder efter en host", lookingN = "Leder efter en host (%d hosts online)", invitedBy = "Inviteret af %s",
    acceptIt = "Acceptér invitationen fra %s", inGroupWait = "I %s's gruppe, venter på skiftet",
    moved = "Flyttet til et andet lag", leavingIn = "Flyttet. Forlader gruppen om %ds",
    sameLayer = "%s er på dit lag. Forlod gruppen.", refused = "Spillet flyttede dig ikke. Dine 10 skift denne time kan være brugt.",
    noHost = "Ingen host svarede. Prøv igen om lidt.", stopped = "Stoppet",
    notHere = "Skift virker ude i verden, ikke herinde.", grouped = "Forlad din gruppe først.",
    fighting = "Ikke i kamp. Prøv igen om et par sekunder.", spent = "Ingen skift tilbage denne time. Vent %s.",
    noRoute = "Kan ikke spørge: LayerETA kanalen er ikke klar, og du er ikke i layer kanalen (/join layer).",
    lsOn = "Skift spørger også andre hosts i zonen om en invite.", lsOff = "Skift spørger ikke længere andre hosts i zonen.", lsAsked = "Leder efter en host (spurgte %d spillere)",
    hint = "Klik: åbn eller luk  ·  Træk: flyt", locked = "Boksen er låst", unlocked = "Boksen er låst op",
    hostNowOn = "Du inviterer nu LayerETA brugere i din zone, der vil skifte lag.", hostNowOff = "Du hoster ikke længere.",
    chanOn = "Skift skriver også \"inv\" i layer kanalen.", chanOff = "Skift skriver ikke længere i layer kanalen.",
    help = "/leta: vis eller skjul  ·  /leta swap  ·  /leta host  ·  /leta channel  ·  /leta others  ·  /leta lock  ·  /leta leave <sekunder>  ·  /leta debug  ·  /leta da|en",
  },
}
local function L(key, ...)
  local pack = TEXT[cfg and cfg.lang or "en"] or TEXT.en
  local s = pack[key] or TEXT.en[key] or key
  if select("#", ...) > 0 then return string.format(s, ...) end
  return s
end
local function say(msg) print("|cffffd24aLayerETA|r: " .. msg) end

local DEFAULTS = { lang = "en", open = false, hidden = false, locked = false, leaveDelay = 4, scale = 1, channel = true, layerswap = true }

-- ================================================================================== helpers ==
-- Forever hands some values to addons as "secret": we never read those.
local function hidden(v) return type(issecretvalue) == "function" and issecretvalue(v) or false end
local function text(v) return not hidden(v) and type(v) == "string" and v ~= "" end
local function bare(name) return text(name) and (name:match("^([^%-]+)") or name) or nil end
local function call(fn, ...) if type(fn) ~= "function" then return false end return pcall(fn, ...) end

local function myName() local ok, n = call(UnitName, "player"); return ok and text(n) and n or nil end
local function inInstance() local ok, yes = call(IsInInstance); return ok and yes == true end
local function inGroup() local ok, yes = call(IsInGroup); return ok and yes == true end
local function inCombat() local ok, yes = call(InCombatLockdown); return ok and yes == true end

-- the zone the player is in, as a map id (the same number on every client). A cave or a house
-- inside a zone counts as that zone, so two players in the same zone always agree.
local function zoneId()
  if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
  local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
  if not ok or hidden(id) or type(id) ~= "number" then return nil end
  local zoneType = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
  local steps = 0
  while steps < 8 do
    steps = steps + 1
    local okInfo, info = pcall(C_Map.GetMapInfo, id)
    if not okInfo or type(info) ~= "table" then break end
    local kind, up = info.mapType or 0, info.parentMapID or 0
    if kind <= zoneType or up == 0 then break end
    id = up
  end
  return id
end

local function zoneName(id)
  if not (id and C_Map and C_Map.GetMapInfo) then return nil end
  local ok, info = pcall(C_Map.GetMapInfo, id)
  local n = ok and type(info) == "table" and info.name or nil
  return text(n) and n or nil
end

local function spot(id)
  if not (id and C_Map and C_Map.GetPlayerMapPosition) then return nil end
  local ok, pos = pcall(C_Map.GetPlayerMapPosition, id, "player")
  if not ok or hidden(pos) or type(pos) ~= "table" then return nil end
  local x, y = pos.x, pos.y
  if type(pos.GetXY) == "function" then
    local okXY, px, py = pcall(pos.GetXY, pos)
    if okXY then x, y = px, py end
  end
  if type(x) == "number" and type(y) == "number" and x > 0 and y > 0 then return x, y end
end

-- Hosting is on unless this character turned it off. The choice is stored per character and stays
-- until the player turns it on again: a reload, a login or a new version never changes it.
local function hosting()
  local offFor = cfg and cfg.hostOffFor
  return not (type(offFor) == "table" and offFor[myName() or "?"])
end
local function setHosting(on)
  cfg.hostOffFor = type(cfg.hostOffFor) == "table" and cfg.hostOffFor or {}
  cfg.hostOffFor[myName() or "?"] = (not on) or nil
end

-- ================================================================== ten moves an hour ==
-- Forever moves a character to another layer at most ten times in an hour. Each move is stored
-- with its time, per character, so the count survives a reload.
local Quota = { LIMIT = 10, WINDOW = 3600 }
function Quota.list()
  cfg.moveLog = cfg.moveLog or {}
  local who = myName() or "?"
  local now, fresh = time(), {}
  for _, at in ipairs(cfg.moveLog[who] or {}) do
    if type(at) == "number" and now - at < Quota.WINDOW then fresh[#fresh + 1] = at end
  end
  cfg.moveLog[who] = fresh
  return fresh
end
function Quota.left() return math.max(0, Quota.LIMIT - #Quota.list()) end
function Quota.untilNext()
  local log = Quota.list()
  if #log < Quota.LIMIT then return "0:00" end
  local secs = math.max(0, Quota.WINDOW - (time() - log[1]))
  return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end
function Quota.add()
  local log = Quota.list()
  log[#log + 1] = time()
  local left = Quota.left()
  if left == 3 or left == 1 then say(L("quotaLow", left)) end
end

-- ======================================================================= network ==
-- LayerETA's own channel and message format. Every message is one line:
--   "1;ask;<ticket>;<zone>;<name,name,...>;<h>"  a player wants another layer. The names are hosts
--                                             that recently turned out to share its layer. "h" when
--                                             the asker hosts too: hosts serve those first.
--   "1;took;<ticket>"                         the asker accepted an invite, other hosts stand down.
--   "1;here"                                  a host says it is online (answer to "1;who", and every
--                                             5 minutes while hosting).
--   "1;who"                                   who hosts right now? (sent with an ask, answered by hosts)
-- The channel has a password, so only LayerETA joins it and nobody can type in it by accident.
local Net = { TAG = "LETA", CHANNEL = "LayerETAnet", KEY = "eta7layer", VERSION = "1" }

function Net.channelId()
  local ok, id = call(GetChannelName, Net.CHANNEL)
  if ok and type(id) == "number" and id > 0 then return id end
end

function Net.join()
  if Net.channelId() then Net.tidy(); return end
  call(JoinTemporaryChannel, Net.CHANNEL, Net.KEY)
  if C_Timer then C_Timer.After(2, Net.tidy) end
end

-- the channel carries only addon messages: keep it out of every chat window
function Net.tidy()
  if type(ChatFrame_RemoveChannel) ~= "function" then return end
  for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local frame = _G["ChatFrame" .. i]
    if frame then pcall(ChatFrame_RemoveChannel, frame, Net.CHANNEL) end
  end
end

function Net.ready()
  return Net.channelId() ~= nil and C_ChatInfo and type(C_ChatInfo.SendAddonMessage) == "function"
end

function Net.post(...)
  local id = Net.channelId()
  if not id then return false end
  local line = table.concat({ Net.VERSION, ... }, ";")
  local ok = pcall(C_ChatInfo.SendAddonMessage, Net.TAG, line, "CHANNEL", id)
  return ok
end

function Net.split(line)
  local out = {}
  for piece in string.gmatch(line .. ";", "([^;]*);") do out[#out + 1] = piece end
  return out
end

-- ===================================================================== asking ==
local Ask = { WINDOW = 45, OWN_FIRST = 3, CHECK_AFTER = 3, GIVE_UP = 12, COOLDOWN = 5, SAME_FOR = 900 }
local job          -- the swap in progress, or nil
local lastPress = -100
local fightEndedAt = -100
local hostsOnline, hostsSeenAt = {}, 0

-- hosts that turned out to stand on our layer, remembered for a while
local function sameLayerHosts()
  cfg.sameAs = cfg.sameAs or {}
  local now, names = time(), {}
  for who, at in pairs(cfg.sameAs) do
    if type(at) ~= "number" or now - at > Ask.SAME_FOR then cfg.sameAs[who] = nil else names[#names + 1] = who end
  end
  return names
end

local function note(msg, secs)
  cfg._note, cfg._noteUntil = msg, GetTime() + (secs or 10)
  if paint then paint() end
end

local function finish(msg, secs)
  job = nil
  note(msg, secs)
end

local function quitGroup()
  if not inGroup() then return end
  if C_PartyInfo and C_PartyInfo.LeaveParty then pcall(C_PartyInfo.LeaveParty) else call(LeaveParty) end
end

-- the layer channel players type "inv" in; nil when the player has not joined it
local function layerChannel()
  local ok, id = call(GetChannelName, "layer")
  if ok and type(id) == "number" and id > 0 then return id end
end

local function countHosts()
  local n, now = 0, GetTime()
  for _, at in pairs(hostsOnline) do if now - at < 120 then n = n + 1 end end
  return n
end

local function startSwap()
  local now = GetTime()
  if job then finish(L("stopped"), 5); return end
  if now - lastPress < Ask.COOLDOWN then return end
  if inInstance() then note(L("notHere"), 8); return end
  if inGroup() then note(L("grouped"), 8); return end
  if inCombat() or now - fightEndedAt < 6 then note(L("fighting"), 6); return end
  if Quota.left() == 0 then note(L("spent", Quota.untilNext()), 8); return end

  local useNet = Net.ready()
  local chan = cfg.channel and layerChannel() or nil
  local LS = ns.LayerSwapAsk
  local useLS = cfg.layerswap and LS and LS.available() and zoneId() ~= nil
  if not useNet and not chan and not useLS then note(L("noRoute"), 12); return end
  lastPress = now

  local ticket = string.format("%05d%04d", time() % 100000, math.random(0, 9999))
  if useNet then
    Net.post("who")
    Net.post("ask", ticket, tostring(zoneId() or 0), table.concat(sameLayerHosts(), ","), hosting() and "h" or "-")
  end
  -- a button click counts as a key press, so the game lets us say "inv" in a channel here
  if chan and type(SendChatMessage) == "function" then pcall(SendChatMessage, "inv", "CHANNEL", nil, chan) end

  local mine = { ticket = ticket, startedAt = now }
  job = mine
  -- LayerETA hosts always come first. Other hosts in the zone are only asked when no LayerETA host
  -- has invited within a few seconds (or at once, when our own channel is not ready).
  if useLS then
    local function askOthers()
      if job ~= mine or mine.host then return end
      local zone = zoneId()
      local x, y = spot(zone)
      LS.start(zone, zoneName(zone), x, y, function() return job == mine and not mine.host end)
    end
    if useNet then C_Timer.After(Ask.OWN_FIRST, askOthers) else askOthers() end
  end
  paint()
  C_Timer.After(Ask.WINDOW, function()
    if job == mine and not mine.host then finish(L("noHost"), 10) end
  end)
end

local function onInvite(from)
  local j = job
  if not j or j.host or GetTime() - j.startedAt > Ask.WINDOW then return end  -- only invites we asked for
  j.host = text(from) and from or "?"
  Net.post("took", j.ticket)
  if call(AcceptGroup) then
    call(StaticPopup_Hide, "PARTY_INVITE")
  else
    j.manual = true
  end
  paint()
end

local function onJoined()
  local j = job
  if j and j.host and not j.inGroupAt and inGroup() then
    j.inGroupAt, j.manual = GetTime(), nil
    paint()
  end
end

local function onMoved()
  local j = job
  if not j or not j.inGroupAt or j.movedAt then return end
  j.movedAt = GetTime()
  Quota.add()
  paint()
end

-- after the join: how does the game mark the host? 1 = elsewhere (another layer), nil = beside us
local function hostPlacement(who)
  if type(UnitPhaseReason) ~= "function" or not text(who) then return nil end
  for i = 1, 4 do
    local unit = "party" .. i
    local okName, n = call(UnitName, unit)
    if okName and text(n) and (n == who or n == bare(who)) then
      local ok, reason = pcall(UnitPhaseReason, unit)
      if not ok or hidden(reason) then return nil end
      if reason == nil then return "same" end
      if reason == 1 then return "other" end
      return nil
    end
  end
end

local function stepJob(now)
  local j = job
  if not j or not j.inGroupAt then return end
  if j.movedAt then
    local leaveAt = j.movedAt + math.max(0, cfg.leaveDelay or 4)
    if now >= leaveAt then job = nil; quitGroup(); note(L("moved"), 15) end
    return
  end
  local waited = now - j.inGroupAt
  if waited < Ask.CHECK_AFTER then return end
  local where = hostPlacement(j.host)
  local who = bare(j.host) or "?"
  if where == "same" or waited > Ask.GIVE_UP then
    cfg.sameAs = cfg.sameAs or {}
    cfg.sameAs[who] = time()
    job = nil; quitGroup(); note(L("sameLayer", who), 15)
  elseif where == "other" then
    job = nil; quitGroup(); note(L("refused"), 20)
  end
end

-- ===================================================================== hosting ==
-- With "Host for others" on, LayerETA invites askers in your zone. Only while you are alone, out of
-- combat and out of instances (on by default, one click on the switch turns it off), at most HOST_MAX invites per HOST_WINDOW, and never twice per ticket.
local Host = { MAX = 5, WINDOW = 600, STAY = 40 }
local tickets = {}       -- [ticket] = "seen" or "took"
local guestAt            -- when our last guest was invited

function Host.recent()
  cfg.hostLog = cfg.hostLog or {}
  local now, keep = time(), {}
  for _, at in ipairs(cfg.hostLog) do if type(at) == "number" and now - at < Host.WINDOW then keep[#keep + 1] = at end end
  cfg.hostLog = keep
  return keep
end

function Host.able()
  return hosting() and not inGroup() and not inInstance() and not inCombat() and #Host.recent() < Host.MAX
end

-- Askers who host for others come first. Their "h" only counts when we have heard them say "here"
-- in the last 10 minutes, so the flag alone is not enough. The last invite in our budget is kept
-- for such askers, and they get a shorter wait than everyone else.
function Host.isFellowHost(sender, flag)
  local seen = hostsOnline[sender]
  return flag == "h" and seen ~= nil and GetTime() - seen < 600
end

function Host.onAsk(sender, ticket, zone, skip, flag)
  if not Host.able() or tickets[ticket] then return end
  local fellow = Host.isFellowHost(sender, flag)
  if not fellow and #Host.recent() >= Host.MAX - 1 then return end
  tickets[ticket] = "seen"
  if tostring(zoneId() or -1) ~= zone then return end
  local me = myName()
  for who in string.gmatch(skip or "", "[^,]+") do if who == me then return end end
  -- several hosts may hear the same ask: each waits a short random moment, the first one invites
  -- and the asker's "took" makes the rest stand down
  local wait = fellow and (0.2 + math.random() * 0.6) or (1.2 + math.random() * 1.8)
  C_Timer.After(wait, function()
    if tickets[ticket] == "took" or not Host.able() then return end
    local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if call(invite, sender) then
      tickets[ticket] = "took"
      local log = Host.recent()
      log[#log + 1] = time()
      guestAt = GetTime()
      if paint then paint() end
    end
  end)
end

-- a guest who stays too long: we leave, which ends the little group
function Host.step(now)
  if not guestAt then return end
  if not inGroup() then
    if now - guestAt > 30 then guestAt = nil end
    return
  end
  if now - guestAt > Host.STAY then
    local okN, size = call(GetNumGroupMembers)
    if okN and type(size) == "number" and size <= 2 then quitGroup() end
    guestAt = nil
  end
end

function Host.onMessage(parts, sender)
  local kind = parts[2]
  if kind == "ask" and parts[3] and parts[4] then
    Host.onAsk(sender, parts[3], parts[4], parts[5], parts[6])
  elseif kind == "took" and parts[3] then
    tickets[parts[3]] = "took"
  elseif kind == "who" then
    if hosting() and GetTime() - hostsSeenAt > 5 then hostsSeenAt = GetTime(); Net.post("here") end
  elseif kind == "here" then
    hostsOnline[sender] = GetTime()
    if job and paint then paint() end
  end
end

-- ========================================================================= box ==
local WIDTH = 160
local box = CreateFrame("Frame", "LayerETAFrame", UIParent)
box:SetSize(WIDTH, 40)
box:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -220, -520)
box:SetMovable(true); box:EnableMouse(true); box:SetClampedToScreen(true); box:RegisterForDrag("LeftButton")

local function label(parent, font, size, r, g, b)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(font, size, "")
  fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 0.6)
  if r then fs:SetTextColor(r, g, b) end
  return fs
end

do -- panel background in three slices, shared with the other ETA addons
  local function slice(file)
    local t = box:CreateTexture(nil, "BACKGROUND")
    t:SetTexture(IMG .. file); t:SetTexCoord(0, 520 / 1024, 0, 40 / 64)
    return t
  end
  local top, bottom, middle = slice("PanelTop"), slice("PanelBottom"), slice("PanelMid")
  top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(20)
  bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(20)
  middle:SetPoint("TOPLEFT", top, "BOTTOMLEFT"); middle:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT")
end

local mark = box:CreateTexture(nil, "ARTWORK")
mark:SetSize(26, 26); mark:SetPoint("TOPLEFT", 8, -8); mark:SetTexture(IMG .. "Mark")
local head = label(box, FONT_BOLD, 12, 0.91, 0.92, 0.94); head:SetPoint("TOPLEFT", 40, -8)
local sub = label(box, FONT_SEMI, 10, 0.55, 0.58, 0.64); sub:SetPoint("TOPLEFT", 40, -23)
sub:SetWidth(WIDTH - 48); sub:SetJustifyH("LEFT"); if sub.SetWordWrap then sub:SetWordWrap(false) end

local rule = box:CreateTexture(nil, "ARTWORK"); rule:SetHeight(1); rule:SetColorTexture(1, 1, 1, 0.06)
rule:SetPoint("TOPLEFT", 12, -40); rule:SetPoint("TOPRIGHT", -12, -40)

local info = label(box, FONT_SEMI, 10, 0.75, 0.78, 0.84)
info:SetPoint("TOPLEFT", 12, -47); info:SetPoint("TOPRIGHT", -12, -47); info:SetJustifyH("LEFT")
if info.SetWordWrap then info:SetWordWrap(true) end

-- the host switch: the label on the left, a small flat switch on the right. The whole row is the
-- click target. Off: dark track, grey knob left. On: gold track, dark knob right.
local hostLine = CreateFrame("Button", nil, box)
hostLine:SetHeight(14)
local hostText = label(hostLine, FONT_SEMI, 10); hostText:SetPoint("LEFT", 2, 0)
local trackEdge = hostLine:CreateTexture(nil, "ARTWORK")
trackEdge:SetSize(24, 12); trackEdge:SetPoint("RIGHT", -2, 0)
trackEdge:SetTexture(IMG .. "SwitchTrack"); trackEdge:SetTexCoord(0, 48 / 64, 0, 24 / 32)
local trackFill = hostLine:CreateTexture(nil, "ARTWORK", nil, 1)
trackFill:SetPoint("TOPLEFT", trackEdge, "TOPLEFT", 1, -1); trackFill:SetPoint("BOTTOMRIGHT", trackEdge, "BOTTOMRIGHT", -1, 1)
trackFill:SetTexture(IMG .. "SwitchTrack"); trackFill:SetTexCoord(0, 48 / 64, 0, 24 / 32)
local knob = hostLine:CreateTexture(nil, "ARTWORK", nil, 2)
knob:SetSize(8, 8); knob:SetTexture(IMG .. "SwitchKnob")
local hostNote = label(box, FONT_SEMI, 9, 0.62, 0.82, 1)
local function drawSwitch()
  local on, hot = cfg and hosting(), hostLine.hot
  knob:ClearAllPoints()
  if on then
    trackEdge:SetVertexColor(0.85, 0.66, 0.24); trackFill:SetVertexColor(hot and 0.92 or 0.85, hot and 0.72 or 0.66, hot and 0.3 or 0.24)
    knob:SetPoint("RIGHT", trackEdge, "RIGHT", -2, 0); knob:SetVertexColor(0.1, 0.08, 0.03)
    hostText:SetTextColor(0.91, 0.92, 0.94)
  else
    trackEdge:SetVertexColor(0.23, 0.25, 0.29); trackFill:SetVertexColor(hot and 0.2 or 0.16, hot and 0.22 or 0.18, hot and 0.26 or 0.21)
    knob:SetPoint("LEFT", trackEdge, "LEFT", 2, 0); knob:SetVertexColor(0.55, 0.58, 0.64)
    hostText:SetTextColor(0.75, 0.78, 0.84)
  end
end
hostLine:SetScript("OnClick", function()
  setHosting(not hosting())
  say(hosting() and L("hostNowOn") or L("hostNowOff"))
  paint()
end)
hostLine:SetScript("OnEnter", function() hostLine.hot = true; drawSwitch() end)
hostLine:SetScript("OnLeave", function() hostLine.hot = false; drawSwitch() end)

-- the gold pill button; grey while a swap runs, then it says Stop
local button = CreateFrame("Button", nil, box)
button:SetSize(90, 22); button:SetPoint("BOTTOM", 0, 10)
local pill = button:CreateTexture(nil, "BACKGROUND"); pill:SetAllPoints()
pill:SetTexture(IMG .. "Button"); pill:SetTexCoord(0, 240 / 256, 0, 48 / 64)
local caption = button:CreateFontString(nil, "OVERLAY"); caption:SetFont(FONT_BOLD, 11, ""); caption:SetPoint("CENTER")
local function tint()
  local hot = button.hot
  if button.busy then
    pill:SetVertexColor(hot and 0.34 or 0.26, hot and 0.36 or 0.28, hot and 0.42 or 0.33)
    caption:SetTextColor(0.91, 0.92, 0.94); caption:SetShadowOffset(1, -1); caption:SetShadowColor(0, 0, 0, 0.6)
  else
    pill:SetVertexColor(1, hot and 0.88 or 0.8, hot and 0.5 or 0.33)
    caption:SetTextColor(0.1, 0.08, 0.03); caption:SetShadowOffset(0, 0)
  end
end
button:SetScript("OnEnter", function() button.hot = true; tint() end)
button:SetScript("OnLeave", function() button.hot = false; tint(); caption:SetPoint("CENTER", 0, 0) end)
button:SetScript("OnMouseDown", function() caption:SetPoint("CENTER", 0, -1) end)
button:SetScript("OnMouseUp", function() caption:SetPoint("CENTER", 0, 0) end)
button:SetScript("OnClick", function() startSwap() end)
tint()

box:SetScript("OnDragStart", function(self) self.dragging = true; if not cfg.locked then self:StartMoving() end end)
box:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local x, y = self:GetLeft(), self:GetTop()
  if x and y then self:ClearAllPoints(); self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y); cfg.point = { x, y } end
end)
box:SetScript("OnMouseUp", function(self, which)
  if self.dragging then self.dragging = nil; return end
  if which == "LeftButton" and cfg then cfg.open = not cfg.open; paint() end
end)
box:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:AddLine("LayerETA", 1, 0.82, 0.3)
  GameTooltip:AddLine(L("hint"), 0.6, 0.6, 0.6); GameTooltip:Show()
end)
box:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function jobText()
  local j = job
  if not j then
    if cfg._note and GetTime() < (cfg._noteUntil or 0) then return cfg._note end
    return nil
  end
  if j.movedAt then
    local left = math.ceil(j.movedAt + (cfg.leaveDelay or 4) - GetTime())
    return L("leavingIn", math.max(0, left))
  end
  if j.inGroupAt then return L("inGroupWait", bare(j.host) or "?") end
  if j.host then return j.manual and L("acceptIt", bare(j.host) or "?") or L("invitedBy", bare(j.host) or "?") end
  local asked = ns.LayerSwapAsk and ns.LayerSwapAsk.sentCount() or 0
  if asked > 0 then return L("lsAsked", asked) end
  local n = countHosts()
  return n > 0 and L("lookingN", n) or L("looking")
end

paint = function()
  if not cfg then return end
  if cfg.hidden then box:Hide(); return end
  box:Show()
  if box.scaleNow ~= cfg.scale then box.scaleNow = cfg.scale; box:SetScale(cfg.scale or 1) end
  head:SetText(L("title"))
  local status = jobText()
  local quota = L("quota", Quota.left())
  local open = cfg.open and true or false
  rule:SetShown(open); info:SetShown(open); hostLine:SetShown(open); button:SetShown(open)
  hostNote:SetShown(open and hosting())
  local height = 40
  if open then
    sub:SetText(quota)
    local y = 47
    info:ClearAllPoints(); info:SetPoint("TOPLEFT", 12, -y); info:SetPoint("TOPRIGHT", -12, -y)
    info:SetText(status or "")
    if status then y = y + math.max(11, info:GetStringHeight() or 11) + 6 end
    hostLine:ClearAllPoints(); hostLine:SetPoint("TOPLEFT", 12, -y); hostLine:SetPoint("TOPRIGHT", -12, -y)
    local hosted = #Host.recent()
    hostText:SetText(L("hostLabel"))
    drawSwitch()
    y = y + 14 + 6
    if hosting() then
      hostNote:ClearAllPoints(); hostNote:SetPoint("TOPLEFT", 14, -(y - 4))
      hostNote:SetText(hosted > 0 and L("hostCount", hosted) or L("hosting"))
      y = y + 12 + 4
    end
    local busy = job ~= nil and not job.inGroupAt
    local spent = not job and Quota.left() == 0
    caption:SetText(busy and L("stop") or (spent and L("waitBtn", Quota.untilNext())) or L("swap"))
    button:SetWidth(math.max(90, (caption:GetStringWidth() or 40) + 26))
    if button.busy ~= busy then button.busy = busy; tint() end
    height = y + 22 + 10
  else
    sub:SetText(status or quota)
  end
  if box.heightNow ~= height then box.heightNow = height; box:SetHeight(height) end
end

-- ===================================================================== events ==
local events = CreateFrame("Frame")
local wanted = { "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "CHAT_MSG_ADDON",
  "PARTY_INVITE_REQUEST", "GROUP_JOINED", "GROUP_ROSTER_UPDATE", "GROUP_LEFT", "SHARD_TRANSFER", "WHO_LIST_UPDATE" }
for _, ev in ipairs(wanted) do pcall(events.RegisterEvent, events, ev) end

local joinedOnce = false
events:SetScript("OnEvent", function(_, ev, a1, a2, a3, a4)
  if ev == "ADDON_LOADED" then
    if a1 ~= NAME then return end
    LayerETADB = type(LayerETADB) == "table" and LayerETADB or {}
    cfg = LayerETADB
    for k, v in pairs(DEFAULTS) do if cfg[k] == nil then cfg[k] = v end end
    -- data from LayerETA 3.x that this version no longer uses
    cfg.letters, cfg.hist, cfg.book, cfg.asked, cfg.moves, cfg.host = nil, nil, nil, nil, nil, nil
    cfg._note, cfg._noteUntil = nil, nil
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, Net.TAG) end
    if cfg.point then box:ClearAllPoints(); box:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cfg.point[1], cfg.point[2]) end
    return
  end
  if not cfg then return end
  if ev == "PLAYER_ENTERING_WORLD" then
    -- join our channel a little after login, so the game's own channels keep their numbers
    if not joinedOnce then joinedOnce = true; C_Timer.After(8, Net.join) end
    paint()
  elseif ev == "PLAYER_REGEN_ENABLED" then
    fightEndedAt = GetTime()
  elseif ev == "CHAT_MSG_ADDON" then
    if hidden(a1) or a1 ~= Net.TAG or hidden(a3) or a3 ~= "CHANNEL" or not text(a2) or not text(a4) then return end
    if a4 == myName() or bare(a4) == myName() then return end
    local parts = Net.split(a2)
    if parts[1] ~= Net.VERSION then return end
    Host.onMessage(parts, a4)
  elseif ev == "PARTY_INVITE_REQUEST" then
    onInvite(a1)
  elseif ev == "GROUP_JOINED" or ev == "GROUP_ROSTER_UPDATE" then
    onJoined()
  elseif ev == "GROUP_LEFT" then
    if job and job.inGroupAt then finish(job.movedAt and L("moved") or nil, 10) end
  elseif ev == "SHARD_TRANSFER" then
    onMoved()
  elseif ev == "WHO_LIST_UPDATE" then
    if ns.LayerSwapAsk then ns.LayerSwapAsk.onWhoList(myName()) end
  end
end)

local lastHere = -1000
C_Timer.NewTicker(1, function()
  if not cfg then return end
  local now = GetTime()
  -- while hosting, say "here" now and then, so other hosts know this player hosts too
  if hosting() and Net.channelId() and now - lastHere > 300 then lastHere = now; Net.post("here") end
  stepJob(now)
  Host.step(now)
  if job or (cfg._noteUntil and now < cfg._noteUntil + 1) or Quota.left() < Quota.LIMIT then paint() end
end)

-- ===================================================================== commands ==
SLASH_LAYERETA1 = "/leta"
SLASH_LAYERETA2 = "/layereta"
SlashCmdList.LAYERETA = function(input)
  if not cfg then return end
  local cmd, arg = string.match(string.lower(input or ""), "^%s*(%S*)%s*(.-)%s*$")
  if cmd == "swap" then startSwap()
  elseif cmd == "host" then setHosting(not hosting()); say(hosting() and L("hostNowOn") or L("hostNowOff")); paint()
  elseif cmd == "channel" then cfg.channel = not cfg.channel; say(cfg.channel and L("chanOn") or L("chanOff"))
  elseif cmd == "others" then cfg.layerswap = not cfg.layerswap; say(cfg.layerswap and L("lsOn") or L("lsOff"))
  elseif cmd == "lock" then cfg.locked = not cfg.locked; say(cfg.locked and L("locked") or L("unlocked"))
  elseif cmd == "leave" and tonumber(arg) then cfg.leaveDelay = math.max(0, math.min(120, tonumber(arg)))
  elseif cmd == "da" or cmd == "en" then cfg.lang = cmd; paint()
  elseif cmd == "debug" then
    say("debug")
    print("  LayerETA channel: " .. tostring((Net.channelId())) .. "   layer channel: " .. tostring((layerChannel())))
    print("  zone map id: " .. tostring((zoneId())) .. "   swaps left: " .. Quota.left())
    print("  hosting: " .. tostring(hosting()) .. " (" .. #Host.recent() .. " invites in 10 min)   hosts seen: " .. countHosts())
    print("  swap running: " .. tostring(job ~= nil) .. "   skipped hosts: " .. table.concat(sameLayerHosts(), ", "))
  elseif cmd == "help" or cmd == "?" then say(L("help"))
  else cfg.hidden = not cfg.hidden; paint() end
end
