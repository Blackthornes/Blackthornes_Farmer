-- The run graph on Kills & Loot (UI/RunGraph.lua) and the Run Recap that
-- stays (UI/Recap.lua), the owner said build them 2026-11-26.
--
-- What matters: the graph is on unless unticked, shows only once the panel
-- knows its gold an hour, and hides in Slim Bar, Like Quest List and when
-- unticked; it takes a point at most once a minute, from the panel's own
-- numbers, and starts again after a Clear; your usual here is the play in
-- this zone before this session; the lines move only when a point is
-- added. The Run Recap stays until closed unless unticked, and then fades
-- as before.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("rungraph")

local ns = env.Load({ ui = true })
local Graph = ns.RunGraph
local TUI = ns.TrackerUI

ns.Harvest:OnEnable()
ns.Tracker:OnEnable()
TUI:OnEnable()

local seconds, copper = nil, 0
Graph.Read = function()
    if not seconds then return nil end
    return seconds, copper
end
local zone = "Duskwood"
_G.GetRealZoneText = function() return zone end
local perHour
local realPerHour = TUI.PerHour
TUI.PerHour = function() return perHour end

suite.check("on unless unticked", Graph.On() and ns.db.runGraph == nil)

TUI:Refresh()
suite.check("no gold an hour yet, no graph", not Graph:Shows(TUI) and TUI:Top() == TUI.TOP)
suite.check("before a clock, no points", Graph.points == nil)

--------------------------------------------------------------------------------
-- Points
--------------------------------------------------------------------------------

seconds, copper = 10, 100
TUI:Refresh()
suite.check("the first redraw starts the run", Graph.points and #Graph.points == 1 and Graph.points[1].s == 0)
seconds, copper = 40, 200
TUI:Refresh()
suite.check("under a minute in, no new point", #Graph.points == 1, #Graph.points)
for minute = 1, 12 do
    seconds, copper = minute * 60 + 5, minute * 1000
    TUI:Refresh()
end
suite.check("then one a minute", #Graph.points == 13, #Graph.points)
local series = Graph:Series()
suite.check("the line has a rate for each point", series and #series == 12)
-- 1000 copper a minute is 60000 an hour.
local last = series[#series].rate
suite.check("each read over the last ten minutes", math.abs(last - 60000) < 2000, last)

local version = Graph.version
TUI:Refresh()
suite.check("a redraw with nothing new leaves the line", Graph.version == version)

--------------------------------------------------------------------------------
-- The strip on the panel
--------------------------------------------------------------------------------

perHour = 60000
TUI:Refresh()
suite.check("with gold an hour, the graph shows", Graph:Shows(TUI) and Graph.strip:IsShown())
suite.check("the column moves down for it", TUI:Top() == TUI.TOP + Graph.HEIGHT)
suite.check("gold an hour is the big number",
    ns.Util.StripColor(Graph.strip.big:GetText()) == "6g an hour", Graph.strip.big:GetText())
suite.check("the length of the run under it", Graph.strip.length:GetText() == "12 min",
    Graph.strip.length:GetText())
suite.check("no usual here yet, no line for it", Graph.strip.usual:GetText() == ""
    and Graph.strip.versus:GetText() == "")

local drawn = Graph.drawn
TUI:Refresh()
suite.check("the lines are not drawn again for nothing", Graph.drawn == drawn)

-- Folded, Slim Bar and Like Quest List hide it.
ns.SlimBar:Set(2)
suite.check("hidden in Slim Bar", not Graph:Shows(TUI) and not Graph.strip:IsShown())
TUI.frame.IsMouseOver = function() return true end
ns.SlimBar:Look(ns.SlimBar.LOOK)
suite.check("even with the list open", not Graph.strip:IsShown() and TUI:Top() == TUI.TOP)
TUI.frame.IsMouseOver = function() return false end
ns.SlimBar:Set(1)
suite.check("back with Full Panel", Graph.strip:IsShown())
ns.PanelStyle:Set("quest")
suite.check("hidden in Like Quest List", not Graph.strip:IsShown())
ns.PanelStyle:Set("boxed")
Graph:SetOn(false)
suite.check("unticked, it goes", ns.db.runGraph == false and not Graph.strip:IsShown()
    and TUI:Top() == TUI.TOP)
Graph:SetOn(true)
suite.check("ticked, it comes back", ns.db.runGraph == nil and Graph.strip:IsShown())

--------------------------------------------------------------------------------
-- Your usual here
--------------------------------------------------------------------------------

local pace = ns.db.zonePace and ns.db.zonePace.Duskwood
suite.check("each minute adds to the zone's pace", pace and pace.s >= 700 and pace.c >= 11000,
    pace and (pace.s .. " " .. pace.c))
suite.check("this session alone is no usual", Graph.UsualIn("Duskwood") == nil)

-- An hour played here before, at 3g an hour.
pace.s = pace.s + 3600
pace.c = pace.c + 30000
Graph.drawn = nil
TUI:Refresh()
suite.check("with play here before, the usual shows", Graph.strip.usual:GetText() == "- - your usual here")
suite.check("and how far over it you are", Graph.strip.versus:GetText() == "100% over your usual here",
    Graph.strip.versus:GetText())
local over, color = Graph.VersusText(15000, 30000)
suite.check("and under", over == "50% under your usual here" and color == "muted")
zone = "Elwynn Forest"
suite.check("another zone has its own", Graph.UsualIn(zone) == nil)
zone = "Duskwood"

--------------------------------------------------------------------------------
-- A Clear starts again
--------------------------------------------------------------------------------

seconds, copper = 20, 0
TUI:Refresh()
suite.check("a Clear starts a new run", #Graph.points == 1)
seconds = nil
TUI:Refresh()
suite.check("no clock, no run", Graph.points == nil)
TUI.PerHour = realPerHour

--------------------------------------------------------------------------------
-- The Run Recap
--------------------------------------------------------------------------------

local Recap = ns.RecapUI
local summary = { kills = 102, copper = 142000, seconds = 2520, rate = 201700, zone = "Duskwood",
    items = { { name = "Wizard's Belt", count = 1, worth = 18500 },
              { name = "Silk Cloth", count = 46, worth = 55200 } },
    rest = 68300 }
suite.check("the Run Recap stays unless unticked", Recap.Stays() and ns.db.recapStays == nil)
Recap:Show(summary, "YOUR RUN")
suite.check("it says how long and where",
    ns.Util.StripColor(Recap.sub:GetText()):find("42m in Duskwood", 1, true) ~= nil, Recap.sub:GetText())
suite.check("what you made, an hour and kills",
    Recap.big[1].caption:GetText() == "made" and Recap.big[2].caption:GetText() == "an hour"
    and Recap.big[3].value:GetText() == "102")
suite.check("the drops, with how many",
    ns.Util.StripColor(Recap.lines[2].left:GetText()) == "Silk Cloth x46", Recap.lines[2].left:GetText())
suite.check("then the coin and everything else", Recap.lines[3].left:GetText() == "Coin and everything else")
suite.check("no countdown", Recap.holding == nil and not Recap.timer:IsShown())
Recap:Tick(120)
suite.check("it stays", Recap:IsShown())
Recap.closeButton:Click()
suite.check("Close puts it away", not Recap:IsShown())

Recap:SetStays(false)
Recap:Show(summary, "YOUR RUN")
suite.check("unticked, it counts down", Recap.holding == Recap.HOLD and ns.db.recapStays == false)
Recap:SetStays(true)
suite.check("ticked while it shows, it stays", Recap.holding == nil)
Recap:Hide()

-- A run saved before the drops were kept shows its best drop.
local rows = Recap.Rows({ kills = 30, copper = 100, best = "Silk Cloth" })
suite.check("an old run shows its best drop", #rows == 1 and rows[1][1] == "Best drop")

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local keys = {}
for _, key in ipairs(ns.SettingsUI.SETTING_KEYS) do keys[key] = true end
suite.check("Set Default puts both back", keys.runGraph and keys.recapStays)
ns.SettingsUI:Show()
local controls = ns.SettingsUI.controls
suite.check("both have their switch", controls.runGraph ~= nil and controls.recapStays ~= nil)

suite.done()
