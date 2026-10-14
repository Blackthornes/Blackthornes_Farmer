-- Blackthornes Farmer -- Logic/TopFarm.lua
-- After an auction scan, your board in its new order (the owner,
-- 2026-10-14: "can Farmer give an alert after an auction scan if it detects
-- a new top farm?", then "a rankings shuffle animation if other positions
-- change too").
--
-- Only your own verified kills count (the owner: "it bases this on your
-- verified kills"): the board is RankUp's measured one, mobs you have
-- killed MIN_KILLS times or more, coin included. Database estimates and
-- guild data never reach it.
--
-- How it knows a scan finished: Tradeskills tells it
-- (`_G.BlackthornesTS.Prices:WatchScans`, read in a pcall). Without that
-- call (no Tradeskills, or an older one) it looks once when the auction
-- house closes, since TSM's or Auctionator's prices may have moved.
--
-- What it shows, one pop-up a scan at most:
--   a new top farm  a different mob is first now, worth at least LEAD more
--                   a kill than the old leader at the new prices, and that
--                   mob was not called the top farm in the last QUIET
--                   seconds: the board shuffles, the new leader rises to
--                   the top, the top farm sound plays;
--   a shuffle       otherwise, when places in the top moved: the board
--                   shuffles with the rank-up chime.
--
-- Either waits, sound and all, until the auction house and the game's
-- other windows are closed and no fight is on (TopFarm:Busy).
--
-- Smooth play: nothing happens until SETTLE seconds after the scan, never
-- in a fight, and the board is valued again a few mobs a frame
-- (RankUp:Build with the old order kept until the new one is done).

local _, ns = ...
local L = ns.L

local TopFarm = ns.NewModule("TopFarm")

local Util = ns.Util

-- Seconds after a scan before looking, so the scan's own work is done.
TopFarm.SETTLE = 2
-- How much more a kill the new leader must be worth than the old one.
TopFarm.LEAD = 1.10
-- The same mob is called the top farm at most once in this many seconds.
TopFarm.QUIET = 24 * 60 * 60

function TopFarm.On()
    return not (ns.db and ns.db.topFarmAlert == false)
end

--- True when Tradeskills will tell us about each scan.
function TopFarm:Watching()
    return self.watching and true or false
end

local function InCombat()
    local ok, fighting = pcall(function()
        return (InCombatLockdown and InCombatLockdown())
            or (UnitAffectingCombat and UnitAffectingCombat("player"))
    end)
    return ok and fighting and true or false
end

--------------------------------------------------------------------------------
-- Hearing about a scan
--------------------------------------------------------------------------------

--- Ask Tradeskills to tell us when a scan finishes. True when it will.
function TopFarm:Watch()
    if self.watching then return true end
    local ts = rawget(_G, "BlackthornesTS")
    local prices = type(ts) == "table" and ts.Prices
    if type(prices) ~= "table" or type(prices.WatchScans) ~= "function" then return false end

    local ok, watching = pcall(prices.WatchScans, prices, function() TopFarm:ScanFinished() end)
    self.watching = ok and watching and true or false
    return self.watching
end

--- A scan finished (or, without Tradeskills' word, the auction house
--- closed): look SETTLE seconds later.
function TopFarm:ScanFinished()
    if not self.On() or self.pending then return end
    self.pending = true
    C_Timer.After(self.SETTLE, function()
        TopFarm.pending = false
        TopFarm:Look()
    end)
end

--- Value the board again with the new prices, and show what moved.
function TopFarm:Look()
    if not self.On() then return end
    if InCombat() then
        self.waiting = true
        return
    end
    self.waiting = false

    local RankUp = ns.RankUp
    -- No order yet (still laying out after login, with these prices
    -- already), or one being laid out now: nothing to compare with.
    if not (RankUp and RankUp.snapshot) or RankUp.building then return end

    RankUp:Build(true, function(old, new) TopFarm:Compare(old, new) end)
end

--------------------------------------------------------------------------------
-- What moved
--------------------------------------------------------------------------------

--- The told list: when each mob was last called the top farm.
local function Told()
    if not ns.db then return {} end
    ns.db.topFarmTold = type(ns.db.topFarmTold) == "table" and ns.db.topFarmTold or {}
    return ns.db.topFarmTold
end

--- What the scan did to the board. `old` and `new` are RankUp snapshots.
--- Returns the move for the pop-up, or nil when no place in the top moved:
--- { before, after, mob, from, to, scan = true, newTop, passed, climbs,
--- lead }.
function TopFarm.Moves(old, new, now)
    if type(old) ~= "table" or type(new) ~= "table" then return nil end
    local before, after = old.list or {}, new.list or {}
    if #after == 0 then return nil end

    local top = ns.RankUp.TOP
    local wasRank = {}
    for _, entry in ipairs(before) do wasRank[entry.mob] = entry.rank end

    local moved = false
    local climbs = {}
    for rank = 1, math.min(top, #after) do
        local entry = after[rank]
        local was = wasRank[entry.mob]
        if was ~= rank then moved = true end
        if was and was > rank then climbs[entry.mob] = was - rank end
    end
    if not moved then return nil end

    local move = {
        scan = true,
        before = ns.RankUp.Top(before, top + 1),
        after = ns.RankUp.Top(after, top + 1),
        climbs = climbs,
    }

    -- A new top farm: a different mob first, by a clear margin at the new
    -- prices, and not called the top farm lately.
    local leader, oldLeader = after[1], before[1]
    if oldLeader and leader.mob ~= oldLeader.mob then
        local rival = new.byMob[oldLeader.mob]
        local rivalValue = rival and rival.value or 0
        local told = Told()[leader.mob]
        if leader.value >= rivalValue * TopFarm.LEAD
            and not (tonumber(told) and (now or time()) - told < TopFarm.QUIET) then
            move.newTop = true
            move.passed = oldLeader.mob
            move.passedValue = rivalValue
            move.lead = rivalValue > 0 and (leader.value / rivalValue - 1) or nil
        end
    end

    -- The mob the pop-up lights: the new leader, else the longest climb.
    if move.newTop then
        move.mob = leader.mob
    else
        local best, bestClimb
        for mob, climb in pairs(climbs) do
            if not best or climb > bestClimb or (climb == bestClimb and mob < best) then
                best, bestClimb = mob, climb
            end
        end
        move.mob = best
    end

    if move.mob then
        move.from = wasRank[move.mob]
        move.to = new.byMob[move.mob] and new.byMob[move.mob].rank
        move.new = not move.from
    end
    return move
end

--- The new order is laid out: show what moved.
--- The new order is laid out. What moved is kept until the auction house
--- and the game's other windows are closed (the owner, 2026-10-14: the
--- sound played behind the auction house), then shown, sound and all.
--- A second scan before then folds into the first: the board shows the
--- move from the order before the first to the order after the last.
function TopFarm:Compare(old, new)
    if not self.On() then return end
    if not self.heldOld then self.heldOld = old end
    self.heldNew = new
    self:TryShow()
end

--- The game windows that would cover the pop-up, one at a time: the
--- auction house, then any of the game's own panels (bags and the like
--- are not panels, so they never hold it).
local PANELS = { "left", "center", "right", "doublewide", "fullscreen" }

function TopFarm:Busy()
    if self.atAuction or InCombat() then return true end

    for _, name in ipairs({ "AuctionHouseFrame", "AuctionFrame" }) do
        local frame = rawget(_G, name)
        if type(frame) == "table" then
            local ok, shown = pcall(frame.IsShown, frame)
            if ok and shown then return true end
        end
    end

    local getPanel = rawget(_G, "GetUIPanel")
    if type(getPanel) == "function" then
        for _, key in ipairs(PANELS) do
            local ok, panel = pcall(getPanel, key)
            if ok and panel then return true end
        end
    end
    return false
end

--- Show what is held now if nothing covers it; else look again every
--- WAIT_TICK seconds, and at once when the auction house closes or a
--- fight ends. Only while something is held.
TopFarm.WAIT_TICK = 1

function TopFarm:TryShow()
    if not self.heldNew then return self:StopWaiting() end
    if not self.On() then
        self.heldOld, self.heldNew = nil, nil
        return self:StopWaiting()
    end

    if self:Busy() then
        if not self.ticker and C_Timer and C_Timer.NewTicker then
            self.ticker = C_Timer.NewTicker(self.WAIT_TICK, function() TopFarm:TryShow() end)
        end
        return
    end
    self:StopWaiting()

    local old, new = self.heldOld, self.heldNew
    self.heldOld, self.heldNew = nil, nil

    local move = TopFarm.Moves(old, new, time())
    if not move then return end

    if move.newTop then Told()[move.mob] = time() end
    move.sound = ns.RankUp.SoundOn()

    if ns.RankUpUI then
        local ok, err = pcall(ns.RankUpUI.Show, ns.RankUpUI, move)
        if not ok then ns.Debug("top farm pop-up:", tostring(err)) end
    end
end

function TopFarm:StopWaiting()
    if self.ticker then
        pcall(self.ticker.Cancel, self.ticker)
        self.ticker = nil
    end
end

--- True while a pop-up waits for the windows to close.
function TopFarm:Holding()
    return self.heldNew ~= nil
end

--- The pop-up as a scan would show it, from the board as it stands: the
--- second mob rises to the top (`/farm topfarm test`, Settings).
function TopFarm:Try()
    local snapshot = ns.RankUp:BuildNow()
    local list = snapshot and snapshot.list or {}
    if #list < 2 then
        ns.Print(L.Format("you need two mobs with %d kills each on your board to see it.", ns.Tracker.MIN_KILLS))
        return
    end

    -- The board as it stood "before": the top two the other way round.
    local before = {}
    for index, entry in ipairs(list) do
        before[index] = { mob = entry.mob, value = entry.value, kills = entry.kills, rank = index }
    end
    before[1], before[2] = before[2], before[1]
    before[1].rank, before[2].rank = 1, 2
    before[2].value = math.floor(list[1].value * 0.8)

    local byMob = {}
    for _, entry in ipairs(list) do byMob[entry.mob] = entry end

    local move = TopFarm.Moves({ list = before }, { list = list, byMob = byMob }, 0)
    if not move then return end
    move.newTop, move.passed = true, list[2].mob
    move.passedValue = list[2].value
    move.lead = list[2].value > 0 and (list[1].value / list[2].value - 1) or nil
    move.mob, move.from, move.to, move.new = list[1].mob, 2, 1, false
    move.sound = ns.RankUp.SoundOn()

    if ns.RankUpUI then ns.RankUpUI:Show(move) end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function TopFarm:OnEnable()
    -- At PLAYER_LOGIN, so Tradeskills has loaded whichever comes first.
    self:Watch()

    ns.RegisterEvent(self, "AUCTION_HOUSE_SHOW", function()
        TopFarm.atAuction = true
    end)
    ns.RegisterEvent(self, "AUCTION_HOUSE_CLOSED", function()
        TopFarm.atAuction = false
        if not TopFarm:Watch() then TopFarm:ScanFinished() end
        TopFarm:TryShow()
    end)

    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        if TopFarm.waiting then TopFarm:Look() end
        TopFarm:TryShow()
    end)
end

--------------------------------------------------------------------------------
-- Command
--------------------------------------------------------------------------------

function TopFarm:SetOn(on)
    if ns.db then ns.db.topFarmAlert = on and true or false end
    if not on then
        self.waiting = false
        self.heldOld, self.heldNew = nil, nil
        self:StopWaiting()
    end
end

ns.RegisterCommand("topfarm", L["show your top 15 after an auction scan and call out a new top farm (on/off, test)"], function(rest)
    local argument = Util.Trim(rest):lower()

    if argument == "test" then
        TopFarm:Try()
        return
    end

    if argument == "on" then
        TopFarm:SetOn(true)
    elseif argument == "off" then
        TopFarm:SetOn(false)
    else
        TopFarm:SetOn(not TopFarm.On())
    end
    ns.Print(TopFarm.On()
        and L["after an auction scan, your top 15 shows its new order and calls out a new top farm. /farm topfarm off to stop."]
        or L["nothing shows after an auction scan. /farm topfarm on to bring it back."])

    if ns.SettingsUI and ns.SettingsUI.Refresh then ns.SettingsUI:Refresh() end
end)
