-- LayerETA: ask hosts outside LayerETA for an invite.
-- Copyright (c) 2026 Rasmus. All Rights Reserved.
--
-- This file asks players in your zone who host with another layer addon for a group invite. It
-- only sends a short request line; it does not host or read layers. All code here is our own.
--
--   1. a /who search for the players in your zone
--   2. one hidden addon whisper to each of them, in the request format those hosts answer
--   3. a host who hears it may invite you; LayerETA itself handles the invite (LayerETA.lua)
--
-- The game's own who list would pop open when the answer arrives, so the list frames stop listening
-- to WHO_LIST_UPDATE while our search runs and listen again right after.

local _, ns = ...
local Ask = {}
ns.HostAsk = Ask

local PREFIX = "Layer" .. "Swap"   -- the addon message prefix those hosts listen on
local PER_SECOND = 5   -- whispers per second, so the client never throttles us
local MAX_NAMES = 40
local LIST_FRAMES = { "FriendsFrame", "WhoFrame", "LFGWhoListFrame" }

local run        -- the search in progress: { line, zone, names, sent, stillWanted }
local quieted = {}

local function plain(v) return not (type(issecretvalue) == "function" and issecretvalue(v)) end

function Ask.available()
  return C_FriendList and type(C_FriendList.SendWho) == "function" and type(C_FriendList.GetWhoInfo) == "function"
    and C_ChatInfo and type(C_ChatInfo.SendAddonMessage) == "function"
end

local function quiet()
  for _, name in ipairs(LIST_FRAMES) do
    local frame = _G[name]
    if type(frame) == "table" and frame.IsEventRegistered and not quieted[name] then
      local okShown, shown = pcall(frame.IsShown, frame)
      local okReg, reg = pcall(frame.IsEventRegistered, frame, "WHO_LIST_UPDATE")
      if okShown and shown ~= true and okReg and reg == true then
        pcall(frame.UnregisterEvent, frame, "WHO_LIST_UPDATE")
        quieted[name] = frame
      end
    end
  end
end

local function loud()
  for name, frame in pairs(quieted) do
    pcall(frame.RegisterEvent, frame, "WHO_LIST_UPDATE")
    quieted[name] = nil
  end
end

local function whisperNext(r)
  if run ~= r then return end
  if not r.stillWanted() then run = nil; return end
  local n = 0
  while n < PER_SECOND and #r.names > 0 do
    local target = table.remove(r.names, 1)
    local ok = pcall(C_ChatInfo.SendAddonMessage, PREFIX, r.line, "WHISPER", target)
    if ok then r.sent = r.sent + 1 end
    n = n + 1
  end
  if #r.names > 0 then C_Timer.After(1, function() whisperNext(r) end) else run = nil end
end

-- start one ask. stillWanted() returns false once the swap is over or an invite came in.
function Ask.start(zoneMapId, zoneName, x, y, stillWanted, skip)
  if not Ask.available() or not zoneMapId then return false end
  local line = "inv layer <LS " .. zoneMapId .. " r2"
  if x and y then line = line .. string.format(" %.1f,%.1f", x * 100, y * 100) end
  line = line .. ">"
  run = { line = line, zone = zoneName, names = nil, sent = 0, stillWanted = stillWanted or function() return true end, skip = skip or {} }
  local r = run
  quiet()
  local filter = zoneName and ('z-"' .. zoneName .. '"') or ""
  local ok = pcall(C_FriendList.SendWho, filter)
  if not ok then run = nil; loud(); return false end
  C_Timer.After(10, function() if run == r and not r.names then run = nil end; loud() end)
  return true
end

-- WHO_LIST_UPDATE: collect the names and start whispering
function Ask.onWhoList(myName)
  local r = run
  loud()
  if not r or r.names then return end
  r.names = {}
  local okN, count = pcall(C_FriendList.GetNumWhoResults)
  if not okN or not plain(count) or type(count) ~= "number" then count = 0 end
  for i = 1, math.min(count, MAX_NAMES) do
    local ok, who = pcall(C_FriendList.GetWhoInfo, i)
    local name = ok and type(who) == "table" and plain(who.fullName) and who.fullName or nil
    local short = type(name) == "string" and name:match("^([^%-]+)") or name
    if type(name) == "string" and name ~= "" and name ~= myName and short ~= myName and not r.skip[short] and not r.skip[name] then
      r.names[#r.names + 1] = name
    end
  end
  whisperNext(r)
end

function Ask.sentCount() return run and run.sent or 0 end
