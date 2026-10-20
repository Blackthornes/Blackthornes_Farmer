-- Gather to cap on the Grind tab (the owner approved the mockup,
-- 2026-10-20).
--
-- What matters: your skill and cap come from the client; the path runs a
-- stop a node from the ladder (the data's skill winning), each to the next
-- stop's skill; the one you are on says your spots there and about how
-- many gathers are left by Classic's skill-up chance; the zone is where you
-- mapped the most, else the data's nearest your level; later stops say the
-- rank to train when they pass your cap, else the zone's mob levels; worth
-- an hour is your own pace where you have one, else a typical hour; hidden
-- nodes are left out; it is laid out again only when something it reads
-- moves; the Grind tab draws it at the top of the Ore, Herbs and Leather
-- views, Show the Way aims the arrow and Set Goal makes a goal; a skill you
-- lack shows nothing new.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("gathertocap")
local check = suite.check

local ns = env.Load({ ui = true })
local GatherToCap, UIPath, GrindingUI, DB = ns.GatherToCap, ns.GatherToCapUI, ns.GrindingUI, ns.DB

-- Every item 10 copper.
ns.Value.UnitPrice = function(_, id) if id then return 10, "auction" end end

--------------------------------------------------------------------------------
-- The chance and the gathers
--------------------------------------------------------------------------------

check("a point for sure under 25 over", GatherToCap.Chance(89, 65) == 1)
check("still sure at 25 over", GatherToCap.Chance(90, 65) == 1)
check("half way down at 62.5 over", math.abs(GatherToCap.Chance(127.5, 65) - 0.5) < 1e-9)
check("never nothing", GatherToCap.Chance(400, 65) == GatherToCap.MIN_CHANCE)
check("sure points are one gather each", GatherToCap.Gathers(1, 26, 1) == 25)
local tin = GatherToCap.Gathers(87, 125, 65)
local sum = 0
for skill = 87, 124 do sum = sum + 1 / GatherToCap.Chance(skill, 65) end
check("slower ones count more", tin == math.ceil(sum - 1e-9) and tin > 38, tin)

--------------------------------------------------------------------------------
-- The skill from the client
--------------------------------------------------------------------------------

_G.GetProfessions = function() return 1, 2 end
_G.GetProfessionInfo = function(index)
    if index == 1 then return "Herbalism", 0, 12, 75 end
    return "Mining", 0, 87, 150
end
local skill, most = GatherToCap.ReadSkill("Mining")
check("skill and cap from the professions", skill == 87 and most == 150)
check("a skill you lack is nil", GatherToCap.ReadSkill("Skinning") == nil)
_G.GetProfessions = nil
_G.GetNumSkillLines = function() return 2 end
_G.GetSkillLineInfo = function(index)
    if index == 1 then return "Professions", true end
    return "Mining", false, nil, 90, 0, 0, 150
end
skill, most = GatherToCap.ReadSkill("Mining")
check("else from the skill lines", skill == 90 and most == 150)
_G.GetNumSkillLines, _G.GetSkillLineInfo, _G.GetProfessionInfo = nil, nil, nil

check("the next rank over a cap of 150", GatherToCap.NextRank(150).key == "Expert")
check("none at 300", GatherToCap.NextRank(300) == nil)

--------------------------------------------------------------------------------
-- The path
--------------------------------------------------------------------------------

local skills = { Mining = { 87, 150 } }
GatherToCap.ReadSkill = function(name)
    local entry = skills[name]
    if entry then return entry[1], entry[2] end
end

ns.Spots.MAP_ZONES[99902] = "Wetlands"
ns.db.gathering = ns.db.gathering or {}
ns.db.gathering.spots = {
    { map = 99902, x = 0.5, y = 0.4, node = "Tin Vein", kind = "ore" },
    { map = 99902, x = 0.52, y = 0.41, node = "Tin Vein", kind = "ore" },
    { map = 99902, x = 0.6, y = 0.45, node = "Tin Vein", kind = "ore" },
}

local function StopFor(path, node)
    for _, stop in ipairs(path.stops) do if stop.node == node then return stop end end
end

local path = GatherToCap:Path("ore")
check("a path for Mining", path and path.english == "Mining" and path.skill == 87 and path.most == 150)
local copper, now, iron = StopFor(path, "Copper Vein"), StopFor(path, "Tin Vein"), StopFor(path, "Iron Deposit")
check("Copper is done", copper and copper.state == "done" and copper.from == 1 and copper.to == 65)
check("Tin is the one you're on", now and now.state == "now" and now.from == 65 and now.to == 125
    and path.stops[path.current] == now)
check("in the zone you mapped it", now.zone == "Wetlands" and now.spots == 3 and #now.spotList == 3)
check("with the zone's levels", now.minLevel == 20 and now.maxLevel == 30)
check("about this many gathers", now.gathers == tin, now.gathers)
check("its item", now.item == "Tin Ore" and now.itemID == 2771)
check("Iron is later and passes your cap", iron.state == "later" and iron.from == 125 and iron.to == 175
    and iron.train and iron.train.key == "Expert")
check("silver is no stop", StopFor(path, "Silver Vein") == nil)
check("the last stop runs to 300", path.stops[#path.stops].to == 300)
check("Copper with no spots goes to the data's zone nearest level 25",
    copper.zone == "The Barrens", copper.zone)

check("worth from a typical hour without your own pace", now.perHour == 800 and not now.own, now.perHour)
check("kept until something moves", GatherToCap:Path("ore") == path)

ns.db.gathering.pace = { ["Wetlands|Tin Vein"] = { seconds = 720, gathers = 10, items = { ["Tin Ore"] = 40 } } }
ns.GrindGather.paceVersion = (ns.GrindGather.paceVersion or 0) + 1
path = GatherToCap:Path("ore")
now = StopFor(path, "Tin Vein")
check("your own pace wins", now.perHour == 2000 and now.own, now.perHour)

table.insert(ns.db.gathering.spots, { map = 99902, x = 0.7, y = 0.4, node = "Tin Vein", kind = "ore" })
local again = GatherToCap:Path("ore")
check("a new spot lays it out again", again ~= path and StopFor(again, "Tin Vein").spots == 4)

DB:Hide("source", "Iron Deposit")
check("a hidden node is left out", StopFor(GatherToCap:Path("ore"), "Iron Deposit") == nil)
DB:Unhide("source", "Iron Deposit")
check("and back", StopFor(GatherToCap:Path("ore"), "Iron Deposit") ~= nil)

local shown = GatherToCap.Shown(GatherToCap:Path("ore"), 3)
check("shown: the last one done, now and three after", #shown == 5 and shown[1].state == "done"
    and shown[2].state == "now" and shown[5].state == "later")

--------------------------------------------------------------------------------
-- The words
--------------------------------------------------------------------------------

path = GatherToCap:Path("ore")
now, iron = StopFor(path, "Tin Vein"), StopFor(path, "Iron Deposit")
check("the heading", UIPath.HeadingText(path) == "MINING 87 / 150", UIPath.HeadingText(path))
check("the title", UIPath.TitleText(now) == "Tin Vein in Wetlands")
check("now to", UIPath.RangeText(now) == "now to 125")
check("a range", UIPath.RangeText(iron) == "125 to 175")
check("the line under the one you're on", UIPath.SubText(path, now)
    == ("You've mapped 4 spots here. About %d more gathers."):format(now.gathers), UIPath.SubText(path, now))
check("training first", UIPath.SubText(path, iron) == "Train Expert Mining at 125 first.", UIPath.SubText(path, iron))
check("worth an hour", UIPath.WorthText(now):find("an hour") ~= nil)

skills.Herbalism = { 12, 75 }
local herbs = GatherToCap:Path("herbs")
local mageroyal, briar = StopFor(herbs, "Mageroyal"), StopFor(herbs, "Briarthorn")
check("Herbalism starts at Peacebloom", herbs.stops[herbs.current].node == "Peacebloom")
check("a later stop under your cap says the mobs' levels",
    UIPath.SubText(herbs, mageroyal):find("^Mobs here are level %d+ to %d+%.$") ~= nil, UIPath.SubText(herbs, mageroyal))
check("past it, the rank to train", UIPath.SubText(herbs, briar) == "Train Journeyman Herbalism at 50 first.")
check("no spots, no spot sentence", not UIPath.SubText(herbs, herbs.stops[herbs.current]):find("mapped"))

--------------------------------------------------------------------------------
-- The Grind tab
--------------------------------------------------------------------------------

ns.HandleSlash("grind 20-30 ore")
check("the path shows on Ore", UIPath.frame:IsShown() and GrindingUI.pathRoom > 0)
check("its heading", UIPath.head:GetText() == "MINING 87 / 150" and UIPath.note:GetText() == "Gather to cap")
local rows = UIPath.rows
check("a done row, then the one you're on", rows[1]:IsShown() and rows[1].stop.state == "done"
    and rows[1].done:IsShown() and not rows[1].button:IsShown())
check("the one you're on is lit, with Show the Way", rows[2].stop.state == "now" and rows[2].active:IsShown()
    and rows[2].button:IsShown() and rows[2].button.label:GetText() == "Show the Way")
check("later ones have no button", rows[3].stop.state == "later" and not rows[3].button:IsShown())
check("a segment a stop", #UIPath.meter.segments >= #GatherToCap:Path("ore").stops)
check("the list moves down under it", GrindingUI.headings.mob._point[3] == -8 - GrindingUI.pathRoom)
check("Set Goal shows", UIPath.goalButton:IsShown())

local aimed
local grind0 = ns.Arrow.Grind
ns.Arrow.Grind = function(_, camp) aimed = camp return true end
local print0 = ns.Print
ns.Print = function() end
rows[2].button:GetScript("OnClick")(rows[2].button, "LeftButton")
check("Show the Way aims the arrow at your spots", aimed and aimed.zone == "Wetlands" and #aimed.mobs == 4
    and aimed.mobs[1].name == "Tin Vein", aimed and #aimed.mobs)

local set, opened
local setGoal0, show0 = ns.Goals.Set, ns.GoalsUI.Show
ns.Goals.Set = function(_, name, amount)
    set = { name, amount }
    return { item = name, target = amount, have = 0 }
end
ns.GoalsUI.Show = function() opened = true end
UIPath.goalButton:GetScript("OnClick")(UIPath.goalButton, "LeftButton")
local current = GatherToCap:Path("ore").stops[GatherToCap:Path("ore").current]
check("Set Goal asks for the main item", set and set[1] == "Tin Ore"
    and set[2] >= math.max(20, current.gathers), set and set[2])
check("and opens the goals", opened)
ns.Goals.Set, ns.GoalsUI.Show = setGoal0, show0

ns.HandleSlash("grind herbs")
check("Herbs has its own", UIPath.frame:IsShown() and UIPath.head:GetText() == "HERBALISM 12 / 75")

skills.Herbalism = nil
GrindingUI:Render()
check("a skill you lack shows nothing new", not UIPath.frame:IsShown() and GrindingUI.pathRoom == 0)
check("the headings go back up", GrindingUI.headings.mob._point[3] == -8)

ns.HandleSlash("grind cloth")
check("the mob views have none", not UIPath.frame:IsShown())

skills.Mining = { 300, 300 }
ns.HandleSlash("grind ore")
check("at the top everything is done", UIPath.frame:IsShown() and not UIPath.goalButton:IsShown()
    and GatherToCap:Path("ore").current == nil)

--------------------------------------------------------------------------------
-- Skinning
--------------------------------------------------------------------------------

skills.Skinning = { 94, 150 }
local skin = GatherToCap:Path("skinning")
check("a path for Skinning", skin and #skin.stops > 0 and skin.current)
local onSkin = skin.stops[skin.current]
check("by bands of beasts, with a camp", onSkin.camp and onSkin.from <= 94 and onSkin.to > 94)
aimed = nil
GatherToCap:ShowTheWay(onSkin)
check("Show the Way follows the camp", aimed == onSkin.camp)
ns.HandleSlash("grind leather")
check("the Leather view shows it", UIPath.frame:IsShown()
    and UIPath.head:GetText() == "SKINNING 94 / 150")

ns.Arrow.Grind, ns.Print = grind0, print0

suite.done()
