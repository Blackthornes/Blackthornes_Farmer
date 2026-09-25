-- The fanfare when a mob's drop rates unlock (Trent, 2026-09-25).
--
-- What matters: it fires once, on the kill that makes 20, and not before,
-- after, or on a second window on the same corpse; the line starts
-- "Blackthornes Farmer:" and goes to your own chat window; a sound plays, a
-- plainer one if the first will not; a sound that errors costs the sound,
-- never the kill; and /farm celebrate off silences it.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("celebrate")

local ns = env.Load({ ui = true })
local Tracker = ns.Tracker

local played = {}
local refuse = {}
_G.PlaySound = function(sound, channel)
    played[#played + 1] = { sound = sound, channel = channel }
    return not refuse[sound]
end

local serial = 0
local function Loot(mob, items, guid)
    serial = serial + 1
    env.world.target = { name = mob, level = 8, dead = true, guid = guid or ("C-" .. serial) }
    env.world.loot = items or {}
    Tracker:OnLoot()
end

local function ChatSince(mark)
    return table.concat(env.chat, "\n", mark + 1)
end

local WOLF = "Mangy Wolf"
local FANG = { name = "Large Fang", id = 5637 }

suite.check("it is on by default", ns.db.trackerCelebrate == true)

local mark = #env.chat
for index = 1, 19 do Loot(WOLF, index % 4 == 0 and { FANG } or {}) end

suite.check("nothing before 20 kills", not ChatSince(mark):find("unlocked", 1, true)
    and #played == 0, ChatSince(mark))

Loot(WOLF, { FANG }, "C-twenty")
local said = ChatSince(mark)

suite.check("the 20th kill celebrates",
    said:find("Blackthornes Farmer:", 1, true) ~= nil
        and said:find("Drop rates unlocked for", 1, true) ~= nil, said)
suite.check("naming the mob", said:find(WOLF, 1, true) ~= nil, said)
suite.check("and its best drop with its rate",
    said:find("Best drop: Large Fang", 1, true) ~= nil and said:find("25%", 1, true) ~= nil,
    said)
suite.check("with no other addon prefix in front",
    said:find("Farmer|r |c", 1, true) == nil, said)
suite.check("a sound plays", #played == 1 and played[1].sound == 12891, #played)

-- A second window on the 20th corpse is not another kill.
mark = #env.chat
Loot(WOLF, {}, "C-twenty")
suite.check("skinning the 20th corpse does not celebrate again",
    not ChatSince(mark):find("unlocked", 1, true) and #played == 1)

Loot(WOLF, {})
suite.check("nor does the 21st kill", not ChatSince(mark):find("unlocked", 1, true)
    and #played == 1)

-- A client that will not play the first sound gets the plainer one.
refuse[12891] = true
local BOAR = "Mottled Boar"
for _ = 1, 20 do Loot(BOAR, {}) end
suite.check("a refused sound falls back to the level-up chime",
    played[#played].sound == 888, played[#played].sound)
suite.check("nothing has dropped says so",
    table.concat(env.chat, "\n"):find("Nothing has dropped yet.", 1, true) ~= nil)
refuse[12891] = nil

-- A sound that errors costs the sound, not the kill.
_G.PlaySound = function() error("no sound here") end
local ok, err = pcall(function()
    for _ = 1, 20 do Loot("Young Wolf", {}) end
end)
suite.check("a failing sound does not break the kill", ok, err)
suite.check("which still counts", Tracker:Store()["Young Wolf"].kills == 20)

-- Turned off, it is silent.
_G.PlaySound = function(sound) played[#played + 1] = { sound = sound } end
local before = #played
ns.HandleSlash("celebrate off")
suite.check("/farm celebrate off turns it off", ns.db.trackerCelebrate == false)
mark = #env.chat
for _ = 1, 20 do Loot("Kobold Vermin", {}) end
suite.check("and then nothing plays or prints",
    #played == before and not ChatSince(mark):find("unlocked", 1, true))

ns.HandleSlash("celebrate on")
suite.check("/farm celebrate on turns it back on", ns.db.trackerCelebrate == true)

suite.done()
