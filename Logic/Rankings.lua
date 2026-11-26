-- Blackthornes Farmer -- Logic/Rankings.lua
-- Every mob we can put a value on, best first: what is worth farming?
--
-- The worth of a kill is Value:ForMob's number, nothing new. What this adds is
-- the ordering, and keeping two kinds of number apart that must never be
-- ranked against each other:
--
--   measured   your own tally, MIN_KILLS kills or more, coin included;
--   estimate   the database's drop rates, one of each item, no coin.
--
-- An estimate leaves coin out and assumes one of each drop, so it runs low; put
-- in one list with measured values it would sink below mobs that are worth
-- less. So each is ranked on its own, measured first.
--
-- A mob you have killed but not enough times to value, and with no estimate
-- either, is not ranked at all. It is listed with how many kills it still
-- needs, since that is the way onto the board.

local _, ns = ...
local L = ns.L

local Rankings = ns.NewModule("Rankings")

-- Kinds whose `name` is a creature. A node or a school has no kill to value.
local CREATURE_KINDS = { mob = true, skinning = true }

--- Every mob name the database gives a drop rate for.
local function RatedMobs(names)
    for name, sources in pairs(ns.DB:ByName()) do
        for _, source in ipairs(sources) do
            if source.chance and CREATURE_KINDS[ns.DB.KindOf(source)] then
                names[name] = true
                break
            end
        end
    end
end

--- Where the database puts a mob and at what level: the lowest band first,
--- as the search lists it. Nil when the database does not know the mob.
function Rankings:Spot(mobName)
    -- One zone's line of a mob (Tracker's "One line a zone") looks in that
    -- zone first.
    local name, zone = ns.Tracker.SplitKey(mobName)
    local best, here

    for _, source in ipairs(ns.DB:ByName()[name] or {}) do
        -- Classic's generated rows are for the search (Data_ClassicDrops).
        if CREATURE_KINDS[ns.DB.KindOf(source)] and not source.searchOnly then
            if not best or (source.minLevel or 0) < (best.minLevel or 0) then
                best = source
            end
            if zone and source.zone == zone
                and (not here or (source.minLevel or 0) < (here.minLevel or 0)) then
                here = source
            end
        end
    end

    return here or best
end

--- The levels you met a mob at, from your own loot records: { min, max } by
--- mob name. Laid out once and kept until a corpse is recorded
--- (Harvest.changes) or LEVELS_KEEP seconds pass, since the board asks for
--- every mob in one go. A mob the database has no row for (most of what the
--- shipped data leaves out) still gets a level this way.
Rankings.LEVELS_KEEP = 60

function Rankings:OwnLevels()
    local Harvest = ns.Harvest
    local changes = Harvest and Harvest.changes or 0
    local now = GetTime and GetTime() or 0
    local kept = self.ownLevels
    if kept and kept.changes == changes and now - kept.at < self.LEVELS_KEEP then
        return kept.levels
    end

    -- By name, and by each zone's line key, for a mob split by zone.
    local levels = {}
    local function Note(key, low, high)
        local seen = levels[key]
        if seen then
            seen.min = math.min(seen.min, low)
            seen.max = math.max(seen.max, high)
        else
            levels[key] = { min = low, max = high }
        end
    end
    for _, record in pairs(Harvest and Harvest.records or {}) do
        local mob, low, high = record.mob, tonumber(record.minLevel), tonumber(record.maxLevel)
        if type(mob) == "string" and low then
            high = high or low
            Note(mob, low, high)
            if type(record.zone) == "string" then
                Note(ns.Tracker.ZoneKey(mob, record.zone), low, high)
            end
        end
    end

    self.ownLevels = { changes = changes, at = now, levels = levels }
    return levels
end

--- A mob's level for the board: "18-19". The levels you met it at first,
--- like where you farm it, else the database's, else nil.
--- Returns the text, the lowest level (for sorting) and the highest.
function Rankings:LevelFor(mobName, spot)
    local levels = self:OwnLevels()
    local own = levels[mobName] or levels[ns.Tracker.NameOf(mobName)]
    if own then
        return ns.Search:LevelText({ minLevel = own.min, maxLevel = own.max }), own.min, own.max
    end
    if spot and spot.minLevel then
        local low = tonumber(spot.minLevel)
        return ns.Search:LevelText(spot), low, tonumber(spot.maxLevel) or low
    end
    return nil, nil, nil
end

--------------------------------------------------------------------------------
-- Near my level
--------------------------------------------------------------------------------

-- The owner said build it (2026-11-23, from a mockup): a tick box on
-- Rankings that shows only mobs near the character's level, from
-- NEAR_BELOW levels under to NEAR_ABOVE over, on both boards and the list
-- of mobs not ranked yet. A mob shows when any level it was met at falls in
-- that band; one with no level is left out while ticked. The ranks count
-- from #1 inside the band. Off unless ticked, kept in `rankingsNearLevel`
-- (account wide, never rename it). Only the tab's board (Rankings:Build)
-- follows it: the rank-up pop-up and the top 15 after a scan rank every
-- level, so `outsideVersion` is left alone.
Rankings.NEAR_BELOW = 3
Rankings.NEAR_ABOVE = 2

function Rankings.NearLevel()
    return ns.db ~= nil and ns.db.rankingsNearLevel == true
end

function Rankings:SetNearLevel(on)
    if not ns.db then return end
    on = on and true or false
    if (ns.db.rankingsNearLevel == true) == on then return end
    ns.db.rankingsNearLevel = on
    if ns.RankingsUI then ns.RankingsUI:Refresh() end
end

--- The character's level, or nil when the client won't say.
function Rankings.PlayerLevel()
    if type(UnitLevel) ~= "function" then return nil end
    local ok, level = pcall(UnitLevel, "player")
    if not ok then return nil end
    local readable, number = pcall(tonumber, level)
    if not readable or type(number) ~= "number" or number < 1 then return nil end
    return number
end

--- Does an entry pass "Near my level"? Always, while the box is off or the
--- character's level can't be read; never for a mob with no level.
function Rankings:NearYou(entry, level)
    if not self.NearLevel() then return true end
    level = level or self.PlayerLevel()
    if not level then return true end
    local low, high = entry.minLevel, entry.maxLevel or entry.minLevel
    if not low then return false end
    return high >= level - self.NEAR_BELOW and low <= level + self.NEAR_ABOVE
end

--------------------------------------------------------------------------------
-- Outside dungeons only
--------------------------------------------------------------------------------

-- The owner asked (2026-10-14) for a tick box on Rankings that leaves out mobs
-- found only in dungeons. Off unless ticked, kept in `rankingsOutside`
-- (account wide, never rename it). The rank-up pop-up and the top farm
-- alert after an auction scan rank the same board, so they follow it too.

--- Moves whenever the tick box does, so what was laid out for the other
--- answer is laid out again (RankUp).
Rankings.outsideVersion = 0

function Rankings.OutsideOnly()
    return ns.db ~= nil and ns.db.rankingsOutside == true
end

function Rankings:SetOutsideOnly(on)
    if not ns.db then return end
    on = on and true or false
    if (ns.db.rankingsOutside == true) == on then return end
    ns.db.rankingsOutside = on
    self.outsideVersion = self.outsideVersion + 1
    -- The rank-up order sees the version move and is laid out again.
    if ns.RankingsUI then ns.RankingsUI:Refresh() end
end

--------------------------------------------------------------------------------
-- Skip Uncommon and better
--------------------------------------------------------------------------------

-- The owner asked (2026-10-18) for a tick box on Rankings that leaves
-- Uncommon, Rare and Epic drops out of what a kill is worth, so the board
-- ranks what a mob gives every time. Kept in `rankingsSkipUncommon`
-- (account wide, never rename it).
--
-- A player asked, the owner said build it (2026-11-18, from a mockup): the
-- box became "Exclude Rarity:", a drop-down of what is left out: "none"
-- (every drop, the default), "epic" (Epic and better), "rare" (Rare and
-- better) or "uncommon" (Uncommon and better, the old box ticked). Kept in
-- `rankingsExclude` (account wide, never rename it). A save from before
-- with the box ticked and no `rankingsExclude` reads as "uncommon";
-- `rankingsSkipUncommon` is kept in step and never deleted. A change moves
-- `outsideVersion` too, so the rank-up order is laid out again.

Rankings.EXCLUDE = { "none", "epic", "rare", "uncommon" }
-- The lowest item quality each choice leaves out.
Rankings.EXCLUDE_FROM = { epic = 4, rare = 3, uncommon = 2 }

function Rankings.Exclude()
    local db = ns.db
    if not db then return "none" end
    local saved = db.rankingsExclude
    if saved == "none" or Rankings.EXCLUDE_FROM[saved] then return saved end
    return db.rankingsSkipUncommon == true and "uncommon" or "none"
end

function Rankings:SetExclude(choice)
    if not ns.db then return end
    if choice ~= "none" and not self.EXCLUDE_FROM[choice] then return end
    local was = self.Exclude()
    ns.db.rankingsExclude = choice
    ns.db.rankingsSkipUncommon = choice == "uncommon"
    if was == choice then return end
    self.outsideVersion = self.outsideVersion + 1
    if ns.RankingsUI then ns.RankingsUI:Refresh() end
end

--- The words a player sees for each choice, in the drop-down and in chat.
function Rankings.ExcludeWord(choice)
    local words = {
        none = L["Nothing"],
        epic = L["Epic and Above"],
        rare = L["Rare and Above"],
        uncommon = L["Uncommon and Above"],
    }
    return words[choice] or words.none
end

-- Each choice in the colour of the lowest rarity it leaves out.
Rankings.EXCLUDE_COLORS = { epic = "ffa335ee", rare = "ff0070dd", uncommon = "ff1eff00" }

--- The drop-down's options, in order, each { text, value }.
function Rankings.ExcludeOptions()
    local options = {}
    for _, choice in ipairs(Rankings.EXCLUDE) do
        local text = Rankings.ExcludeWord(choice)
        local color = Rankings.EXCLUDE_COLORS[choice]
        options[#options + 1] = { text = color and ("|c" .. color .. text .. "|r") or text, value = choice, plain = text }
    end
    return options
end

--- The old tick box's question: are Uncommon and better left out?
function Rankings.SkipUncommon()
    return Rankings.Exclude() == "uncommon"
end

function Rankings:SetSkipUncommon(on)
    self:SetExclude(on and "uncommon" or "none")
end

--- A priced drop's quality: its loot link's colour, else the client's.
--- Nil while it is not known.
function Rankings.QualityOf(drop)
    local WorldDrops = ns.WorldDrops
    if not (WorldDrops and WorldDrops.QualityOf and drop) then return nil end
    local id = drop.id
    if not id and ns.Tracker and ns.Tracker.LookOf then id = ns.Tracker:LookOf(drop.name).id end
    if not id and ns.Value.ItemID then id = ns.Value:ItemID(drop.name) end
    local quality = WorldDrops.QualityOf(id, drop.name)
    return type(quality) == "number" and quality or nil
end

--- Is a priced drop Uncommon or better? A drop whose quality is not
--- known yet stays in.
function Rankings.IsUncommonOrBetter(drop)
    local quality = Rankings.QualityOf(drop)
    return quality ~= nil and quality >= 2
end

--- A worth and its details with drops of quality `from` and better taken
--- out: coin and the drops left. A fresh details table; the one given is
--- untouched. A drop whose quality is not known yet stays in.
function Rankings.WithoutQuality(value, details, from)
    local kept = {}
    for key, field in pairs(details) do kept[key] = field end
    kept.priced = {}
    local total = tonumber(details.coin) or 0
    for _, drop in ipairs(details.priced or {}) do
        local quality = Rankings.QualityOf(drop)
        if not (quality and quality >= from) then
            kept.priced[#kept.priced + 1] = drop
            total = total + (drop.perKill or 0)
        end
    end
    if #kept.priced == #(details.priced or {}) then return value, details end
    return total, kept
end

--- The same with Uncommon and better taken out.
function Rankings.WithoutUncommon(value, details)
    return Rankings.WithoutQuality(value, details, 2)
end

-- The owner said build it (2026-11-15, from a mockup): a tick box on
-- Rankings that prices every drop at what a vendor pays, not the auction
-- house. Drops a vendor won't buy count as nothing. Off unless ticked,
-- kept in `rankingsVendorOnly` (account wide, never rename it). It moves
-- `outsideVersion` too, so the rank-up order is laid out again.

function Rankings.VendorOnly()
    return ns.db ~= nil and ns.db.rankingsVendorOnly == true
end

function Rankings:SetVendorOnly(on)
    if not ns.db then return end
    on = on and true or false
    if (ns.db.rankingsVendorOnly == true) == on then return end
    ns.db.rankingsVendorOnly = on
    self.outsideVersion = self.outsideVersion + 1
    if ns.RankingsUI then ns.RankingsUI:Refresh() end
end

--- What a vendor pays for one of a priced drop, or nil.
function Rankings.VendorOf(drop)
    local id = drop.id
    if not id and ns.Tracker and ns.Tracker.LookOf then id = ns.Tracker:LookOf(drop.name).id end
    if not id and ns.Value.ItemID then id = ns.Value:ItemID(drop.name) end
    if not id then return nil end
    local price = ns.Value:VendorPrice(id)
    if type(price) == "number" and price > 0 then return price end
    return nil
end

--- A worth and its details with every drop at its vendor price: coin and
--- the drops a vendor buys, best first. A fresh details table; the one
--- given is untouched.
function Rankings.WithVendorPrices(value, details)
    local kept = {}
    for key, field in pairs(details) do kept[key] = field end
    kept.priced = {}
    local total = tonumber(details.coin) or 0
    for _, drop in ipairs(details.priced or {}) do
        local vendor = drop.from == "vendor" and drop.unit or Rankings.VendorOf(drop)
        if vendor and vendor > 0 then
            local copy = {}
            for key, field in pairs(drop) do copy[key] = field end
            local unit = tonumber(drop.unit) or 0
            if unit > 0 then
                copy.perKill = (drop.perKill or 0) * vendor / unit
            else
                copy.perKill = 0
            end
            copy.unit, copy.from = vendor, "vendor"
            kept.priced[#kept.priced + 1] = copy
            total = total + copy.perKill
        end
    end
    table.sort(kept.priced, function(a, b) return (a.perKill or 0) > (b.perKill or 0) end)
    return total, kept
end

--- The zone part of a kill's place, "The Sepulcher, Silverpine Forest":
--- the zone the client named (GetRealZoneText), which inside a dungeon is
--- the dungeon.
local function PlaceZone(place)
    return ns.Tracker.PlaceZone(place)
end

--- Is a database row for a mob inside a dungeon? A row from Classic's data
--- names the dungeon as its subzone ("The Deadmines" in Westfall). A row
--- recorded in game has the dungeon as its zone; its subzone is the open
--- world's when the zone is not (Ruins of Lordaeron in Tirisfal Glades).
local function SourceInside(source)
    local Spots = ns.Spots
    if Spots.IsInstance(source.zone) then return true end
    return (source.provenance or "classic") == "classic" and Spots.IsInstance(source.location)
end

--- Is `mobName` found only in dungeons and raids? Told by where your kills
--- of it were (every kill with a place inside one), else by where the
--- database puts it (every place inside one). A mob neither tells about,
--- killed before places were kept and not in the data, counts as outside.
function Rankings:InDungeon(mobName)
    local Spots = ns.Spots
    -- One zone's line is inside when its zone is.
    local name, zone = ns.Tracker.SplitKey(mobName)
    if zone then return Spots.IsInstance(zone) and true or false end
    local places = ns.Tracker:Places(mobName)
    if #places > 0 then
        for _, place in ipairs(places) do
            if not Spots.IsInstance(PlaceZone(place.name)) then return false end
        end
        return true
    end

    local any = false
    for _, source in ipairs(ns.DB:ByName()[name] or {}) do
        if CREATURE_KINDS[ns.DB.KindOf(source)] then
            if not SourceInside(source) then return false end
            any = true
        end
    end
    return any
end

--- Is `mobName` left off the board? Hidden, or in a dungeon while the tick
--- box says outside only.
function Rankings:LeftOut(mobName)
    local Tracker = ns.Tracker
    local name, zone = Tracker.SplitKey(mobName)
    if ns.DB:IsHiddenSource(name) then return true end
    -- A name killed in two zones is ranked a line a zone, never as a whole.
    if not zone and Tracker:IsSplit(name) then return true end
    return self.OutsideOnly() and self:InDungeon(mobName)
end

--- One entry for a mob, or nil when it is on no list.
function Rankings:Entry(mobName)
    local value, details = ns.Value:ForMob(mobName)
    local excludeFrom = self.EXCLUDE_FROM[self.Exclude()]
    if value and excludeFrom then value, details = self.WithoutQuality(value, details, excludeFrom) end
    if value and self.VendorOnly() then value, details = self.WithVendorPrices(value, details) end
    local summary = ns.Tracker:Summary(mobName)
    local spot = self:Spot(mobName)

    local entry = {
        mob = mobName,
        value = value,
        details = details,
        kills = summary and summary.kills or 0,
        needed = summary and summary.needed or 0,
        spot = spot,
    }
    entry.level, entry.minLevel, entry.maxLevel = self:LevelFor(mobName, spot)

    -- Where you farm it beats where the database says it lives.
    local places = summary and summary.places
    if places and places[1] then
        entry.where = places[1].name
    elseif spot then
        local landmark = ns.DB:WhereText(spot)
        local zone = ns.Spots.Show(spot.zone)
        entry.where = landmark and (zone .. ", " .. landmark) or zone
    end

    if value then
        entry.group = details.basis == "tally" and "measured" or "estimate"
        entry.best = details.priced[1]
    elseif summary and summary.kills > 0 then
        -- Enough kills but nothing priced: it waits on prices, not kills.
        entry.group = "pending"
        entry.unpriced = summary.rated
    else
        return nil
    end

    return entry
end

--- Every name the board asks about, as a list: each tallied line (one for
--- each zone of a name killed in more than one) and each mob the database
--- gives a drop rate for.
function Rankings:Names()
    local names = {}
    for key in pairs(ns.Tracker:Tallies()) do
        if type(key) == "string" then names[key] = true end
    end
    RatedMobs(names)

    local list = {}
    for name in pairs(names) do list[#list + 1] = name end
    return list
end

--- Put one mob on `board`, when it belongs there. A mob on the hide list
--- is not ranked (DB:IsHiddenSource), nor a dungeon's with "Outside
--- dungeons only" ticked, nor one far from `level` with "Near my level"
--- ticked.
function Rankings:AddTo(board, name, level)
    local entry = not self:LeftOut(name) and self:Entry(name)
    if entry and self:NearYou(entry, level) then
        local list = board[entry.group]
        list[#list + 1] = entry
        return entry
    end
    return nil
end

--- Sort a filled board and number its ranks. Returns the board.
function Rankings:Finish(board)
    local function ByValue(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.mob < b.mob
    end

    table.sort(board.measured, ByValue)
    table.sort(board.estimate, ByValue)
    table.sort(board.pending, function(a, b)
        if a.needed ~= b.needed then return a.needed < b.needed end
        return a.mob < b.mob
    end)

    for _, group in ipairs({ "measured", "estimate" }) do
        for rank, entry in ipairs(board[group]) do
            entry.rank = rank
        end
    end

    return board
end

--- The board: { measured = {...}, estimate = {...}, pending = {...} }, each
--- entry { mob, value, details, kills, needed, where, level, best, rank }.
-- Measured and estimates are ranked by worth per kill; pending by how close
-- each is to MIN_KILLS.
function Rankings:Build()
    local board = { measured = {}, estimate = {}, pending = {} }
    local level = self.NearLevel() and self.PlayerLevel() or nil

    for _, name in ipairs(self:Names()) do
        self:AddTo(board, name, level)
    end

    return self:Finish(board)
end

--------------------------------------------------------------------------------
-- The board over a few frames
--------------------------------------------------------------------------------

-- The board prices every drop of every rated mob, a few thousand items,
-- and the first asking of a session reads each one's tooltip for its
-- vendor price. Done in one go the game stood still for a moment when the
-- Rankings tab opened (the owner, 2026-11-26). BuildSoon does the same
-- work a slice a frame and hands over the same board as Build.
-- SLICE_MS is how long one frame's slice may run; SLICE_MOBS is a slice
-- on a client with no clock to time it by.
Rankings.SLICE_MS = 5
Rankings.SLICE_MOBS = 60

local function Clock()
    if type(debugprofilestop) ~= "function" then return nil end
    local ok, now = pcall(debugprofilestop)
    return ok and tonumber(now) or nil
end

--- Build the board over a few frames and call `done(board)` with it. The
--- first slice runs at once, so a short board is ready before this
--- returns. Asking again drops the build under way: only the newest
--- calls back. Without a timer it is Build, at once. `each(entry)`, when
--- given, is called for every mob as it goes on the board, inside the
--- slice's time (the tab measures its texts there).
function Rankings:BuildSoon(done, each)
    local after = C_Timer and C_Timer.After
    local job = {
        names = self:Names(),
        at = 1,
        board = { measured = {}, estimate = {}, pending = {} },
        level = self.NearLevel() and self.PlayerLevel() or nil,
    }
    self.job = job
    local sliced = type(after) == "function"

    local function Step()
        if self.job ~= job then return end

        local started, count = Clock(), 0
        while job.at <= #job.names do
            local entry = self:AddTo(job.board, job.names[job.at], job.level)
            if entry and each then each(entry) end
            job.at = job.at + 1
            count = count + 1
            if sliced then
                if started then
                    local now = Clock()
                    if not now or now - started >= self.SLICE_MS then break end
                elseif count >= self.SLICE_MOBS then
                    break
                end
            end
        end

        if job.at > #job.names then
            self.job = nil
            done(self:Finish(job.board))
            return
        end

        after(0, Step)
    end

    Step()
end

--- Is a board being built over frames right now?
function Rankings:Building()
    return self.job ~= nil
end

-- A ding moves the band: the tab draws again while the box is ticked.
function Rankings:OnEnable()
    ns.RegisterEvent(self, "PLAYER_LEVEL_UP", function()
        if Rankings.NearLevel() and ns.RankingsUI then ns.RankingsUI:Refresh() end
    end)
end

ns.RegisterCommand("rankings", L["mobs ranked by what a kill is worth, or only those outside dungeons"], function(arg)
    local word, value = (arg or ""):lower():match("^(%S*)%s*(%S*)")
    if word == "outside" then
        if value == "on" or value == "off" then
            Rankings:SetOutsideOnly(value == "on")
        else
            Rankings:SetOutsideOnly(not Rankings.OutsideOnly())
        end
        ns.Print(Rankings.OutsideOnly() and L["Rankings show only mobs outside dungeons."]
            or L["Rankings show mobs from dungeons too."])
        if ns.SettingsUI then ns.SettingsUI:Refresh() end
        return
    end
    if word == "uncommon" or word == "exclude" then
        if word == "uncommon" then
            if value == "on" or value == "off" then
                Rankings:SetSkipUncommon(value == "on")
            else
                Rankings:SetSkipUncommon(not Rankings.SkipUncommon())
            end
        elseif value == "none" or Rankings.EXCLUDE_FROM[value] then
            Rankings:SetExclude(value)
        end
        local choice = Rankings.Exclude()
        if choice == "none" then
            ns.Print(L["Rankings count every drop in worth per kill."])
        else
            ns.Print(L.Format("Worth per kill leaves out drops that are %s.", Rankings.ExcludeWord(choice)))
        end
        if ns.SettingsUI then ns.SettingsUI:Refresh() end
        return
    end
    if word == "level" then
        if value == "on" or value == "off" then
            Rankings:SetNearLevel(value == "on")
        else
            Rankings:SetNearLevel(not Rankings.NearLevel())
        end
        ns.Print(Rankings.NearLevel() and L["Rankings show only mobs near your level."]
            or L["Rankings show mobs of every level."])
        if ns.SettingsUI then ns.SettingsUI:Refresh() end
        return
    end
    if word == "vendor" then
        if value == "on" or value == "off" then
            Rankings:SetVendorOnly(value == "on")
        else
            Rankings:SetVendorOnly(not Rankings.VendorOnly())
        end
        ns.Print(Rankings.VendorOnly() and L["Rankings use vendor prices."]
            or L["Rankings use auction prices again."])
        if ns.SettingsUI then ns.SettingsUI:Refresh() end
        return
    end
    ns.UI:Show()
    ns.UI:ShowTab("rankings")
end)

-- The short form, kept out of the help list so it is not there twice.
ns.commands.rank = ns.commands.rankings
