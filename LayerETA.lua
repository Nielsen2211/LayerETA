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
--   * The click also asks other hosts in the zone for an invite (HostAsk.lua, our own code that only
--     sends a request line). /leta others turns that off.
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
    title = "LayerETA", swap = "Swap", swapLayer = "Swap layer", stop = "Stop", ready = "Ready", swapping = "Swapping", newSince = "New layer since %s", spentShort = "Next swap in %s", waitShort = "Wait", stepAsk = "Ask", stepInvite = "Invite", stepMove = "Move", hourLabel = "Swaps this hour", small = "Small view", bigView = "Big view",
    quota = "%d/15 swaps this hour", spent = "15 swaps this hour. Next one in %s.", waitBtn = "Wait %s",
    hostLabel = "Host for others", hosting = "Hosting", hostCount = "Hosting · %d invited",
    looking = "Looking for a host", lookingN = "Looking for a host (%d hosts online)", invitedBy = "Invited by %s",
    acceptIt = "Accept the invite from %s", inGroupWait = "In %s's group, waiting for the move",
    moved = "Moved to another layer", leavingIn = "Moved. Leaving the group in %ds",
    sameLayer = "%s is on your layer. Left the group.", refused = "The game did not move you. Try again in a little while.",
    noHost = "No host answered. Try again in a little while.", stopped = "Stopped",
    notHere = "Swapping works in the open world, not in here.", grouped = "Leave your group first.",
    fighting = "Not during combat. Try again in a few seconds.",
    noRoute = "No way to ask: the LayerETA channel is not ready and you are not in the layer channel (/join layer).",
    othersOn = "Swap also asks other hosts in your zone for an invite.", othersOff = "Swap no longer asks other hosts in your zone.", othersAsked = "Looking for a host (asked %d players)",
    hint = "Click: big or small view  ·  Drag: move", locked = "Box locked", unlocked = "Box unlocked",
    hostNowOn = "You now invite LayerETA users in your zone who want another layer.", hostNowOff = "You no longer host.",
    chanOn = "Swap also writes \"inv\" in the layer channel.", chanOff = "Swap no longer writes in the layer channel.",
    help = "/leta: show or hide  ·  /leta swap  ·  /leta big|small  ·  /leta host  ·  /leta channel  ·  /leta others  ·  /leta lock  ·  /leta leave <seconds>  ·  /leta debug  ·  /leta da|en",
  },
  da = {
    title = "LayerETA", swap = "Skift", swapLayer = "Skift lag", stop = "Stop", ready = "Klar", swapping = "Skifter", newSince = "Nyt lag siden %s", spentShort = "Næste skift om %s", waitShort = "Vent", stepAsk = "Spørg", stepInvite = "Invite", stepMove = "Flyt", hourLabel = "Skift denne time", small = "Lille visning", bigView = "Stor visning",
    quota = "%d/15 skift denne time", spent = "15 skift denne time. Næste om %s.", waitBtn = "Vent %s",
    hostLabel = "Host for andre", hosting = "Hoster", hostCount = "Hoster · %d inviteret",
    looking = "Leder efter en host", lookingN = "Leder efter en host (%d hosts online)", invitedBy = "Inviteret af %s",
    acceptIt = "Acceptér invitationen fra %s", inGroupWait = "I %s's gruppe, venter på skiftet",
    moved = "Flyttet til et andet lag", leavingIn = "Flyttet. Forlader gruppen om %ds",
    sameLayer = "%s er på dit lag. Forlod gruppen.", refused = "Spillet flyttede dig ikke. Prøv igen om lidt.",
    noHost = "Ingen host svarede. Prøv igen om lidt.", stopped = "Stoppet",
    notHere = "Skift virker ude i verden, ikke herinde.", grouped = "Forlad din gruppe først.",
    fighting = "Ikke i kamp. Prøv igen om et par sekunder.",
    noRoute = "Kan ikke spørge: LayerETA kanalen er ikke klar, og du er ikke i layer kanalen (/join layer).",
    othersOn = "Skift spørger også andre hosts i zonen om en invite.", othersOff = "Skift spørger ikke længere andre hosts i zonen.", othersAsked = "Leder efter en host (spurgte %d spillere)",
    hint = "Klik: stor eller lille visning  ·  Træk: flyt", locked = "Boksen er låst", unlocked = "Boksen er låst op",
    hostNowOn = "Du inviterer nu LayerETA brugere i din zone, der vil skifte lag.", hostNowOff = "Du hoster ikke længere.",
    chanOn = "Skift skriver også \"inv\" i layer kanalen.", chanOff = "Skift skriver ikke længere i layer kanalen.",
    help = "/leta: vis eller skjul  ·  /leta swap  ·  /leta big|small  ·  /leta host  ·  /leta channel  ·  /leta others  ·  /leta lock  ·  /leta leave <sekunder>  ·  /leta debug  ·  /leta da|en",
  },
}
local function L(key, ...)
  local pack = TEXT[cfg and cfg.lang or "en"] or TEXT.en
  local s = pack[key] or TEXT.en[key] or key
  if select("#", ...) > 0 then return string.format(s, ...) end
  return s
end
local function say(msg) print("|cffffd24aLayerETA|r: " .. msg) end

local DEFAULTS = { lang = "en", open = false, hidden = false, locked = false, leaveDelay = 4, scale = 1, channel = true, others = true }

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
-- At most 15 swaps in a rolling hour per character. Each move is stored with its time, so the
-- count survives a reload and a login.
local Quota = { LIMIT = 15, WINDOW = 3600 }
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
function Quota.count() return #Quota.list() end
function Quota.full() return Quota.count() >= Quota.LIMIT end
function Quota.untilNext()
  local log = Quota.list()
  if #log < Quota.LIMIT then return "0:00" end
  local secs = math.max(0, Quota.WINDOW - (time() - log[#log - Quota.LIMIT + 1]))
  return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end
function Quota.add()
  local log = Quota.list()
  log[#log + 1] = time()
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
local Ask = { WINDOW = 45, OWN_FIRST = 3, CHECK_AFTER = 3, GIVE_UP = 12, COOLDOWN = 5, SAME_FOR = 900, USED_FOR = 3600, SKIP_CHARS = 200 }
local job          -- the swap in progress, or nil
local lastDoneAt   -- GetTime() when the last swap ended with a move
local lastPress = -100
local fightEndedAt = -100
local hostsOnline, hostsSeenAt = {}, 0

-- Hosts we skip, so swaps spread over many hosts: a host that invited us is not used again for an
-- hour, and a host that turned out to stand on our layer is skipped for 15 minutes. Hosts that
-- invited us come first in the list; the list stays under SKIP_CHARS so the request fits.
local function hostsToSkip()
  local now, list = time(), {}
  local function collect(book, keep)
    if type(book) ~= "table" then return end
    for who, at in pairs(book) do
      if type(at) ~= "number" or now - at > keep then book[who] = nil else list[#list + 1] = { who = who, at = at, used = book == cfg.usedHosts } end
    end
  end
  collect(cfg.usedHosts, Ask.USED_FOR)
  collect(cfg.sameAs, Ask.SAME_FOR)
  table.sort(list, function(a, b)
    if (a.used or false) ~= (b.used or false) then return a.used == true end
    return a.at > b.at
  end)
  local names, seen, length = {}, {}, 0
  for _, e in ipairs(list) do
    if not seen[e.who] and length + #e.who + 1 <= Ask.SKIP_CHARS then
      seen[e.who] = true; names[#names + 1] = e.who; length = length + #e.who + 1
    end
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
  if Quota.full() then note(L("spent", Quota.untilNext()), 8); return end

  local useNet = Net.ready()
  local chan = cfg.channel and layerChannel() or nil
  local ext = ns.HostAsk
  local useExt = cfg.others and ext and ext.available() and zoneId() ~= nil
  if not useNet and not chan and not useExt then note(L("noRoute"), 12); return end
  lastPress = now

  local ticket = string.format("%05d%04d", time() % 100000, math.random(0, 9999))
  if useNet then
    Net.post("who")
    Net.post("ask", ticket, tostring(zoneId() or 0), table.concat(hostsToSkip(), ","), hosting() and "h" or "-")
  end
  -- a button click counts as a key press, so the game lets us say "inv" in a channel here
  if chan and type(SendChatMessage) == "function" then pcall(SendChatMessage, "inv", "CHANNEL", nil, chan) end

  local mine = { ticket = ticket, startedAt = now }
  job = mine
  -- LayerETA hosts always come first. Other hosts in the zone are only asked when no LayerETA host
  -- has invited within a few seconds (or at once, when our own channel is not ready).
  if useExt then
    local function askOthers()
      if job ~= mine or mine.host then return end
      local zone = zoneId()
      local x, y = spot(zone)
      local skip = {}
      for _, who in ipairs(hostsToSkip()) do skip[who] = true end
      ext.start(zone, zoneName(zone), x, y, function() return job == mine and not mine.host end, skip)
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
  -- a host that moved us within the hour is not used again: let its invite lapse and wait for another
  local used = cfg.usedHosts and bare(from) and cfg.usedHosts[bare(from)]
  if type(used) == "number" and time() - used < Ask.USED_FOR then return end
  j.host = text(from) and from or "?"
  if bare(from) then cfg.usedHosts = cfg.usedHosts or {}; cfg.usedHosts[bare(from)] = time() end
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
    if now >= leaveAt then job = nil; lastDoneAt = now; quitGroup(); note(L("moved"), 15) end
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
-- Two views, chosen per character and remembered:
--   big   : status, one wide Swap button, the three steps of a swap, the hour's swaps as 15 ticks,
--           and the host switch
--   small : one line with the status dot, x/15 and a small Swap button
-- A click on the box (not on a button) switches between them.
local BIG_W, SMALL_W, PAD = 176, 176, 10
local C = {
  text = { 0.91, 0.92, 0.94 }, soft = { 0.55, 0.58, 0.64 }, faint = { 0.42, 0.45, 0.52 },
  gold = { 0.95, 0.76, 0.31 }, blue = { 0.62, 0.82, 1 }, green = { 0.5, 0.82, 0.5 }, slot = { 0.16, 0.18, 0.21 },
}
local function rgb(c) return c[1], c[2], c[3] end

local box = CreateFrame("Frame", "LayerETAFrame", UIParent)
box:SetSize(BIG_W, 40)
box:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -220, -520)
box:SetMovable(true); box:EnableMouse(true); box:SetClampedToScreen(true); box:RegisterForDrag("LeftButton")

local function label(parent, font, size, color)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(font, size, "")
  fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 0.6)
  if color then fs:SetTextColor(rgb(color)) end
  return fs
end
local function flat(parent, layer, color)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  t:SetColorTexture(1, 1, 1, 1); t:SetVertexColor(rgb(color or C.slot))
  return t
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

-- head: mark, name, and a status line with a coloured dot
local mark = box:CreateTexture(nil, "ARTWORK")
mark:SetSize(24, 24); mark:SetPoint("TOPLEFT", 9, -8); mark:SetTexture(IMG .. "Mark")
local head = label(box, FONT_BOLD, 12, C.text); head:SetPoint("TOPLEFT", 40, -8)
local dot = box:CreateTexture(nil, "ARTWORK"); dot:SetSize(6, 6); dot:SetTexture(IMG .. "SwitchKnob")
dot:SetPoint("TOPLEFT", 40, -26)
local sub = label(box, FONT_SEMI, 10, C.soft); sub:SetPoint("LEFT", dot, "RIGHT", 4, 0)
sub:SetJustifyH("LEFT"); if sub.SetWordWrap then sub:SetWordWrap(false) end

-- big view parts
local big = CreateFrame("Frame", nil, box); big:SetAllPoints()
local rule1 = flat(big, "ARTWORK", { 1, 1, 1 }); rule1:SetAlpha(0.06); rule1:SetHeight(1)

local steps = {}
for i = 1, 3 do
  local bar = flat(big); bar:SetHeight(2)
  local word = label(big, FONT_SEMI, 9, C.faint)
  steps[i] = { bar = bar, word = word }
end
local msg = label(big, FONT_SEMI, 10, C.text); msg:SetJustifyH("LEFT")
if msg.SetWordWrap then msg:SetWordWrap(true) end

-- the wide Swap button: gold, flat, a little darker under the mouse; grey while a swap runs
local wide = CreateFrame("Button", nil, big); wide:SetHeight(28)
local wideBg = wide:CreateTexture(nil, "BACKGROUND"); wideBg:SetAllPoints()
wideBg:SetTexture(IMG .. "Bar"); wideBg:SetTexCoord(0, 300 / 512, 0, 56 / 64)
local wideText = label(wide, FONT_BOLD, 12); wideText:SetPoint("CENTER"); wideText:SetShadowOffset(0, 0)

local hourLeft = label(big, FONT_SEMI, 9, C.faint)
local hourRight = label(big, FONT_SEMI, 9, C.faint)
local ticks = {}
for i = 1, 15 do ticks[i] = flat(big) end
local rule2 = flat(big, "ARTWORK", { 1, 1, 1 }); rule2:SetAlpha(0.06); rule2:SetHeight(1)

-- the host switch: label left, a small flat switch right; the whole row is the click target
local hostLine = CreateFrame("Button", nil, big); hostLine:SetHeight(14)
local hostText = label(hostLine, FONT_SEMI, 10); hostText:SetPoint("LEFT", 0, 0)
local trackEdge = hostLine:CreateTexture(nil, "ARTWORK")
trackEdge:SetSize(24, 12); trackEdge:SetPoint("RIGHT", 0, 0)
trackEdge:SetTexture(IMG .. "SwitchTrack"); trackEdge:SetTexCoord(0, 48 / 64, 0, 24 / 32)
local trackFill = hostLine:CreateTexture(nil, "ARTWORK", nil, 1)
trackFill:SetPoint("TOPLEFT", trackEdge, "TOPLEFT", 1, -1); trackFill:SetPoint("BOTTOMRIGHT", trackEdge, "BOTTOMRIGHT", -1, 1)
trackFill:SetTexture(IMG .. "SwitchTrack"); trackFill:SetTexCoord(0, 48 / 64, 0, 24 / 32)
local knob = hostLine:CreateTexture(nil, "ARTWORK", nil, 2); knob:SetSize(8, 8); knob:SetTexture(IMG .. "SwitchKnob")
local hostNote = label(big, FONT_SEMI, 9, C.blue)

local function drawSwitch()
  local on, hot = cfg and hosting(), hostLine.hot
  knob:ClearAllPoints()
  if on then
    trackEdge:SetVertexColor(0.85, 0.66, 0.24); trackFill:SetVertexColor(hot and 0.92 or 0.85, hot and 0.72 or 0.66, hot and 0.3 or 0.24)
    knob:SetPoint("RIGHT", trackEdge, "RIGHT", -2, 0); knob:SetVertexColor(0.1, 0.08, 0.03)
    hostText:SetTextColor(rgb(C.text))
  else
    trackEdge:SetVertexColor(0.23, 0.25, 0.29); trackFill:SetVertexColor(hot and 0.2 or 0.16, hot and 0.22 or 0.18, hot and 0.26 or 0.21)
    knob:SetPoint("LEFT", trackEdge, "LEFT", 2, 0); knob:SetVertexColor(rgb(C.soft))
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

-- small view: a small pill button at the right end of the head line
local mini = CreateFrame("Button", nil, box); mini:SetSize(54, 20); mini:SetPoint("RIGHT", box, "TOPRIGHT", -PAD, -20)
local miniBg = mini:CreateTexture(nil, "BACKGROUND"); miniBg:SetAllPoints()
miniBg:SetTexture(IMG .. "Button"); miniBg:SetTexCoord(0, 240 / 256, 0, 48 / 64)
local miniText = label(mini, FONT_BOLD, 10); miniText:SetPoint("CENTER"); miniText:SetShadowOffset(0, 0)

local function paintButton(btn, bg, txt)
  local hot = btn.hot
  if btn.busy then
    bg:SetVertexColor(hot and 0.3 or 0.17, hot and 0.32 or 0.18, hot and 0.37 or 0.21); txt:SetTextColor(rgb(C.text))
  else
    bg:SetVertexColor(hot and 1 or 0.95, hot and 0.82 or 0.76, hot and 0.38 or 0.31); txt:SetTextColor(0.1, 0.08, 0.03)
  end
end
for _, b in ipairs({ { wide, wideBg, wideText }, { mini, miniBg, miniText } }) do
  local btn, bg, txt = b[1], b[2], b[3]
  btn:SetScript("OnEnter", function() btn.hot = true; paintButton(btn, bg, txt) end)
  btn:SetScript("OnLeave", function() btn.hot = false; paintButton(btn, bg, txt); txt:SetPoint("CENTER", 0, 0) end)
  btn:SetScript("OnMouseDown", function() txt:SetPoint("CENTER", 0, -1) end)
  btn:SetScript("OnMouseUp", function() txt:SetPoint("CENTER", 0, 0) end)
  btn:SetScript("OnClick", function() startSwap() end)
end

-- the view is stored per character
local function view()
  local v = type(cfg.viewFor) == "table" and cfg.viewFor[myName() or "?"]
  return v == "small" and "small" or "big"
end
local function setView(v)
  cfg.viewFor = type(cfg.viewFor) == "table" and cfg.viewFor or {}
  cfg.viewFor[myName() or "?"] = v
  paint()
end

box:SetScript("OnDragStart", function(self) self.dragging = true; if not cfg.locked then self:StartMoving() end end)
box:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local x, y = self:GetLeft(), self:GetTop()
  if x and y then self:ClearAllPoints(); self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y); cfg.point = { x, y } end
end)
box:SetScript("OnMouseUp", function(self, which)
  if self.dragging then self.dragging = nil; return end
  if which == "LeftButton" and cfg then setView(view() == "big" and "small" or "big") end
end)
box:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:AddLine("LayerETA", 1, 0.82, 0.3)
  GameTooltip:AddLine(L("hint"), 0.6, 0.6, 0.6); GameTooltip:Show()
end)
box:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- where a swap is: 0 nothing, 1 asking, 2 invited or in the group, 3 moved
local function stage()
  local j = job
  if j then
    if j.movedAt then return 3 end
    if j.host then return 2 end
    return 1
  end
  if lastDoneAt and GetTime() - lastDoneAt < 10 then return 3 end
  return 0
end

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
  local asked = ns.HostAsk and ns.HostAsk.sentCount() or 0
  if asked > 0 then return L("othersAsked", asked) end
  local n = countHosts()
  return n > 0 and L("lookingN", n) or L("looking")
end

-- the line under the name, and its dot: green ready, blue swapping, gold for a fresh layer
local function headline()
  if job then return L("swapping"), C.blue end
  if Quota.full() then return L("spentShort", Quota.untilNext()), C.faint end
  local log = Quota.list()
  local last = log[#log]
  if last and time() - last < 600 then return L("newSince", date("%H:%M", last)), C.gold end
  return L("ready"), C.green
end

paint = function()
  if not cfg then return end
  if cfg.hidden then box:Hide(); return end
  box:Show()
  if box.scaleNow ~= cfg.scale then box.scaleNow = cfg.scale; box:SetScale(cfg.scale or 1) end
  head:SetText(L("title"))
  local line, color = headline()
  dot:SetVertexColor(rgb(color))
  local count = Quota.count()
  local busy = job ~= nil and not job.inGroupAt
  local spent = not job and Quota.full()
  local isBig = view() == "big"
  big:SetShown(isBig); mini:SetShown(not isBig)

  if not isBig then
    box:SetWidth(SMALL_W)
    sub:SetText(line .. "  ·  " .. count .. "/15")
    sub:SetWidth(SMALL_W - 40 - 64)
    miniText:SetText(busy and L("stop") or (spent and L("waitShort")) or L("swap"))
    mini.busy = busy or spent; paintButton(mini, miniBg, miniText)
    if box.heightNow ~= 40 then box.heightNow = 40; box:SetHeight(40) end
    return
  end

  box:SetWidth(BIG_W)
  sub:SetText(line); sub:SetWidth(BIG_W - 56)
  local inner = BIG_W - 2 * PAD
  local y = 40
  rule1:ClearAllPoints(); rule1:SetPoint("TOPLEFT", PAD, -y); rule1:SetPoint("TOPRIGHT", -PAD, -y)
  y = y + 8

  -- the three steps, shown while a swap runs and a moment after it moved you
  local now = stage()
  local stepW = (inner - 8) / 3
  local names = { L("stepAsk"), L("stepInvite"), L("stepMove") }
  for i, st in ipairs(steps) do
    st.bar:SetShown(now > 0); st.word:SetShown(now > 0)
    if now > 0 then
      st.bar:ClearAllPoints(); st.bar:SetPoint("TOPLEFT", PAD + (i - 1) * (stepW + 4), -y); st.bar:SetWidth(stepW)
      st.word:ClearAllPoints(); st.word:SetPoint("TOP", st.bar, "BOTTOM", 0, -4); st.word:SetText(names[i])
      local c = (i < now or now == 3) and C.gold or (i == now and C.blue) or C.slot
      st.bar:SetVertexColor(rgb(c))
      st.word:SetTextColor(rgb((i < now or now == 3) and { 0.75, 0.78, 0.84 } or (i == now and C.blue) or C.faint))
    end
  end
  if now > 0 then y = y + 20 end

  local status = jobText()
  msg:SetShown(status ~= nil)
  if status then
    msg:ClearAllPoints(); msg:SetPoint("TOPLEFT", PAD, -y); msg:SetWidth(inner)
    msg:SetText(status)
    y = y + math.max(12, msg:GetStringHeight() or 12) + 7
  end

  wide:ClearAllPoints(); wide:SetPoint("TOPLEFT", PAD, -y); wide:SetWidth(inner)
  wideText:SetText(busy and L("stop") or (spent and L("waitBtn", Quota.untilNext())) or L("swapLayer"))
  wide.busy = busy or spent; paintButton(wide, wideBg, wideText)
  y = y + 28 + 10

  hourLeft:ClearAllPoints(); hourLeft:SetPoint("TOPLEFT", PAD, -y); hourLeft:SetText(L("hourLabel"))
  hourRight:ClearAllPoints(); hourRight:SetPoint("TOPRIGHT", -PAD, -y); hourRight:SetText(count .. "/15")
  y = y + 14
  local tickW = (inner - 14 * 2) / 15
  for i, t in ipairs(ticks) do
    t:ClearAllPoints(); t:SetPoint("TOPLEFT", PAD + (i - 1) * (tickW + 2), -y); t:SetSize(tickW, 4)
    t:SetVertexColor(rgb(i <= count and C.gold or C.slot))
  end
  y = y + 4 + 9
  rule2:ClearAllPoints(); rule2:SetPoint("TOPLEFT", PAD, -y); rule2:SetPoint("TOPRIGHT", -PAD, -y)
  y = y + 8

  hostLine:ClearAllPoints(); hostLine:SetPoint("TOPLEFT", PAD, -y); hostLine:SetPoint("TOPRIGHT", -PAD, -y)
  hostText:SetText(L("hostLabel")); drawSwitch()
  y = y + 14
  hostNote:SetShown(hosting())
  if hosting() then
    local hosted = #Host.recent()
    hostNote:ClearAllPoints(); hostNote:SetPoint("TOPLEFT", PAD, -(y + 2))
    hostNote:SetText(hosted > 0 and L("hostCount", hosted) or L("hosting"))
    y = y + 14
  end
  local height = y + 10
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
    if job and job.inGroupAt then
      if job.movedAt then lastDoneAt = GetTime() end
      finish(job.movedAt and L("moved") or nil, 10)
    end
  elseif ev == "SHARD_TRANSFER" then
    onMoved()
  elseif ev == "WHO_LIST_UPDATE" then
    if ns.HostAsk then ns.HostAsk.onWhoList(myName()) end
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
  if job or (cfg._noteUntil and now < cfg._noteUntil + 1) or Quota.count() > 0 then paint() end
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
  elseif cmd == "others" then cfg.others = not cfg.others; say(cfg.others and L("othersOn") or L("othersOff"))
  elseif cmd == "small" or cmd == "big" then setView(cmd)
  elseif cmd == "lock" then cfg.locked = not cfg.locked; say(cfg.locked and L("locked") or L("unlocked"))
  elseif cmd == "leave" and tonumber(arg) then cfg.leaveDelay = math.max(0, math.min(120, tonumber(arg)))
  elseif cmd == "da" or cmd == "en" then cfg.lang = cmd; paint()
  elseif cmd == "debug" then
    say("debug")
    print("  LayerETA channel: " .. tostring((Net.channelId())) .. "   layer channel: " .. tostring((layerChannel())))
    print("  zone map id: " .. tostring((zoneId())) .. "   swaps this hour: " .. Quota.count() .. "/15")
    print("  hosting: " .. tostring(hosting()) .. " (" .. #Host.recent() .. " invites in 10 min)   hosts seen: " .. countHosts())
    print("  swap running: " .. tostring(job ~= nil) .. "   skipped hosts: " .. table.concat(hostsToSkip(), ", "))
  elseif cmd == "help" or cmd == "?" then say(L("help"))
  else cfg.hidden = not cfg.hidden; paint() end
end
