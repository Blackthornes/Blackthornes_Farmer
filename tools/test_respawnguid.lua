-- A mob that comes back with the guid its last corpse had.
--
-- Forever 1.60.1 scrambles the spawn part of a creature's guid, so a mob
-- that respawns can carry the guid its last corpse had. That corpse was
-- counted, and every kill of the new mob after it was taken for a second
-- look at the old one: the count stopped on that mob (a player, 2026-11-22).
-- Once the guid is seen alive again it is a new mob and counts.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("respawnguid")

local ns = env.Load()
local Harvest, Tracker = ns.Harvest, ns.Tracker

local MOB = "Moonrage Whitescalp"
local GUID = "Creature-0-x9F3A-B7-C1D2-1769-Z0Q8W1"
local FANG = { name = "Large Fang", id = 5637 }

local function Kill(loot)
    env.world.target = { name = MOB, level = 12, dead = true, guid = GUID }
    env.world.loot = loot or { FANG }
    Harvest:RecordCorpse()
    return Tracker:OnLoot()
end

local function Respawn()
    env.world.target = { name = MOB, level = 12, dead = false, guid = GUID }
    Harvest:NoteUnit("target")
end

local function Kills()
    local mob = ns.db.tracker.mobs[MOB]
    return mob and mob.kills or 0
end

Respawn()
Kill()
suite.check("the first kill counts", Kills() == 1, Kills())

Kill()
suite.check("opening the same corpse again is no new kill", Kills() == 1, Kills())

Respawn()
Kill()
suite.check("the mob back alive with that guid counts again", Kills() == 2, Kills())

Respawn()
Kill({})
suite.check("and again, even with nothing on it", Kills() == 3, Kills())

-- A corpse only seen dead is never let go by this.
Tracker.corpses["Creature-0-a-b-c-1769-dead"] = {}
env.world.target = { name = MOB, level = 12, dead = true, guid = "Creature-0-a-b-c-1769-dead" }
Harvest:NoteUnit("target")
suite.check("a corpse seen dead stays counted", Tracker.corpses["Creature-0-a-b-c-1769-dead"] ~= nil)

suite.done()
