-- Blackthornes Farmer -- Data/Data_Leather.lua
-- Seed data: leather. Skinning entries name the beasts worth skinning and use
-- the beasts' own level range.

local _, ns = ...

local DB = ns.DB

DB:RegisterItem({
    name = "Light Leather",
    id = 2318,
    category = "Leatherworking",
    sources = {
        { kind = "skinning", name = "boars and wolves", zone = "Elwynn Forest", minLevel = 2, maxLevel = 10, requires = "Skinning 1" },
        { kind = "skinning", name = "boars and scorpids", zone = "Durotar", minLevel = 2, maxLevel = 10, requires = "Skinning 1" },
        { kind = "skinning", name = "prairie wolves and kodo", zone = "Mulgore", minLevel = 5, maxLevel = 12, requires = "Skinning 1", note = "thickest low-level beast population" },
        { kind = "skinning", name = "young stags and thistle boars", zone = "Teldrassil", minLevel = 3, maxLevel = 10, requires = "Skinning 1" },
    },
})

DB:RegisterItem({
    name = "Medium Leather",
    id = 2319,
    category = "Leatherworking",
    sources = {
        { kind = "skinning", name = "plainstriders and zhevras", zone = "The Barrens", minLevel = 12, maxLevel = 22, requires = "Skinning 100" },
        { kind = "skinning", name = "coyotes and harvest watchers", zone = "Westfall", minLevel = 12, maxLevel = 20, requires = "Skinning 100" },
        { kind = "skinning", name = "bears and nightsabers", zone = "Ashenvale", minLevel = 18, maxLevel = 28, requires = "Skinning 100" },
        { kind = "skinning", name = "mountain lions and bears", zone = "Hillsbrad Foothills", minLevel = 20, maxLevel = 30, requires = "Skinning 100" },
    },
})

DB:RegisterItem({
    name = "Heavy Leather",
    id = 4234,
    category = "Leatherworking",
    sources = {
        { kind = "skinning", name = "raptors and tigers", zone = "Stranglethorn Vale", minLevel = 30, maxLevel = 42, requires = "Skinning 150", note = "the standard heavy/thick route" },
        { kind = "skinning", name = "mountain lions and vultures", zone = "Arathi Highlands", minLevel = 30, maxLevel = 40, requires = "Skinning 150" },
        { kind = "skinning", name = "yetis", zone = "Hillsbrad Foothills", minLevel = 30, maxLevel = 35, requires = "Skinning 150" },
        { kind = "skinning", name = "buzzards and scorpids", zone = "Badlands", minLevel = 35, maxLevel = 45, requires = "Skinning 150" },
    },
})

DB:RegisterItem({
    name = "Thick Leather",
    id = 4304,
    category = "Leatherworking",
    sources = {
        { kind = "skinning", name = "raptors and basilisks", zone = "Tanaris", minLevel = 40, maxLevel = 50, requires = "Skinning 200" },
        { kind = "skinning", name = "hippogryphs and yetis", zone = "Feralas", minLevel = 40, maxLevel = 50, requires = "Skinning 200" },
        { kind = "skinning", name = "owlbeasts and chimaera", zone = "The Hinterlands", minLevel = 40, maxLevel = 50, requires = "Skinning 200" },
        { kind = "skinning", name = "stegodons and diemetradons", zone = "Un'Goro Crater", minLevel = 48, maxLevel = 55, requires = "Skinning 200" },
    },
})

DB:RegisterItem({
    name = "Rugged Leather",
    id = 8170,
    category = "Leatherworking",
    sources = {
        { kind = "skinning", name = "stegodons and pterrordax", zone = "Un'Goro Crater", minLevel = 48, maxLevel = 55, requires = "Skinning 250", note = "best rugged density, and devilsaurs nearby" },
        { kind = "skinning", name = "winterspring owls and bears", zone = "Winterspring", minLevel = 53, maxLevel = 60, requires = "Skinning 250" },
        { kind = "skinning", name = "plaguebats and rot hides", zone = "Eastern Plaguelands", minLevel = 53, maxLevel = 60, requires = "Skinning 250" },
        { kind = "skinning", name = "scorpids and basilisks", zone = "Silithus", minLevel = 55, maxLevel = 60, requires = "Skinning 250" },
    },
})

DB:RegisterItem({
    name = "Devilsaur Leather",
    id = 15417,
    category = "Leatherworking",
    note = "Only from devilsaurs. Expect the spawns to be contested.",
    sources = {
        { kind = "skinning", name = "Devilsaur", zone = "Un'Goro Crater", minLevel = 55, maxLevel = 57, requires = "Skinning 300", note = "elite-damage hitters; bring a pet or a friend" },
        { kind = "skinning", name = "Tyrant Devilsaur", zone = "Un'Goro Crater", minLevel = 57, maxLevel = 57, requires = "Skinning 300", note = "rare spawn" },
    },
})

--------------------------------------------------------------------------------
-- Scraps and hides
--
-- A hide comes off the same beasts as the leather of its tier, just rarely,
-- so each hide's places are its leather's places.
--------------------------------------------------------------------------------

DB:RegisterItem({
    name = "Ruined Leather Scraps",
    id = 2934,
    category = "Leatherworking",
    aliases = { "leather scraps" },
    note = "Off the very lowest beasts. Three make a piece of Light Leather.",
    sources = {
        { kind = "skinning", name = "boars and wolves", zone = "Elwynn Forest", minLevel = 1, maxLevel = 10, requires = "Skinning 1" },
        { kind = "skinning", name = "boars and scorpids", zone = "Durotar", minLevel = 1, maxLevel = 10, requires = "Skinning 1" },
        { kind = "skinning", name = "plainstriders and wolves", zone = "Mulgore", minLevel = 1, maxLevel = 10, requires = "Skinning 1" },
        { kind = "skinning", name = "nightsabers and boars", zone = "Teldrassil", minLevel = 1, maxLevel = 10, requires = "Skinning 1" },
    },
})

DB:RegisterItem({
    name = "Light Hide",
    id = 783,
    category = "Leatherworking",
    sources = {
        { kind = "skinning", name = "wolves and boars", zone = "Westfall", minLevel = 10, maxLevel = 20, requires = "Skinning 1" },
        { kind = "skinning", name = "wolves and bears", zone = "Darkshore", minLevel = 10, maxLevel = 20, requires = "Skinning 1" },
        { kind = "skinning", name = "bears and boars", zone = "Loch Modan", minLevel = 10, maxLevel = 20, requires = "Skinning 1" },
        { kind = "skinning", name = "plainstriders and zhevras", zone = "The Barrens", minLevel = 10, maxLevel = 25, requires = "Skinning 1" },
    },
})

DB:RegisterItem({
    name = "Medium Hide",
    id = 4232,
    category = "Leatherworking",
    sources = {
        { kind = "skinning", name = "plainstriders and zhevras", zone = "The Barrens", minLevel = 12, maxLevel = 25, requires = "Skinning 100" },
        { kind = "skinning", name = "bears and nightsabers", zone = "Ashenvale", minLevel = 18, maxLevel = 28, requires = "Skinning 100" },
        { kind = "skinning", name = "mountain lions and bears", zone = "Hillsbrad Foothills", minLevel = 20, maxLevel = 30, requires = "Skinning 100" },
        { kind = "skinning", name = "raptors and crocolisks", zone = "Wetlands", minLevel = 20, maxLevel = 30, requires = "Skinning 100" },
    },
})

DB:RegisterItem({
    name = "Heavy Hide",
    id = 4235,
    category = "Leatherworking",
    sources = {
        { kind = "skinning", name = "raptors and tigers", zone = "Stranglethorn Vale", minLevel = 30, maxLevel = 42, requires = "Skinning 150" },
        { kind = "skinning", name = "mountain lions and vultures", zone = "Arathi Highlands", minLevel = 30, maxLevel = 40, requires = "Skinning 150" },
        { kind = "skinning", name = "kodos and scorpids", zone = "Desolace", minLevel = 30, maxLevel = 40, requires = "Skinning 150" },
        { kind = "skinning", name = "buzzards and scorpids", zone = "Badlands", minLevel = 35, maxLevel = 45, requires = "Skinning 150" },
    },
})

DB:RegisterItem({
    name = "Thick Hide",
    id = 8169,
    category = "Leatherworking",
    sources = {
        { kind = "skinning", name = "raptors and basilisks", zone = "Tanaris", minLevel = 40, maxLevel = 50, requires = "Skinning 200" },
        { kind = "skinning", name = "hippogryphs and yetis", zone = "Feralas", minLevel = 40, maxLevel = 50, requires = "Skinning 200" },
        { kind = "skinning", name = "owlbeasts and chimaera", zone = "The Hinterlands", minLevel = 40, maxLevel = 50, requires = "Skinning 200" },
        { kind = "skinning", name = "stegodons and diemetradons", zone = "Un'Goro Crater", minLevel = 48, maxLevel = 55, requires = "Skinning 200" },
    },
})

DB:RegisterItem({
    name = "Rugged Hide",
    id = 8171,
    category = "Leatherworking",
    sources = {
        { kind = "skinning", name = "stegodons and pterrordax", zone = "Un'Goro Crater", minLevel = 48, maxLevel = 55, requires = "Skinning 250" },
        { kind = "skinning", name = "winterspring owls and bears", zone = "Winterspring", minLevel = 53, maxLevel = 60, requires = "Skinning 250" },
        { kind = "skinning", name = "plaguebats and rot hides", zone = "Eastern Plaguelands", minLevel = 53, maxLevel = 60, requires = "Skinning 250" },
        { kind = "skinning", name = "scorpids and basilisks", zone = "Silithus", minLevel = 55, maxLevel = 60, requires = "Skinning 250" },
    },
})

--------------------------------------------------------------------------------
-- Scales and special leathers
--------------------------------------------------------------------------------

DB:RegisterItem({
    name = "Scorpid Scale",
    id = 8154,
    category = "Leatherworking",
    sources = {
        { kind = "skinning", name = "scorpids", zone = "Tanaris", minLevel = 40, maxLevel = 50, requires = "Skinning 200" },
        { kind = "skinning", name = "scorpids", zone = "Blasted Lands", minLevel = 45, maxLevel = 55, requires = "Skinning 200" },
    },
})

DB:RegisterItem({
    name = "Heavy Scorpid Scale",
    id = 15408,
    category = "Leatherworking",
    sources = {
        { kind = "skinning", name = "scorpids", zone = "Burning Steppes", minLevel = 50, maxLevel = 58, requires = "Skinning 250" },
        { kind = "skinning", name = "scorpids", zone = "Silithus", minLevel = 55, maxLevel = 60, requires = "Skinning 250" },
    },
})

DB:RegisterItem({
    name = "Turtle Scale",
    id = 8167,
    category = "Leatherworking",
    sources = {
        { kind = "skinning", name = "sea turtles", zone = "Tanaris", minLevel = 40, maxLevel = 50, requires = "Skinning 200", note = "the coast" },
        { kind = "skinning", name = "sea turtles", zone = "Feralas", minLevel = 40, maxLevel = 50, requires = "Skinning 200", note = "the coast" },
        { kind = "skinning", name = "sea turtles", zone = "Azshara", minLevel = 48, maxLevel = 55, requires = "Skinning 200", note = "the coast" },
    },
})

DB:RegisterItem({
    name = "Worn Dragonscale",
    id = 8165,
    category = "Leatherworking",
    sources = {
        { kind = "skinning", name = "dragonkin", zone = "Badlands", location = "Lethlor Ravine", minLevel = 40, maxLevel = 45, requires = "Skinning 200" },
        { kind = "skinning", name = "black dragonkin", zone = "Dustwallow Marsh", location = "the Wyrmbog", minLevel = 40, maxLevel = 45, requires = "Skinning 200" },
        { kind = "skinning", name = "blue dragonkin", zone = "Azshara", minLevel = 48, maxLevel = 55, requires = "Skinning 250" },
        { kind = "skinning", name = "black dragonkin", zone = "Burning Steppes", minLevel = 50, maxLevel = 58, requires = "Skinning 250" },
    },
})

DB:RegisterItem({
    name = "Green Dragonscale",
    id = 15412,
    category = "Leatherworking",
    sources = {
        { kind = "skinning", name = "green dragonkin", zone = "Swamp of Sorrows", minLevel = 40, maxLevel = 45, requires = "Skinning 200" },
    },
})

DB:RegisterItem({
    name = "Blue Dragonscale",
    id = 15415,
    category = "Leatherworking",
    sources = {
        { kind = "skinning", name = "blue dragonkin", zone = "Azshara", minLevel = 48, maxLevel = 55, requires = "Skinning 250" },
        { kind = "skinning", name = "blue dragonkin", zone = "Winterspring", location = "Mazthoril", minLevel = 55, maxLevel = 60, requires = "Skinning 275" },
    },
})

DB:RegisterItem({
    name = "Frostsaber Leather",
    id = 15422,
    category = "Leatherworking",
    note = "Only from Winterspring's frostsabers.",
    sources = {
        { kind = "skinning", name = "frostsabers", zone = "Winterspring", minLevel = 55, maxLevel = 60, requires = "Skinning 275" },
    },
})

DB:RegisterItem({
    name = "Core Leather",
    id = 17012,
    category = "Leatherworking",
    note = "Raid only. Skinned off Molten Core's core hounds.",
    sources = {
        { kind = "skinning", name = "Core Hound", zone = "Searing Gorge", location = "Molten Core", minLevel = 60, maxLevel = 60, requires = "Skinning 300", note = "raid" },
    },
})

--------------------------------------------------------------------------------
-- Leatherworking reagents that drop rather than skin
--------------------------------------------------------------------------------

DB:RegisterItem({
    name = "Raptor Hide",
    id = 4461,
    category = "Leatherworking",
    note = "A loot drop off raptors, not a skinning result.",
    sources = {
        { kind = "mob", name = "raptors", zone = "Wetlands", minLevel = 20, maxLevel = 30 },
        { kind = "mob", name = "raptors", zone = "Arathi Highlands", minLevel = 30, maxLevel = 40 },
        { kind = "mob", name = "raptors", zone = "Stranglethorn Vale", minLevel = 30, maxLevel = 42 },
        { kind = "mob", name = "raptors", zone = "Dustwallow Marsh", minLevel = 35, maxLevel = 45 },
    },
})

DB:RegisterItem({
    name = "Black Whelp Scale",
    id = 7286,
    category = "Leatherworking",
    sources = {
        { kind = "mob", name = "black dragon whelps", zone = "Redridge Mountains", minLevel = 15, maxLevel = 20 },
        { kind = "mob", name = "black dragon whelps", zone = "Wetlands", minLevel = 20, maxLevel = 25 },
    },
})

DB:RegisterItem({
    name = "Red Whelp Scale",
    id = 7287,
    category = "Leatherworking",
    sources = {
        { kind = "mob", name = "red dragon whelps", zone = "Wetlands", minLevel = 20, maxLevel = 25, note = "the Dragonmaw side" },
    },
})

DB:RegisterItem({
    name = "Slimy Murloc Scale",
    id = 5784,
    category = "Leatherworking",
    sources = {
        { kind = "mob", name = "murlocs", zone = "Wetlands", minLevel = 20, maxLevel = 30 },
        { kind = "mob", name = "murlocs", zone = "Hillsbrad Foothills", minLevel = 20, maxLevel = 30 },
        { kind = "mob", name = "murlocs", zone = "Stranglethorn Vale", minLevel = 30, maxLevel = 40 },
    },
})

DB:RegisterItem({
    name = "Thick Murloc Scale",
    id = 5785,
    category = "Leatherworking",
    sources = {
        { kind = "mob", name = "murlocs", zone = "Stranglethorn Vale", minLevel = 35, maxLevel = 45, note = "the southern coast" },
        { kind = "mob", name = "murlocs", zone = "Swamp of Sorrows", minLevel = 35, maxLevel = 45 },
    },
})

DB:RegisterItem({
    name = "Deviate Scale",
    id = 6470,
    category = "Leatherworking",
    sources = {
        { kind = "mob", name = "Deviate creatures", zone = "The Barrens", location = "Wailing Caverns", minLevel = 17, maxLevel = 24, note = "instance, and the mobs round its mouth" },
    },
})

DB:RegisterItem({
    name = "Perfect Deviate Scale",
    id = 6471,
    category = "Leatherworking",
    note = "The rare version of Deviate Scale, from the same mobs.",
    sources = {
        { kind = "mob", name = "Deviate creatures", zone = "The Barrens", location = "Wailing Caverns", minLevel = 17, maxLevel = 24, note = "instance" },
    },
})
