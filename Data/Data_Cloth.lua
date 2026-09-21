-- Blackthornes Farmer -- Data/Data_Cloth.lua
-- Seed data: cloth.
--
-- Cloth is the clearest "which mobs do I kill" case, so these entries name the
-- mob and use the mob's own level range.

local _, ns = ...

local DB = ns.DB

DB:RegisterItem({
    name = "Linen Cloth",
    id = 2589,
    category = "Cloth",
    aliases = { "linen" },
    sources = {
        { kind = "mob", name = "Riverpaw gnolls", zone = "Elwynn Forest", minLevel = 8, maxLevel = 12 },
        { kind = "mob", name = "Defias Trapper / Smuggler", zone = "Westfall", minLevel = 12, maxLevel = 18, note = "Moonbrook and the Gold Coast farms" },
        { kind = "mob", name = "Kolkar centaurs", zone = "The Barrens", minLevel = 12, maxLevel = 18 },
        { kind = "mob", name = "Riverpaw gnolls", zone = "Redridge Mountains", minLevel = 15, maxLevel = 20 },
    },
})

-- Wool Cloth is the worked example of a fully researched item: every row names
-- the mob, its level, where in the zone it stands, and roughly how often it
-- drops. Use this shape for the rest of the data.
--
-- Drop rates and coordinates are Classic-era figures. Coordinates are only
-- given where the landmark is unambiguous; everywhere else the location name
-- is the honest answer, because a coordinate that is wrong costs a flight
-- while a landmark name does not.
DB:RegisterItem({
    name = "Wool Cloth",
    id = 2592,
    category = "Cloth",
    aliases = { "wool" },
    note = "Any humanoid in the low twenties drops it. Pick the densest camp you can pull safely.",
    sources = {
        --------------------------------------------------------------------
        -- Instances: the highest density, and no competition for spawns
        --------------------------------------------------------------------
        { name = "Shadowfang Moonwalker", zone = "Silverpine Forest",
          location = "Shadowfang Keep", coords = { 45.0, 68.0 },
          minLevel = 22, maxLevel = 23, chance = 45,
          note = "instance -- the densest wool in the bracket" },

        { name = "Shadowfang Darksoul", zone = "Silverpine Forest",
          location = "Shadowfang Keep", coords = { 45.0, 68.0 },
          minLevel = 23, maxLevel = 24, chance = 42, note = "instance" },

        { name = "Shadowfang Ragetooth", zone = "Silverpine Forest",
          location = "Shadowfang Keep", coords = { 45.0, 68.0 },
          minLevel = 24, maxLevel = 25, chance = 40, note = "instance" },

        { name = "Scarlet Neophyte", zone = "Tirisfal Glades",
          location = "Scarlet Monastery, Graveyard wing", coords = { 85.0, 32.0 },
          minLevel = 28, maxLevel = 30, chance = 35,
          note = "instance -- starts dropping silk too at this level" },

        --------------------------------------------------------------------
        -- Outdoor camps
        --------------------------------------------------------------------
        { name = "Syndicate Rogue", zone = "Hillsbrad Foothills",
          location = "Durnholde Keep", coords = { 80.0, 60.0 },
          minLevel = 25, maxLevel = 26, chance = 32,
          note = "tight respawn, easy to circle" },

        { name = "Syndicate Watchman", zone = "Hillsbrad Foothills",
          location = "Durnholde Keep", coords = { 80.0, 60.0 },
          minLevel = 26, maxLevel = 27, chance = 30 },

        { name = "Syndicate Footpad", zone = "Hillsbrad Foothills",
          location = "Southshore to Tarren Mill road camps",
          minLevel = 24, maxLevel = 25, chance = 28,
          note = "contested ground on a PvP realm" },

        { name = "Blackrock Champion", zone = "Redridge Mountains",
          location = "Stonewatch Keep", coords = { 73.0, 55.0 },
          minLevel = 24, maxLevel = 26, chance = 30 },

        { name = "Blackrock Shadowcaster", zone = "Redridge Mountains",
          location = "Stonewatch Keep", coords = { 73.0, 55.0 },
          minLevel = 23, maxLevel = 25, chance = 28 },

        { name = "Blackrock Outrunner", zone = "Redridge Mountains",
          location = "Render's Camp", minLevel = 20, maxLevel = 22, chance = 25 },

        { name = "Nightbane Dark Runner", zone = "Duskwood",
          location = "Raven Hill Cemetery", coords = { 18.0, 48.0 },
          minLevel = 22, maxLevel = 24, chance = 28 },

        { name = "Nightbane Vile Fang", zone = "Duskwood",
          location = "Raven Hill Cemetery", coords = { 18.0, 48.0 },
          minLevel = 24, maxLevel = 26, chance = 27 },

        { name = "Dragonmaw Bonewarder", zone = "Wetlands",
          location = "Angerfang Encampment", coords = { 34.0, 53.0 },
          minLevel = 25, maxLevel = 27, chance = 30 },

        { name = "Dragonmaw Centurion", zone = "Wetlands",
          location = "Angerfang Encampment", coords = { 34.0, 53.0 },
          minLevel = 26, maxLevel = 28, chance = 29 },

        { name = "Venture Co. Strip Miner", zone = "Stonetalon Mountains",
          location = "Windshear Crag", minLevel = 22, maxLevel = 25, chance = 26 },

        { name = "Venture Co. Supervisor", zone = "Stonetalon Mountains",
          location = "Windshear Crag", minLevel = 25, maxLevel = 27, chance = 28 },

        { name = "Syndicate Highwayman", zone = "Alterac Mountains",
          location = "Sofera's Naze and the Ruins of Alterac",
          minLevel = 28, maxLevel = 30, chance = 30 },

        { name = "Crushridge Brute", zone = "Alterac Mountains",
          location = "Ruins of Alterac", minLevel = 29, maxLevel = 31, chance = 28 },

        { name = "Galak Wrangler", zone = "Thousand Needles",
          location = "Galak Hold", minLevel = 26, maxLevel = 28, chance = 25 },

        { name = "Boulderfist Ogre", zone = "Arathi Highlands",
          location = "Boulderfist Hall", minLevel = 30, maxLevel = 32, chance = 24,
          note = "top of the wool bracket; silk starts appearing here" },
    },
})

DB:RegisterItem({
    name = "Silk Cloth",
    id = 4306,
    category = "Cloth",
    aliases = { "silk" },
    sources = {
        { kind = "mob", name = "Bloodscalp / Skullsplitter trolls", zone = "Stranglethorn Vale", minLevel = 30, maxLevel = 40 },
        { kind = "mob", name = "Kolkar / Magram centaurs", zone = "Desolace", minLevel = 33, maxLevel = 38 },
        { kind = "mob", name = "Scarlet Crusade", zone = "Scarlet Monastery", minLevel = 32, maxLevel = 40, note = "instance -- the densest silk in the game" },
        { kind = "mob", name = "Dark Iron dwarves", zone = "Badlands", minLevel = 38, maxLevel = 42 },
    },
})

DB:RegisterItem({
    name = "Mageweave Cloth",
    id = 4338,
    category = "Cloth",
    aliases = { "mageweave" },
    sources = {
        { kind = "mob", name = "Woodpaw gnolls", zone = "Feralas", minLevel = 42, maxLevel = 47 },
        { kind = "mob", name = "Southsea pirates", zone = "Tanaris", minLevel = 42, maxLevel = 47, note = "Lost Rigger Cove" },
        { kind = "mob", name = "Sandfury trolls", zone = "Zul'Farrak", minLevel = 44, maxLevel = 47, note = "instance" },
        { kind = "mob", name = "Vilebranch trolls", zone = "The Hinterlands", minLevel = 45, maxLevel = 50 },
    },
})

DB:RegisterItem({
    name = "Runecloth",
    id = 14047,
    category = "Cloth",
    aliases = { "rune cloth" },
    note = "Every humanoid above about 50 drops it -- pick the zone you can kill fastest in.",
    sources = {
        { kind = "mob", name = "Deadwood / Winterfall furbolgs", zone = "Felwood", minLevel = 48, maxLevel = 55 },
        { kind = "mob", name = "Blackrock orcs", zone = "Burning Steppes", minLevel = 50, maxLevel = 58 },
        { kind = "mob", name = "Scarlet Crusade", zone = "Western Plaguelands", minLevel = 52, maxLevel = 58, note = "Hearthglen, if you can survive it" },
        { kind = "mob", name = "Scourge", zone = "Eastern Plaguelands", minLevel = 53, maxLevel = 60 },
        { kind = "mob", name = "Winterfall furbolgs", zone = "Winterspring", minLevel = 53, maxLevel = 60, note = "also drops Winterfall Firewater" },
        { kind = "mob", name = "Twilight's Hammer cultists", zone = "Silithus", minLevel = 55, maxLevel = 60 },
    },
})
