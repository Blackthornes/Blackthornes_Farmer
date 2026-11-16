-- Saved Farms (2026-11-16, off unless ticked): save a farm once and run it
-- again with one click.
--
-- What matters: with the box unticked nothing shows and nothing is saved;
-- ticked, the Farms tab comes; a farm saves, edits and goes, at most 20;
-- Start sets the goal past what you have, points the arrow and starts the
-- timer if you use it; the run ends on the goal, the timer's Stop, Stop on
-- the tab or logging out, and is kept under the character's GUID only (an
-- unread GUID writes nothing); An Hour comes from your runs at today's
-- prices, else your pace, never a kill farm's pace; today's list starts
-- fresh each day; the tab, the box, the Search strip and Your Run's button
-- draw without error; and old saves without any of it load as they were.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("savedfarms")

local clock = 1000000
local copper = 0
local bags = {}

local function Login(saved, name)
    local ns = env.Load({ ui = true })
    _G.time = function() return clock end
    _G.GetTime = function() return clock end
    _G.date = function(format, at) return os.date(format, at or clock) end
    _G.C_Item = { GetItemCount = function(item) return bags[item] or 0 end }
    if name then _G.UnitName = function(unit) if unit == "player" then return name end end end
    _G.BlackthornesFarmerDB = saved or {}
    ns.LoadSavedVariables()
    ns.db.oneWindow = false
    for _, module in ipairs(ns.moduleOrder) do
        if module.OnEnable then pcall(module.OnEnable, module) end
    end
    ns.Value.Session = function() return copper end
    ns.Goals.quietUntil = 0
    return ns
end

local ns = Login()
local F, UI = ns.SavedFarms, ns.SavedFarmsUI
local SILK = ns.Value:ItemID("Silk Cloth")
suite.check("Silk Cloth is known", SILK ~= nil)
ns.Value.UnitPrice = function(_, id) if id == SILK then return 300 end return nil end

-- Off by default.
suite.check("off unless ticked", F.On() == false and ns.db.savedFarms == nil)
suite.check("Last Farm on Search waits for it", F.LastOnSearch() == false)
suite.check("nothing saves while off", F:Save({ item = "Silk Cloth", amount = 60 }) == nil)
suite.check("nothing was written", ns.db.farmList == nil and ns.db.farmRuns == nil)
ns.UI:Build()
local function FarmsTab(strip)
    for _, tab in ipairs(strip.tabs) do if tab.key == "farms" then return tab end end
end
suite.check("no Farms tab while off", FarmsTab(ns.UI.tabStrip).standing == false)
ns.UI:ShowTab("farms")
suite.check("the tab can't be opened while off", ns.UI.tab == "search")

-- Ticked.
F:SetOn(true)
suite.check("ticked saves savedFarms", ns.db.savedFarms == true and F.On())
suite.check("the Farms tab comes", FarmsTab(ns.UI.tabStrip).standing == true)
suite.check("Last Farm on Search on by default", F.LastOnSearch() == true)

-- Saving.
local farm = F:Save({ name = "Silk Cloth", item = "Silk Cloth", amount = 60, how = "spot",
    zone = "Hillsbrad Foothills", mob = "Hillsbrad Farmer", daily = true })
suite.check("a farm saves", farm ~= nil and farm.id == 1 and #F:List() == 1)
suite.check("it keeps what the box said", farm.amount == 60 and farm.how == "spot"
    and farm.zone == "Hillsbrad Foothills" and farm.mob == "Hillsbrad Farmer" and farm.daily == true)
local none, why = F:Save({ name = "x", amount = 5, how = "spot" })
suite.check("an item farm needs an item", none == nil and why ~= nil)
local zero = F:Save({ item = "Silk Cloth", amount = 0, how = "goal" })
suite.check("and an amount", zero == nil)
local route = F:Save({ name = "Morning herbs", item = "Peacebloom", how = "route" })
suite.check("a route needs no amount", route ~= nil and route.amount == nil and route.how == "route")
suite.check("a herb's route runs on the Herbs page", route.page == "herbs")
local kills = F:Save({ name = "Gnoll kills", how = "kills", amount = 300, mob = "Redridge Gnoll" })
suite.check("a kill farm needs no item", kills ~= nil and kills.item == nil)
suite.check("ids go up", route.id == 2 and kills.id == 3)

for index = #F:List() + 1, F.MAX do F:Save({ item = "Silk Cloth", amount = index, how = "goal" }) end
suite.check("up to 20", #F:List() == F.MAX)
suite.check("never a 21st", F:Save({ item = "Silk Cloth", amount = 1, how = "goal" }) == nil and #F:List() == F.MAX)
for index = F.MAX, 4, -1 do F:Remove(F:List()[index].id) end
suite.check("remove takes a farm off", #F:List() == 3)

local edited = F:Edit(farm.id, { name = "Silk", item = "Silk Cloth", amount = 40, how = "spot",
    zone = "Hillsbrad Foothills", mob = "Hillsbrad Farmer", daily = true })
suite.check("edit changes it in place", edited == farm and farm.name == "Silk" and farm.amount == 40 and farm.id == 1)

-- Today's list.
local list, done = F:TodayList()
suite.check("Every Day farms are on today's list", #list == 1 and list[1] == farm and done == 0)
F:ToggleToday(route.id)
list = F:TodayList()
suite.check("Add to Today adds one", #list == 2)

-- Gold an hour before any run: your pace times today's price.
ns.Pace.ForItem = function(_, item) if item == "Silk Cloth" then return { seconds = 30 } end end
local hour, from = F:AnHour(farm)
suite.check("before a run, your pace at today's price", from == "pace" and math.abs(hour - 120 * 300) < 0.01)
suite.check("a kill farm never uses a pace", F:AnHour(kills) == nil)

-- Starting.
bags[SILK] = 10
ns.SessionTimer:SetOn(true)
local aimed
ns.Arrow.Aim = function(_, item, spot) aimed = { item = item, spot = spot } return true end
suite.check("Start starts", F:Start(farm.id) == true)
local goal = ns.Goals:Find("Silk Cloth")
suite.check("the goal is what you have plus the farm's amount", goal and goal.target == 50)
suite.check("the arrow goes to the spot", aimed and aimed.item == "Silk Cloth"
    and aimed.spot.name == "Hillsbrad Farmer" and aimed.spot.zone == "Hillsbrad Foothills")
suite.check("the timer starts when you use it", ns.SessionTimer.state == "timing" and F.run.timer == true)

-- Stop on the timer ends the run and keeps it.
clock = clock + 1200
bags[SILK] = 30
copper = 9000
ns.SessionTimer:Stop()
local runs = F:Runs()
suite.check("the timer's Stop ends the run", F.run == nil and #runs == 1)
local run = runs[1]
suite.check("the run keeps time, what you got and the gold",
    run.id == farm.id and run.seconds == 1200 and run.got == 20 and run.copper == 9000)
suite.check("kept under this character's GUID", ns.db.farmRuns["Player-1-Blackthornes"] ~= nil)
suite.check("not done yet: 20 of 40", F:DoneToday(farm) == false)
suite.check("Your Run offers no Save This Farm for a saved farm",
    not (ns.RecapUI.frame and rawget(ns.RecapUI.frame, "saveFarm") and ns.RecapUI.frame.saveFarm:IsShown()))

-- An Hour from runs, at today's price.
F.rates = nil
hour, from = F:AnHour(farm)
suite.check("from your runs", from == "runs" and math.abs(hour - 27000) < 0.01)
ns.Value.UnitPrice = function(_, id) if id == SILK then return 600 end return nil end
F.rates = nil
hour = F:AnHour(farm)
-- 9000 copper, 6000 of it the silk; now worth 12000: 15000 in 20 minutes.
suite.check("repriced at today's price", math.abs(hour - 45000) < 0.01)
suite.check("a run's own rate", math.abs(F.RunRate(run, "Silk Cloth") - 45000) < 0.01)

-- The goal reached ends the run, done for today.
F:Start(farm.id)
clock = clock + 600
bags[SILK] = 70
ns.Goals:Update()
suite.check("the goal done ends the run", F.run == nil and #F:Runs() == 2)
suite.check("and marks the farm done today", F:DoneToday(farm) == true)
local _, doneCount = F:TodayList()
suite.check("today's count moves", doneCount == 1)

-- Repeat starts the newest run's farm.
suite.check("the last farm is the newest run's", F:LastFarm().farm == farm)
suite.check("Repeat starts it", F:Repeat() == true and F.run and F.run.id == farm.id)
F:End("stop")

-- A short run with nothing got is not kept.
F:Start(farm.id)
clock = clock + 5
F:End("stop")
suite.check("a run of seconds with nothing got is not kept", #F:Runs() == 2)

-- At most ten runs kept.
for _ = 1, 12 do
    F:Start(farm.id)
    clock = clock + 120
    F:End("stop")
end
suite.check("ten runs kept", #F:Runs() == F.KEEP_RUNS)

-- A kill farm starts a kill goal.
ns.SessionTimer:SetOn(false)
suite.check("a kill farm starts", F:Start(kills.id) == true)
local killGoal = ns.KillGoal:Current()
suite.check("with a kill goal of its amount and mob", killGoal and killGoal.target == 300
    and killGoal.mob == "Redridge Gnoll")
F:End("stop")

-- Logging out ends the run.
F:Start(farm.id)
clock = clock + 300
local before = #F:Runs()
for _, handler in pairs({ ns.SavedFarms.PLAYER_LOGOUT }) do handler() end
suite.check("logging out ends the run", F.run == nil)

-- Words.
suite.check("today", F.When(clock) == "Today")
suite.check("yesterday", F.When(clock - 86400) == "Yesterday")
suite.check("2 days ago", F.When(clock - 2 * 86400) == "2 days ago")
suite.check("last week", F.When(clock - 8 * 86400) == "Last week")
suite.check("never", F.When(nil) == "Never")
suite.check("minutes", F.Duration(26 * 60) == "26 min" and F.Duration(65 * 60) == "1 hr 5 min")
suite.check("the Goal column says Route for a route", UI.GoalText(route) == "Route" and UI.GoalText(farm) == "40")

-- The tab draws.
ns.UI:Show()
ns.UI:ShowTab("farms")
suite.check("the Farms tab opens", ns.UI.tab == "farms" and ns.UI.farmsView:IsShown())
local ok, err = pcall(UI.Render, UI)
suite.check("it draws without error", ok, err)
suite.check("saved farms listed", #UI.saved.list.data == 3)
suite.check("today's farms listed", #UI.today.list.data == 2)
suite.check("runs listed", #UI.runs.list.data == F.KEEP_RUNS)
suite.check("the Last Farm card shows", UI.card.button:IsShown())
local top, bottom = UI.LastLines(F:LastFarm())
suite.check("its lines read as the mockup", top:find("in Hillsbrad Foothills") ~= nil
    and bottom:find("in all%.") ~= nil)
suite.check("today's count", UI.todayCount:GetText() == "1 of 2 done today.")

-- Sorting.
local sorted = UI.Sort("saved", { { farm = { name = "b" } }, { farm = { name = "a" } } }, "farm", true)
suite.check("sorts by Farm", sorted[1].farm.name == "a")
sorted = UI.Sort("saved", { { farm = { name = "x" }, hour = 5 }, { farm = { name = "y" }, hour = 9 } }, "hour", false)
suite.check("sorts by An Hour", sorted[1].hour == 9)

-- The Save Farm box.
suite.check("Save Farm opens the box", UI:SaveItem("Silk Cloth") == true and UI.box:IsShown())
suite.check("filled from the item", UI.box.item:GetText() == "Silk Cloth" and UI.box.how:GetValue() == "spot")
UI.box.name:SetText("Silk again")
suite.check("Confirm saves it", UI:ConfirmBox() == true and #F:List() == 4 and not UI.box:IsShown())
-- New Farm: typing in Item: lists matching items, and a pick fills Zone:.
UI:OpenBox({})
suite.check("Zone: waits for an item", #UI.box.zoneChoices == 0)
UI.box.item:SetText("silk")
UI:Suggest("silk")
local first = UI.box.suggest.rows[1]
suite.check("typing lists items", UI.box.suggest:IsShown() and first:IsShown() and first.item ~= nil)
local silkFound = false
for _, row in ipairs(UI.box.suggest.rows) do
    if row:IsShown() and row.item.name == "Silk Cloth" then silkFound = row end
end
suite.check("Silk Cloth is among them", silkFound ~= false)
UI:PickItem(silkFound.item)
suite.check("a pick fills Item: and Name:", UI.box.item:GetText() == "Silk Cloth" and UI.box.name:GetText() == "Silk Cloth")
suite.check("and Zone: lists its zones", #UI.box.zoneChoices > 0 and not UI.box.suggest:IsShown())
suite.check("each is a real zone", UI.box.zoneChoices[1].zone ~= nil)
local zoneSeen, zoneOnce = {}, true
for _, option in ipairs(UI.box.zoneChoices) do
    if zoneSeen[option.zone] then zoneOnce = false end
    zoneSeen[option.zone] = true
end
suite.check("each zone once", zoneOnce)
local best = true
for index = 2, #UI.box.zoneChoices do
    if not UI.BestFirst(UI.box.zoneChoices[index - 1], UI.box.zoneChoices[index])
        and UI.BestFirst(UI.box.zoneChoices[index], UI.box.zoneChoices[index - 1]) then best = false end
end
suite.check("best drop chance first", best)
suite.check("Mob: starts on Any Mob", UI.box.mob:GetValue() == 1 and UI.box.mobChoices[1].mob == nil)
local fields = UI:BoxFields()
suite.check("the zone saves with the farm", fields.zone == UI.box.zoneChoices[1].zone and fields.mob == nil)

-- Zone order and mob choices from known sources.
local fakeItem = { name = "Test Cloth", sources = {
    { zone = "Desolace", name = "Kolkar Mauler", chance = 21, minLevel = 33, maxLevel = 34 },
    { zone = "Desolace", name = "Burning Blade Summoner", chance = 31, minLevel = 36, maxLevel = 37 },
    { zone = "Tanaris", name = "Wastewander Rogue", chance = 44, minLevel = 40, maxLevel = 41 },
    { zone = "Swamp of Sorrows", kind = "herb", minLevel = 35, maxLevel = 45 },
    { zone = "Badlands", name = "Dustbelcher Brute", minLevel = 30, maxLevel = 31 },
} }
local zones = UI.ZoneOptions(fakeItem)
suite.check("zones best chance first", zones[1].zone == "Tanaris" and zones[2].zone == "Desolace")
suite.check("a zone takes its best mob's chance", zones[2].chance == 31 and zones[2].minLevel == 33 and zones[2].maxLevel == 37)
suite.check("zones with no chance go last, lowest level first", zones[3].zone == "Badlands" and zones[4].zone == "Swamp of Sorrows")
suite.check("no chance shows --", zones[3].columns[1].text == "--")
local mobs = UI.MobOptions(fakeItem, "Desolace")
suite.check("Any Mob first, then mobs best first", mobs[1].mob == nil and mobs[2].mob == "Burning Blade Summoner"
    and mobs[3].mob == "Kolkar Mauler" and #mobs == 3)
suite.check("a herb zone has no mobs", #UI.MobOptions(fakeItem, "Swamp of Sorrows") == 1)

-- Mob: greys for Route Mode and saves no mob.
local realGetItem = ns.DB.GetItem
ns.DB.GetItem = function(db, name) if name == "Test Cloth" then return fakeItem end return realGetItem(db, name) end
UI.box.item:SetText("Test Cloth")
UI.box.zoneChoices = zones
UI.box.zone:SetOptions(zones)
UI.box.zone:SetValue(2)
UI:ZonePicked("Kolkar Mauler")
suite.check("a mob can be picked", UI.box.mob:IsEnabled() and UI:BoxFields().zone == "Desolace")
UI.box.how:SetValue("route")
UI:MobState()
suite.check("Route Mode greys Mob:", not UI.box.mob:IsEnabled() and UI:BoxFields().mob == nil)
UI.box.how:SetValue("spot")
UI:MobState()
UI.box.zone:SetValue(4)
UI:ZonePicked()
suite.check("a herb zone greys Mob:", not UI.box.mob:IsEnabled())
ns.DB.GetItem = realGetItem

-- An old farm with a mob opens as it was saved.
UI:CloseBox()
UI:OpenBox({ name = "Old", item = "Silk Cloth", zone = "Nowhere Vale", mob = "Old Mob", amount = 5, how = "spot" }, nil)
fields = UI:BoxFields()
suite.check("an old farm keeps its zone and mob", fields.zone == "Nowhere Vale" and fields.mob == "Old Mob")
UI:CloseBox()
UI:OpenBox({ name = "Old", item = "Silk Cloth", zone = "Nowhere Vale", amount = 5, how = "spot" }, nil)
suite.check("one with only a zone opens on Any Mob", UI:BoxFields().mob == nil and UI.box.mob:GetValue() == 1)
UI:OpenBox({})
UI:PickTop("silk")
UI:ItemTyped("Silk Clo")
suite.check("a part name leaves Zone: empty", #UI.box.zoneChoices == 0)
UI:PickTop("silk clo")
suite.check("Enter takes the best match", UI.box.item:GetText() == "Silk Cloth" and #UI.box.zoneChoices > 0)
UI:CloseBox()

UI:OpenBox(F:Find(route.id), route.id)
UI.box.amount:SetText("25")
suite.check("Edit keeps the same farm", UI:ConfirmBox() == true and F:Find(route.id).amount == 25 and #F:List() == 4)

-- The Search strip.
ns.UI:ShowTab("search")
UI:PlaceSearchStrip()
suite.check("the Last Farm strip shows on Search", UI.strip and UI.strip:IsShown())
F:SetLastOnSearch(false)
suite.check("and goes when unticked", not UI.strip:IsShown() and ns.db.lastFarmOnSearch == false)
F:SetLastOnSearch(true)

-- Your Run offers Save This Farm when the run was no saved farm.
ns.SessionTimer:SetOn(true)
ns.SessionTimer:Start()
clock = clock + 120
ns.SessionTimer:Stop()
suite.check("Your Run shows Save This Farm", rawget(ns.RecapUI.frame, "saveFarm") and ns.RecapUI.frame.saveFarm:IsShown())

-- Settings.
ns.SettingsUI:Show()
local controls = ns.SettingsUI.controls
suite.check("the Saved Farms box is on the Goals page", controls.savedFarms ~= nil and controls.lastFarmOnSearch ~= nil)
ns.SettingsUI:Refresh()
suite.check("it shows the setting", controls.savedFarms.checked == true)

-- Unticked: the tab goes, the farms stay.
F:SetOn(false)
suite.check("unticked, the Farms tab goes", FarmsTab(ns.UI.tabStrip).standing == false)
suite.check("the farms are kept", #ns.db.farmList == 4)
F:SetOn(true)

-- /farm farms and /farm repeat.
ns.HandleSlash("farms off")
suite.check("/farm farms off", F.On() == false)
ns.HandleSlash("farms on")
suite.check("/farm farms on", F.On() == true)
ns.HandleSlash("repeat")
suite.check("/farm repeat starts the last farm", F.run ~= nil)
F:End("stop")

-- One key per character: a GUID the client won't read writes nothing.
local saved = ns.db
local ns2 = Login(saved, "Another")
local F2 = ns2.SavedFarms
suite.check("another character has no runs of its own", #F2:Runs() == 0)
suite.check("but sees the same farms", #F2:List() == 4)
ns2.Goals.me = nil
_G.UnitGUID = function() return nil end
suite.check("an unread GUID starts nothing", F2:Start(1) == false and F2.run == nil)
suite.check("and keeps no day", F2:Today(true) == nil)

-- An old save loads as it was.
local ns3 = Login({ goals = { list = {} } }, "Blackthornes")
suite.check("an old save loads with Saved Farms off", ns3.SavedFarms.On() == false and ns3.db.farmList == nil)

suite.done()
