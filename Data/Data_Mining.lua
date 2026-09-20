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
    note = "Rare spawn that shares node points with tin -- farm tin routes and take what appears.",
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
