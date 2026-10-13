-- A mob's 100th kill (2026-10-13, a reward kept quiet): the banner, coins
-- raining down the panel, the rim burning for ten seconds and cooling, and
-- a crown after the mob's name from then on. The owner's typed test plays
-- it all without touching anything saved.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("champion")

local ns = env.Load({ ui = true })
local Tracker = ns.Tracker
local TUI = ns.TrackerUI
local FX = ns.TrackerFX

_G.PlaySoundFile = function() return true end
_G.PlaySound = function() return true end

TUI:OnEnable()
TUI.frame:Show()

local serial = 0
local function Loot(mob)
    serial = serial + 1
    env.world.target = { name = mob, level = 8, dead = true, guid = "CH-" .. serial }
    env.world.loot = {}
    Tracker:OnLoot()
end

local function BandOf(mob)
    for _, line in ipairs(TUI.shown or {}) do
        if line.style == "mob" and line.mob == mob then return line end
    end
end

local MOB = "Witchwing Slayer"
for _ = 1, 99 do Loot(MOB) end
TUI:Refresh()
suite.check("no crown at 99", not BandOf(MOB).crowned, BandOf(MOB).left)

Loot(MOB)
TUI:Refresh()
suite.check("the 100th kill crowns its name", BandOf(MOB).crowned
    and BandOf(MOB).left:find(TUI.CROWN, 1, true) ~= nil, BandOf(MOB).left)
suite.check("coins fall", FX.rain and FX.rain:IsShown())
suite.check("and the rim burns", FX.burn and FX.burn:IsShown())

-- Ten seconds on it still burns; a moment after the fade it is out.
for _ = 1, 95 do FX:Step(0.1) end
suite.check("the coins have landed", not FX.rain:IsShown())
suite.check("the rim still burns at 9.5 seconds", FX.burn:IsShown())
for _ = 1, 25 do FX:Step(0.1) end
suite.check("and has cooled away by 12", not FX.burn:IsShown())

Loot(MOB)
TUI:Refresh()
suite.check("the crown stays", BandOf(MOB).crowned)

--------------------------------------------------------------------------------
-- The test: the whole show, nothing changed.
--------------------------------------------------------------------------------

local function Snapshot()
    return ns.Serialize and ns.Serialize.Encode(ns.db) or nil
end

local OTHER = "Mangy Wolf"
for _ = 1, 3 do Loot(OTHER) end
TUI:Refresh()
FX:Forget()

local before = Snapshot()
local kills = Tracker:Store()[OTHER].kills
local mark = #env.chat
ns.HandleSlash("celebrate champion")
TUI:Refresh()

suite.check("the test shows the banner", FX.banner and FX.banner:IsShown())
suite.check("with the coins and the burn", FX.rain:IsShown() and FX.burn:IsShown())
suite.check("and a crown on the panel's mob", BandOf(OTHER) and BandOf(OTHER).crowned)
suite.check("it counts no kill", Tracker:Store()[OTHER].kills == kills)
suite.check("it leaves celebrate as it was", ns.db.trackerCelebrate == true)
suite.check("it saves nothing", before == nil or Snapshot() == before)
suite.check("the line says champion",
    table.concat(env.chat, "\n", mark + 1):find("champion", 1, true) ~= nil)

-- The test is never in the command's help.
local help = ns.commandHelp and ns.commandHelp.celebrate or ""
suite.check("its help keeps quiet", not tostring(help):lower():find("champion", 1, true))

--------------------------------------------------------------------------------
-- The 1000th: the screen taken over, Ragnaros, and legendary orange after.
--------------------------------------------------------------------------------

local voiced = {}
_G.PlaySoundFile = function(id) voiced[#voiced + 1] = id return true end
FX.saidAt = {}
Tracker:Store()[MOB].kills = 998
Loot(MOB)
TUI:Refresh()
suite.check("no takeover at 999", not (FX.stage and FX.stage:IsShown()))
suite.check("nor orange yet", not BandOf(MOB).bane)
Loot(MOB)
TUI:Refresh()
suite.check("the 1000th takes the screen", FX.stage and FX.stage:IsShown())
suite.check("naming them all", FX.stage.big:GetText() == "WITCHWING SLAYERS", FX.stage.big:GetText())
suite.check("with Ragnaros", voiced[#voiced] == FX.VOICE.bane, voiced[#voiced])
suite.check("and the name in legendary orange", BandOf(MOB).bane
    and BandOf(MOB).left:find("ffff8000", 1, true) ~= nil
    and BandOf(MOB).left:find(TUI.LEGENDARY_CROWN, 1, true) ~= nil, BandOf(MOB).left)
suite.check("the stage takes no mouse", not FX.stage:IsMouseEnabled())
for _ = 1, 60 do FX:StepStage(0.1) end
suite.check("and gives the screen back after a few seconds", not FX.stage:IsShown())
Loot(MOB)
TUI:Refresh()
suite.check("the 1001st does not take it again", not FX.stage:IsShown())
suite.check("the orange stays", BandOf(MOB).bane)

suite.check("plurals", FX.Plural("Witchwing Slayer") == "Witchwing Slayers"
    and FX.Plural("Defias Thief") == "Defias Thieves"
    and FX.Plural("Bloodscalp Harpy") == "Bloodscalp Harpies"
    and FX.Plural("Murloc Fisherman") == "Murloc Fishermen"
    and FX.Plural("Kobold Miner") == "Kobold Miners", FX.Plural("Defias Thief"))

-- The test word: the whole show, nothing changed.
before = Snapshot()
kills = Tracker:Store()[OTHER].kills
ns.HandleSlash("celebrate bane")
TUI:Refresh()
suite.check("the bane test takes the screen", FX.stage:IsShown())
suite.check("and colours the panel's first mob", TUI.banePreview ~= nil
    and BandOf(TUI.banePreview) and BandOf(TUI.banePreview).bane, TUI.banePreview)
suite.check("counting no kill", Tracker:Store()[OTHER].kills == kills)
suite.check("saving nothing", before == nil or Snapshot() == before)
suite.check("its help keeps quiet too", not tostring(help):lower():find("bane", 1, true))

suite.done()
