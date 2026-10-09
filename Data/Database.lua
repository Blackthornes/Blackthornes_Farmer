-- Blackthornes Farmer -- Data/Database.lua
-- The item database and the API the data files register through.
--
-- Deliberately not a flat drop table. Every entry is an item with a list of
-- sources, and a source says what kind of thing it is, where it is, and what
-- level you will be fighting at. That shape is what lets one search answer
-- "where do I get this" and "what is worth farming here" from the same rows.

local _, ns = ...

local DB = ns.NewModule("DB")

local Util = ns.Util

-- items[lowercase name] = item; order keeps iteration stable across sessions.
DB.items = {}
DB.order = {}

-- Counts every item or source added, so the index by name below knows when
-- it is out of date. The data only changes while the files load.
DB.changes = 0

-- Where a row's facts came from. Everything seeded from Classic is "classic"
-- until somebody actually confirms it on Forever, because Forever is classic
-- content on a retail engine and its drop tables are nobody's to assume. A
-- wrong farming spot costs an hour of someone's evening, so the window says
-- which rows have been checked rather than presenting all of them as equal.
DB.PROVENANCE = {
    classic = "from Classic data",
    forever = "confirmed on Forever",
}

DB.DEFAULT_PROVENANCE = "classic"

-- What a source actually is. Every source names one of these so the window can
-- label it; an unknown kind falls back to the raw string rather than vanishing.
DB.KIND_LABEL = {
    mob       = "mob",
    node      = "mining node",
    herb      = "herb node",
    skinning  = "skinning",
    fishing   = "fishing",
    container = "container",
    vendor    = "vendor",
    quest     = "quest",
}

--[[----------------------------------------------------------------------------
  Data files call:

    ns.DB:RegisterItem({
      name     = "Copper Ore",
      id       = 2770,                -- optional, for item links later
      category = "Mining",
      aliases  = { "copper" },        -- optional extra search terms
      note     = "...",               -- optional one-liner
      sources  = {
        { kind = "node", name = "Copper Vein", zone = "Durotar",
          minLevel = 1, maxLevel = 10, requires = "Mining 1",
          location = "Tiragarde Keep", coords = { 55.4, 12.8 }, chance = 35,
          provenance = "forever" },   -- omit until somebody has checked in game
      },
    })

  Only `zone` and `minLevel` are required. `location` is where in the zone,
  `coords` is { x, y } on the zone map, and `chance` is a drop rate in percent.
  Everything optional is simply not drawn when it is missing, so a thin entry
  and a fully researched one live in the same list without one looking broken.

  Registering a name that already exists merges the new sources into the
  existing item, so the database can be split across as many files as we like
  and a later data pack can extend what ships here.
------------------------------------------------------------------------------]]

function DB:RegisterItem(def)
    if type(def) ~= "table" or type(def.name) ~= "string" or def.name == "" then
        ns.Warn("skipped a data entry with no name")
        return nil
    end

    local key = def.name:lower()
    local item = self.items[key]
    self.changes = (self.changes or 0) + 1

    if not item then
        item = {
            name     = def.name,
            id       = def.id,
            category = def.category or "Misc",
            aliases  = {},
            note     = def.note,
            sources  = {},
        }
        self.items[key] = item
        self.order[#self.order + 1] = key
    else
        item.id       = item.id or def.id
        item.category = def.category or item.category
        item.note     = item.note or def.note
    end

    for _, alias in ipairs(def.aliases or {}) do
        item.aliases[#item.aliases + 1] = alias
    end

    for _, source in ipairs(def.sources or {}) do
        self:AddSource(item, source)
    end

    return item
end

--- Add one source to an item, given either the item table or its name.
--- The source already recorded for this same spot, if there is one.
--
-- Same creature or node, same zone, same subzone. Compared case-insensitively
-- because the two sides come from different places: the seed files are typed
-- by hand and the harvested ones come back from the client.
local function SameSpot(item, source)
    if type(source.name) ~= "string" or source.name == "" then return nil end

    local name = source.name:lower()
    local zone = source.zone:lower()
    local location = (source.location or ""):lower()

    for index, existing in ipairs(item.sources) do
        if type(existing.name) == "string"
            and existing.name:lower() == name
            and type(existing.zone) == "string"
            and existing.zone:lower() == zone
            and (existing.location or ""):lower() == location then
            return index, existing
        end
    end

    return nil
end

function DB:AddSource(item, source)
    if type(item) == "string" then
        item = self.items[item:lower()]
    end

    if not item or type(source) ~= "table" then return nil end
    self.changes = (self.changes or 0) + 1

    -- A source with nowhere to go is not a lead, it is noise.
    if type(source.zone) ~= "string" or source.zone == "" then
        ns.Warn(("skipped a source with no zone on %s"):format(item.name))
        return nil
    end

    source.kind = source.kind or "mob"
    source.minLevel = source.minLevel or source.level
    source.maxLevel = source.maxLevel or source.minLevel

    -- Unmarked means nobody has checked it on Forever, which is the honest
    -- default for anything carried over from Classic.
    if not self.PROVENANCE[source.provenance] then
        source.provenance = self.DEFAULT_PROVENANCE
    end

    -- Coordinates are map percentages. A malformed pair is dropped rather than
    -- stored, because a row that points somewhere wrong is worse than a row
    -- that admits it does not know: one wastes a flight, the other does not.
    if source.coords then
        local x, y = source.coords[1], source.coords[2]

        if type(x) ~= "number" or type(y) ~= "number"
            or x < 0 or x > 100 or y < 0 or y > 100 then
            ns.Warn(("dropped bad coordinates on %s in %s"):format(item.name, source.zone))
            source.coords = nil
        end
    end

    -- Same reasoning for a nonsense drop rate.
    if source.chance and (type(source.chance) ~= "number"
        or source.chance <= 0 or source.chance > 100) then
        ns.Warn(("dropped a bad drop rate on %s in %s"):format(item.name, source.zone))
        source.chance = nil
    end

    -- Measured beats carried over. The two can disagree, and when they do the
    -- Classic row is the wrong one: Witchwing Slayers are level 20-21 in
    -- Classic and 16-17 on Forever, so showing both sends somebody to a camp
    -- four levels off, under a drop rate nobody measured here. One row per
    -- spot, and the one that was actually looted wins.
    --
    -- Only across provenances. Two rows of the same kind for one spot are a
    -- data-entry duplicate, which is not this function's problem to guess at.
    local index, existing = SameSpot(item, source)

    if existing and existing.provenance ~= source.provenance then
        if source.provenance == "forever" then
            item.sources[index] = source
            return source
        end

        if existing.provenance == "forever" then
            return nil
        end
    end

    item.sources[#item.sources + 1] = source
    return source
end

function DB:GetItem(name)
    if type(name) ~= "string" then return nil end
    return self.items[Util.Trim(name):lower()]
end

function DB:CountItems()
    return #self.order
end

function DB:CountSources()
    local total = 0
    for _, key in ipairs(self.order) do
        total = total + #self.items[key].sources
    end
    return total
end

--- Every source by the name of its mob or node: [name] = { { item, source },
--- ... }, items in registration order and each item's sources in order, as
--- walking Iterate would find them. Built on first use and again only after
--- a source is added, so valuing a mob no longer walks the whole database.
function DB:ByName()
    if self.byName and self.byNameAt == self.changes then return self.byName end

    local byName = {}
    for _, key in ipairs(self.order) do
        local item = self.items[key]
        for _, source in ipairs(item.sources or {}) do
            local name = source.name
            if type(name) == "string" then
                local list = byName[name]
                if not list then
                    list = {}
                    byName[name] = list
                end
                list[#list + 1] = { item = item, source = source }
            end
        end
    end

    self.byName, self.byNameAt = byName, self.changes
    return byName
end

--- Every item, in registration order.
function DB:Iterate()
    local index = 0
    return function()
        index = index + 1
        local key = self.order[index]
        if key then return self.items[key] end
    end
end

function DB:KindLabel(kind)
    return self.KIND_LABEL[kind] or kind
end

-- Short tag for the column view, where "mining node" is too wide to fit.
DB.KIND_TAG = {
    mob       = "MOB",
    node      = "ORE",
    herb      = "HERB",
    skinning  = "SKIN",
    fishing   = "FISH",
    container = "BOX",
    vendor    = "NPC",
    quest     = "QUEST",
}

function DB:KindTag(kind)
    return self.KIND_TAG[kind] or string.upper(kind or "?")
end

--- "Durnholde Keep, 80.6 45.2" -- whichever parts are known.
function DB:WhereText(source)
    local coords = source.coords

    if source.location and coords then
        return ("%s  %.1f, %.1f"):format(source.location, coords[1], coords[2])
    end

    if source.location then return source.location end
    if coords then return ("%.1f, %.1f"):format(coords[1], coords[2]) end

    return nil
end

--- How many sources come from each provenance, for `/farm data`.
function DB:CountByProvenance()
    local counts = {}

    for key in pairs(self.PROVENANCE) do
        counts[key] = 0
    end

    for _, key in ipairs(self.order) do
        for _, source in ipairs(self.items[key].sources) do
            local kind = source.provenance or self.DEFAULT_PROVENANCE
            counts[kind] = (counts[kind] or 0) + 1
        end
    end

    return counts
end

--[[----------------------------------------------------------------------------
  Creature types, as the Forever client names them ("Humanoid", "Beast"),
  by mob name. Only ever filled from what the game itself said: the harvest
  export writes the types the addon read off mobs in game
  (Logic/Grinding.lua), and the generated data file hands them back here:

    DB:CreatureTypes({ ["Witchwing Slayer"] = "Humanoid" })

  Nothing is typed in by hand or guessed from a mob's name or drops. A mob
  with no entry is a mob whose type nobody has seen yet.
------------------------------------------------------------------------------]]

DB.creatureTypes = {}

function DB:CreatureTypes(map)
    if type(map) ~= "table" then return end
    for name, kind in pairs(map) do
        if type(name) == "string" and name ~= "" and type(kind) == "string" and kind ~= "" then
            self.creatureTypes[name] = kind
        end
    end
end
