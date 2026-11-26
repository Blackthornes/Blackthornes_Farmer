-- The Home tab (2026-11-26): a first tab that asks what you want to do.
--
-- What matters: Farmer opens on Home the first time and on the tab last
-- used after that; the cards you can't use are left out; each card goes
-- where it says; Best Mobs for Me ticks Near My Level for now without
-- saving it; HERE and LAST RUN read what Farmer keeps; and the tab draws
-- without error.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("home")
local check = suite.check

local level = 24
local skills = nil

local function Login(saved)
    local ns = env.Load({ ui = true })
    _G.UnitLevel = function(unit) if unit == "player" then return level end end
    _G.BlackthornesFarmerDB = saved or {}
    ns.LoadSavedVariables()
    ns.db.oneWindow = false
    for _, module in ipairs(ns.moduleOrder) do
        if module.OnEnable then pcall(module.OnEnable, module) end
    end
    ns.Spots.Skills = function() return skills end
    ns.Fishing.Skill = function() return skills and skills.Fishing end
    return ns
end

local function Keys(cards)
    local keys = {}
    for _, card in ipairs(cards) do keys[#keys + 1] = card.key end
    return table.concat(keys, ",")
end

--------------------------------------------------------------------------------
-- Opens on Home the first time, then on the tab last used
--------------------------------------------------------------------------------

local ns = Login()
local UI, Home = ns.UI, ns.HomeUI
check("the tab list starts with Home", UI.Tabs()[1].key == "home")
UI:Toggle()
check("the first open is on Home", UI.tab == "home", UI.tab)
check("Home shows", Home.view:IsShown())
check("the search tab is hidden", not UI.searchView:IsShown())
UI:Hide()
UI:ShowTab("grind")
UI:Hide()
UI:Toggle()
check("after that it opens on the tab last used", UI.tab == "grind", UI.tab)
UI:Hide()
ns.db.lastTab = "search"
UI:Toggle()
check("a player who used Search opens on Search, as before", UI.tab == "search", UI.tab)
UI:Hide()

--------------------------------------------------------------------------------
-- Cards you can't use are left out
--------------------------------------------------------------------------------

skills = {}
ns.db.savedFarms = false
ns.db.grindTo60 = nil
check("no skills, no Saved Farms, no Grind to 60: two cards",
    Keys(Home.Cards()) == "find,best", Keys(Home.Cards()))
skills = { Herbalism = 80, Mining = 120, Fishing = 40 }
ns.db.savedFarms = nil
ns.db.grindTo60 = true
check("every card when you can use them all",
    Keys(Home.Cards()) == "find,best,gather,fish,farm,level", Keys(Home.Cards()))
check("Best Mobs for Me names your level",
    Home.Cards()[2].text == "The mobs worth the most near level 24.", Home.Cards()[2].text)
level = 60
check("no Level Up at the cap", not Keys(Home.Cards()):find("level"), Keys(Home.Cards()))
level = 24
check("Gather goes to your best skill's page", Home.GatherPage() == "ore", Home.GatherPage())
skills = nil
check("a client that won't say keeps the Gather card", Keys(Home.Cards()):find("gather") ~= nil)
skills = { Herbalism = 80, Mining = 120, Fishing = 40 }

--------------------------------------------------------------------------------
-- Each card goes where it says
--------------------------------------------------------------------------------

UI:ShowTab("home")
ns.db.rankingsNearLevel = nil
Home.GO.best()
check("Best Mobs for Me opens Rankings", UI.tab == "rankings", UI.tab)
check("with Near My Level ticked", ns.Rankings.NearLevel())
check("but not saved", ns.db.rankingsNearLevel == nil, tostring(ns.db.rankingsNearLevel))
ns.Rankings:SetNearLevel(false)
check("unticking the box takes it back", not ns.Rankings.NearLevel())
check("and still saves nothing new", ns.db.rankingsNearLevel ~= true)

Home.GO.gather()
check("Gather opens Grind", UI.tab == "grind")
check("on the ore page", ns.db.grindGives == "ore", tostring(ns.db.grindGives))
Home.GO.fish()
check("Fish opens Grind's Fish page", UI.tab == "grind" and ns.db.grindGives == "fish")
Home.GO.level()
check("Level Up opens Grind to 60", UI.tab == "grind" and ns.GrindTo60.Shown())
Home.GO.farm()
check("Repeat a Farm opens Farms", UI.tab == "farms", UI.tab)
Home.GO.find()
check("Find an Item opens Search", UI.tab == "search", UI.tab)

UI:ShowTab("home")
Home.searchBox:SetText("Linen Cloth")
Home.goButton:GetScript("OnClick")(Home.goButton, "LeftButton")
check("Search searches from Home", UI.tab == "search" and ns.db.lastSearch == "Linen Cloth",
    tostring(ns.db.lastSearch))

--------------------------------------------------------------------------------
-- HERE and LAST RUN
--------------------------------------------------------------------------------

check("no run yet: nothing", Home.LastRun() == nil)
local guid = ns.SavedFarms.Me()
ns.db.farmList = { { id = 1, name = "Linen", item = "Linen Cloth", zone = "Duskwood", how = "spot" } }
ns.db.farmRuns = { [guid] = { { id = 1, name = "Linen", at = 5000, seconds = 1800, got = 12,
    copper = 9000, itemsCopper = 6000 } } }
local run = Home.LastRun()
check("the last saved farm run", run and run.farm and run.farm.id == 1)
check("its gold an hour", run and math.floor(run.rate + 0.5) == 18000, run and run.rate)
check("its item", run and run.item == "Linen Cloth" and run.count == 12)

local store = ns.Stats:Store()
store.sessions[#store.sessions + 1] = { day = "x", at = 9000, seconds = 600, copper = 3000, kills = 5 }
run = Home.LastRun()
check("a newer Stats session wins", run and run.farm == nil and run.copper == 3000)
store.sessions[#store.sessions].seconds = 10
run = Home.LastRun()
check("a session too short to count is passed over", run and run.farm ~= nil)

local here = Home.Here()
check("HERE gives counts", type(here.locked) == "number" and type(here.herbs) == "number")

UI:ShowTab("home")
local ok, err = pcall(Home.Render, Home, true)
check("Home draws", ok, tostring(err))
check("LAST RUN shows the farm's lines", Home.last.rows[1]:IsShown() and Home.last.rows[3]:IsShown())

--------------------------------------------------------------------------------
-- Nothing on it runs on a timer
--------------------------------------------------------------------------------

check("Home has no OnUpdate", Home.view:GetScript("OnUpdate") == nil)

suite.done()
