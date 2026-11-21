-- Panel Style (UI/PanelStyle.lua, the owner said build it 2026-11-21):
-- Kills & Loot and Goals boxed (the default) or like the game's quest list.
--
-- What matters: boxed unless picked, so nothing changes for anyone who
-- never picks it; Like Quest List drops the glass, rim, rule and card
-- edges, gives every word a shadow, turns the heading the game's yellow
-- with a line under it and shows the buttons only under the mouse; a panel
-- never dragged lines up under the quest list (the goals panel closing up
-- when Kills & Loot hides), a dragged one keeps its spot, and the quest
-- list is only read; Boxed puts every piece back.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("panelstyle")

local ns = env.Load({ ui = true })
local Style = ns.PanelStyle
local TUI = ns.TrackerUI
local GUI = ns.GoalsUI

TUI:OnEnable()
TUI:Build()
GUI:Build()

local function Settle() ns.Motion:FinishAll() end
local function Near(a, b) return type(a) == "number" and math.abs(a - b) < 0.001 end

suite.check("boxed unless picked", not Style:IsQuest() and Style:Index() == 1
    and ns.db.panelStyle == nil)
suite.check("both panels are handed over", Style.panels.tracker ~= nil and Style.panels.goals ~= nil)

-- The rim shows, as on screen.
local rim = TUI.frame.borderTextures[1]
rim._shown = true
TUI.rule._shown = true
local goalsRim = GUI.frame.borderTextures[1]
goalsRim._shown = true
local trackerRest = TUI.frame.haloRest

-- Every piece of glass remembers the alpha it was given.
for _, part in ipairs(TUI.glassParts) do
    part.texture.SetAlpha = function(self, value) self._alpha = value end
end

-- The game's quest list, at the right of the screen.
local list = env.Stub({ _right = 1900, _top = 1000, _shown = true })
list.GetBottom = function() return 700 end
list.IsVisible = function() return true end
_G.ObjectiveTrackerFrame = list
-- Nothing of the list may be changed.
local touched = false
for _, name in ipairs({ "SetPoint", "ClearAllPoints", "Hide", "Show", "SetAlpha", "HookScript", "SetScript" }) do
    list[name] = function() touched = true end
end

suite.check("picking a style by its index saves it", Style:Set(2) and ns.db.panelStyle == "quest")
Settle()

suite.check("no glass at all", TUI.glassBare == true)
local bare = true
for _, part in ipairs(TUI.glassParts) do
    if not Near(part.texture._alpha, 0) then bare = false end
end
suite.check("every piece of glass is clear, the open card's too", bare)
suite.check("the mouse brings no glass back", TUI.seeThroughWatch:GetScript("OnUpdate") == nil)
suite.check("the rim and the rule go", not rim:IsShown() and not TUI.rule:IsShown())
suite.check("the goals panel's rim goes", not goalsRim:IsShown())
suite.check("the glow round the edge rests at nothing", TUI.frame.haloRest == false)
local y = Style.YELLOW
suite.check("the heading is the game's yellow",
    TUI.title._color and Near(TUI.title._color[1], y[1]) and Near(TUI.title._color[2], y[2]))
suite.check("a thin line sits under each heading",
    Style.panels.tracker.line:IsShown() and Style.panels.goals.line:IsShown())
suite.check("the buttons wait for the mouse", TUI.gems.close:GetAlpha() == 0
    and TUI.toolbar.sort:GetAlpha() == 0 and GUI.gems.close:GetAlpha() == 0)

-- Under the mouse the buttons show.
TUI.frame.IsMouseOver = function() return true end
local watch = Style.panels.tracker.watch
watch:GetScript("OnUpdate")(watch, 1)
suite.check("under the mouse the buttons show", TUI.gems.close:GetAlpha() == 1
    and TUI.toolbar.clear:GetAlpha() == 1)
TUI.frame.IsMouseOver = function() return false end
watch:GetScript("OnUpdate")(watch, 1)
suite.check("and go again when it leaves", TUI.gems.close:GetAlpha() == 0)

-- A card drawn now has no edges round it.
local first, last = TUI:CreateLine(TUI.frame, 1), TUI:CreateLine(TUI.frame, 2)
TUI:DrawCard(1, first, last, true)
local card = TUI.cards[1]
suite.check("a card has no edges", not card.edges[1]:IsShown())

-- Never dragged, Kills & Loot lines up under the quest list.
ns.db.trackerPoint, ns.db.trackerRelativePoint = "TOPLEFT", nil
ns.db.trackerX, ns.db.trackerY = 8, -190
TUI:Place()
local p = TUI.frame._point
suite.check("never dragged, it lines up under the quest list",
    p and p[1] == "TOPRIGHT" and p[3] == "BOTTOMLEFT" and p[4] == 1900
    and p[5] == 700 - Style.GAP, p and table.concat({ tostring(p[1]), tostring(p[4]), tostring(p[5]) }, " "))

-- The quest list showing nothing: its top, where its first line would be.
list.IsVisible = function() return false end
TUI:Place()
p = TUI.frame._point
suite.check("an empty quest list puts it at the list's top", p and p[5] == 1000 - Style.GAP)
list.IsVisible = function() return true end

-- The lowest line showing inside the list counts, not the list's frame.
local line1 = env.Stub({ _height = 20 })
line1.IsVisible = function() return true end
line1.GetBottom = function() return 900 end
local hidden = env.Stub({ _height = 20 })
hidden.IsVisible = function() return false end
hidden.GetBottom = function() return 100 end
list.GetChildren = function() return line1, hidden end
list.GetBottom = function() return 200 end
TUI:Place()
p = TUI.frame._point
suite.check("it follows the last line the list shows", p and p[5] == 900 - Style.GAP, p and p[5])
list.GetChildren = function() end
list.GetBottom = function() return 700 end

-- Dragged, it keeps its spot.
ns.db.trackerPoint, ns.db.trackerRelativePoint = "TOPLEFT", "BOTTOMLEFT"
ns.db.trackerX, ns.db.trackerY = 300, 800
TUI:Place()
p = TUI.frame._point
suite.check("dragged, it keeps its spot", p and p[1] == "TOPLEFT" and p[4] == 300 and p[5] == 800)
ns.db.trackerPoint, ns.db.trackerRelativePoint = "TOPLEFT", nil
ns.db.trackerX, ns.db.trackerY = 8, -190

-- Kills & Loot hidden: the goals panel closes up under the quest list.
TUI.frame:Hide()
ns.db.goalsX, ns.db.goalsY = nil, nil
GUI:Place()
p = GUI.frame._point
suite.check("with Kills & Loot hidden, the goals panel goes under the quest list",
    p and p[1] == "TOPRIGHT" and p[4] == 1900)
-- Dragged, the goals panel keeps its spot.
ns.db.goalsX, ns.db.goalsY = 400, 500
GUI.frame._point = nil
GUI:Place()
suite.check("a dragged goals panel stays put", rawget(GUI.frame, "_point") == nil)
ns.db.goalsX, ns.db.goalsY = nil, nil

-- A list that raises when read (a secret value) gives no spot.
list.GetRight = function() error("secret") end
suite.check("a list that will not say gives no spot", Style.QuestListEdge() == nil)
GUI:Place()
p = GUI.frame._point
suite.check("then the goals panel takes its own first spot", p and p[1] == "TOPLEFT" and p[4] == 8)
list.GetRight = function() return 1900 end

suite.check("the quest list is only read", not touched)

-- The follower moves the panels only when the list moved.
local follower = Style.follower
suite.check("the follower runs while it is on", follower:GetScript("OnUpdate") ~= nil)
local placed = 0
local realPlace = Style.PlacePanels
Style.PlacePanels = function() placed = placed + 1 end
Style.lastRight, Style.lastBottom = 1900, 700
follower:GetScript("OnUpdate")(follower, 2)
suite.check("nothing moves while the list stays", placed == 0)
list.GetBottom = function() return 640 end
TUI.frame:Hide()
GUI.frame:Hide()
follower:GetScript("OnUpdate")(follower, 2)
suite.check("with both panels away, nothing is read or moved", placed == 0)
TUI.frame:Show()
follower:GetScript("OnUpdate")(follower, 2)
suite.check("a list that grew moves them once", placed == 1)
Style.PlacePanels = realPlace

-- Transparent picked while it is on brings no glass back.
TUI:SetSeeThroughLevel(1)
TUI:SetSeeThrough(true)
Settle()
suite.check("Transparent leaves it bare", TUI.glassBare == true
    and Near(TUI.glassParts[1].texture._alpha, 0))
TUI:SetSeeThrough(false)
ns.SeeThrough:Set("goals", 2)
suite.check("so does the goals panel's", ns.SeeThrough.states.goals.bare == true
    and ns.SeeThrough.states.goals.watch:GetScript("OnUpdate") == nil)
ns.SeeThrough:Set("goals", 0)

-- Boxed puts every piece back.
TUI.frame:Show()
suite.check("Boxed is saved", Style:Set("boxed") and ns.db.panelStyle == "boxed")
Settle()
suite.check("the glass is back", TUI.glassBare == nil and Near(TUI.glassParts[1].texture._alpha, 1))
suite.check("the rim and rule come back", rim:IsShown() and TUI.rule:IsShown() and goalsRim:IsShown())
suite.check("the glow round the edge rests again", TUI.frame.haloRest == trackerRest)
suite.check("the line goes", not Style.panels.tracker.line:IsShown())
suite.check("the buttons show again", TUI.gems.close:GetAlpha() == 1 and GUI.gems.close:GetAlpha() == 1)
suite.check("the follower sleeps", follower:GetScript("OnUpdate") == nil)
TUI:DrawCard(1, first, last, true)
suite.check("cards have their edges again", card.edges[1]:IsShown())
TUI:Place()
p = TUI.frame._point
suite.check("boxed, it goes back to its first spot", p and p[1] == "TOPLEFT" and p[4] == 8)

suite.check("a word it does not know changes nothing", not Style:Set("round") and ns.db.panelStyle == "boxed")

suite.done()
