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

suite.done()
