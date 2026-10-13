-- A corpse opened again counts once, whatever came in between.
--
-- The owner's report (2026-10-13): bags full, a corpse kept what could not be
-- taken; after looting another mob, opening that corpse again counted a kill
-- and its drops a second time. With area loot the leftovers of every corpse
-- nearby come round in the next window, so a corpse first seen in another's
-- window looked new when it was opened itself.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("reopen")
local ns = env.Load({ ui = true })
local Tracker, Harvest = ns.Tracker, ns.Harvest

-- Units by token: the target, the mouse and the interact key.
local units = {}
_G.UnitName = function(unit)
    if unit == "player" then return "Blackthornes" end
    local mob = units[unit]
    return mob and mob.name or nil
end
_G.UnitIsDead = function(unit)
    local mob = units[unit]
    return mob ~= nil and mob.dead ~= false
end
_G.UnitGUID = function(unit)
    if unit == "player" then return "Player-1-Blackthornes" end
    local mob = units[unit]
    if not mob then return nil end
    if mob.secretGuid then return env.Secret("guid") end
    return mob.guid
end
_G.UnitIsPlayer = function(unit) return unit == "player" end

local MOB = "Mottled Boar"
local function Boar(id) return { name = MOB, level = 6, guid = "Creature-0-1-2-3-113-" .. id } end
local A, B, C = Boar("A"), Boar("B"), Boar("C")

--- One loot window: `who` is what the units point at, `slots` the window as
--- { name, quantity, sources = { guid, count, ... } }.
local function Open(who, slots)
    units = who
    local loot, sources = {}, {}
    for i, slot in ipairs(slots) do
        loot[i] = { name = slot[1], quantity = slot[2], money = slot.money }
        sources[i] = slot.sources
    end
    env.world.loot = loot
    _G.GetLootSourceInfo = function(slot) return unpack(sources[slot] or {}) end
    Harvest.lootReading = {}
    Harvest:RecordCorpse()
    local kill = Tracker:OnLoot()
    Harvest.lootReading = nil
    return kill
end

local function Kills() return ns.db.tracker.mobs[MOB].kills end
local function Session(name) return Tracker.sessionLoot[name] or 0 end
local function Corpses()
    local total = 0
    for _, record in pairs(Harvest.records) do
        if record.mob == MOB then total = total + record.corpses end
    end
    return total
end
local function Dropped(name)
    local times = 0
    for _, record in pairs(Harvest.records) do
        local entry = record.mob == MOB and record.items[name]
        if entry then times = times + entry.corpses end
    end
    return times
end

local function Fresh()
    Tracker:Reset()
    Harvest:Reset()
end

--------------------------------------------------------------------------------
-- No area loot: open A, loot B, open A again
--------------------------------------------------------------------------------

Fresh()
Open({ target = A }, { { "Boar Meat", 1, sources = { A.guid, 1 } } })
Open({ target = B }, { { "Boar Meat", 1, sources = { B.guid, 1 } } })
suite.check("opened again with B still targeted, by the mouse",
    not Open({ target = B, mouseover = A }, { { "Boar Meat", 1, sources = { A.guid, 1 } } }))
suite.check("by the interact key",
    not Open({ softinteract = A }, { { "Boar Meat", 1, sources = { A.guid, 1 } } }))
suite.check("with nothing pointing at it",
    not Open({}, { { "Boar Meat", 1, sources = { A.guid, 1 } } }))
suite.check("two kills", Kills() == 2, Kills())
suite.check("two corpses", Corpses() == 2, Corpses())
suite.check("meat from two corpses", Dropped("Boar Meat") == 2, Dropped("Boar Meat"))
suite.check("two meat this session", Session("Boar Meat") == 2, Session("Boar Meat"))

--------------------------------------------------------------------------------
-- Area loot with full bags: A's window holds B's loot too, and both keep it
--------------------------------------------------------------------------------

Fresh()
-- A and B die together; opening A shows both. Bags full: nothing taken.
suite.check("A is a kill", Open({ target = A }, {
    { "Boar Meat", 1, sources = { A.guid, 1 } },
    { "Chunk of Boar Meat", 2, sources = { B.guid, 2 } },
}) == true)
suite.check("B's loot is the session's", Session("Chunk of Boar Meat") == 2, Session("Chunk of Boar Meat"))

-- C, killed later, opened with A's and B's leftovers in its window.
suite.check("C is a kill", Open({ target = C }, {
    { "Boar Meat", 2, sources = { C.guid, 1, A.guid, 1 } },
    { "Chunk of Boar Meat", 2, sources = { B.guid, 2 } },
    { "3 Copper", money = true, sources = { C.guid, 3 } },
}) == true)
suite.check("A's leftover meat is not looted twice", Session("Boar Meat") == 2, Session("Boar Meat"))
suite.check("nor B's", Session("Chunk of Boar Meat") == 2, Session("Chunk of Boar Meat"))

-- Then the first corpses, opened by hand, each with its own leftovers.
suite.check("B opened by itself is no new kill",
    not Open({ target = B }, { { "Chunk of Boar Meat", 2, sources = { B.guid, 2 } } }))
suite.check("A opened again is no new kill", not Open({ target = A }, {
    { "Boar Meat", 1, sources = { A.guid, 1 } },
}))
suite.check("still two kills", Kills() == 2, Kills())
suite.check("still two corpses", Corpses() == 2, Corpses())
suite.check("meat from two corpses", Dropped("Boar Meat") == 2, Dropped("Boar Meat"))
suite.check("B's chunks are no corpse's drop", Dropped("Chunk of Boar Meat") == 0,
    Dropped("Chunk of Boar Meat"))
suite.check("the session's loot is what dropped",
    Session("Boar Meat") == 2 and Session("Chunk of Boar Meat") == 2,
    Session("Boar Meat"), Session("Chunk of Boar Meat"))

--------------------------------------------------------------------------------
-- Nothing names the corpse: a new one in the window is the one opened
--------------------------------------------------------------------------------

Fresh()
Open({ target = A }, {
    { "Boar Meat", 1, sources = { A.guid, 1 } },
    { "Chunk of Boar Meat", 1, sources = { B.guid, 1 } },
})
-- Neither unit points at a corpse; the window holds B's leftovers, then C's.
units = { target = { name = MOB, level = 6, guid = C.guid, dead = false } }
Harvest:NoteUnit("target")
Open({}, {
    { "Chunk of Boar Meat", 1, sources = { B.guid, 1 } },
    { "Boar Meat", 1, sources = { C.guid, 1 } },
})
suite.check("C counts, not B", Kills() == 2 and Corpses() == 2, Kills(), Corpses())
suite.check("and B's chunk is not looted again", Session("Chunk of Boar Meat") == 1,
    Session("Chunk of Boar Meat"))

--------------------------------------------------------------------------------
-- A target whose guid will not be read
--------------------------------------------------------------------------------

Fresh()
local hidden = { name = MOB, level = 6, guid = A.guid, secretGuid = true }
Open({ target = hidden }, { { "Boar Meat", 1, sources = { A.guid, 1 } } })
Open({ target = B }, { { "Boar Meat", 1, sources = { B.guid, 1 } } })
Open({ target = hidden }, { { "Boar Meat", 1, sources = { A.guid, 1 } } })
suite.check("the window's one corpse gives it its guid", Kills() == 2 and Corpses() == 2,
    Kills(), Corpses())

suite.done()
