-- The progress bar toward drop rates (2026-09-27: "can we make the
-- counter for how many more of a mob you have to kill to unlock drop rates
-- a progress bar like the goals?").
--
-- What matters: the bar sits under the mob with a goal's "N / 20" count, it
-- slides up rather than jumping, passing a quarter, half and three quarters
-- pulses it and floats a cheer, the last few float "N more!" in green, and it
-- goes when the rates unlock.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("killbar")

local ns = env.Load({ ui = true })
local Tracker = ns.Tracker
local TUI = ns.TrackerUI
local FX = ns.TrackerFX

_G.PlaySoundFile = function() return true end
_G.C_Item = { GetItemInfo = function() return "item", nil, 1, 1, 1, "", "", 1, "", "", 0 end }

TUI:OnEnable()

local serial = 0
local function Loot(mob)
    serial = serial + 1
    env.world.target = { name = mob, level = 8, dead = true, guid = "BAR-" .. serial }
    env.world.loot = {}
    Tracker:OnLoot()
end

local function Bar(mob)
    for index, line in ipairs(TUI.shown or {}) do
        if line.key == "mob:" .. mob .. ":progress" then return line, TUI.lines[index] end
    end
end

local function Settle()
    for _ = 1, 100 do FX:Step(0.1) end
end

local function Floats()
    local out = {}
    for _, label in ipairs(FX.floats or {}) do
        if FX.Floating(label) then out[#out + 1] = ns.Util.StripColor(label:GetText()) end
    end
    return table.concat(out, ",")
end

local MOB = "Kobold Vermin"

for _ = 1, 4 do Loot(MOB) end
Settle()

local line, row = Bar(MOB)
suite.check("the bar is there", line ~= nil)
suite.check("its count reads 4 / 20", line and ns.Util.StripColor(line.right) == "4 / 20",
    line and line.right)
suite.check("no mark passed yet", line and line.milestone == 0)

local width = TUI:ProgressWidth(row)
suite.check("it has room to be a bar", width >= 60, width)
suite.check("its fill is a fifth of it",
    math.abs(row.progress.fill:GetWidth() - width * 0.2) < 1, row.progress.fill:GetWidth())

-- The fifth kill passes the first mark.
Loot(MOB)
line, row = Bar(MOB)
suite.check("five kills pass the first mark", line.milestone == 1)
suite.check("the fill starts where it was", math.abs(row.progress.fill:GetWidth() - width * 0.2) < 1,
    row.progress.fill:GetWidth())
FX:Step(0.2)
local middle = row.progress.fill:GetWidth()
suite.check("and slides up", middle > width * 0.2 and middle < width * 0.25, middle)
suite.check("the mark pulses the bar", FX.FlashOf(row) ~= nil)
FX:Step(0.3)
suite.check("and floats 25%!", Floats():find("25%!", 1, true) ~= nil, Floats())
Settle()
suite.check("the fill lands at a quarter", math.abs(row.progress.fill:GetWidth() - width * 0.25) < 1,
    row.progress.fill:GetWidth())
suite.check("everything ends", #FX.effects == 0, #FX.effects)

for _ = 6, 10 do Loot(MOB) end
Settle()
FX.floats = FX.floats or {}

-- Up to the last stretch.
for _ = 11, 17 do Loot(MOB) end
Settle()
line = Bar(MOB)
suite.check("17 is not the last stretch", not line.final)

Loot(MOB)
line, row = Bar(MOB)
suite.check("18 of 20 is", line.final == true)
FX:Step(0.5)
suite.check("and floats 2 more!", Floats():find("2 more!", 1, true) ~= nil, Floats())
Settle()

-- Subtle: the slide, no floats.
ns.db.trackerEffects = "subtle"
Loot(MOB)
FX:Step(0.5)
suite.check("subtle floats nothing", Floats() == "", Floats())
Settle()
ns.db.trackerEffects = nil

Loot(MOB)
suite.check("at 20 the bar goes", Bar(MOB) == nil)
Settle()

-- Off: the bar is drawn, nothing moves.
ns.db.trackerEffects = "off"
Loot("Tunnel Rat")
Loot("Tunnel Rat")
suite.check("off starts nothing", #FX.effects == 0, #FX.effects)
line, row = Bar("Tunnel Rat")
suite.check("but the bar is drawn", line ~= nil and row.progress.fill:IsShown())

suite.done()
