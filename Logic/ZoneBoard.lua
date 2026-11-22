-- Blackthornes Farmer -- Logic/ZoneBoard.lua
-- The Zone Board (the owner said build it, 2026-11-18, from a mockup whose
-- words he approved, option A): one small window for the zone you stand in.
--
--   FINISH  every mob the drop list and your own loot put in this zone, with
--           your own kills on its line here, until each has 20 and its drop
--           list opens. Rares, bosses, town guards, critters and dungeon
--           mobs are left out; Skip puts one away for this zone.
--   BEST    the mobs here you have unlocked (20 or more of your own kills on
--           the zone's line), ranked by Rankings' own worth a kill. Every
--           other mob is a mystery: "N more kills to find out", never a
--           rate, an item or a guess (option A, no coin hint).
--
-- Take Me There starts a hunt: the arrow points at the mob's camp
-- (Arrow:Grind) and the board shows it while it runs: the mob hunted on top,
-- Next Mob and Stop (UI/ZoneBoard.lua).
-- At the 20th kill the hunt moves on by itself. Finishing the zone and a new
-- best mob each get a moment (UI/ZoneBoardFX.lua).
--
-- Smooth play: the zone's list is laid out once a zone change (or when what
-- it is built from moves), BUDGET mobs a frame, and kept. A kill moves one
-- row's count. Worth is worked out again only after an auction scan or a
-- 20th kill. Nothing here runs on a timer; the windows ask for distances
-- once a second while they show.
--
-- Saved, account wide, never rename them:
--   zoneBoard          nil off, true on (off until ticked)
--   zoneBoardHunt      the old Hunt Window: box, left in saves, unread
--   zoneBoardBanner    nil on, false off (Zone Done Banner:)
--   zoneBoardNear      nil on, false off (Near Me First:)
--   zoneBoardShowDone  true when Show Finished: is ticked
--   zoneBoardTab       "finish" or "best"
--   zoneBoardSkips     [zone][mob] = true, the mobs Skip put away
--   zoneBoardLeftOut   [mob] = "rare" | "boss" | "faction", read in game
--   zoneBoardDone      [zone] = time the zone was finished
--   zoneBoardScale     its size grip (zoneHuntScale, the old hunt
--                      window's, is left in saves, unread)
-- Own kills only: no shipped or guild data ranks a mob or shows a rate.

local _, ns = ...
local L = ns.L

local ZoneBoard = ns.NewModule("ZoneBoard")

ZoneBoard.ALMOST = 15         -- kills from which a row says ALMOST
ZoneBoard.HIGH = 3            -- levels over yours that read orange
ZoneBoard.BUDGET = 150        -- mob spots looked at a frame while laying out
ZoneBoard.CARD_DELAY = 1.5    -- seconds after the 20 kill fanfare for the card

-- Town guards known by name. Most others are told in game: a town guard
-- belongs to the Alliance or the Horde (UnitFactionGroup), a wild mob to
-- neither.
ZoneBoard.GUARDS = {
    ["Stormwind City Guard"] = true, ["Stormwind Royal Guard"] = true, ["Stormwind City Patroller"] = true,
    ["Ironforge Guard"] = true, ["Ironforge Mountaineer"] = true, ["Darnassus Sentinel"] = true,
    ["Orgrimmar Grunt"] = true, ["Undercity Guardian"] = true, ["Bluffwatcher"] = true,
    ["Ironforge Guard Captain"] = true, ["Silvermoon Guardian"] = true,
}
local GUARD_PATTERNS = { "^Deathguard ", " Guard$", " Grunt$", " Sentinel$", "Bluffwatcher", " Guardian$" }
-- Pattern guards count only where the name also starts with a town's.
local TOWN_WORDS = {
    "Stormwind", "Ironforge", "Darnassus", "Orgrimmar", "Undercity", "Thunder Bluff", "Goldshire",
    "Southshore", "Tarren Mill", "Lakeshire", "Sentinel Hill", "Menethil", "Booty Bay", "Ratchet",
    "Gadgetzan", "Everlook", "Theramore", "Crossroads", "Razor Hill", "Kharanos", "Brill", "Astranaar",
    "Auberdine", "Darkshire", "Hammerfall", "Stonard", "Kargath", "Splintertree", "Camp Taurajo",
    "Bloodhoof", "Sepulcher", "Nijel's Point", "Feathermoon", "Camp Mojache", "Thalanaar", "Refuge Pointe",
}

local function Tracker() return ns.Tracker end
local function Spots() return ns.Spots end

local function Fighting()
    return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

function ZoneBoard.IsOn() return not (ns.db and ns.db.zoneBoard == false) end
function ZoneBoard.BannerOn() return not (ns.db and ns.db.zoneBoardBanner == false) end
function ZoneBoard.NearFirst() return not (ns.db and ns.db.zoneBoardNear == false) end
function ZoneBoard.ShowDone() return ns.db and ns.db.zoneBoardShowDone == true or false end

-- Never in a fight: a redraw then waits for PLAYER_REGEN_ENABLED.
local function Redraw()
    if Fighting() then
        ZoneBoard.waiting = true
        return
    end
    if ns.ZoneBoardUI and ns.ZoneBoardUI.Refresh then pcall(ns.ZoneBoardUI.Refresh, ns.ZoneBoardUI) end
end

local function Others()
    if ns.TrackerUI and ns.TrackerUI.Refresh then pcall(ns.TrackerUI.Refresh, ns.TrackerUI) end
    if ns.SettingsUI and ns.SettingsUI.Refresh then pcall(ns.SettingsUI.Refresh, ns.SettingsUI) end
end

function ZoneBoard:SetOn(on)
    if not ns.db then return end
    if on then ns.db.zoneBoard = nil else ns.db.zoneBoard = false end
    if not on then self:StopHunt() end
    Redraw()
    Others()
end

function ZoneBoard:SetBanner(on)
    if not ns.db then return end
    if on then ns.db.zoneBoardBanner = nil else ns.db.zoneBoardBanner = false end
end

function ZoneBoard:SetNearFirst(on)
    if not ns.db then return end
    if on then ns.db.zoneBoardNear = nil else ns.db.zoneBoardNear = false end
    Redraw()
end

function ZoneBoard:SetShowDone(on)
    if not ns.db then return end
    ns.db.zoneBoardShowDone = on and true or nil
    Redraw()
end

function ZoneBoard.Tab()
    local tab = ns.db and ns.db.zoneBoardTab
    return tab == "best" and "best" or "finish"
end

function ZoneBoard:SetTab(tab)
    if not ns.db then return end
    ns.db.zoneBoardTab = tab == "best" and "best" or nil
end

--------------------------------------------------------------------------------
-- Who is left out
--------------------------------------------------------------------------------

local function Store(key)
    if not ns.db then return {} end
    if type(ns.db[key]) ~= "table" then ns.db[key] = {} end
    return ns.db[key]
end

--- Read what kind of mob `unit` is, from Harvest:NoteUnit for every mob you
--- meet: a rare, a boss or a town guard is kept, once. One pcall each, a
--- write only when it is new.
function ZoneBoard:Learn(unit, name)
    if not ZoneBoard.IsOn() or type(name) ~= "string" or name == "" then return end
    local Readable = ns.Harvest and ns.Harvest.Readable
    if not Readable then return end
    local kind
    if type(UnitClassification) == "function" then
        local ok, value = pcall(UnitClassification, unit)
        value = ok and Readable(value) or nil
        if value == "rare" or value == "rareelite" then kind = "rare"
        elseif value == "worldboss" then kind = "boss" end
    end
    if not kind and type(UnitFactionGroup) == "function" then
        local ok, faction = pcall(UnitFactionGroup, unit)
        faction = ok and Readable(faction) or nil
        if faction == "Alliance" or faction == "Horde" then kind = "faction" end
    end
    if not kind then return end
    local store = Store("zoneBoardLeftOut")
    if store[name] ~= kind then
        store[name] = kind
        self.version = (self.version or 0) + 1
    end
end

--- Is `name` a town guard by its name alone?
function ZoneBoard.IsGuardName(name)
    if type(name) ~= "string" then return false end
    if ZoneBoard.GUARDS[name] then return true end
    for _, pattern in ipairs(GUARD_PATTERNS) do
        if name:find(pattern) then
            if pattern == "^Deathguard " or pattern == "Bluffwatcher" then return true end
            for _, town in ipairs(TOWN_WORDS) do
                if name:find(town, 1, true) == 1 then return true end
            end
        end
    end
    return false
end

--- Why a mob spot is left off the board, or nil when it is on it.
function ZoneBoard.LeftOut(mob)
    local name = mob and mob.name
    if type(name) ~= "string" then return "none" end
    local Grinding = ns.Grinding
    if Grinding and Grinding.IsGroup(name) then return "group" end
    if Spots().IsInstance(mob.zone) or Spots().IsInstance(mob.location) then return "dungeon" end
    local learned = ns.db and type(ns.db.zoneBoardLeftOut) == "table" and ns.db.zoneBoardLeftOut[name]
    if learned then return learned end
    if ZoneBoard.IsGuardName(name) then return "faction" end
    if Grinding and Grinding.TypeOf(name) == "Critter" then return "critter" end
    -- A boss shows as level -1 ("??").
    if tonumber(mob.minLevel) and tonumber(mob.minLevel) < 0 then return "boss" end
    return nil
end

--------------------------------------------------------------------------------
-- Skips
--------------------------------------------------------------------------------

function ZoneBoard.Skipped(zone, name)
    local skips = ns.db and type(ns.db.zoneBoardSkips) == "table" and ns.db.zoneBoardSkips[zone]
    return type(skips) == "table" and skips[name] == true or false
end

function ZoneBoard:Skip(zone, name)
    if type(zone) ~= "string" or type(name) ~= "string" then return end
    local skips = Store("zoneBoardSkips")
    skips[zone] = type(skips[zone]) == "table" and skips[zone] or {}
    skips[zone][name] = true
    self.version = (self.version or 0) + 1
    -- BEST is kept between draws: build it again without this mob.
    self.worth = nil
    if self.hunt and self.hunt.target == name then self:NextMob() end
    Redraw()
    self:CheckDone(zone)
end

--- How many mobs are hidden from `zone`'s board.
function ZoneBoard.SkipCount(zone)
    local skips = ns.db and type(ns.db.zoneBoardSkips) == "table" and ns.db.zoneBoardSkips[zone]
    local count = 0
    if type(skips) == "table" then
        for _, on in pairs(skips) do if on == true then count = count + 1 end end
    end
    return count
end

--- Bring back every mob skipped in `zone`.
function ZoneBoard:Unskip(zone)
    local skips = ns.db and type(ns.db.zoneBoardSkips) == "table" and ns.db.zoneBoardSkips
    if skips then skips[zone] = nil end
    self.version = (self.version or 0) + 1
    self.worth = nil
    Redraw()
end

--------------------------------------------------------------------------------
-- Your kills on a zone's line
--------------------------------------------------------------------------------

--- Your own kills of `name` in `zone` (the data's English name), and the key
--- of its line there for Rankings: the zone's once the name is split, else
--- the name.
function ZoneBoard.Kills(name, zone)
    local T = Tracker()
    local mob = T and type(name) == "string" and T:Store()[name]
    if type(mob) ~= "table" then return 0, name end
    local kills, kept = 0, nil
    local most = -1
    for where, tally in pairs(type(mob.zones) == "table" and mob.zones or {}) do
        if type(where) == "string" and type(tally) == "table" and Spots().English(where) == zone then
            local count = tonumber(tally.kills) or 0
            kills = kills + count
            if count > most then most, kept = count, where end
        end
    end
    local key = name
    if kept and T:IsSplit(name) then key = T.ZoneKey(name, kept) end
    return kills, key
end

--------------------------------------------------------------------------------
-- The zone's mobs
--------------------------------------------------------------------------------

--- The zone you stand in, by the data's English name, or nil.
function ZoneBoard.Here()
    local ok, player = pcall(Spots().Player, Spots())
    local zone = ok and player and player.zone
    if type(zone) ~= "string" or zone == "" then return nil end
    return zone
end

--- What the list is laid out from: the Grind tab's mob spots, hides, skips
--- and what was learned in game.
local function Stamp(zone)
    local grind = ns.Grinding
    local mobs = grind and grind.cacheStamp or ""
    return table.concat({ tostring(zone), tostring(mobs), tostring(ZoneBoard.version or 0),
        tostring(ns.DB and ns.DB.hiddenVersion or 0) }, "|")
end

--- One entry a mob name in the zone: { name, zone, location, spots,
--- minLevel, maxLevel }. Spots are the Grind tab's (Grinding:Mobs). Laid out
--- in one go; Build spreads the same work over frames.
local function Collect(zone, list, byName, mob)
    if mob.zone ~= zone then return end
    local why = ZoneBoard.LeftOut(mob)
    if why then
        list.leftOut[mob.name] = why
        return
    end
    local entry = byName[mob.name]
    if not entry then
        entry = { name = mob.name, zone = zone, spots = {} }
        byName[mob.name] = entry
        list.entries[#list.entries + 1] = entry
    end
    entry.spots[#entry.spots + 1] = mob
    if mob.minLevel then
        entry.minLevel = math.min(entry.minLevel or mob.minLevel, mob.minLevel)
        entry.maxLevel = math.max(entry.maxLevel or mob.maxLevel or mob.minLevel, mob.maxLevel or mob.minLevel)
    end
    -- The place named most often, else the first.
    if mob.location and not entry.location then entry.location = mob.location end
end

local function Finish(list)
    table.sort(list.entries, function(a, b) return a.name < b.name end)
    -- A learned rare or guard leaves; a later sighting can come between
    -- spots of one name.
    for index = #list.entries, 1, -1 do
        if list.leftOut[list.entries[index].name] then table.remove(list.entries, index) end
    end
    list.ready = true
    return list
end

--- The zone's list, kept until its stamp moves: { zone, entries, leftOut,
--- ready }. `now` lays it out at once (the tests, a command); else it is
--- laid out BUDGET spots a frame and `ready` says when.
function ZoneBoard:List(zone, now)
    zone = zone or ZoneBoard.Here()
    if not zone then return nil end
    local stamp = Stamp(zone)
    local kept = self.list
    if kept and kept.stamp == stamp and (kept.ready or self.building == stamp) then return kept end
    if kept and kept.stamp ~= stamp and kept.zone == zone and kept.ready and not now then
        -- Same zone, something moved: keep showing the old list while the
        -- new one is laid out.
        self:Build(zone, stamp)
        return kept
    end
    if now then
        local grind = ns.Grinding
        local list = { zone = zone, stamp = stamp, entries = {}, leftOut = {} }
        local byName = {}
        for _, mob in pairs(grind and grind:Mobs().all or {}) do Collect(zone, list, byName, mob) end
        self.list = Finish(list)
        self.building = nil
        return self.list
    end
    self:Build(zone, stamp)
    return self.list and self.list.zone == zone and self.list or nil
end

--- Lay out the zone's list over frames.
function ZoneBoard:Build(zone, stamp)
    if self.building == stamp then return end
    self.building = stamp
    local grind = ns.Grinding
    local all = grind and grind:Mobs().all or {}
    -- Grinding:Mobs may have moved its stamp while it laid out.
    stamp = Stamp(zone)
    self.building = stamp
    local keys = {}
    for key in pairs(all) do keys[#keys + 1] = key end
    local list = { zone = zone, stamp = stamp, entries = {}, leftOut = {} }
    local byName, index = {}, 1
    local function Step()
        if ZoneBoard.building ~= stamp then return end
        local last = math.min(#keys, index + ZoneBoard.BUDGET - 1)
        for i = index, last do
            local mob = all[keys[i]]
            if mob then Collect(zone, list, byName, mob) end
        end
        index = last + 1
        if index <= #keys then
            if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
                C_Timer.After(0, Step)
            else
                Step()
            end
            return
        end
        ZoneBoard.list = Finish(list)
        ZoneBoard.building = nil
        ZoneBoard.worth = nil
        Redraw()
    end
    Step()
end

--- Each entry's kills and level colour, read fresh: cheap, a table look up
--- each. Returns the rows FINISH shows, unlocked and total counts.
function ZoneBoard:Rows(list)
    list = list or self:List()
    local rows, unlocked, total = {}, 0, 0
    if not list then return rows, 0, 0 end
    for _, entry in ipairs(list.entries) do
        if not ZoneBoard.Skipped(list.zone, entry.name) then
            entry.kills, entry.key = ZoneBoard.Kills(entry.name, list.zone)
            entry.done = entry.kills >= Tracker().MIN_KILLS
            total = total + 1
            if entry.done then unlocked = unlocked + 1 end
            if not entry.done or ZoneBoard.ShowDone() then rows[#rows + 1] = entry end
        end
    end
    return rows, unlocked, total
end

--- How far you are from an entry's nearest spot, in yards, or nil.
function ZoneBoard.Yards(entry, here)
    local Arrow = ns.Arrow
    if not (Arrow and here and entry) then return nil end
    local map = Arrow:ZoneMap(Spots().ZoneOf(entry.zone), here)
    if not map then return nil end
    local best
    for _, spot in ipairs(entry.spots or {}) do
        local coords = spot.coords
        if type(coords) == "table" and tonumber(coords[1]) and tonumber(coords[2]) then
            local north, west = Arrow.Offset(here, map, coords[1] / 100, coords[2] / 100)
            if north then
                local yards = Arrow.Measure(north, west)
                if not best or yards < best then best = yards end
            end
        end
    end
    return best
end

--- Where you stand, or nil.
function ZoneBoard.Position()
    local Arrow = ns.Arrow
    if not Arrow then return nil end
    local ok, here = pcall(Arrow.Here, Arrow)
    return ok and here or nil
end

--- Put the FINISH rows in order: nearest first with Near Me First, else the
--- ones closest to 20 first. Yards are measured here; `here` may be nil.
function ZoneBoard.Order(rows, here)
    for _, entry in ipairs(rows) do entry.yards = ZoneBoard.Yards(entry, here) end
    local near = ZoneBoard.NearFirst()
    table.sort(rows, function(a, b)
        if (a.done and true or false) ~= (b.done and true or false) then return not a.done end
        if near and (a.yards ~= nil) ~= (b.yards ~= nil) then return a.yards ~= nil end
        if near and a.yards and b.yards and a.yards ~= b.yards then return a.yards < b.yards end
        if a.kills ~= b.kills then return a.kills > b.kills end
        return a.name < b.name
    end)
    return rows
end

--- The colour key of a level: orange well above yours.
function ZoneBoard.LevelColor(entry, level)
    local low = entry and tonumber(entry.minLevel)
    if not level and type(UnitLevel) == "function" and ns.Harvest and ns.Harvest.ReadableNumber then
        local ok, value = pcall(UnitLevel, "player")
        level = ok and ns.Harvest.ReadableNumber(value) or nil
    end
    if not (low and level) then return "muted" end
    if low >= level + ZoneBoard.HIGH then return "orange" end
    if low >= level - 2 then return "warn" end
    if low >= level - 8 then return "good" end
    return "muted"
end

--------------------------------------------------------------------------------
-- BEST
--------------------------------------------------------------------------------

--- The unlocked mobs ranked by worth a kill, and the mysteries by kills to
--- go: { ranked = { { entry, value, best, bestID } }, mysteries = { entry } }.
--- Kept until a scan or a 20th kill (or the zone's list) moves it.
function ZoneBoard:Best(list)
    list = list or self:List()
    if not list then return { ranked = {}, mysteries = {} } end
    local kept = self.worth
    if kept and kept.stamp == list.stamp and kept.zone == list.zone then return kept end
    local out = { ranked = {}, mysteries = {}, stamp = list.stamp, zone = list.zone }
    self:Rows(list)
    local all = {}
    for _, entry in ipairs(list.entries) do
        if not ZoneBoard.Skipped(list.zone, entry.name) then all[#all + 1] = entry end
    end
    for _, entry in ipairs(all) do
        if entry.done then
            local ok, ranking = pcall(ns.Rankings.Entry, ns.Rankings, entry.key)
            if ok and ranking and ranking.group == "measured" and ranking.value then
                local best = ranking.best
                local id = best and Tracker():LookOf(best.name).id
                out.ranked[#out.ranked + 1] = { entry = entry, value = ranking.value,
                    best = best and best.name, bestID = id }
            end
        else
            out.mysteries[#out.mysteries + 1] = entry
        end
    end
    table.sort(out.ranked, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.entry.name < b.entry.name
    end)
    table.sort(out.mysteries, function(a, b)
        if a.kills ~= b.kills then return a.kills > b.kills end
        return a.name < b.name
    end)
    self.worth = out
    return out
end

--- Forget the worth: an auction scan finished, or a mob unlocked.
function ZoneBoard:Reprice()
    self.worth = nil
    Redraw()
end

--------------------------------------------------------------------------------
-- The hunt
--------------------------------------------------------------------------------

function ZoneBoard:Hunting() return self.hunt ~= nil end

--- The entry a hunt aims at.
function ZoneBoard:Target()
    local hunt = self.hunt
    local list = hunt and self:List(hunt.zone)
    if not list then return nil end
    for _, entry in ipairs(list.entries) do
        if entry.name == hunt.target then return entry end
    end
    return nil
end

--- The mobs still to finish, in the hunt's order: nearest first, the ones
--- passed with Next Mob last.
function ZoneBoard:Queue(here)
    local list = self.hunt and self:List(self.hunt.zone)
    if not list then return {} end
    local rows = self:Rows(list)
    local open = {}
    for _, entry in ipairs(rows) do
        if not entry.done then open[#open + 1] = entry end
    end
    for _, entry in ipairs(open) do entry.yards = ZoneBoard.Yards(entry, here) end
    local passed = self.hunt.passed or {}
    table.sort(open, function(a, b)
        if (passed[a.name] or 0) ~= (passed[b.name] or 0) then return (passed[a.name] or 0) < (passed[b.name] or 0) end
        if (a.yards ~= nil) ~= (b.yards ~= nil) then return a.yards ~= nil end
        if a.yards and b.yards and a.yards ~= b.yards then return a.yards < b.yards end
        if a.kills ~= b.kills then return a.kills > b.kills end
        return a.name < b.name
    end)
    return open
end

--- The camp for the arrow: the target's spots, and those of mobs still to
--- finish at the same place, so two mobs that share a camp are done together.
function ZoneBoard:Camp(entry, queue)
    if not entry then return nil end
    local camp = { zone = entry.zone, location = entry.location, label = entry.location or Spots().Show(entry.zone),
        mobs = {}, zoneBoard = true }
    for _, spot in ipairs(entry.spots) do camp.mobs[#camp.mobs + 1] = spot end
    for _, other in ipairs(queue or {}) do
        if other ~= entry and other.location and other.location == entry.location then
            for _, spot in ipairs(other.spots) do camp.mobs[#camp.mobs + 1] = spot end
        end
    end
    return camp
end

--- The mob after the target in the queue, for the board's "Then:" row.
function ZoneBoard:After(queue)
    for _, entry in ipairs(queue or {}) do
        if not self.hunt or entry.name ~= self.hunt.target then return entry end
    end
    return nil
end

local function Aim(entry, queue)
    local camp = ZoneBoard:Camp(entry, queue)
    if camp and ns.Arrow and ns.Arrow.Grind then pcall(ns.Arrow.Grind, ns.Arrow, camp) end
end

--- Take Me There: hunt `name` (else the first mob still to finish) in the
--- zone you stand in. Returns the entry, or nil when nothing is left.
function ZoneBoard:StartHunt(name)
    if not ZoneBoard.IsOn() then return nil end
    local zone = ZoneBoard.Here()
    local list = zone and self:List(zone, true)
    if not list then return nil end
    self.hunt = { zone = zone, passed = {} }
    local here = ZoneBoard.Position()
    local queue = self:Queue(here)
    local entry
    for _, candidate in ipairs(queue) do
        if candidate.name == name then entry = candidate end
    end
    entry = entry or queue[1]
    if not entry then
        self.hunt = nil
        Redraw()
        return nil
    end
    self.hunt.target = entry.name
    Aim(entry, queue)
    Redraw()
    return entry
end

--- Next Mob, or the hunt moving on after a 20th kill.
function ZoneBoard:NextMob(passing)
    local hunt = self.hunt
    if not hunt then return nil end
    if passing and hunt.target then
        hunt.round = (hunt.round or 0) + 1
        hunt.passed[hunt.target] = hunt.round
    end
    local queue = self:Queue(ZoneBoard.Position())
    local entry
    for _, candidate in ipairs(queue) do
        if candidate.name ~= hunt.target or #queue == 1 then entry = candidate; break end
    end
    if not entry then
        self:StopHunt()
        return nil
    end
    hunt.target = entry.name
    Aim(entry, queue)
    Redraw()
    return entry
end

--- Stop: the arrow goes back to your goals, the board's buttons go back.
function ZoneBoard:StopHunt()
    if not self.hunt then return end
    self.hunt = nil
    if ns.Arrow and ns.Arrow.grind and ns.Arrow.grind.zoneBoard then pcall(ns.Arrow.StopGrind, ns.Arrow) end
    Redraw()
end

--------------------------------------------------------------------------------
-- A kill
--------------------------------------------------------------------------------

--- A new kill of `name`, in the client's `place` zone, from Tracker:Record.
--- Moves one row; a 20th kill on the zone's line turns its card over, may
--- crown a new best, moves the hunt on and may finish the zone.
function ZoneBoard:Killed(name, place)
    if not ZoneBoard.IsOn() or type(name) ~= "string" then return end
    local zone = place and Spots().English(place)
    if not zone then return end
    local list = self.list
    if not (list and list.zone == zone and list.ready) then
        -- The board was never opened in this zone: only a 20th kill lays
        -- the list out, so the card and the moments still come.
        if ZoneBoard.Kills(name, zone) ~= Tracker().MIN_KILLS then return end
        list = self:List(zone, true)
        if not list then return end
    end
    local entry
    for _, candidate in ipairs(list.entries) do
        if candidate.name == name then entry = candidate; break end
    end
    if not entry or ZoneBoard.Skipped(zone, name) then return end
    local kills, key = ZoneBoard.Kills(name, zone)
    entry.kills, entry.key = kills, key
    if kills ~= Tracker().MIN_KILLS then
        if ns.ZoneBoardUI and ns.ZoneBoardUI.Killed then pcall(ns.ZoneBoardUI.Killed, ns.ZoneBoardUI, entry) end
        return
    end
    self:Unlocked(entry)
end

--- A mob just reached 20 here.
function ZoneBoard:Unlocked(entry)
    local zone = entry.zone
    self.worth = nil
    entry.done = true
    -- Finished: a heat map turned on from its eye goes off (the owner,
    -- 2026-11-18). One from the Map button (heatMob) stays.
    local Heat = ns.Heat
    if Heat and Heat.IsPicked and Heat:IsPicked(entry.name) then
        pcall(Heat.SetPicked, Heat, entry.name, false)
    end
    local after = self:Best()
    local rank, ranked
    for index, item in ipairs(after.ranked) do
        if item.entry.name == entry.name then rank, ranked = index, item end
    end

    -- On top with another mob below it: that one was the best before.
    local FX = ns.ZoneBoardFX
    if FX then
        pcall(FX.Card, FX, entry, ranked)
        if rank == 1 and after.ranked[2] then
            pcall(FX.NewBest, FX, zone, ranked, after.ranked[2])
        end
    end

    -- The hunt moves on, after the fight when there is one: picking the
    -- next mob sorts the zone's mobs by distance.
    local done = self:CheckDone(zone)
    if not done and self.hunt and self.hunt.zone == zone and self.hunt.target == entry.name then
        if Fighting() then self.hunt.moveOn = true else self:NextMob() end
    end
    Redraw()
end

--- Is every mob here unlocked? The first time, the Zone Done moment, a
--- stamp and the end of the hunt. Returns true when the zone is done.
function ZoneBoard:CheckDone(zone)
    local list = self.list
    if not (list and list.zone == zone and list.ready) then return false end
    local _, unlocked, total = self:Rows(list)
    if total == 0 or unlocked < total then return false end
    local stamps = Store("zoneBoardDone")
    local first = not stamps[zone]
    if first then stamps[zone] = (type(time) == "function" and time()) or true end
    if self.hunt and self.hunt.zone == zone then self:StopHunt() end
    if first then
        local best = self:Best(list).ranked[1]
        ns.Print(L.Format("%s done! All %d mobs unlocked.", Spots().Show(zone), total))
        if ns.ZoneBoardFX then pcall(ns.ZoneBoardFX.ZoneDone, ns.ZoneBoardFX, zone, total, best) end
    end
    return true
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

--- An auction scan finished (Tradeskills tells us, as it does TopFarm).
function ZoneBoard:Watch()
    if self.watching then return true end
    local ts = rawget(_G, "BlackthornesTS")
    local prices = type(ts) == "table" and ts.Prices
    if type(prices) ~= "table" or type(prices.WatchScans) ~= "function" then return false end
    local ok, watching = pcall(prices.WatchScans, prices, function()
        ZoneBoard.worth = nil
        if not Fighting() then Redraw() end
    end)
    self.watching = ok and watching and true or false
    return self.watching
end

function ZoneBoard:OnEnable()
    ns.RegisterEvent(self, "ZONE_CHANGED_NEW_AREA", function()
        local zone = ZoneBoard.Here()
        if ZoneBoard.hunt and zone and ZoneBoard.hunt.zone ~= zone then ZoneBoard:StopHunt() end
        ZoneBoard.worth = nil
        if ZoneBoard.IsOn() and ns.ZoneBoardUI and ns.ZoneBoardUI.Shown and ns.ZoneBoardUI:Shown() then
            ZoneBoard:List(zone)
        end
        Redraw()
    end)
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function() ZoneBoard:Watch() end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        local hunt = ZoneBoard.hunt
        if hunt and hunt.moveOn then
            hunt.moveOn = nil
            ZoneBoard:NextMob()
        end
        if ZoneBoard.waiting then
            ZoneBoard.waiting = nil
            Redraw()
        end
    end)
end

--------------------------------------------------------------------------------
-- /farm zone
--------------------------------------------------------------------------------

ns.RegisterCommand("zone", L["the Zone Board: on, off or reset"], function(rest)
    local word = (rest or ""):lower():match("^%s*(%S*)")
    if word == "on" or word == "off" then
        ZoneBoard:SetOn(word == "on")
        ns.Print(ZoneBoard.IsOn() and L["The Zone Board is on."] or L["The Zone Board is off."])
        return
    end
    if word == "reset" then
        if ns.ZoneBoardUI then ns.ZoneBoardUI:ResetPlace() end
        ns.Print(L["The Zone Board is back in its first spot."])
        return
    end
    if not ZoneBoard.IsOn() then
        ns.Print(L["Turn on Zone Board in Settings first."])
        return
    end
    if ns.ZoneBoardUI then ns.ZoneBoardUI:Toggle() end
end)
