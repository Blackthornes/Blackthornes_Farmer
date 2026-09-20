--[[ Seed data: herbs. Levels are the zone's level band. --------------------]]

local BF = BlackthornesFarmer

BF:RegisterItem({
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

BF:RegisterItem({
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

BF:RegisterItem({
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

BF:RegisterItem({
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

BF:RegisterItem({
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

BF:RegisterItem({
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

BF:RegisterItem({
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

BF:RegisterItem({
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

BF:RegisterItem({
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

BF:RegisterItem({
	name = "Mountain Silversage",
	id = 13464,
	category = "Herbalism",
	sources = {
		{ kind = "herb", zone = "Un'Goro Crater", minLevel = 48, maxLevel = 55, requires = "Herbalism 280" },
		{ kind = "herb", zone = "Burning Steppes", minLevel = 50, maxLevel = 58, requires = "Herbalism 280" },
		{ kind = "herb", zone = "Winterspring", minLevel = 53, maxLevel = 60, requires = "Herbalism 280" },
		{ kind = "herb", zone = "Silithus", minLevel = 55, maxLevel = 60, requires = "Herbalism 280" },
	},
})

BF:RegisterItem({
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
