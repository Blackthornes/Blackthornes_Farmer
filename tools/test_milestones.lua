-- The kill milestones between the 100th and the 1000th (2026-10-15, kept
-- quiet like the others): baby talk and hearts at 200, a silver laurel at
-- 250, Slayer across the screen at 500 with the laurel turning gold, a
-- dark laugh and a red edge at a beast's 666th, and at 750 a live mob
-- trembles on its tooltip. The owner's typed tests play each one without
-- touching anything saved.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("milestones")

local ns = env.Load({ ui = true })
local Tracker = ns.Tracker
local TUI = ns.TrackerUI
local FX = ns.TrackerFX
local KillTooltip = ns.KillTooltip

local played = {}
_G.PlaySoundFile = function(id) played[#played + 1] = id return true end
_G.PlaySound = function() return true end

TUI:OnEnable()
TUI.frame:Show()

local serial = 0
local function Loot(mob)
    serial = serial + 1
    env.world.target = { name = mob, level = 8, dead = true, guid = "MS-" .. serial }
    env.world.loot = {}
    Tracker:OnLoot()
end

local function BandOf(mob)
    for _, line in ipairs(TUI.shown or {}) do
        if line.style == "mob" and line.mob == mob then return line end
    end
end

local function LastChat(mark)
    return table.concat(env.chat, "\n", mark + 1)
end

local function KillTo(mob, kills)
    Tracker:Store()[mob].kills = kills - 1
    FX:Forget()
    if FX.banner then FX.banner:Hide() end
    local mark = #env.chat
    local sounds = #played
    Loot(mob)
    TUI:Refresh()
    return LastChat(mark), played[#played], #played > sounds
end

local MOB = "Kobold Laborer"
Loot(MOB)

--------------------------------------------------------------------------------
-- Which kills count
--------------------------------------------------------------------------------

suite.check("200, 250, 500 and 750 are milestones", Tracker.IsMilestone(200, MOB)
    and Tracker.IsMilestone(250, MOB) and Tracker.IsMilestone(500, MOB)
    and Tracker.IsMilestone(750, MOB))
suite.check("others are not", not Tracker.IsMilestone(199, MOB)
    and not Tracker.IsMilestone(300, MOB) and not Tracker.IsMilestone(1000, MOB))
suite.check("666 is not, for a mob that is no beast", not Tracker.IsMilestone(666, MOB))
ns.db.creatureTypes = ns.db.creatureTypes or {}
ns.db.creatureTypes["Mangy Wolf"] = "Beast"
suite.check("666 is, for a beast", Tracker.IsMilestone(666, "Mangy Wolf"))
suite.check("a fanfare kill silences the rank-up chime", Tracker.HasFanfare(500, MOB)
    and Tracker.HasFanfare(100, MOB) and not Tracker.HasFanfare(501, MOB))

suite.check("baby talk", Tracker.BabyTalk("Kobolds") == "Kobowds"
    and Tracker.BabyTalk("Large Rat") == "Wawge Wat", Tracker.BabyTalk("Large Rat"))

--------------------------------------------------------------------------------
-- 200: UwU
--------------------------------------------------------------------------------

local chat, sound = KillTo(MOB, 200)
suite.check("the 200th talks baby talk", chat:find("Kobowd Wabowews", 1, true) ~= nil
    and chat:find("OwO", 1, true) ~= nil, chat)
suite.check("under an UwU banner", FX.banner and FX.banner:IsShown()
    and FX.banner.title:GetText() == "UwU", FX.banner and FX.banner.title:GetText())
suite.check("hearts float up", FX.hearts and FX.hearts:IsShown())
suite.check("with its own sound", sound == Tracker.SOUNDS.cute, sound)
for _ = 1, 40 do FX:Step(0.1) end
suite.check("and the hearts are gone after a few seconds", not FX.hearts:IsShown())
chat = KillTo(MOB, 201)
suite.check("then it's back to normal", not chat:find("OwO", 1, true))
suite.check("still a plain crown at 201", BandOf(MOB).left:find(TUI.CROWN, 1, true) ~= nil
    and not BandOf(MOB).left:find("Laurel", 1, true), BandOf(MOB).left)

--------------------------------------------------------------------------------
-- 250: the silver laurel
--------------------------------------------------------------------------------

chat, sound = KillTo(MOB, 250)
suite.check("the 250th knows your name", chat:find("They know your name now.", 1, true) ~= nil, chat)
suite.check("with a soft chime", sound == Tracker.SOUNDS.laurel, sound)
suite.check("the laurel wraps the crown", BandOf(MOB).left:find("Laurel", 1, true) ~= nil
    and BandOf(MOB).left:find(TUI.CROWN, 1, true) ~= nil, BandOf(MOB).left)
suite.check("in silver", BandOf(MOB).left:find(":205:215:230|t", 1, true) ~= nil, BandOf(MOB).left)
suite.check("the tooltip says so", KillTooltip.MarkLine(250) == "They know your name.")
suite.check("nothing below it", KillTooltip.MarkLine(249) == nil)

--------------------------------------------------------------------------------
-- 500: Slayer
--------------------------------------------------------------------------------

chat, sound = KillTo(MOB, 500)
suite.check("the 500th makes you a slayer", chat:find("slayer of its kind", 1, true) ~= nil, chat)
suite.check("with the war drum", sound == Tracker.SOUNDS.slayer, sound)
suite.check("the Slayer sweep crosses the screen", FX.stage and FX.stage:IsShown()
    and FX.stage.top:GetText() == "SLAYER OF" and FX.stage.big:GetText() == "KOBOLD LABORERS",
    FX.stage and FX.stage.big:GetText())
suite.check("sparks burst off the panel", FX.burst and FX.burst:IsShown())
suite.check("the laurel turns gold", BandOf(MOB).left:find(":255:205:70|t", 1, true) ~= nil, BandOf(MOB).left)
suite.check("the stage takes no mouse", not FX.stage:IsMouseEnabled())
for _ = 1, 50 do FX:StepStage(0.1) end
suite.check("and the sweep is gone after a few seconds", not FX.stage:IsShown())
suite.check("the tooltip says Slayer", KillTooltip.MarkLine(600) == "Slayer of its kind")

--------------------------------------------------------------------------------
-- 666: only for a beast
--------------------------------------------------------------------------------

chat = KillTo(MOB, 666)
suite.check("nothing at a humanoid's 666th", not chat:find("dark", 1, true)
    and not (FX.edge and FX.edge:IsShown()), chat)

local WOLF = "Mangy Wolf"
Loot(WOLF)
FX.saidAt = {}
chat, sound = KillTo(WOLF, 666)
suite.check("a beast's 666th: something dark", chat:find("Something dark is watching.", 1, true) ~= nil, chat)
suite.check("the dark laugh", sound == FX.VOICE.beast, sound)
suite.check("the screen's edge flickers red", FX.edge and FX.edge:IsShown())
suite.check("taking no mouse", not FX.edge:IsMouseEnabled())
for _ = 1, 15 do FX:StepEdge(0.1) end
suite.check("for only a moment", not FX.edge:IsShown())

--------------------------------------------------------------------------------
-- 750: they fear you
--------------------------------------------------------------------------------

chat, sound = KillTo(MOB, 750)
suite.check("the 750th: they tremble", chat:find("They tremble when they see you.", 1, true) ~= nil, chat)
suite.check("with the heartbeat", sound == Tracker.SOUNDS.fear, sound)
suite.check("the crown warms", BandOf(MOB).left:find(TUI.WARM_CROWN, 1, true) ~= nil, BandOf(MOB).left)
suite.check("a dead one does not tremble", not KillTooltip.Alive("target"))
env.world.target = { name = MOB, level = 8, dead = false, guid = "MS-alive" }
suite.check("a live one does", KillTooltip.Alive("target"))
suite.check("an unknown unit does not", not KillTooltip.Alive(nil))

--------------------------------------------------------------------------------
-- 1000 keeps the laurel, in legendary orange
--------------------------------------------------------------------------------

KillTo(MOB, 1000)
suite.check("at 1000 the laurel goes legendary", BandOf(MOB).bane
    and BandOf(MOB).left:find(":255:150:40|t", 1, true) ~= nil
    and BandOf(MOB).left:find(TUI.LEGENDARY_CROWN, 1, true) ~= nil, BandOf(MOB).left)
suite.check("the tooltip still says Bane", KillTooltip.MarkLine(1000) == "Bane of its kind")
for _ = 1, 60 do FX:StepStage(0.1) end

--------------------------------------------------------------------------------
-- Celebrate off: quiet
--------------------------------------------------------------------------------

ns.db.trackerCelebrate = false
chat = KillTo(MOB, 200)
suite.check("celebrate off keeps the 200th quiet", not chat:find("OwO", 1, true))
ns.db.trackerCelebrate = true

--------------------------------------------------------------------------------
-- The typed tests: the show, nothing changed, never in the help.
--------------------------------------------------------------------------------

local function Snapshot()
    return ns.Serialize and ns.Serialize.Encode(ns.db) or nil
end

local OTHER = "Young Wolf"
Loot(OTHER)
TUI:Refresh()
local help = tostring(ns.commandHelp and ns.commandHelp.celebrate or ""):lower()

for word, kills in pairs(Tracker.PREVIEWS) do
    FX:Forget()
    local before = Snapshot()
    local count = Tracker:Store()[OTHER].kills
    local mark = #env.chat
    ns.HandleSlash("celebrate " .. word)
    TUI:Refresh()
    suite.check(word .. ": says its line", #env.chat > mark, word)
    suite.check(word .. ": counts no kill", Tracker:Store()[OTHER].kills == count, word)
    suite.check(word .. ": saves nothing", before == nil or Snapshot() == before, word)
    suite.check(word .. ": keeps quiet in the help", not help:find(word, 1, true), word)
    if kills >= Tracker.LAUREL_KILLS and kills ~= Tracker.BEAST_KILLS then
        local band = BandOf(TUI.markPreview and TUI.markPreview.mob)
        suite.check(word .. ": marks the panel's first mob", band
            and band.left:find("Laurel", 1, true) ~= nil, band and band.left)
    end
    FX:StepStage(10)
    FX:StepEdge(10)
end

suite.done()
