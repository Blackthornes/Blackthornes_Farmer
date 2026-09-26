-- The second round of panel effects (Trent, 2026-09-26): kill streaks, the
-- rare-drop pulse, and the banner when a mob's drop rates unlock.
--
-- What matters: a streak runs while kills come within a minute of each other,
-- shows from its third kill with the session's best beside it, runs out on
-- its own and starts again; a green drop pulses on its line and floats as
-- "Nice! ..."; the 20th kill drops the banner and pulses the mob's band; and
-- Off shows none of it, though the streak line itself stays.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("streak")

local ns = env.Load({ ui = true })
local Tracker = ns.Tracker
local TUI = ns.TrackerUI
local FX = ns.TrackerFX

local clock = 1000
_G.GetTime = function() return clock end
_G.PlaySoundFile = function() return true end

TUI:OnEnable()

local serial = 0
local function Loot(mob, items)
    serial = serial + 1
    env.world.target = { name = mob, level = 8, dead = true, guid = "S-" .. serial }
    env.world.loot = items or {}
    Tracker:OnLoot()
end

local function Shown(key)
    for index, line in ipairs(TUI.shown or {}) do
        if line.key == key then return line, TUI.lines[index] end
    end
end

local function Settle()
    for _ = 1, 100 do FX:Step(0.1) end
end

local FANG = { name = "Large Fang", id = 5637 }

--------------------------------------------------------------------------------
-- Streaks
--------------------------------------------------------------------------------

Loot("Mangy Wolf", { FANG })
suite.check("one kill is a streak of one", Tracker:Streak() == 1, Tracker:Streak())
clock = clock + 30
Loot("Mangy Wolf", { FANG })
suite.check("two within a minute", Tracker:Streak() == 2, Tracker:Streak())
suite.check("not shown yet", Shown("streak") == nil)

clock = clock + 55
Loot("Mangy Wolf", { FANG })
local line = Shown("streak")
suite.check("shown from the third", line ~= nil)
suite.check("as x3", line and line.right == "x3", line and line.right)
suite.check("no best to beat yet", line and line.left == "Kill streak", line and line.left)

clock = clock + 61
suite.check("a minute and more runs it out", Tracker:Streak() == 0, Tracker:Streak())
TUI:Refresh()
suite.check("and the line goes", Shown("streak") == nil)

Loot("Mangy Wolf", { FANG })
suite.check("the next kill starts again", Tracker.streak == 1, Tracker.streak)
suite.check("the best is kept", Tracker.bestStreak == 3, Tracker.bestStreak)

for _ = 1, 3 do
    clock = clock + 10
    Loot("Mangy Wolf", { FANG })
end
line = Shown("streak")
suite.check("a new run shows", line and line.right == "x4", line and line.right)
suite.check("new best, nothing to beat", line and line.left == "Kill streak", line and line.left)

Settle()
clock = clock + 10
Loot("Mangy Wolf", { FANG })
local _, row = Shown("streak")
local cheered = false
for _, label in ipairs(FX.floats or {}) do
    if FX.Floating(label) and ns.Util.StripColor(label:GetText()) == "Streak x5!" then cheered = true end
end
suite.check("every fifth kill cheers", cheered)
suite.check("and its line glows", row and FX.FlashOf(row) ~= nil)

Settle()
clock = clock + 100
Loot("Mangy Wolf", { FANG })
for _ = 1, 2 do
    clock = clock + 5
    Loot("Mangy Wolf", { FANG })
end
line = Shown("streak")
suite.check("a shorter run shows the best", line and line.left == "Kill streak  (best 5)", line and line.left)

--------------------------------------------------------------------------------
-- Rare drops pulse
--------------------------------------------------------------------------------

ns.db.tracker.looks["Scouting Cloak"] = { color = "ff1eff00" }
local CLOAK = { name = "Scouting Cloak", id = 4690 }

Settle()
clock = clock + 5
Loot("Mangy Wolf", { CLOAK })
local _, cloakRow = Shown("loot:Scouting Cloak")
suite.check("the cloak's line pulses", cloakRow and FX.FlashOf(cloakRow) ~= nil)

local pulsing = false
for _, effect in ipairs(FX.effects) do
    if effect.row == cloakRow and effect.duration > 2 then pulsing = true end
end
suite.check("longer than a plain glow", pulsing)

local nice = false
for _, label in ipairs(FX.floats or {}) do
    if FX.Floating(label) and ns.Util.StripColor(label:GetText()) == "Nice! +1 Scouting Cloak" then
        nice = true
    end
end
suite.check("and floats with a cheer", nice)

--------------------------------------------------------------------------------
-- The unlock banner
--------------------------------------------------------------------------------

Settle()
local wolf = Tracker:Store()["Mangy Wolf"].kills
for _ = wolf + 1, Tracker.MIN_KILLS - 1 do
    clock = clock + 5
    Loot("Mangy Wolf", { FANG })
end
Settle()
suite.check("no banner before the 20th", not (FX.banner and FX.banner:IsShown()))

clock = clock + 5
Loot("Mangy Wolf", { FANG })
suite.check("20 kills", Tracker:Store()["Mangy Wolf"].kills == Tracker.MIN_KILLS)
suite.check("the banner drops", FX.banner and FX.banner:IsShown())
suite.check("says so", FX.banner and FX.banner.title:GetText() == "DROP RATES UNLOCKED",
    FX.banner and FX.banner.title:GetText())
suite.check("and for what", FX.banner and FX.banner.subject:GetText() == "Mangy Wolf  |  20 kills",
    FX.banner and FX.banner.subject:GetText())

local _, bandRow = Shown("mob:Mangy Wolf")
local gold = false
for _, effect in ipairs(FX.effects) do
    if effect.row == bandRow and effect.duration > 2 then gold = true end
end
suite.check("the band pulses gold", gold)

Settle()
suite.check("the banner goes", not FX.banner:IsShown())

-- Off: no banner, though the milestone still reaches chat.
ns.HandleSlash("effects off")
FX:Unlocked({ title = "DROP RATES UNLOCKED", subject = "x", key = "mob:Mangy Wolf" })
suite.check("off: no banner", not FX.banner:IsShown())
ns.HandleSlash("effects full")

-- A banner that fails never stops the fanfare.
local unlocked = FX.Unlocked
FX.Unlocked = function() error("boom") end
local ok = pcall(Tracker.Fanfare, Tracker, "line", nil, { title = "T" })
suite.check("a broken banner is dropped", ok)
FX.Unlocked = unlocked

_G.GetTime = nil
_G.PlaySoundFile = nil

suite.done()
