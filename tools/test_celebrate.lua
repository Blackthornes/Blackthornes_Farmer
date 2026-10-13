-- The fanfare when a mob's drop rates unlock (2026-09-25).
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

-- Anything the addon tries to say in public. It never should: Forever
-- blocks a chat send from a loot event ("ADDON BLOCKED" at a fishing spot's
-- 20th cast, 2026-10-13), and the owner had the emote taken out.
local sent = {}
_G.SendChatMessage = function(text, chatType)
    sent[#sent + 1] = { text = text, chatType = chatType }
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

suite.check("nothing is said in public", #sent == 0, #sent)

-- A second window on the 20th corpse is not another kill.
mark = #env.chat
Loot(WOLF, {}, "C-twenty")
suite.check("skinning the 20th corpse does not celebrate again",
    not ChatSince(mark):find("unlocked", 1, true) and #played == 1)

Loot(WOLF, {})
suite.check("nor does the 21st kill", not ChatSince(mark):find("unlocked", 1, true)
    and #played == 1)

-- Nor through the newer chat call.
local modern = {}
_G.C_ChatInfo = { SendChatMessage = function(text, chatType)
    modern[#modern + 1] = { text = text, chatType = chatType }
end }
for _ = 1, 20 do Loot("Riverpaw Gnoll", {}) end
suite.check("C_ChatInfo.SendChatMessage is never called", #modern == 0, #modern)
_G.C_ChatInfo = nil

-- A client that will not play the first sound gets the plainer one.
refuse[12891] = true
local BOAR = "Mottled Boar"
for _ = 1, 20 do Loot(BOAR, {}) end
suite.check("a refused sound falls back to the level-up chime",
    played[#played].sound == 888, played[#played].sound)
suite.check("nothing has dropped says so",
    table.concat(env.chat, "\n"):find("Nothing has dropped yet.", 1, true) ~= nil)
refuse[12891] = nil

-- A sound kit the client does not have answers nil rather than false, and
-- that must fall back the same way (the fallback was never reached before).
_G.PlaySound = function(sound)
    played[#played + 1] = { sound = sound, channel = "Master" }
    if sound == 12891 then return nil end
    return true
end
for _ = 1, 20 do Loot("Timber Wolf", {}) end
suite.check("a sound the client lacks falls back to the level-up chime",
    played[#played].sound == 888, played[#played].sound)
_G.PlaySound = function(sound, channel)
    played[#played + 1] = { sound = sound, channel = channel }
    return not refuse[sound]
end

-- A sound that errors costs the sound, not the kill.
_G.PlaySound = function() error("no sound here") end
local ok, err = pcall(function()
    for _ = 1, 20 do Loot("Young Wolf", {}) end
end)
suite.check("a failing sound does not break the kill", ok, err)
suite.check("which still counts", Tracker:Store()["Young Wolf"].kills == 20)

-- Turned off, it is silent.
_G.PlaySound = function(sound) played[#played + 1] = { sound = sound } return true end
local before, sentBefore = #played, #sent
ns.HandleSlash("celebrate off")
suite.check("/farm celebrate off turns it off", ns.db.trackerCelebrate == false)
mark = #env.chat
for _ = 1, 20 do Loot("Kobold Vermin", {}) end
suite.check("and then nothing plays or prints",
    #played == before and not ChatSince(mark):find("unlocked", 1, true))

suite.check("or is said in public", #sent == sentBefore)

ns.HandleSlash("celebrate on")
suite.check("/farm celebrate on turns it back on", ns.db.trackerCelebrate == true)

--------------------------------------------------------------------------------
-- Fishing: the same fanfare when a spot's catch rates unlock at 20 casts
-- (2026-09-25: "i didn't see/hear a fanfare or emote when i hit 20
-- fishing casts in one location").
--------------------------------------------------------------------------------

local Fishing = ns.Fishing
local SMALLFISH = "Raw Brilliant Smallfish"

local function Cast(zone, location, items)
    return Fishing:Record(zone, location, nil, items or { SMALLFISH }, nil, nil, nil)
end

before, sentBefore = #played, #sent
mark = #env.chat
for _ = 1, 19 do Cast("Elwynn Forest", "Crystal Lake") end
suite.check("no fanfare before 20 casts",
    #played == before and #sent == sentBefore and not ChatSince(mark):find("unlocked", 1, true))

Cast("Elwynn Forest", "Crystal Lake")
said = ChatSince(mark)
suite.check("the 20th cast at a spot celebrates",
    said:find("Blackthornes Farmer:", 1, true) ~= nil
        and said:find("Catch rates unlocked for", 1, true) ~= nil, said)
suite.check("naming the spot and where it is",
    said:find("open water", 1, true) ~= nil
        and said:find("in Crystal Lake, Elwynn Forest", 1, true) ~= nil, said)
suite.check("and its best catch", said:find("Best catch: " .. SMALLFISH, 1, true) ~= nil, said)
suite.check("a sound plays", #played == before + 1, #played - before)
-- The report: this cast raised "ADDON BLOCKED", since an emote was sent
-- from it. Now nothing is.
suite.check("nothing is said in public at a fishing spot either", #sent == sentBefore,
    #sent - sentBefore)

mark = #env.chat
Cast("Elwynn Forest", "Crystal Lake")
suite.check("the 21st cast does not celebrate again",
    #played == before + 1 and #sent == sentBefore
        and not ChatSince(mark):find("unlocked", 1, true))

-- Each spot unlocks on its own.
for _ = 1, 20 do Cast("Elwynn Forest", "Stone Cairn Lake") end
suite.check("another spot gets its own fanfare", #played == before + 2, #played - before)

-- The same switches as kills.
ns.HandleSlash("celebrate off")
before, mark = #played, #env.chat
for _ = 1, 20 do Cast("Westfall", "Moonbrook") end
suite.check("with celebrate off, nothing for fishing either",
    #played == before and not ChatSince(mark):find("unlocked", 1, true))
ns.HandleSlash("celebrate on")

suite.done()
