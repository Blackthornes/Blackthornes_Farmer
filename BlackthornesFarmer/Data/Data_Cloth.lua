--[[--------------------------------------------------------------------------
  Seed data: cloth.

  Cloth is the clearest "which mobs do I kill" case, so these entries name the
  mob and use the mob's own level range.
----------------------------------------------------------------------------]]

local BF = BlackthornesFarmer

BF:RegisterItem({
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

BF:RegisterItem({
	name = "Wool Cloth",
	id = 2592,
	category = "Cloth",
	aliases = { "wool" },
	sources = {
		{ kind = "mob", name = "Blackrock orcs", zone = "Redridge Mountains", minLevel = 20, maxLevel = 25, note = "Render's Camp and Stonewatch" },
		{ kind = "mob", name = "Nightbane worgen", zone = "Duskwood", minLevel = 22, maxLevel = 28 },
		{ kind = "mob", name = "Shadowfang Keep trash", zone = "Silverpine Forest", minLevel = 22, maxLevel = 28, note = "instance -- fast, repeatable clears" },
		{ kind = "mob", name = "Syndicate", zone = "Hillsbrad Foothills", minLevel = 25, maxLevel = 30, note = "Durnholde and the Southshore road camps" },
	},
})

BF:RegisterItem({
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

BF:RegisterItem({
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

BF:RegisterItem({
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
