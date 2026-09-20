--[[--------------------------------------------------------------------------
  Seed data: leather. Skinning entries name the beasts worth skinning and use
  the beasts' own level range.
----------------------------------------------------------------------------]]

local BF = BlackthornesFarmer

BF:RegisterItem({
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

BF:RegisterItem({
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

BF:RegisterItem({
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

BF:RegisterItem({
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

BF:RegisterItem({
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

BF:RegisterItem({
	name = "Devilsaur Leather",
	id = 15417,
	category = "Leatherworking",
	note = "Only from devilsaurs -- expect the spawns to be contested.",
	sources = {
		{ kind = "skinning", name = "Devilsaur", zone = "Un'Goro Crater", minLevel = 55, maxLevel = 57, requires = "Skinning 300", note = "elite-damage hitters; bring a pet or a friend" },
		{ kind = "skinning", name = "Tyrant Devilsaur", zone = "Un'Goro Crater", minLevel = 57, maxLevel = 57, requires = "Skinning 300", note = "rare spawn" },
	},
})
