-- Text that wraps never lies over what is under it (2026-10-28, a German
-- screenshot showed lines running into the rows below). German runs about
-- 30% longer, so a hint or note that fits one line in English takes two or
-- three: the window grows and what follows moves down, and English, which
-- fits, keeps its old size.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("wrapfit")

local ns = env.Load({ ui = true })
local Theme = ns.Theme
local L = ns.L

local function Label(text)
    local label = Theme.CreateLabel(UIParent, "small", "text")
    label:SetText(text)
    return label
end

-- Measuring.
suite.check("an empty label takes no room", Theme.WrappedHeight(Label(""), "small", 200) == 0)
local one = Theme.WrappedHeight(Label("Short"), "small", 200)
local three = Theme.WrappedHeight(Label(string.rep("x", 500)), "small", 200)
suite.check("one line is one line tall", one == Theme.sizes.small + 2)
suite.check("a long line wraps", three > one and three % (Theme.sizes.small + 2) == 0)
suite.check("a line break counts", Theme.WrappedHeight(Label("a\nb"), "small", 200) == 2 * one)

-- Name this mob: the box moves under a long question.
local NamePrompt = ns.NamePrompt
if NamePrompt then
    NamePrompt.ui = nil
    local frame = NamePrompt:Build()
    frame.ask:SetText("Short.")
    NamePrompt:Fit()
    local short = frame:GetHeight()
    frame.ask:SetText(string.rep("Lang ", 120))
    NamePrompt:Fit()
    suite.check("a long question makes the box window taller", frame:GetHeight() > short)
end

-- The plaque grows for a second line that wraps.
local Plaque = ns.Plaque
if Plaque then
    local grew = false
    local button = Plaque.Create(UIParent, { width = 160, onResize = function() grew = true end })
    button:SetLines("Cast", "Fishing 87 / 150")
    local base = button:GetHeight()
    button:SetLines("Cast", string.rep("Angeln ", 20))
    suite.check("a wrapped second line makes the plaque taller", button:GetHeight() > base)
    suite.check("and says so", grew)
    button:SetLines("Cast", "Fishing 87 / 150")
    suite.check("a short one puts it back", button:GetHeight() == base)
end

-- The windows whose hint is set when they are built.
local function Longer(key)
    rawset(L, key, string.rep("Lange Worte ", 40))
end

local importHint = "Click the box and press Ctrl+V to paste what another player sent you (the whole line, starting BFR1). Nothing is added until you press Apply."
if ns.UI and ns.UI.BuildImport then
    local frame = ns.UI:BuildImport()
    local before = frame:GetHeight()
    suite.check("English keeps the import window's size", before == 480, before)
    ns.UI.importFrame = nil
    Longer(importHint)
    local after = ns.UI:BuildImport():GetHeight()
    rawset(L, importHint, nil)
    suite.check("a long paste hint makes the import window taller", after > before)
end

local hiddenHint = "Mobs, nodes and items you hid are left out of the search, Rankings, Grind and the kills panel. Nothing you recorded is lost."
local HiddenUI = ns.HiddenUI
if HiddenUI then
    local before = HiddenUI:Build():GetHeight()
    suite.check("English keeps the hidden list's size", before == 380, before)
    HiddenUI.frame = nil
    Longer(hiddenHint)
    local after = HiddenUI:Build():GetHeight()
    rawset(L, hiddenHint, nil)
    suite.check("a long hint makes the hidden list taller", after > before)
end

-- The rank-up board grows under a long foot line.
local RankUpUI = ns.RankUpUI
if RankUpUI and RankUpUI.Build then
    RankUpUI:Build()
    RankUpUI.frame:SetWidth(360)
    RankUpUI:SetFoot("Up to #3!")
    local short = RankUpUI.frame:GetHeight()
    RankUpUI:SetFoot(string.rep("Hoch auf Platz ", 20))
    suite.check("a long foot makes the board taller", RankUpUI.frame:GetHeight() > short)
end

-- The way there card: a step's words that wrap are measured too.
local TravelCard = ns.TravelCard
if TravelCard and TravelCard.Tall then
    local short = TravelCard.Tall(Label("1. Fly to Ironforge"), "normal", 280)
    local long = TravelCard.Tall(Label(string.rep("Nimm das Boot nach Theramore ", 4)), "normal", 280)
    suite.check("a step that wraps stands taller", long > short and short == Theme.sizes.normal + 2)
end

suite.done()
