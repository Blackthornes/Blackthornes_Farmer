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
