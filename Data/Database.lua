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
function DB:AddSource(item, source)
    if type(item) == "string" then
        item = self.items[item:lower()]
    end

    if not item or type(source) ~= "table" then return nil end

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
