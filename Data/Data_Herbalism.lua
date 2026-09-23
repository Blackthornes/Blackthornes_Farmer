-- Blackthornes Farmer -- Data/Data_Herbalism.lua
-- Seed data: herbs. Levels are the zone's level band.

local _, ns = ...

local DB = ns.DB

DB:RegisterItem({
    name = "Peacebloom",
    id = 2447,
    category = "Herbalism",
    sources = {
        { kind = "herb", zone = "Elwynn Forest", minLevel = 1, maxLevel = 10, requires = "Herbalism 1" },
        { kind = "herb", zone = "Durotar", minLevel = 1, maxLevel = 10, requires = "Herbalism 1" },
        { kind = "herb", zone = "Mulgore", minLevel = 1, maxLevel = 10, requires = "Herbalism 1", note = "wide open, easiest low-level loop" },
        { kind = "herb", zone = "Dun Morogh", minLevel = 1, maxLevel = 10, requires = "Herbalism 1" },
        { kind = "herb", zone = "Teldrassil", minLevel = 1, maxLevel = 10, requires = "Herbalism 1" },
    },
})

DB:RegisterItem({
    name = "Silverleaf",
    id = 765,
    category = "Herbalism",
    sources = {
        { kind = "herb", zone = "Elwynn Forest", minLevel = 1, maxLevel = 10, requires = "Herbalism 1" },
        { kind = "herb", zone = "Teldrassil", minLevel = 1, maxLevel = 10, requires = "Herbalism 1" },
        { kind = "herb", zone = "Durotar", minLevel = 1, maxLevel = 10, requires = "Herbalism 1" },
        { kind = "herb", zone = "Dun Morogh", minLevel = 1, maxLevel = 10, requires = "Herbalism 1" },
    },
})

DB:RegisterItem({
    name = "Earthroot",
    id = 2449,
    category = "Herbalism",
    sources = {
        { kind = "herb", zone = "Dun Morogh", minLevel = 1, maxLevel = 10, requires = "Herbalism 15", note = "favours hillsides and cave mouths" },
        { kind = "herb", zone = "Durotar", minLevel = 1, maxLevel = 10, requires = "Herbalism 15" },
        { kind = "herb", zone = "Darkshore", minLevel = 10, maxLevel = 20, requires = "Herbalism 15" },
        { kind = "herb", zone = "Loch Modan", minLevel = 10, maxLevel = 20, requires = "Herbalism 15" },
    },
})

DB:RegisterItem({
    name = "Mageroyal",
    id = 785,
    category = "Herbalism",
    sources = {
        { kind = "herb", zone = "The Barrens", minLevel = 10, maxLevel = 25, requires = "Herbalism 50" },
        { kind = "herb", zone = "Redridge Mountains", minLevel = 15, maxLevel = 25, requires = "Herbalism 50" },
        { kind = "herb", zone = "Darkshore", minLevel = 10, maxLevel = 20, requires = "Herbalism 50" },
        { kind = "herb", zone = "Hillsbrad Foothills", minLevel = 20, maxLevel = 30, requires = "Herbalism 50" },
    },
})

DB:RegisterItem({
    name = "Briarthorn",
    id = 2450,
    category = "Herbalism",
    sources = {
        { kind = "herb", zone = "Westfall", minLevel = 10, maxLevel = 20, requires = "Herbalism 70" },
        { kind = "herb", zone = "Loch Modan", minLevel = 10, maxLevel = 20, requires = "Herbalism 70" },
        { kind = "herb", zone = "The Barrens", minLevel = 10, maxLevel = 25, requires = "Herbalism 70" },
        { kind = "herb", zone = "Darkshore", minLevel = 10, maxLevel = 20, requires = "Herbalism 70" },
        { kind = "herb", zone = "Hillsbrad Foothills", minLevel = 20, maxLevel = 30, requires = "Herbalism 70" },
    },
})

DB:RegisterItem({
    name = "Stranglekelp",
    id = 3820,
    category = "Herbalism",
    note = "Underwater only -- swim the coastline, not the interior.",
    sources = {
        { kind = "herb", zone = "Wetlands", minLevel = 20, maxLevel = 30, requires = "Herbalism 85", note = "shallow coast, easy pulls" },
        { kind = "herb", zone = "Hillsbrad Foothills", minLevel = 20, maxLevel = 30, requires = "Herbalism 85" },
        { kind = "herb", zone = "Desolace", minLevel = 30, maxLevel = 40, requires = "Herbalism 85" },
        { kind = "herb", zone = "Stranglethorn Vale", minLevel = 30, maxLevel = 45, requires = "Herbalism 85", note = "densest kelp beds in the game" },
    },
})

DB:RegisterItem({
    name = "Kingsblood",
    id = 3356,
    category = "Herbalism",
    sources = {
        { kind = "herb", zone = "Hillsbrad Foothills", minLevel = 20, maxLevel = 30, requires = "Herbalism 125" },
        { kind = "herb", zone = "Arathi Highlands", minLevel = 30, maxLevel = 40, requires = "Herbalism 125" },
        { kind = "herb", zone = "Stranglethorn Vale", minLevel = 30, maxLevel = 45, requires = "Herbalism 125" },
        { kind = "herb", zone = "Desolace", minLevel = 30, maxLevel = 40, requires = "Herbalism 125" },
    },
})

DB:RegisterItem({
    name = "Goldthorn",
    id = 3821,
    category = "Herbalism",
    sources = {
        { kind = "herb", zone = "Arathi Highlands", minLevel = 30, maxLevel = 40, requires = "Herbalism 170" },
        { kind = "herb", zone = "Badlands", minLevel = 35, maxLevel = 45, requires = "Herbalism 170" },
        { kind = "herb", zone = "Stranglethorn Vale", minLevel = 30, maxLevel = 45, requires = "Herbalism 170" },
        { kind = "herb", zone = "The Hinterlands", minLevel = 40, maxLevel = 50, requires = "Herbalism 170" },
    },
})

DB:RegisterItem({
    name = "Dreamfoil",
    id = 13463,
    category = "Herbalism",
    note = "Mana-potion staple, so it sells steadily.",
    sources = {
        { kind = "herb", zone = "Un'Goro Crater", minLevel = 48, maxLevel = 55, requires = "Herbalism 270" },
        { kind = "herb", zone = "Azshara", minLevel = 48, maxLevel = 55, requires = "Herbalism 270" },
        { kind = "herb", zone = "Eastern Plaguelands", minLevel = 53, maxLevel = 60, requires = "Herbalism 270" },
        { kind = "herb", zone = "Winterspring", minLevel = 53, maxLevel = 60, requires = "Herbalism 270" },
        { kind = "herb", zone = "Silithus", minLevel = 55, maxLevel = 60, requires = "Herbalism 270", note = "flat and fast if you can clear the bugs" },
    },
})

DB:RegisterItem({
    name = "Mountain Silversage",
    id = 13465,
    category = "Herbalism",
    sources = {
        { kind = "herb", zone = "Un'Goro Crater", minLevel = 48, maxLevel = 55, requires = "Herbalism 280" },
        { kind = "herb", zone = "Burning Steppes", minLevel = 50, maxLevel = 58, requires = "Herbalism 280" },
        { kind = "herb", zone = "Winterspring", minLevel = 53, maxLevel = 60, requires = "Herbalism 280" },
        { kind = "herb", zone = "Silithus", minLevel = 55, maxLevel = 60, requires = "Herbalism 280" },
    },
})

DB:RegisterItem({
    name = "Black Lotus",
    id = 13468,
    category = "Herbalism",
    note = "Very rare timed spawn -- run a full circuit of a zone rather than camping one point.",
    sources = {
        { kind = "herb", zone = "Burning Steppes", minLevel = 50, maxLevel = 58, requires = "Herbalism 300" },
        { kind = "herb", zone = "Eastern Plaguelands", minLevel = 53, maxLevel = 60, requires = "Herbalism 300" },
        { kind = "herb", zone = "Winterspring", minLevel = 53, maxLevel = 60, requires = "Herbalism 300" },
        { kind = "herb", zone = "Silithus", minLevel = 55, maxLevel = 60, requires = "Herbalism 300" },
    },
})

--------------------------------------------------------------------------------
-- The rest of the vanilla herbs, in skill order
--
-- Seeded from Classic as a starting point: the herb, the skill it needs, and
-- the zones it is known to grow in, at the zone's level band. No rates -- a
-- node is picked, not rolled for. Farm a route and mark the rows that hold up.
--------------------------------------------------------------------------------

DB:RegisterItem({
    name = "Swiftthistle",
    id = 2452,
    category = "Herbalism",
    note = "No node of its own -- a bonus that comes out of Mageroyal and Briarthorn.",
    sources = {
        { kind = "herb", name = "Mageroyal and Briarthorn", zone = "The Barrens", minLevel = 10, maxLevel = 25, requires = "Herbalism 50" },
        { kind = "herb", name = "Mageroyal and Briarthorn", zone = "Darkshore", minLevel = 10, maxLevel = 20, requires = "Herbalism 50" },
        { kind = "herb", name = "Mageroyal and Briarthorn", zone = "Hillsbrad Foothills", minLevel = 20, maxLevel = 30, requires = "Herbalism 50" },
    },
})

DB:RegisterItem({
    name = "Bruiseweed",
    id = 2453,
    category = "Herbalism",
    sources = {
        { kind = "herb", zone = "The Barrens", minLevel = 10, maxLevel = 25, requires = "Herbalism 100" },
        { kind = "herb", zone = "Stonetalon Mountains", minLevel = 15, maxLevel = 27, requires = "Herbalism 100" },
        { kind = "herb", zone = "Redridge Mountains", minLevel = 15, maxLevel = 25, requires = "Herbalism 100" },
        { kind = "herb", zone = "Ashenvale", minLevel = 18, maxLevel = 30, requires = "Herbalism 100" },
        { kind = "herb", zone = "Duskwood", minLevel = 18, maxLevel = 30, requires = "Herbalism 100" },
        { kind = "herb", zone = "Hillsbrad Foothills", minLevel = 20, maxLevel = 30, requires = "Herbalism 100" },
        { kind = "herb", zone = "Wetlands", minLevel = 20, maxLevel = 30, requires = "Herbalism 100" },
    },
})

DB:RegisterItem({
    name = "Wild Steelbloom",
    id = 3355,
    category = "Herbalism",
    sources = {
        { kind = "herb", zone = "Stonetalon Mountains", minLevel = 15, maxLevel = 27, requires = "Herbalism 115" },
        { kind = "herb", zone = "Thousand Needles", minLevel = 25, maxLevel = 35, requires = "Herbalism 115" },
        { kind = "herb", zone = "Arathi Highlands", minLevel = 30, maxLevel = 40, requires = "Herbalism 115" },
        { kind = "herb", zone = "Stranglethorn Vale", minLevel = 30, maxLevel = 45, requires = "Herbalism 115" },
        { kind = "herb", zone = "Badlands", minLevel = 35, maxLevel = 45, requires = "Herbalism 115" },
    },
})

DB:RegisterItem({
    name = "Grave Moss",
    id = 3369,
    category = "Herbalism",
    note = "Graveyards only, and not many of them.",
    sources = {
        { kind = "herb", zone = "Duskwood", location = "Raven Hill Cemetery", minLevel = 18, maxLevel = 30, requires = "Herbalism 120" },
        { kind = "herb", zone = "Desolace", location = "Kodo Graveyard", minLevel = 30, maxLevel = 40, requires = "Herbalism 120" },
    },
})

DB:RegisterItem({
    name = "Liferoot",
    id = 3357,
    category = "Herbalism",
    note = "Grows beside water -- follow the rivers and lake shores.",
    sources = {
        { kind = "herb", zone = "Wetlands", minLevel = 20, maxLevel = 30, requires = "Herbalism 150" },
        { kind = "herb", zone = "Hillsbrad Foothills", minLevel = 20, maxLevel = 30, requires = "Herbalism 150" },
        { kind = "herb", zone = "Arathi Highlands", minLevel = 30, maxLevel = 40, requires = "Herbalism 150" },
        { kind = "herb", zone = "Stranglethorn Vale", minLevel = 30, maxLevel = 45, requires = "Herbalism 150" },
        { kind = "herb", zone = "Swamp of Sorrows", minLevel = 35, maxLevel = 45, requires = "Herbalism 150" },
        { kind = "herb", zone = "Dustwallow Marsh", minLevel = 35, maxLevel = 45, requires = "Herbalism 150" },
        { kind = "herb", zone = "The Hinterlands", minLevel = 40, maxLevel = 50, requires = "Herbalism 150" },
    },
})

DB:RegisterItem({
    name = "Fadeleaf",
    id = 3818,
    category = "Herbalism",
    sources = {
        { kind = "herb", zone = "Alterac Mountains", minLevel = 30, maxLevel = 40, requires = "Herbalism 160" },
        { kind = "herb", zone = "Arathi Highlands", minLevel = 30, maxLevel = 40, requires = "Herbalism 160" },
        { kind = "herb", zone = "Stranglethorn Vale", minLevel = 30, maxLevel = 45, requires = "Herbalism 160" },
        { kind = "herb", zone = "Swamp of Sorrows", minLevel = 35, maxLevel = 45, requires = "Herbalism 160" },
        { kind = "herb", zone = "Dustwallow Marsh", minLevel = 35, maxLevel = 45, requires = "Herbalism 160" },
    },
})

DB:RegisterItem({
    name = "Khadgar's Whisker",
    id = 3358,
    category = "Herbalism",
    aliases = { "khadgars whisker" },
    sources = {
        { kind = "herb", zone = "Arathi Highlands", minLevel = 30, maxLevel = 40, requires = "Herbalism 185" },
        { kind = "herb", zone = "Stranglethorn Vale", minLevel = 30, maxLevel = 45, requires = "Herbalism 185" },
        { kind = "herb", zone = "Swamp of Sorrows", minLevel = 35, maxLevel = 45, requires = "Herbalism 185" },
        { kind = "herb", zone = "Dustwallow Marsh", minLevel = 35, maxLevel = 45, requires = "Herbalism 185" },
        { kind = "herb", zone = "The Hinterlands", minLevel = 40, maxLevel = 50, requires = "Herbalism 185" },
        { kind = "herb", zone = "Feralas", minLevel = 40, maxLevel = 50, requires = "Herbalism 185" },
    },
})

DB:RegisterItem({
    name = "Wintersbite",
    id = 3819,
    category = "Herbalism",
    note = "Only grows in Alterac Mountains.",
    sources = {
        { kind = "herb", zone = "Alterac Mountains", minLevel = 30, maxLevel = 40, requires = "Herbalism 195" },
    },
})

DB:RegisterItem({
    name = "Firebloom",
    id = 4625,
    category = "Herbalism",
    sources = {
        { kind = "herb", zone = "Badlands", minLevel = 35, maxLevel = 45, requires = "Herbalism 205" },
        { kind = "herb", zone = "Tanaris", minLevel = 40, maxLevel = 50, requires = "Herbalism 205" },
        { kind = "herb", zone = "Searing Gorge", minLevel = 43, maxLevel = 50, requires = "Herbalism 205" },
        { kind = "herb", zone = "Blasted Lands", minLevel = 45, maxLevel = 55, requires = "Herbalism 205" },
    },
})

DB:RegisterItem({
    name = "Purple Lotus",
    id = 8831,
    category = "Herbalism",
    sources = {
        { kind = "herb", zone = "Ashenvale", minLevel = 18, maxLevel = 30, requires = "Herbalism 210" },
        { kind = "herb", zone = "Stranglethorn Vale", minLevel = 30, maxLevel = 45, requires = "Herbalism 210" },
        { kind = "herb", zone = "Tanaris", minLevel = 40, maxLevel = 50, requires = "Herbalism 210" },
        { kind = "herb", zone = "Feralas", minLevel = 40, maxLevel = 50, requires = "Herbalism 210" },
        { kind = "herb", zone = "The Hinterlands", minLevel = 40, maxLevel = 50, requires = "Herbalism 210" },
        { kind = "herb", zone = "Azshara", minLevel = 48, maxLevel = 55, requires = "Herbalism 210" },
    },
})

DB:RegisterItem({
    name = "Arthas' Tears",
    id = 8836,
    category = "Herbalism",
    aliases = { "arthas tears" },
    sources = {
        { kind = "herb", zone = "Felwood", minLevel = 48, maxLevel = 55, requires = "Herbalism 220" },
        { kind = "herb", zone = "Western Plaguelands", minLevel = 51, maxLevel = 58, requires = "Herbalism 220" },
        { kind = "herb", zone = "Eastern Plaguelands", minLevel = 53, maxLevel = 60, requires = "Herbalism 220" },
    },
})

DB:RegisterItem({
    name = "Sungrass",
    id = 8838,
    category = "Herbalism",
    sources = {
        { kind = "herb", zone = "Feralas", minLevel = 40, maxLevel = 50, requires = "Herbalism 230" },
        { kind = "herb", zone = "The Hinterlands", minLevel = 40, maxLevel = 50, requires = "Herbalism 230" },
        { kind = "herb", zone = "Blasted Lands", minLevel = 45, maxLevel = 55, requires = "Herbalism 230" },
        { kind = "herb", zone = "Azshara", minLevel = 48, maxLevel = 55, requires = "Herbalism 230" },
        { kind = "herb", zone = "Felwood", minLevel = 48, maxLevel = 55, requires = "Herbalism 230" },
        { kind = "herb", zone = "Un'Goro Crater", minLevel = 48, maxLevel = 55, requires = "Herbalism 230" },
        { kind = "herb", zone = "Eastern Plaguelands", minLevel = 53, maxLevel = 60, requires = "Herbalism 230" },
        { kind = "herb", zone = "Silithus", minLevel = 55, maxLevel = 60, requires = "Herbalism 230" },
    },
})

DB:RegisterItem({
    name = "Blindweed",
    id = 8839,
    category = "Herbalism",
    note = "A swamp herb -- wet, low ground.",
    sources = {
        { kind = "herb", zone = "Swamp of Sorrows", minLevel = 35, maxLevel = 45, requires = "Herbalism 235" },
        { kind = "herb", zone = "Dustwallow Marsh", minLevel = 35, maxLevel = 45, requires = "Herbalism 235" },
        { kind = "herb", zone = "Un'Goro Crater", minLevel = 48, maxLevel = 55, requires = "Herbalism 235" },
    },
})

DB:RegisterItem({
    name = "Ghost Mushroom",
    id = 8845,
    category = "Herbalism",
    note = "Caves and underground only.",
    sources = {
        { kind = "herb", zone = "Desolace", location = "Maraudon", minLevel = 40, maxLevel = 49, requires = "Herbalism 245", note = "instance" },
        { kind = "herb", zone = "The Hinterlands", minLevel = 40, maxLevel = 50, requires = "Herbalism 245", note = "the troll caves" },
    },
})

DB:RegisterItem({
    name = "Gromsblood",
    id = 8846,
    category = "Herbalism",
    note = "Grows where demons have been -- look near their camps.",
    sources = {
        { kind = "herb", zone = "Ashenvale", location = "Demon Fall Canyon", minLevel = 18, maxLevel = 30, requires = "Herbalism 250" },
        { kind = "herb", zone = "Desolace", location = "Mannoroc Coven", minLevel = 30, maxLevel = 40, requires = "Herbalism 250" },
        { kind = "herb", zone = "Blasted Lands", minLevel = 45, maxLevel = 55, requires = "Herbalism 250" },
        { kind = "herb", zone = "Felwood", minLevel = 48, maxLevel = 55, requires = "Herbalism 250" },
    },
})

DB:RegisterItem({
    name = "Golden Sansam",
    id = 13464,
    category = "Herbalism",
    sources = {
        { kind = "herb", zone = "Swamp of Sorrows", minLevel = 35, maxLevel = 45, requires = "Herbalism 260" },
        { kind = "herb", zone = "Feralas", minLevel = 40, maxLevel = 50, requires = "Herbalism 260" },
        { kind = "herb", zone = "The Hinterlands", minLevel = 40, maxLevel = 50, requires = "Herbalism 260" },
        { kind = "herb", zone = "Azshara", minLevel = 48, maxLevel = 55, requires = "Herbalism 260" },
        { kind = "herb", zone = "Un'Goro Crater", minLevel = 48, maxLevel = 55, requires = "Herbalism 260" },
        { kind = "herb", zone = "Burning Steppes", minLevel = 50, maxLevel = 58, requires = "Herbalism 260" },
        { kind = "herb", zone = "Silithus", minLevel = 55, maxLevel = 60, requires = "Herbalism 260" },
    },
})

DB:RegisterItem({
    name = "Plaguebloom",
    id = 13466,
    category = "Herbalism",
    sources = {
        { kind = "herb", zone = "Felwood", minLevel = 48, maxLevel = 55, requires = "Herbalism 285" },
        { kind = "herb", zone = "Western Plaguelands", minLevel = 51, maxLevel = 58, requires = "Herbalism 285" },
        { kind = "herb", zone = "Eastern Plaguelands", minLevel = 53, maxLevel = 60, requires = "Herbalism 285" },
    },
})

DB:RegisterItem({
    name = "Icecap",
    id = 13467,
    category = "Herbalism",
    note = "Only grows in Winterspring.",
    sources = {
        { kind = "herb", zone = "Winterspring", minLevel = 53, maxLevel = 60, requires = "Herbalism 290" },
    },
})
