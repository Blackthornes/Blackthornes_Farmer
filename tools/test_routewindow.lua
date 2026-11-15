-- The Route Window, Leveling Mode and the train line (the owner said build
-- it, 2026-11-15, from a mockup whose words he approved).
--
-- What matters: the window is off unless ticked and shows only while a
-- route runs with Route Mode on; the close gem keeps it away until the
-- next route; it lists at most four stops, the next one first, wrapping
-- round the loop; the title names the zone, and folded the next stop; the
-- status words follow the mockup; Leveling Mode is kept per page; the
-- train line warns near the cap and says so at it; the foot line counts
-- stops; and /farm routewindow turns it on, off and back to its spot.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("routewindow")
local check = suite.check

local ns = env.Load({ ui = true })
local L = ns.L
local RouteWindow, GatherRoute = ns.RouteWindow, ns.GatherRoute

check("the module loads", RouteWindow ~= nil and GatherRoute ~= nil)
check("the command is there", type(ns.commands.routewindow) == "table" and type(ns.commands.routewindow.fn) == "function")

-- Off unless ticked ----------------------------------------------------------
ns.db.routeWindow = nil
check("off by default", RouteWindow.IsOn() == false)
RouteWindow:SetOn(true)
check("ticking saves true", ns.db.routeWindow == true and RouteWindow.IsOn())
RouteWindow:SetOn(false)
check("unticking saves nothing", ns.db.routeWindow == nil)

-- When it shows ----------------------------------------------------------------
local realRunning = GatherRoute.Running
local running = false
GatherRoute.Running = function() return running end
GatherRoute.page = nil

RouteWindow:SetOn(true)
check("not without Route Mode", RouteWindow:Wanted() == false)
GatherRoute.page = "herb"
check("not before a route starts", RouteWindow:Wanted() == false)
running = true
check("shows while a route runs", RouteWindow:Wanted() == true)
RouteWindow:Close()
check("the close gem puts it away", RouteWindow:Wanted() == false)
running = false
RouteWindow:Refresh()
check("a route ending forgets the close", RouteWindow.closed == nil)
running = true
check("the next route shows it again", RouteWindow:Wanted() == true)
RouteWindow:SetOn(false)
check("unticked it never shows", RouteWindow:Wanted() == false)
RouteWindow:Refresh()
check("unticked leaves no window up", not (RouteWindow.frame and RouteWindow.frame:IsShown()))

-- The stops ---------------------------------------------------------------------
local function Stop(n, node, extra)
    local stop = { n = n, spot = { node = node, kind = "herb" } }
    for k, v in pairs(extra or {}) do stop[k] = v end
    return stop
end
local stops = {
    Stop(1, "Peacebloom", { done = true }),
    Stop(2, "Silverleaf", { done = true }),
    Stop(3, "Earthroot", { next = true, yards = 40 }),
    Stop(4, "Mageroyal"),
    Stop(5, "Briarthorn"),
    Stop(6, "Bruiseweed"),
}
local plan = { stops = stops, nextStop = stops[3], zone = "Elwynn Forest", loopSeconds = 360 }
local shown = RouteWindow.Stops(plan)
check("at most four stops", #shown == 4)
check("the next stop comes first", shown[1] == stops[3])
check("then the loop's order", shown[2] == stops[4] and shown[4] == stops[6])
local short = { stops = { stops[1], stops[2], stops[3] }, nextStop = stops[3] }
check("stops done are left out", #RouteWindow.Stops(short) == 1)
local wrap = { stops = { Stop(1, "A"), Stop(2, "B"), Stop(3, "C", { next = true }) } }
wrap.nextStop = wrap.stops[3]
local round = RouteWindow.Stops(wrap)
check("it wraps round the loop", #round == 3 and round[2] == wrap.stops[1])
check("no plan, no stops", #RouteWindow.Stops(nil) == 0)

-- The title -------------------------------------------------------------------
check("the title names the zone", RouteWindow.Title(plan, false) == L["ROUTE"] .. " Elwynn Forest")
check("folded it names the next stop", RouteWindow.Title(plan, true) == L.Format("%s %s, %d yd", L["ROUTE"], "Earthroot", 40))
check("folded with no yards", RouteWindow.Title({ nextStop = Stop(1, "Tin Vein") }, true) == L["ROUTE"] .. " Tin Vein")
check("no zone, the word alone", RouteWindow.Title({}, false) == L["ROUTE"])

-- The status words -----------------------------------------------------------
check("the next stop", (GatherRoute.Status(stops[3], 100)) == L["Go here next"])
local up, upColor = RouteWindow.Status(Stop(4, "Mageroyal", { back = true }), 100)
check("Should be up reads green", up == L["Should be up"] and upColor == "good")
check("a grey spot has no skill", (GatherRoute.Status(Stop(5, "x", { tier = 4 }), 100)) == L["No skill here"])
local back = GatherRoute.Status(Stop(6, "x", { at = 100 + 240 }), 100)
check("a resting spot says when", back == L.Format("Back in %s", ns.Respawn.Duration(240)))

-- Leveling Mode -----------------------------------------------------------------
ns.db.grindRouteLeveling = nil
check("Leveling Mode off unless ticked", GatherRoute.Leveling("herbs") == false)
GatherRoute:SetLeveling("herbs", true)
check("kept for that page only", GatherRoute.Leveling("herbs") and not GatherRoute.Leveling("ore")
    and ns.db.grindRouteLeveling.herbs == true)
check("the route's page reads it", GatherRoute.PageGives() == "herbs" and GatherRoute.LevelingOn())
GatherRoute:SetLeveling("cloth", true)
check("not on a page without routes", GatherRoute.Leveling("cloth") == false)
GatherRoute:SetLeveling("herbs", false)
check("unticked leaves nothing saved", ns.db.grindRouteLeveling == nil)

-- The train line ----------------------------------------------------------------
local realRead = ns.GatherToCap.ReadSkill
local skill, cap = 60, 75
ns.GatherToCap.ReadSkill = function() return skill, cap end
check("nothing far from the cap", GatherRoute.TrainText() == nil)
skill = 72
local warn, warnColor = GatherRoute.TrainText()
check("warns near the cap", warn == L.Format("Train %s %s to keep going. Your skill stops at %d.",
    L["Journeyman"], L["Herbalism"], 75) and warnColor == "warn")
skill = 75
local at, atColor = GatherRoute.TrainText()
check("says so at the cap", at == L.Format("You've hit %d. Train %s %s at a trainer to get more skill.",
    75, L["Journeyman"], L["Herbalism"]) and atColor == "loss")

-- The foot line -----------------------------------------------------------------
skill = 72
plan.leveling = nil
check("the foot counts stops and the loop", GatherRoute.FootText(plan)
    == L.Format("Stop %d of %d. One loop: about %s.", 3, 6, ns.Respawn.Duration(360)))
plan.leveling = true
check("with Leveling Mode it shows the skill", GatherRoute.FootText(plan)
    == L.Format("%s %d / %d. Stop %d of %d.", L["Herbalism"], 72, 75, 3, 6))
check("no plan, no foot", GatherRoute.FootText(nil) == "")
ns.GatherToCap.ReadSkill = realRead

-- /farm routewindow -------------------------------------------------------------
local command = ns.commands.routewindow.fn
command("on")
check("on ticks it", ns.db.routeWindow == true)
command("off")
check("off unticks it", ns.db.routeWindow == nil)
command("")
check("alone it flips", ns.db.routeWindow == true)
ns.db.routeWindowScale = 120
ns.db.windowSpots = { [RouteWindow.SPOT_KEY] = { x = 10, y = 20 } }
command("reset")
check("reset puts its size back", ns.db.routeWindowScale == nil)
check("reset forgets its spot", ns.db.windowSpots[RouteWindow.SPOT_KEY] == nil)
check("reset leaves it ticked", ns.db.routeWindow == true)
command("off")

GatherRoute.Running = realRunning
GatherRoute.page = nil
suite.done()
