-- Blackthornes Farmer -- Data/Data_Mining.lua
-- Seed data: ores and mining nodes.
--
-- Levels on a node are the zone's level band, not the node's -- they answer
-- "will the mobs around this node eat me?". Levels on a mob are the mob's own.

local _, ns = ...

local DB = ns.DB

DB:RegisterItem({
    name = "Copper Ore",
    id = 2770,
    category = "Mining",
    aliases = { "copper" },
    sources = {
        { kind = "node", name = "Copper Vein", zone = "Durotar", minLevel = 1, maxLevel = 10, requires = "Mining 1" },
        { kind = "node", name = "Copper Vein", zone = "Elwynn Forest", minLevel = 1, maxLevel = 10, requires = "Mining 1" },
        { kind = "node", name = "Copper Vein", zone = "Dun Morogh", minLevel = 1, maxLevel = 10, requires = "Mining 1" },
        { kind = "node", name = "Copper Vein", zone = "Mulgore", minLevel = 1, maxLevel = 10, requires = "Mining 1" },
        { kind = "node", name = "Copper Vein", zone = "Westfall", minLevel = 10, maxLevel = 20, requires = "Mining 1", note = "dense circuit along the coast" },
        { kind = "node", name = "Copper Vein", zone = "Loch Modan", minLevel = 10, maxLevel = 20, requires = "Mining 1" },
        { kind = "node", name = "Copper Vein", zone = "Darkshore", minLevel = 10, maxLevel = 20, requires = "Mining 1" },
        { kind = "node", name = "Copper Vein", zone = "The Barrens", minLevel = 10, maxLevel = 25, requires = "Mining 1", note = "best single-zone route for a new miner" },
    },
})

DB:RegisterItem({
    name = "Tin Ore",
    id = 2771,
    category = "Mining",
    aliases = { "tin" },
    sources = {
        { kind = "node", name = "Tin Vein", zone = "The Barrens", minLevel = 10, maxLevel = 25, requires = "Mining 65" },
        { kind = "node", name = "Tin Vein", zone = "Redridge Mountains", minLevel = 15, maxLevel = 25, requires = "Mining 65" },
        { kind = "node", name = "Tin Vein", zone = "Ashenvale", minLevel = 18, maxLevel = 30, requires = "Mining 65" },
        { kind = "node", name = "Tin Vein", zone = "Duskwood", minLevel = 18, maxLevel = 30, requires = "Mining 65" },
        { kind = "node", name = "Tin Vein", zone = "Hillsbrad Foothills", minLevel = 20, maxLevel = 30, requires = "Mining 65" },
        { kind = "node", name = "Tin Vein", zone = "Wetlands", minLevel = 20, maxLevel = 30, requires = "Mining 65" },
    },
})

DB:RegisterItem({
    name = "Silver Ore",
    id = 2775,
    category = "Mining",
    aliases = { "silver" },
    note = "Rare spawn that shares node points with tin. Farm tin routes and take what appears.",
    sources = {
        { kind = "node", name = "Silver Vein", zone = "Hillsbrad Foothills", minLevel = 20, maxLevel = 30, requires = "Mining 75" },
        { kind = "node", name = "Silver Vein", zone = "Wetlands", minLevel = 20, maxLevel = 30, requires = "Mining 75" },
        { kind = "node", name = "Silver Vein", zone = "Ashenvale", minLevel = 18, maxLevel = 30, requires = "Mining 75" },
    },
})

DB:RegisterItem({
    name = "Iron Ore",
    id = 2772,
    category = "Mining",
    aliases = { "iron" },
    sources = {
        { kind = "node", name = "Iron Deposit", zone = "Thousand Needles", minLevel = 25, maxLevel = 35, requires = "Mining 125" },
        { kind = "node", name = "Iron Deposit", zone = "Arathi Highlands", minLevel = 30, maxLevel = 40, requires = "Mining 125", note = "open terrain, fast circuit" },
        { kind = "node", name = "Iron Deposit", zone = "Desolace", minLevel = 30, maxLevel = 40, requires = "Mining 125" },
        { kind = "node", name = "Iron Deposit", zone = "Stranglethorn Vale", minLevel = 30, maxLevel = 45, requires = "Mining 125" },
        { kind = "node", name = "Iron Deposit", zone = "Badlands", minLevel = 35, maxLevel = 45, requires = "Mining 125" },
    },
})

DB:RegisterItem({
    name = "Gold Ore",
    id = 2776,
    category = "Mining",
    aliases = { "gold" },
    note = "Rare spawn on iron routes rather than a route of its own.",
    sources = {
        { kind = "node", name = "Gold Vein", zone = "Thousand Needles", minLevel = 25, maxLevel = 35, requires = "Mining 155" },
        { kind = "node", name = "Gold Vein", zone = "Arathi Highlands", minLevel = 30, maxLevel = 40, requires = "Mining 155" },
        { kind = "node", name = "Gold Vein", zone = "Badlands", minLevel = 35, maxLevel = 45, requires = "Mining 155" },
        { kind = "node", name = "Gold Vein", zone = "Stranglethorn Vale", minLevel = 30, maxLevel = 45, requires = "Mining 155" },
    },
})

DB:RegisterItem({
    name = "Mithril Ore",
    id = 3858,
    category = "Mining",
    aliases = { "mithril" },
    sources = {
        { kind = "node", name = "Mithril Deposit", zone = "Badlands", minLevel = 35, maxLevel = 45, requires = "Mining 175" },
        { kind = "node", name = "Mithril Deposit", zone = "Tanaris", minLevel = 40, maxLevel = 50, requires = "Mining 175" },
        { kind = "node", name = "Mithril Deposit", zone = "Feralas", minLevel = 40, maxLevel = 50, requires = "Mining 175" },
        { kind = "node", name = "Mithril Deposit", zone = "The Hinterlands", minLevel = 40, maxLevel = 50, requires = "Mining 175" },
        { kind = "node", name = "Mithril Deposit", zone = "Searing Gorge", minLevel = 43, maxLevel = 50, requires = "Mining 175", note = "highest node density, but crowded" },
        { kind = "node", name = "Mithril Deposit", zone = "Un'Goro Crater", minLevel = 48, maxLevel = 55, requires = "Mining 175" },
    },
})

DB:RegisterItem({
    name = "Truesilver Ore",
    id = 7911,
    category = "Mining",
    aliases = { "truesilver" },
    note = "Rare spawn on mithril routes.",
    sources = {
        { kind = "node", name = "Truesilver Deposit", zone = "Badlands", minLevel = 35, maxLevel = 45, requires = "Mining 230" },
        { kind = "node", name = "Truesilver Deposit", zone = "Tanaris", minLevel = 40, maxLevel = 50, requires = "Mining 230" },
        { kind = "node", name = "Truesilver Deposit", zone = "Un'Goro Crater", minLevel = 48, maxLevel = 55, requires = "Mining 230" },
        { kind = "node", name = "Truesilver Deposit", zone = "Winterspring", minLevel = 53, maxLevel = 60, requires = "Mining 230" },
    },
})

DB:RegisterItem({
    name = "Thorium Ore",
    id = 10620,
    category = "Mining",
    aliases = { "thorium" },
    sources = {
        { kind = "node", name = "Small Thorium Vein", zone = "Un'Goro Crater", minLevel = 48, maxLevel = 55, requires = "Mining 245" },
        { kind = "node", name = "Small Thorium Vein", zone = "Burning Steppes", minLevel = 50, maxLevel = 58, requires = "Mining 245" },
        { kind = "node", name = "Rich Thorium Vein", zone = "Eastern Plaguelands", minLevel = 53, maxLevel = 60, requires = "Mining 275" },
        { kind = "node", name = "Rich Thorium Vein", zone = "Winterspring", minLevel = 53, maxLevel = 60, requires = "Mining 275", note = "the classic end-game thorium loop" },
        { kind = "node", name = "Rich Thorium Vein", zone = "Silithus", minLevel = 55, maxLevel = 60, requires = "Mining 275" },
    },
})

--------------------------------------------------------------------------------
-- Ores that only come from one place
--------------------------------------------------------------------------------

DB:RegisterItem({
    name = "Incendicite Ore",
    id = 3340,
    category = "Mining",
    aliases = { "incendicite" },
    note = "Only in Thelgen Rock.",
    sources = {
        { kind = "node", name = "Incendicite Mineral Vein", zone = "Wetlands", location = "Thelgen Rock", minLevel = 20, maxLevel = 30, requires = "Mining 65" },
    },
})

DB:RegisterItem({
    name = "Lesser Bloodstone Ore",
    id = 4278,
    category = "Mining",
    aliases = { "bloodstone" },
    note = "Only in Arathi Highlands.",
    sources = {
        { kind = "node", name = "Lesser Bloodstone Deposit", zone = "Arathi Highlands", minLevel = 30, maxLevel = 40, requires = "Mining 75" },
    },
})

DB:RegisterItem({
    name = "Indurium Ore",
    id = 5833,
    category = "Mining",
    aliases = { "indurium" },
    note = "Only inside Uldaman.",
    sources = {
        { kind = "node", name = "Indurium Mineral Vein", zone = "Badlands", location = "Uldaman", minLevel = 35, maxLevel = 45, requires = "Mining 150", note = "instance" },
    },
})

DB:RegisterItem({
    name = "Dark Iron Ore",
    id = 11370,
    category = "Mining",
    aliases = { "dark iron" },
    note = "Only inside Blackrock Mountain.",
    sources = {
        { kind = "node", name = "Dark Iron Deposit", zone = "Searing Gorge", location = "Blackrock Depths", minLevel = 52, maxLevel = 60, requires = "Mining 230", note = "instance" },
        { kind = "node", name = "Dark Iron Deposit", zone = "Searing Gorge", location = "Molten Core", minLevel = 60, maxLevel = 60, requires = "Mining 230", note = "raid" },
    },
})

--------------------------------------------------------------------------------
-- Stone
--
-- Every stone comes out of one ore's veins, so the places to get it are that
-- ore's places. Listed at the best few zones for the vein, not every one.
--------------------------------------------------------------------------------

DB:RegisterItem({
    name = "Rough Stone",
    id = 2835,
    category = "Mining",
    note = "Comes out of Copper Veins.",
    sources = {
        { kind = "node", name = "Copper Vein", zone = "Durotar", minLevel = 1, maxLevel = 10, requires = "Mining 1" },
        { kind = "node", name = "Copper Vein", zone = "Elwynn Forest", minLevel = 1, maxLevel = 10, requires = "Mining 1" },
        { kind = "node", name = "Copper Vein", zone = "Dun Morogh", minLevel = 1, maxLevel = 10, requires = "Mining 1" },
        { kind = "node", name = "Copper Vein", zone = "Westfall", minLevel = 10, maxLevel = 20, requires = "Mining 1" },
        { kind = "node", name = "Copper Vein", zone = "The Barrens", minLevel = 10, maxLevel = 25, requires = "Mining 1" },
    },
})

DB:RegisterItem({
    name = "Coarse Stone",
    id = 2836,
    category = "Mining",
    note = "Comes out of Tin Veins.",
    sources = {
        { kind = "node", name = "Tin Vein", zone = "The Barrens", minLevel = 10, maxLevel = 25, requires = "Mining 65" },
        { kind = "node", name = "Tin Vein", zone = "Redridge Mountains", minLevel = 15, maxLevel = 25, requires = "Mining 65" },
        { kind = "node", name = "Tin Vein", zone = "Ashenvale", minLevel = 18, maxLevel = 30, requires = "Mining 65" },
        { kind = "node", name = "Tin Vein", zone = "Hillsbrad Foothills", minLevel = 20, maxLevel = 30, requires = "Mining 65" },
        { kind = "node", name = "Tin Vein", zone = "Wetlands", minLevel = 20, maxLevel = 30, requires = "Mining 65" },
    },
})

DB:RegisterItem({
    name = "Heavy Stone",
    id = 2838,
    category = "Mining",
    note = "Comes out of Iron Deposits.",
    sources = {
        { kind = "node", name = "Iron Deposit", zone = "Thousand Needles", minLevel = 25, maxLevel = 35, requires = "Mining 125" },
        { kind = "node", name = "Iron Deposit", zone = "Arathi Highlands", minLevel = 30, maxLevel = 40, requires = "Mining 125" },
        { kind = "node", name = "Iron Deposit", zone = "Desolace", minLevel = 30, maxLevel = 40, requires = "Mining 125" },
        { kind = "node", name = "Iron Deposit", zone = "Stranglethorn Vale", minLevel = 30, maxLevel = 45, requires = "Mining 125" },
        { kind = "node", name = "Iron Deposit", zone = "Badlands", minLevel = 35, maxLevel = 45, requires = "Mining 125" },
    },
})

DB:RegisterItem({
    name = "Solid Stone",
    id = 7912,
    category = "Mining",
    note = "Comes out of Mithril Deposits.",
    sources = {
        { kind = "node", name = "Mithril Deposit", zone = "Badlands", minLevel = 35, maxLevel = 45, requires = "Mining 175" },
        { kind = "node", name = "Mithril Deposit", zone = "Tanaris", minLevel = 40, maxLevel = 50, requires = "Mining 175" },
        { kind = "node", name = "Mithril Deposit", zone = "Feralas", minLevel = 40, maxLevel = 50, requires = "Mining 175" },
        { kind = "node", name = "Mithril Deposit", zone = "The Hinterlands", minLevel = 40, maxLevel = 50, requires = "Mining 175" },
        { kind = "node", name = "Mithril Deposit", zone = "Searing Gorge", minLevel = 43, maxLevel = 50, requires = "Mining 175" },
    },
})

DB:RegisterItem({
    name = "Dense Stone",
    id = 12365,
    category = "Mining",
    note = "Comes out of Thorium veins.",
    sources = {
        { kind = "node", name = "Small Thorium Vein", zone = "Un'Goro Crater", minLevel = 48, maxLevel = 55, requires = "Mining 245" },
        { kind = "node", name = "Small Thorium Vein", zone = "Burning Steppes", minLevel = 50, maxLevel = 58, requires = "Mining 245" },
        { kind = "node", name = "Rich Thorium Vein", zone = "Eastern Plaguelands", minLevel = 53, maxLevel = 60, requires = "Mining 275" },
        { kind = "node", name = "Rich Thorium Vein", zone = "Winterspring", minLevel = 53, maxLevel = 60, requires = "Mining 275" },
        { kind = "node", name = "Rich Thorium Vein", zone = "Silithus", minLevel = 55, maxLevel = 60, requires = "Mining 275" },
    },
})

--------------------------------------------------------------------------------
-- Gems
--
-- None has a node of its own: each is an occasional bonus out of particular
-- veins. So a gem's sources are the veins that give it, at those veins' best
-- zones. How often is what a harvest would tell us; nothing here claims to.
--------------------------------------------------------------------------------

DB:RegisterItem({
    name = "Malachite",
    id = 774,
    category = "Gem",
    note = "A bonus out of Copper Veins.",
    sources = {
        { kind = "node", name = "Copper Vein", zone = "Durotar", minLevel = 1, maxLevel = 10, requires = "Mining 1" },
        { kind = "node", name = "Copper Vein", zone = "Westfall", minLevel = 10, maxLevel = 20, requires = "Mining 1" },
        { kind = "node", name = "Copper Vein", zone = "The Barrens", minLevel = 10, maxLevel = 25, requires = "Mining 1" },
    },
})

DB:RegisterItem({
    name = "Tigerseye",
    id = 818,
    category = "Gem",
    note = "A bonus out of Copper Veins.",
    sources = {
        { kind = "node", name = "Copper Vein", zone = "Durotar", minLevel = 1, maxLevel = 10, requires = "Mining 1" },
        { kind = "node", name = "Copper Vein", zone = "Westfall", minLevel = 10, maxLevel = 20, requires = "Mining 1" },
        { kind = "node", name = "Copper Vein", zone = "The Barrens", minLevel = 10, maxLevel = 25, requires = "Mining 1" },
    },
})

DB:RegisterItem({
    name = "Shadowgem",
    id = 1210,
    category = "Gem",
    note = "A bonus out of Copper and Tin Veins.",
    sources = {
        { kind = "node", name = "Copper Vein", zone = "The Barrens", minLevel = 10, maxLevel = 25, requires = "Mining 1" },
        { kind = "node", name = "Tin Vein", zone = "The Barrens", minLevel = 10, maxLevel = 25, requires = "Mining 65" },
        { kind = "node", name = "Tin Vein", zone = "Redridge Mountains", minLevel = 15, maxLevel = 25, requires = "Mining 65" },
        { kind = "node", name = "Tin Vein", zone = "Wetlands", minLevel = 20, maxLevel = 30, requires = "Mining 65" },
    },
})

DB:RegisterItem({
    name = "Moss Agate",
    id = 1206,
    category = "Gem",
    note = "A bonus out of Tin Veins.",
    sources = {
        { kind = "node", name = "Tin Vein", zone = "The Barrens", minLevel = 10, maxLevel = 25, requires = "Mining 65" },
        { kind = "node", name = "Tin Vein", zone = "Redridge Mountains", minLevel = 15, maxLevel = 25, requires = "Mining 65" },
        { kind = "node", name = "Tin Vein", zone = "Hillsbrad Foothills", minLevel = 20, maxLevel = 30, requires = "Mining 65" },
    },
})

DB:RegisterItem({
    name = "Lesser Moonstone",
    id = 1705,
    category = "Gem",
    note = "A bonus out of Tin, Silver and Iron.",
    sources = {
        { kind = "node", name = "Tin Vein", zone = "Hillsbrad Foothills", minLevel = 20, maxLevel = 30, requires = "Mining 65" },
        { kind = "node", name = "Tin Vein", zone = "Wetlands", minLevel = 20, maxLevel = 30, requires = "Mining 65" },
        { kind = "node", name = "Iron Deposit", zone = "Thousand Needles", minLevel = 25, maxLevel = 35, requires = "Mining 125" },
        { kind = "node", name = "Iron Deposit", zone = "Arathi Highlands", minLevel = 30, maxLevel = 40, requires = "Mining 125" },
    },
})

DB:RegisterItem({
    name = "Jade",
    id = 1529,
    category = "Gem",
    note = "A bonus out of Iron Deposits, and Silver and Gold Veins.",
    sources = {
        { kind = "node", name = "Iron Deposit", zone = "Thousand Needles", minLevel = 25, maxLevel = 35, requires = "Mining 125" },
        { kind = "node", name = "Iron Deposit", zone = "Arathi Highlands", minLevel = 30, maxLevel = 40, requires = "Mining 125" },
        { kind = "node", name = "Iron Deposit", zone = "Desolace", minLevel = 30, maxLevel = 40, requires = "Mining 125" },
        { kind = "node", name = "Iron Deposit", zone = "Stranglethorn Vale", minLevel = 30, maxLevel = 45, requires = "Mining 125" },
    },
})

DB:RegisterItem({
    name = "Citrine",
    id = 3864,
    category = "Gem",
    note = "A bonus out of Iron, Gold and Mithril.",
    sources = {
        { kind = "node", name = "Iron Deposit", zone = "Arathi Highlands", minLevel = 30, maxLevel = 40, requires = "Mining 125" },
        { kind = "node", name = "Iron Deposit", zone = "Stranglethorn Vale", minLevel = 30, maxLevel = 45, requires = "Mining 125" },
        { kind = "node", name = "Mithril Deposit", zone = "Badlands", minLevel = 35, maxLevel = 45, requires = "Mining 175" },
        { kind = "node", name = "Mithril Deposit", zone = "Tanaris", minLevel = 40, maxLevel = 50, requires = "Mining 175" },
    },
})

DB:RegisterItem({
    name = "Aquamarine",
    id = 7909,
    category = "Gem",
    note = "A bonus out of Mithril and Truesilver.",
    sources = {
        { kind = "node", name = "Mithril Deposit", zone = "Badlands", minLevel = 35, maxLevel = 45, requires = "Mining 175" },
        { kind = "node", name = "Mithril Deposit", zone = "Tanaris", minLevel = 40, maxLevel = 50, requires = "Mining 175" },
        { kind = "node", name = "Mithril Deposit", zone = "The Hinterlands", minLevel = 40, maxLevel = 50, requires = "Mining 175" },
        { kind = "node", name = "Mithril Deposit", zone = "Searing Gorge", minLevel = 43, maxLevel = 50, requires = "Mining 175" },
    },
})

DB:RegisterItem({
    name = "Star Ruby",
    id = 7910,
    category = "Gem",
    note = "A bonus out of Mithril, Truesilver and small Thorium.",
    sources = {
        { kind = "node", name = "Mithril Deposit", zone = "Searing Gorge", minLevel = 43, maxLevel = 50, requires = "Mining 175" },
        { kind = "node", name = "Mithril Deposit", zone = "Un'Goro Crater", minLevel = 48, maxLevel = 55, requires = "Mining 175" },
        { kind = "node", name = "Small Thorium Vein", zone = "Un'Goro Crater", minLevel = 48, maxLevel = 55, requires = "Mining 245" },
        { kind = "node", name = "Small Thorium Vein", zone = "Burning Steppes", minLevel = 50, maxLevel = 58, requires = "Mining 245" },
    },
})

DB:RegisterItem({
    name = "Large Opal",
    id = 12799,
    category = "Gem",
    note = "A bonus out of Thorium veins.",
    sources = {
        { kind = "node", name = "Small Thorium Vein", zone = "Un'Goro Crater", minLevel = 48, maxLevel = 55, requires = "Mining 245" },
        { kind = "node", name = "Small Thorium Vein", zone = "Burning Steppes", minLevel = 50, maxLevel = 58, requires = "Mining 245" },
        { kind = "node", name = "Rich Thorium Vein", zone = "Eastern Plaguelands", minLevel = 53, maxLevel = 60, requires = "Mining 275" },
        { kind = "node", name = "Rich Thorium Vein", zone = "Winterspring", minLevel = 53, maxLevel = 60, requires = "Mining 275" },
    },
})

DB:RegisterItem({
    name = "Blue Sapphire",
    id = 12361,
    category = "Gem",
    note = "A bonus out of Thorium veins.",
    sources = {
        { kind = "node", name = "Small Thorium Vein", zone = "Un'Goro Crater", minLevel = 48, maxLevel = 55, requires = "Mining 245" },
        { kind = "node", name = "Small Thorium Vein", zone = "Burning Steppes", minLevel = 50, maxLevel = 58, requires = "Mining 245" },
        { kind = "node", name = "Rich Thorium Vein", zone = "Eastern Plaguelands", minLevel = 53, maxLevel = 60, requires = "Mining 275" },
        { kind = "node", name = "Rich Thorium Vein", zone = "Winterspring", minLevel = 53, maxLevel = 60, requires = "Mining 275" },
    },
})

DB:RegisterItem({
    name = "Huge Emerald",
    id = 12364,
    category = "Gem",
    note = "A rare bonus out of Thorium veins.",
    sources = {
        { kind = "node", name = "Small Thorium Vein", zone = "Un'Goro Crater", minLevel = 48, maxLevel = 55, requires = "Mining 245" },
        { kind = "node", name = "Rich Thorium Vein", zone = "Eastern Plaguelands", minLevel = 53, maxLevel = 60, requires = "Mining 275" },
        { kind = "node", name = "Rich Thorium Vein", zone = "Winterspring", minLevel = 53, maxLevel = 60, requires = "Mining 275" },
        { kind = "node", name = "Rich Thorium Vein", zone = "Silithus", minLevel = 55, maxLevel = 60, requires = "Mining 275" },
    },
})

DB:RegisterItem({
    name = "Azerothian Diamond",
    id = 12800,
    category = "Gem",
    note = "A rare bonus out of Thorium veins.",
    sources = {
        { kind = "node", name = "Small Thorium Vein", zone = "Burning Steppes", minLevel = 50, maxLevel = 58, requires = "Mining 245" },
        { kind = "node", name = "Rich Thorium Vein", zone = "Eastern Plaguelands", minLevel = 53, maxLevel = 60, requires = "Mining 275" },
        { kind = "node", name = "Rich Thorium Vein", zone = "Winterspring", minLevel = 53, maxLevel = 60, requires = "Mining 275" },
        { kind = "node", name = "Rich Thorium Vein", zone = "Silithus", minLevel = 55, maxLevel = 60, requires = "Mining 275" },
    },
})

DB:RegisterItem({
    name = "Arcane Crystal",
    id = 12363,
    category = "Gem",
    note = "Rich Thorium only, and rarely. The expensive one.",
    sources = {
        { kind = "node", name = "Rich Thorium Vein", zone = "Eastern Plaguelands", minLevel = 53, maxLevel = 60, requires = "Mining 275" },
        { kind = "node", name = "Rich Thorium Vein", zone = "Winterspring", minLevel = 53, maxLevel = 60, requires = "Mining 275" },
        { kind = "node", name = "Rich Thorium Vein", zone = "Silithus", minLevel = 55, maxLevel = 60, requires = "Mining 275" },
    },
})
