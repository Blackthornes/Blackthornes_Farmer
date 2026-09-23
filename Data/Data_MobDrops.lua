-- Blackthornes Farmer -- Data/Data_MobDrops.lua
-- Seed data: things that drop off mobs rather than out of the ground.
--
-- All of it is Classic data, so none of it is marked confirmed. Forever is
-- classic content on a retail engine and its drop tables are nobody's to
-- assume, so these are leads: farm one, and when it holds up, add
-- provenance = "forever" to that source and it stops being a guess.
--
-- Levels here are the mob's own level range, since that is what decides
-- whether you can kill it.

local _, ns = ...

local DB = ns.DB

--------------------------------------------------------------------------------
-- Spiders and beasts
--------------------------------------------------------------------------------

DB:RegisterItem({
    name = "Spider's Silk",
    id = 3182,
    category = "Mob drop",
    aliases = { "spider silk" },
    sources = {
        { name = "spiders", zone = "Duskwood", minLevel = 20, maxLevel = 28 },
        { name = "spiders", zone = "Wetlands", minLevel = 22, maxLevel = 30 },
        { name = "spiders", zone = "Hillsbrad Foothills", minLevel = 25, maxLevel = 32 },
        { name = "Stranglethorn tigers and spiders", zone = "Stranglethorn Vale", minLevel = 30, maxLevel = 38 },
    },
})

DB:RegisterItem({
    name = "Shadow Silk",
    id = 7072,
    category = "Mob drop",
    note = "The high-level spider silk -- same idea, different bracket.",
    sources = {
        { name = "spiders", zone = "Searing Gorge", minLevel = 45, maxLevel = 52 },
        { name = "spiders", zone = "The Hinterlands", minLevel = 45, maxLevel = 52 },
        { name = "spiders", zone = "Felwood", minLevel = 48, maxLevel = 55 },
        { name = "Plaguebat and spider packs", zone = "Eastern Plaguelands", minLevel = 53, maxLevel = 60 },
    },
})

DB:RegisterItem({
    name = "Large Fang",
    id = 5637,
    category = "Mob drop",
    sources = {
        { name = "raptors", zone = "Stranglethorn Vale", minLevel = 30, maxLevel = 40 },
        { name = "wolves and bears", zone = "Hillsbrad Foothills", minLevel = 25, maxLevel = 32 },
        { name = "hyenas and raptors", zone = "Arathi Highlands", minLevel = 30, maxLevel = 40 },
        { name = "wolves", zone = "Ashenvale", minLevel = 25, maxLevel = 32 },
    },
})

DB:RegisterItem({
    name = "Black Dragonscale",
    id = 15416,
    category = "Leatherworking",
    note = "Skinned off black dragonkin, so it needs Skinning as well as the kill.",
    sources = {
        { kind = "skinning", name = "black dragonkin", zone = "Burning Steppes", minLevel = 52, maxLevel = 58, requires = "Skinning 300" },
        { kind = "skinning", name = "black dragonkin", zone = "Blackrock Spire", minLevel = 55, maxLevel = 60, requires = "Skinning 300", note = "instance" },
        { kind = "skinning", name = "Scalding Whelps", zone = "Burning Steppes", minLevel = 50, maxLevel = 54, requires = "Skinning 300" },
    },
})

--------------------------------------------------------------------------------
-- Demons and undead
--------------------------------------------------------------------------------

DB:RegisterItem({
    name = "Demonic Rune",
    id = 12662,
    category = "Mob drop",
    note = "Mana for a health hit -- the classic warlock and mage farm.",
    sources = {
        { name = "Shadow Council and satyrs", zone = "Felwood", minLevel = 52, maxLevel = 56, note = "Jaedenar" },
        { name = "satyrs", zone = "Azshara", minLevel = 50, maxLevel = 55 },
        { name = "Deadwood and Jadefire satyrs", zone = "Felwood", minLevel = 48, maxLevel = 55 },
    },
})

DB:RegisterItem({
    name = "Essence of Undeath",
    id = 12808,
    category = "Elemental",
    sources = {
        { name = "Scourge", zone = "Eastern Plaguelands", minLevel = 53, maxLevel = 60 },
        { name = "Scourge", zone = "Western Plaguelands", minLevel = 50, maxLevel = 58 },
        { name = "undead", zone = "Scholomance", minLevel = 55, maxLevel = 60, note = "instance" },
        { name = "undead", zone = "Stratholme", minLevel = 56, maxLevel = 60, note = "instance" },
    },
})

--------------------------------------------------------------------------------
-- Elementals
--
-- Each element has a common drop and a rarer one off the same mobs, so they
-- are listed as separate items but farmed in the same place.
--------------------------------------------------------------------------------

DB:RegisterItem({
    name = "Elemental Water",
    id = 7070,
    category = "Elemental",
    sources = {
        { name = "water elementals", zone = "Hillsbrad Foothills", minLevel = 32, maxLevel = 38 },
        { name = "water elementals", zone = "Arathi Highlands", minLevel = 35, maxLevel = 40 },
        { name = "water elementals", zone = "Desolace", minLevel = 35, maxLevel = 42 },
        { name = "water elementals", zone = "Azshara", minLevel = 45, maxLevel = 52 },
    },
})

DB:RegisterItem({
    name = "Essence of Water",
    id = 7080,
    category = "Elemental",
    sources = {
        { name = "water elementals", zone = "Azshara", minLevel = 48, maxLevel = 55 },
        { name = "water elementals", zone = "Felwood", minLevel = 50, maxLevel = 56 },
        { name = "water elementals", zone = "Winterspring", minLevel = 53, maxLevel = 60 },
    },
})

DB:RegisterItem({
    name = "Elemental Air",
    id = 7069,
    category = "Elemental",
    sources = {
        { name = "air elementals", zone = "Arathi Highlands", minLevel = 35, maxLevel = 40 },
        { name = "air elementals", zone = "Badlands", minLevel = 40, maxLevel = 46 },
        { name = "air elementals", zone = "The Hinterlands", minLevel = 45, maxLevel = 50 },
    },
})

DB:RegisterItem({
    name = "Essence of Air",
    id = 7082,
    category = "Elemental",
    sources = {
        { name = "air elementals", zone = "Silithus", minLevel = 55, maxLevel = 60 },
        { name = "air elementals", zone = "Winterspring", minLevel = 53, maxLevel = 60 },
    },
})

DB:RegisterItem({
    name = "Essence of Earth",
    id = 7076,
    category = "Elemental",
    sources = {
        { name = "rock elementals", zone = "Un'Goro Crater", minLevel = 50, maxLevel = 55 },
        { name = "Blazing and stone elementals", zone = "Burning Steppes", minLevel = 50, maxLevel = 58 },
        { name = "earth elementals", zone = "Silithus", minLevel = 55, maxLevel = 60 },
    },
})

DB:RegisterItem({
    name = "Essence of Fire",
    id = 7078,
    category = "Elemental",
    sources = {
        { name = "fire elementals", zone = "Searing Gorge", minLevel = 48, maxLevel = 54 },
        { name = "Firegut ogres and fire elementals", zone = "Burning Steppes", minLevel = 50, maxLevel = 58 },
        { name = "Blazing Elemental", zone = "Un'Goro Crater", minLevel = 50, maxLevel = 53, note = "Fire Plume Ridge" },
    },
})

DB:RegisterItem({
    name = "Living Essence",
    id = 12803,
    category = "Elemental",
    sources = {
        { name = "Bloodpetal and living elementals", zone = "Un'Goro Crater", minLevel = 50, maxLevel = 56 },
        { name = "corrupted elementals", zone = "Felwood", minLevel = 50, maxLevel = 56 },
        { name = "elementals", zone = "Winterspring", minLevel = 53, maxLevel = 60 },
    },
})

--------------------------------------------------------------------------------
-- Extra spots for elementals already listed in Data_Misc
--
-- Registering a name that already exists merges, so these land on the existing
-- items rather than creating duplicates. This is the mechanism a Forever-
-- specific data pack would use to extend what ships here.
--------------------------------------------------------------------------------

DB:RegisterItem({
    name = "Elemental Earth",
    sources = {
        { name = "earth elementals", zone = "Un'Goro Crater", minLevel = 48, maxLevel = 54 },
        { name = "Stonelash and rock elementals", zone = "Desolace", minLevel = 35, maxLevel = 42 },
    },
})

DB:RegisterItem({
    name = "Elemental Fire",
    sources = {
        { name = "fire elementals", zone = "Tanaris", minLevel = 42, maxLevel = 48 },
    },
})
