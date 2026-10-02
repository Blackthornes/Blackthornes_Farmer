-- The effects on a card that was folded a moment ago, and the unlock banner's
-- second line.
--
-- What matters: farming two mobs in turn, each kill opens a card that was
-- folded on the redraw before, and its bar still slides from where it was,
-- cheers the marks it passes and counts down the last few, and its loot
-- icons still flash; and the banner's "Name  |  20 kills" drops the count
-- rather than be cut off when the panel is narrow.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("cardfx")

local ns = env.Load({ ui = true })
local Tracker = ns.Tracker
local TUI = ns.TrackerUI
local FX = ns.TrackerFX

_G.PlaySoundFile = function() return true end
_G.C_Item = { GetItemInfo = function() return "item", nil, 1, 1, 1, "", "", 1, "", "", 0 end }

TUI:OnEnable()

local serial = 0
local function Loot(mob, items)
    serial = serial + 1
    env.world.target = { name = mob, level = 8, dead = true, guid = "Creature-0-1-2-3-400-" .. serial }
    env.world.loot = items or {}
    Tracker:OnLoot()
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

local function Bar(mob)
    for index, line in ipairs(TUI.shown or {}) do
        if line.key == "mob:" .. mob .. ":progress" then return line, TUI.lines[index] end
    end
end

local function IconSlot(name)
    for index, line in ipairs(TUI.shown or {}) do
        for at, icon in ipairs(line.icons or {}) do
            if icon.item == name then return TUI.lines[index].slots[at] end
        end
    end
end

local function Moving(frame)
    for _, effect in ipairs(FX.effects) do
        if effect.row == frame then return true end
    end
    return false
end

local WOOL = { name = "Wool Cloth", id = 2592 }

-- Two mobs in turn: each kill opens its card and folds the other.
for _ = 1, 4 do
    Loot("Gnoll", { WOOL }); Settle()
    Loot("Mangy Wolf", { WOOL }); Settle()
end

local folded
for _, line in ipairs(TUI.shown) do
    if line.key == "mob:Gnoll" then folded = line end
end
suite.check("the other card is folded", folded and folded.folded == true)
suite.check("but still counts its bar", folded and folded.hidden and folded.hidden[1]
    and folded.hidden[1].key == "mob:Gnoll:progress" and folded.hidden[1].count == 4)

-- The fifth Gnoll passes the first mark, on a card folded until now.
Loot("Gnoll", { WOOL })
local line, row = Bar("Gnoll")
local width = TUI:ProgressWidth(row)
suite.check("its bar starts where it was, not empty",
    math.abs(row.progress.fill:GetWidth() - width * 0.2) < 1, row.progress.fill:GetWidth())
FX:Step(0.5)
suite.check("it cheers the mark", Floats():find("25%!", 1, true) ~= nil, Floats())
suite.check("its wool icon flashes", Moving(IconSlot("Wool Cloth")))
Settle()
suite.check("and lands at a quarter", line.milestone == 1
    and math.abs(row.progress.fill:GetWidth() - width * 0.25) < 1, row.progress.fill:GetWidth())

-- The last few still count down.
for _ = 5, 17 do Loot("Mangy Wolf", { WOOL }); Settle() end
Loot("Gnoll", { WOOL }); Settle()
Loot("Mangy Wolf", { WOOL })
FX:Step(0.5)
suite.check("the eighteenth floats 2 more!", Floats():find("2 more!", 1, true) ~= nil, Floats())
Settle()

--------------------------------------------------------------------------------
-- The banner's second line
--------------------------------------------------------------------------------

local subject = "Defias Pillager  |  20 kills"
suite.check("it fits, it is whole", FX.FitSubject(subject, 400) == subject)
suite.check("too narrow, the name alone", FX.FitSubject(subject, 120) == "Defias Pillager",
    FX.FitSubject(subject, 120))
suite.check("a line with no count is left as it is", FX.FitSubject("Copper Vein", 10) == "Copper Vein")

-- The twentieth wolf, on a narrow banner.
Loot("Mangy Wolf", { WOOL }); Settle()
FX:Banner()._width = 130
Loot("Mangy Wolf", { WOOL })
suite.check("the twentieth wolf puts the banner up", FX.banner:IsShown())
suite.check("with the name alone", FX.banner.subject:GetText() == "Mangy Wolf", FX.banner.subject:GetText())
Settle()

FX.banner._width = nil
FX:Unlocked({ title = "DROP RATES UNLOCKED", subject = "Mangy Wolf  |  20 kills", key = "mob:Mangy Wolf" })
suite.check("a wide one has the count too", FX.banner.subject:GetText() == "Mangy Wolf  |  20 kills",
    FX.banner.subject:GetText())
Settle()

_G.PlaySoundFile = nil
_G.C_Item = nil

suite.done()
