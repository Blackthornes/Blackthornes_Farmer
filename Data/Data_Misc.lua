-- Blackthornes Farmer -- Data/Data_Misc.lua
-- Seed data: everything that isn't a profession bracket -- elementals, fish,
-- and a couple of specific mob drops. This file is also the worked example for
-- the source kinds other than "node" and "mob".

local _, ns = ...

local DB = ns.DB

DB:RegisterItem({
    name = "Elemental Fire",
    id = 7068,
    category = "Elemental",
    aliases = { "fire elemental" },
    sources = {
        { kind = "mob", name = "Firegut Ogre Mage", zone = "Burning Steppes", minLevel = 50, maxLevel = 54 },
        { kind = "mob", name = "fire elementals", zone = "Searing Gorge", minLevel = 45, maxLevel = 52 },
        { kind = "mob", name = "Blazing Elemental", zone = "Un'Goro Crater", minLevel = 50, maxLevel = 53, note = "Fire Plume Ridge" },
    },
})

DB:RegisterItem({
    name = "Elemental Earth",
    id = 7067,
    category = "Elemental",
    aliases = { "earth elemental" },
    sources = {
        { kind = "mob", name = "rock elementals", zone = "Badlands", minLevel = 40, maxLevel = 46, note = "Angor Fortress approach" },
        { kind = "mob", name = "earth elementals", zone = "Arathi Highlands", minLevel = 35, maxLevel = 40 },
        { kind = "mob", name = "Boulderfist ogres and elementals", zone = "Silithus", minLevel = 55, maxLevel = 60 },
    },
})

DB:RegisterItem({
    name = "Deviate Fish",
    id = 6522,
    category = "Fishing",
    note = "Only from the pools -- open water in the zone will not give it.",
    sources = {
        { kind = "fishing", name = "Deviate Fish schools", zone = "The Barrens", minLevel = 10, maxLevel = 25, requires = "Fishing 1", note = "Lushwater Oasis and the Forgotten Pools" },
        { kind = "mob", name = "Deviate creatures", zone = "Wailing Caverns", minLevel = 17, maxLevel = 24, note = "instance" },
    },
})

DB:RegisterItem({
    name = "Heavy Silken Thread",
    id = 4291,
    category = "Vendor",
    note = "Not farmed -- buy it from any trade-goods vendor.",
    sources = {
        { kind = "vendor", name = "trade goods vendors", zone = "any capital city", minLevel = 1, maxLevel = 60 },
    },
})

DB:RegisterItem({
    name = "Small Lustrous Pearl",
    id = 5498,
    category = "Fishing",
    sources = {
        { kind = "fishing", name = "clams from Oily Blackmouth schools", zone = "Wetlands", minLevel = 20, maxLevel = 30, requires = "Fishing 1" },
        { kind = "mob", name = "murlocs", zone = "Westfall", minLevel = 12, maxLevel = 18, note = "loot the clams they drop" },
        { kind = "container", name = "Big-mouth Clam", zone = "any coastline", minLevel = 1, maxLevel = 60 },
    },
})

--------------------------------------------------------------------------------
-- Pearls
--
-- All out of clams, which drop off coastal murlocs and naga and turn up in
-- fishing. The pearl depends on the clam, and the clam on the mob's level.
--------------------------------------------------------------------------------

DB:RegisterItem({
    name = "Iridescent Pearl",
    id = 5500,
    category = "Fishing",
    sources = {
        { kind = "container", name = "Thick-shelled Clam", zone = "Stranglethorn Vale", minLevel = 30, maxLevel = 40, note = "off the coastal murlocs and naga" },
        { kind = "container", name = "Thick-shelled Clam", zone = "Desolace", minLevel = 30, maxLevel = 40, note = "off the coastal naga" },
    },
})

DB:RegisterItem({
    name = "Black Pearl",
    id = 7971,
    category = "Fishing",
    sources = {
        { kind = "container", name = "Big-mouth Clam", zone = "Stranglethorn Vale", minLevel = 35, maxLevel = 45, note = "the southern coast" },
        { kind = "container", name = "Big-mouth Clam", zone = "Feralas", minLevel = 40, maxLevel = 50, note = "off the naga" },
    },
})

DB:RegisterItem({
    name = "Golden Pearl",
    id = 13926,
    category = "Fishing",
    sources = {
        { kind = "container", name = "Big-mouth Clam", zone = "Feralas", minLevel = 45, maxLevel = 50, note = "off the naga" },
        { kind = "container", name = "Big-mouth Clam", zone = "Azshara", minLevel = 48, maxLevel = 55, note = "off the naga" },
    },
})

--------------------------------------------------------------------------------
-- Cooking meats
--
-- The dependable ones, low to high. Each comes off one kind of beast, so the
-- places are where that beast lives at a level the recipe wants.
--------------------------------------------------------------------------------

DB:RegisterItem({
    name = "Stringy Wolf Meat",
    id = 2672,
    category = "Cooking",
    sources = {
        { kind = "mob", name = "wolves", zone = "Elwynn Forest", minLevel = 2, maxLevel = 10 },
        { kind = "mob", name = "wolves", zone = "Mulgore", minLevel = 2, maxLevel = 10 },
        { kind = "mob", name = "wolves", zone = "Dun Morogh", minLevel = 2, maxLevel = 10 },
    },
})

DB:RegisterItem({
    name = "Chunk of Boar Meat",
    id = 769,
    category = "Cooking",
    aliases = { "boar meat" },
    sources = {
        { kind = "mob", name = "boars", zone = "Elwynn Forest", minLevel = 2, maxLevel = 10 },
        { kind = "mob", name = "boars", zone = "Durotar", minLevel = 2, maxLevel = 10 },
        { kind = "mob", name = "boars", zone = "Dun Morogh", minLevel = 2, maxLevel = 10 },
        { kind = "mob", name = "boars", zone = "Teldrassil", minLevel = 2, maxLevel = 10 },
    },
})

DB:RegisterItem({
    name = "Crawler Meat",
    id = 2674,
    category = "Cooking",
    sources = {
        { kind = "mob", name = "crawlers", zone = "Westfall", minLevel = 10, maxLevel = 18, note = "the coast" },
        { kind = "mob", name = "crawlers", zone = "Darkshore", minLevel = 10, maxLevel = 18, note = "the coast" },
    },
})

DB:RegisterItem({
    name = "Crawler Claw",
    id = 2675,
    category = "Cooking",
    sources = {
        { kind = "mob", name = "crawlers", zone = "Westfall", minLevel = 10, maxLevel = 18, note = "the coast" },
        { kind = "mob", name = "crawlers", zone = "Darkshore", minLevel = 10, maxLevel = 18, note = "the coast" },
    },
})

DB:RegisterItem({
    name = "Goretusk Liver",
    id = 723,
    category = "Cooking",
    sources = {
        { kind = "mob", name = "Goretusks", zone = "Westfall", minLevel = 11, maxLevel = 16 },
    },
})

DB:RegisterItem({
    name = "Murloc Fin",
    id = 1468,
    category = "Cooking",
    sources = {
        { kind = "mob", name = "murlocs", zone = "Westfall", minLevel = 10, maxLevel = 18, note = "the coast" },
        { kind = "mob", name = "murlocs", zone = "Loch Modan", minLevel = 10, maxLevel = 18 },
        { kind = "mob", name = "murlocs", zone = "Darkshore", minLevel = 10, maxLevel = 18 },
    },
})

DB:RegisterItem({
    name = "Strider Meat",
    id = 5469,
    category = "Cooking",
    sources = {
        { kind = "mob", name = "plainstriders", zone = "The Barrens", minLevel = 10, maxLevel = 20 },
        { kind = "mob", name = "striders", zone = "Darkshore", minLevel = 11, maxLevel = 18 },
    },
})

DB:RegisterItem({
    name = "Clam Meat",
    id = 5503,
    category = "Cooking",
    sources = {
        { kind = "container", name = "Small Barnacled Clam", zone = "Westfall", minLevel = 10, maxLevel = 18, note = "off the coastal murlocs" },
        { kind = "container", name = "Small Barnacled Clam", zone = "The Barrens", minLevel = 10, maxLevel = 20, note = "off the coastal murlocs" },
    },
})

DB:RegisterItem({
    name = "Bear Meat",
    id = 3173,
    category = "Cooking",
    sources = {
        { kind = "mob", name = "bears", zone = "Loch Modan", minLevel = 10, maxLevel = 18 },
        { kind = "mob", name = "bears", zone = "Darkshore", minLevel = 11, maxLevel = 20 },
        { kind = "mob", name = "bears", zone = "Ashenvale", minLevel = 20, maxLevel = 28 },
    },
})

DB:RegisterItem({
    name = "Raptor Egg",
    id = 3685,
    category = "Cooking",
    sources = {
        { kind = "mob", name = "raptors", zone = "The Barrens", minLevel = 14, maxLevel = 22 },
        { kind = "mob", name = "raptors", zone = "Wetlands", minLevel = 20, maxLevel = 28 },
    },
})

DB:RegisterItem({
    name = "Crocolisk Meat",
    id = 2924,
    category = "Cooking",
    sources = {
        { kind = "mob", name = "crocolisks", zone = "Loch Modan", minLevel = 15, maxLevel = 20 },
        { kind = "mob", name = "crocolisks", zone = "Wetlands", minLevel = 20, maxLevel = 25 },
    },
})

DB:RegisterItem({
    name = "Tender Crocolisk Meat",
    id = 3667,
    category = "Cooking",
    sources = {
        { kind = "mob", name = "crocolisks", zone = "Wetlands", minLevel = 22, maxLevel = 28 },
        { kind = "mob", name = "crocolisks", zone = "Stranglethorn Vale", minLevel = 30, maxLevel = 38 },
    },
})

DB:RegisterItem({
    name = "Big Bear Meat",
    id = 3730,
    category = "Cooking",
    sources = {
        { kind = "mob", name = "bears", zone = "Hillsbrad Foothills", minLevel = 25, maxLevel = 32 },
        { kind = "mob", name = "bears", zone = "Alterac Mountains", minLevel = 30, maxLevel = 38 },
    },
})

DB:RegisterItem({
    name = "Lion Meat",
    id = 3731,
    category = "Cooking",
    sources = {
        { kind = "mob", name = "mountain lions", zone = "Hillsbrad Foothills", minLevel = 25, maxLevel = 32 },
        { kind = "mob", name = "mountain lions", zone = "Alterac Mountains", minLevel = 30, maxLevel = 38 },
        { kind = "mob", name = "mountain lions", zone = "Arathi Highlands", minLevel = 30, maxLevel = 38 },
    },
})

DB:RegisterItem({
    name = "Turtle Meat",
    id = 3712,
    category = "Cooking",
    sources = {
        { kind = "mob", name = "turtles", zone = "Stranglethorn Vale", minLevel = 30, maxLevel = 40 },
    },
})

DB:RegisterItem({
    name = "Zesty Clam Meat",
    id = 7974,
    category = "Cooking",
    sources = {
        { kind = "container", name = "Thick-shelled Clam", zone = "Stranglethorn Vale", minLevel = 30, maxLevel = 45, note = "off the coastal murlocs and naga" },
    },
})

DB:RegisterItem({
    name = "Raptor Flesh",
    id = 12184,
    category = "Cooking",
    sources = {
        { kind = "mob", name = "ravasaurs", zone = "Un'Goro Crater", minLevel = 48, maxLevel = 55 },
    },
})

--------------------------------------------------------------------------------
-- Fish
--
-- Where each is caught, at the zone's level band. Fishing skill needed to
-- avoid getaways depends on the water rather than the fish, so it is left off
-- rather than guessed.
--------------------------------------------------------------------------------

DB:RegisterItem({
    name = "Raw Brilliant Smallfish",
    id = 6291,
    category = "Fishing",
    sources = {
        { kind = "fishing", name = "inland water", zone = "Elwynn Forest", minLevel = 1, maxLevel = 10 },
        { kind = "fishing", name = "inland water", zone = "Durotar", minLevel = 1, maxLevel = 10 },
        { kind = "fishing", name = "inland water", zone = "Teldrassil", minLevel = 1, maxLevel = 10 },
        { kind = "fishing", name = "inland water", zone = "Tirisfal Glades", minLevel = 1, maxLevel = 10 },
    },
})

DB:RegisterItem({
    name = "Raw Slitherskin Mackerel",
    id = 6303,
    category = "Fishing",
    sources = {
        { kind = "fishing", name = "the coast", zone = "Durotar", minLevel = 1, maxLevel = 10 },
        { kind = "fishing", name = "the coast", zone = "Teldrassil", minLevel = 1, maxLevel = 10 },
        { kind = "fishing", name = "the coast", zone = "Darkshore", minLevel = 10, maxLevel = 20 },
    },
})

DB:RegisterItem({
    name = "Raw Longjaw Mud Snapper",
    id = 6289,
    category = "Fishing",
    sources = {
        { kind = "fishing", name = "inland water", zone = "Elwynn Forest", minLevel = 1, maxLevel = 10 },
        { kind = "fishing", name = "inland water", zone = "Loch Modan", minLevel = 10, maxLevel = 20 },
        { kind = "fishing", name = "inland water", zone = "Silverpine Forest", minLevel = 10, maxLevel = 20 },
        { kind = "fishing", name = "inland water", zone = "The Barrens", minLevel = 10, maxLevel = 25 },
    },
})

DB:RegisterItem({
    name = "Raw Loch Frenzy",
    id = 6317,
    category = "Fishing",
    note = "Loch Modan's own fish.",
    sources = {
        { kind = "fishing", name = "the loch", zone = "Loch Modan", minLevel = 10, maxLevel = 20 },
    },
})

DB:RegisterItem({
    name = "Raw Rainbow Fin Albacore",
    id = 6361,
    category = "Fishing",
    sources = {
        { kind = "fishing", name = "the coast", zone = "Westfall", minLevel = 10, maxLevel = 20 },
        { kind = "fishing", name = "the coast", zone = "Darkshore", minLevel = 10, maxLevel = 20 },
        { kind = "fishing", name = "the coast", zone = "The Barrens", minLevel = 10, maxLevel = 25 },
    },
})

DB:RegisterItem({
    name = "Raw Bristle Whisker Catfish",
    id = 6308,
    category = "Fishing",
    sources = {
        { kind = "fishing", name = "inland water", zone = "Redridge Mountains", minLevel = 15, maxLevel = 25 },
        { kind = "fishing", name = "inland water", zone = "Ashenvale", minLevel = 18, maxLevel = 30 },
        { kind = "fishing", name = "inland water", zone = "Wetlands", minLevel = 20, maxLevel = 30 },
        { kind = "fishing", name = "inland water", zone = "Hillsbrad Foothills", minLevel = 20, maxLevel = 30 },
    },
})

DB:RegisterItem({
    name = "Oily Blackmouth",
    id = 6358,
    category = "Fishing",
    note = "From schools only -- open water will not give it.",
    sources = {
        { kind = "fishing", name = "Oily Blackmouth schools", zone = "Westfall", minLevel = 10, maxLevel = 20 },
        { kind = "fishing", name = "Oily Blackmouth schools", zone = "The Barrens", minLevel = 10, maxLevel = 25 },
        { kind = "fishing", name = "Oily Blackmouth schools", zone = "Wetlands", minLevel = 20, maxLevel = 30 },
        { kind = "fishing", name = "Oily Blackmouth schools", zone = "Stranglethorn Vale", minLevel = 30, maxLevel = 45 },
    },
})

DB:RegisterItem({
    name = "Firefin Snapper",
    id = 6359,
    category = "Fishing",
    note = "From schools only -- open water will not give it.",
    sources = {
        { kind = "fishing", name = "Firefin Snapper schools", zone = "Westfall", minLevel = 10, maxLevel = 20 },
        { kind = "fishing", name = "Firefin Snapper schools", zone = "The Barrens", minLevel = 10, maxLevel = 25 },
        { kind = "fishing", name = "Firefin Snapper schools", zone = "Wetlands", minLevel = 20, maxLevel = 30 },
        { kind = "fishing", name = "Firefin Snapper schools", zone = "Stranglethorn Vale", minLevel = 30, maxLevel = 45 },
    },
})

DB:RegisterItem({
    name = "Raw Rockscale Cod",
    id = 6362,
    category = "Fishing",
    sources = {
        { kind = "fishing", name = "the coast", zone = "Hillsbrad Foothills", minLevel = 20, maxLevel = 30 },
        { kind = "fishing", name = "the coast", zone = "Desolace", minLevel = 30, maxLevel = 40 },
        { kind = "fishing", name = "the coast", zone = "Stranglethorn Vale", minLevel = 30, maxLevel = 45 },
    },
})

DB:RegisterItem({
    name = "Raw Mithril Head Trout",
    id = 8365,
    category = "Fishing",
    sources = {
        { kind = "fishing", name = "inland water", zone = "Alterac Mountains", minLevel = 30, maxLevel = 40 },
        { kind = "fishing", name = "inland water", zone = "Arathi Highlands", minLevel = 30, maxLevel = 40 },
        { kind = "fishing", name = "inland water", zone = "Stranglethorn Vale", minLevel = 30, maxLevel = 45 },
        { kind = "fishing", name = "inland water", zone = "Swamp of Sorrows", minLevel = 35, maxLevel = 45 },
    },
})

DB:RegisterItem({
    name = "Raw Spotted Yellowtail",
    id = 4603,
    category = "Fishing",
    sources = {
        { kind = "fishing", name = "the coast", zone = "Stranglethorn Vale", minLevel = 30, maxLevel = 45 },
        { kind = "fishing", name = "the coast", zone = "Tanaris", minLevel = 40, maxLevel = 50 },
        { kind = "fishing", name = "the coast", zone = "Feralas", minLevel = 40, maxLevel = 50 },
    },
})

DB:RegisterItem({
    name = "Stonescale Eel",
    id = 13422,
    category = "Fishing",
    note = "From schools only.",
    sources = {
        { kind = "fishing", name = "Stonescale Eel swarms", zone = "Feralas", minLevel = 40, maxLevel = 50 },
        { kind = "fishing", name = "Stonescale Eel swarms", zone = "Tanaris", minLevel = 40, maxLevel = 50 },
        { kind = "fishing", name = "Stonescale Eel swarms", zone = "Azshara", minLevel = 48, maxLevel = 55 },
    },
})

DB:RegisterItem({
    name = "Raw Redgill",
    id = 13758,
    category = "Fishing",
    sources = {
        { kind = "fishing", name = "inland water", zone = "Feralas", minLevel = 40, maxLevel = 50 },
        { kind = "fishing", name = "inland water", zone = "The Hinterlands", minLevel = 40, maxLevel = 50 },
        { kind = "fishing", name = "inland water", zone = "Un'Goro Crater", minLevel = 48, maxLevel = 55 },
        { kind = "fishing", name = "inland water", zone = "Felwood", minLevel = 48, maxLevel = 55 },
    },
})

DB:RegisterItem({
    name = "Raw Glossy Mightfish",
    id = 13754,
    category = "Fishing",
    sources = {
        { kind = "fishing", name = "the coast", zone = "Tanaris", minLevel = 40, maxLevel = 50 },
        { kind = "fishing", name = "the coast", zone = "Feralas", minLevel = 40, maxLevel = 50 },
        { kind = "fishing", name = "the coast", zone = "Azshara", minLevel = 48, maxLevel = 55 },
    },
})

DB:RegisterItem({
    name = "Raw Summer Bass",
    id = 13756,
    category = "Fishing",
    note = "Summer only -- April to September.",
    sources = {
        { kind = "fishing", name = "the coast", zone = "Feralas", minLevel = 40, maxLevel = 50 },
        { kind = "fishing", name = "the coast", zone = "Azshara", minLevel = 48, maxLevel = 55 },
    },
})

DB:RegisterItem({
    name = "Winter Squid",
    id = 13755,
    category = "Fishing",
    note = "Winter only -- October to March.",
    sources = {
        { kind = "fishing", name = "the coast", zone = "Feralas", minLevel = 40, maxLevel = 50 },
        { kind = "fishing", name = "the coast", zone = "Tanaris", minLevel = 40, maxLevel = 50 },
        { kind = "fishing", name = "the coast", zone = "Azshara", minLevel = 48, maxLevel = 55 },
    },
})

DB:RegisterItem({
    name = "Raw Nightfin Snapper",
    id = 13759,
    category = "Fishing",
    note = "Night only.",
    sources = {
        { kind = "fishing", name = "inland water", zone = "Felwood", minLevel = 48, maxLevel = 55 },
        { kind = "fishing", name = "inland water", zone = "Un'Goro Crater", minLevel = 48, maxLevel = 55 },
        { kind = "fishing", name = "inland water", zone = "Western Plaguelands", minLevel = 51, maxLevel = 58 },
        { kind = "fishing", name = "inland water", zone = "Winterspring", minLevel = 53, maxLevel = 60 },
    },
})

DB:RegisterItem({
    name = "Raw Sunscale Salmon",
    id = 13760,
    category = "Fishing",
    note = "Daytime only.",
    sources = {
        { kind = "fishing", name = "inland water", zone = "Felwood", minLevel = 48, maxLevel = 55 },
        { kind = "fishing", name = "inland water", zone = "Un'Goro Crater", minLevel = 48, maxLevel = 55 },
        { kind = "fishing", name = "inland water", zone = "Western Plaguelands", minLevel = 51, maxLevel = 58 },
        { kind = "fishing", name = "inland water", zone = "Winterspring", minLevel = 53, maxLevel = 60 },
    },
})

DB:RegisterItem({
    name = "Raw Whitescale Salmon",
    id = 13889,
    category = "Fishing",
    sources = {
        { kind = "fishing", name = "inland water", zone = "Eastern Plaguelands", minLevel = 53, maxLevel = 60 },
        { kind = "fishing", name = "inland water", zone = "Winterspring", minLevel = 53, maxLevel = 60 },
    },
})
