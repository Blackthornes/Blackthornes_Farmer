-- Blackthornes Farmer -- Data/Data_Cloth.lua
-- Seed data: cloth.
--
-- Cloth is the clearest "which mobs do I kill" case, so these entries name the
-- mob and use the mob's own level range.

local _, ns = ...

local DB = ns.DB

-- Linen and Silk follow the Wool Cloth template: named mob, level band, the
-- landmark it stands at, and a drop rate. Coordinates only where the landmark
-- is unambiguous.
DB:RegisterItem({
    name = "Linen Cloth",
    id = 2589,
    category = "Cloth",
    aliases = { "linen" },
    note = "Almost any humanoid under 20 drops it. Density matters more than the drop rate here.",
    sources = {
        --------------------------------------------------------------------
        -- Westfall: the densest linen in the game for either faction
        --------------------------------------------------------------------
        { name = "Defias Trapper", zone = "Westfall",
          location = "Moonbrook", coords = { 32.0, 70.0 },
          minLevel = 12, maxLevel = 13, chance = 38,
          note = "packed tight; the standard linen farm" },

        { name = "Defias Smuggler", zone = "Westfall",
          location = "Moonbrook", coords = { 32.0, 70.0 },
          minLevel = 14, maxLevel = 15, chance = 36 },

        { name = "Defias Looter", zone = "Westfall",
          location = "Jangolode Mine", minLevel = 10, maxLevel = 12, chance = 32 },

        { name = "Defias Overseer", zone = "Westfall",
          location = "The Deadmines", coords = { 42.0, 72.0 },
          minLevel = 16, maxLevel = 18, chance = 40,
          note = "instance -- no competition for spawns" },

        { name = "Defias Miner", zone = "Westfall",
          location = "The Deadmines", coords = { 42.0, 72.0 },
          minLevel = 15, maxLevel = 17, chance = 38, note = "instance" },

        --------------------------------------------------------------------
        -- Eastern Kingdoms outdoors
        --------------------------------------------------------------------
        { name = "Riverpaw Runt", zone = "Elwynn Forest",
          location = "Jerod's Landing and the Stone Cairn road",
          minLevel = 8, maxLevel = 10, chance = 26 },

        { name = "Riverpaw Gnoll", zone = "Elwynn Forest",
          location = "Jerod's Landing and the Stone Cairn road",
          minLevel = 10, maxLevel = 12, chance = 28 },

        { name = "Riverpaw Brute", zone = "Redridge Mountains",
          location = "Alther's Mill", minLevel = 17, maxLevel = 19, chance = 30 },

        { name = "Riverpaw Taskmaster", zone = "Redridge Mountains",
          location = "Alther's Mill", minLevel = 19, maxLevel = 20, chance = 30 },

        { name = "Pyrewood villagers", zone = "Silverpine Forest",
          location = "Pyrewood Village", minLevel = 10, maxLevel = 14, chance = 28 },

        { name = "Stonesplitter troggs", zone = "Loch Modan",
          location = "Stonesplitter Valley", minLevel = 13, maxLevel = 16, chance = 25 },

        --------------------------------------------------------------------
        -- Kalimdor
        --------------------------------------------------------------------
        { name = "Kolkar Drudge", zone = "The Barrens",
          location = "Kolkar Crag", minLevel = 11, maxLevel = 13, chance = 28 },

        { name = "Kolkar Outrunner", zone = "The Barrens",
          location = "Kolkar Crag", minLevel = 13, maxLevel = 15, chance = 30 },

        { name = "Razormane Quilboar", zone = "The Barrens",
          location = "Razormane Grounds", minLevel = 12, maxLevel = 15, chance = 28 },

        { name = "Razormane Scout", zone = "The Barrens",
          location = "The Sludge Fen road", minLevel = 14, maxLevel = 16, chance = 28 },

        { name = "Searing Blade cultists", zone = "Orgrimmar",
          location = "Ragefire Chasm", minLevel = 13, maxLevel = 16, chance = 35,
          note = "instance, right under the city" },

        { name = "Blackwood furbolgs", zone = "Darkshore",
          location = "Cliffspring Falls", minLevel = 14, maxLevel = 17, chance = 26 },
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
    note = "The thirties bracket. Trolls and the Scarlet Crusade are the two reliable answers.",
    sources = {
        --------------------------------------------------------------------
        -- Scarlet Monastery: the densest silk anywhere
        --------------------------------------------------------------------
        { name = "Scarlet Chaplain", zone = "Tirisfal Glades",
          location = "Scarlet Monastery, Library wing", coords = { 85.0, 32.0 },
          minLevel = 34, maxLevel = 36, chance = 40,
          note = "instance -- the standard silk run" },

        { name = "Scarlet Monk", zone = "Tirisfal Glades",
          location = "Scarlet Monastery, Library wing", coords = { 85.0, 32.0 },
          minLevel = 35, maxLevel = 37, chance = 38, note = "instance" },

        { name = "Scarlet Centurion", zone = "Tirisfal Glades",
          location = "Scarlet Monastery, Armory wing", coords = { 85.0, 32.0 },
          minLevel = 36, maxLevel = 38, chance = 38, note = "instance" },

        --------------------------------------------------------------------
        -- Stranglethorn trolls
        --------------------------------------------------------------------
        { name = "Bloodscalp Axe Thrower", zone = "Stranglethorn Vale",
          location = "Zul'Kunda", minLevel = 32, maxLevel = 34, chance = 30 },

        { name = "Bloodscalp Headhunter", zone = "Stranglethorn Vale",
          location = "Zul'Kunda", minLevel = 33, maxLevel = 35, chance = 30 },

        { name = "Skullsplitter Headhunter", zone = "Stranglethorn Vale",
          location = "Zul'Mamwe", minLevel = 37, maxLevel = 39, chance = 32 },

        { name = "Skullsplitter Witch Doctor", zone = "Stranglethorn Vale",
          location = "Zul'Mamwe", minLevel = 38, maxLevel = 40, chance = 32 },

        --------------------------------------------------------------------
        -- Elsewhere
        --------------------------------------------------------------------
        { name = "Witherbark Headhunter", zone = "Arathi Highlands",
          location = "Witherbark Village", minLevel = 32, maxLevel = 34, chance = 30 },

        { name = "Witherbark Shadow Hunter", zone = "Arathi Highlands",
          location = "Witherbark Village", minLevel = 34, maxLevel = 36, chance = 30 },

        { name = "Magram Scout", zone = "Desolace",
          location = "Magram Village", minLevel = 33, maxLevel = 35, chance = 28 },

        { name = "Kolkar Marauder", zone = "Desolace",
          location = "Kolkar Village", minLevel = 34, maxLevel = 36, chance = 28 },

        { name = "Dark Iron Tunneler", zone = "Badlands",
          location = "Angor Fortress", minLevel = 38, maxLevel = 40, chance = 30 },

        { name = "Dark Iron Shadowcaster", zone = "Badlands",
          location = "Angor Fortress", minLevel = 39, maxLevel = 41, chance = 30 },

        { name = "Galak Marauder", zone = "Thousand Needles",
          location = "Galak Hold", minLevel = 31, maxLevel = 33, chance = 26 },

        { name = "Syndicate Assassin", zone = "Alterac Mountains",
          location = "Ruins of Alterac", minLevel = 31, maxLevel = 33, chance = 28 },

        { name = "Death's Head quilboar", zone = "The Barrens",
          location = "Razorfen Kraul", minLevel = 30, maxLevel = 34, chance = 30,
          note = "instance" },

        { name = "Atal'ai priests", zone = "Swamp of Sorrows",
          location = "The Temple of Atal'Hakkar approach",
          minLevel = 37, maxLevel = 40, chance = 30 },
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
