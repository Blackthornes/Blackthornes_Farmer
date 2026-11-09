-- A German player's search found no farm spots (2026-11-09): "Wollstoff",
-- "Mittleres Leder" and "Zinnerz" found nothing. The client's names were
-- only read from the first search on, the server answers a burst of item
-- asks slowly and drops some, nothing asked again for those, and a search
-- already on screen never ran again when the names came in.
--
-- What matters: on a client in another language the names start coming in
-- after login, an item the client does not know yet is asked for and asked
-- again later, the search finds the German names once they arrive, and the
-- Search tab runs again when they do.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("germansearch")

local WOOL, LEATHER, TIN = 2592, 2319, 2771
local GERMAN = { [WOOL] = "Wollstoff", [LEATHER] = "Mittleres Leder", [TIN] = "Zinnerz" }

-- Timers wait until the test runs them.
local timers = {}
local function Deferred()
    _G.C_Timer = {
        After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end,
        NewTicker = function() return {} end,
    }
end
local function RunTimers(maxDelay)
    for _ = 1, 10000 do
        local index
        for i, timer in ipairs(timers) do
            if not maxDelay or timer.delay <= maxDelay then index = i break end
        end
        if not index then return end
        local timer = table.remove(timers, index)
        timer.fn()
    end
end

-- What the client has loaded, and how many times each was asked for.
local loaded, asks, dropFirst = {}, {}, {}
local fireEvent

local function German(ns)
    _G.GetLocale = function() return "deDE" end
    _G.C_Item = {
        GetItemNameByID = function(id) return loaded[id] and GERMAN[id] or nil end,
        GetItemInfo = function(item)
            if type(item) == "number" and loaded[item] then return GERMAN[item] end
            return nil
        end,
        RequestLoadItemDataByID = function(id)
            asks[id] = (asks[id] or 0) + 1
            if GERMAN[id] and not (dropFirst[id] and asks[id] == 1) then
                loaded[id] = true
                fireEvent(ns.eventFrame, "GET_ITEM_INFO_RECEIVED", id, true)
            end
        end,
    }
    fireEvent = ns.eventFrame:GetScript("OnEvent")
end

local function Finds(ns, query, id)
    for _, result in ipairs(ns.Search:Run(query)) do
        if result.item and result.item.id == id then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- An English client reads nothing at login
--------------------------------------------------------------------------------

local ns = env.Load({ ui = true })
Deferred()
ns.DB:OnEnable()
RunTimers()
suite.check("English: nothing is read at login", not ns.DB.learning)

--------------------------------------------------------------------------------
-- A German client
--------------------------------------------------------------------------------

timers, loaded, asks = {}, {}, {}
dropFirst = { [WOOL] = true }
ns = env.Load({ ui = true })
German(ns)
Deferred()
local DB = ns.DB
suite.check("Wool Cloth is in the data", DB:GetItem("Wool Cloth") and DB:GetItem("Wool Cloth").id == WOOL)
suite.check("Medium Leather is in the data", DB:GetItem("Medium Leather") ~= nil)
suite.check("Tin Ore is in the data", DB:GetItem("Tin Ore") and DB:GetItem("Tin Ore").id == TIN)

local told = 0
DB.namesWatchers.test = function() told = told + 1 end

DB:OnEnable()
suite.check("nothing read the moment you log in", not DB.learning)
suite.check("the start waits a moment", timers[1] and timers[1].delay == DB.NAMES_START)

-- The first pass, without the retries.
RunTimers(0)
RunTimers(DB.NAMES_START)
suite.check("the names start coming in after login", DB.learning)
suite.check("an item the client did not know is asked for", (asks[LEATHER] or 0) >= 1)
suite.check("Zinnerz is Tin Ore", Finds(ns, "Zinnerz", TIN))
suite.check("Mittleres Leder is Medium Leather", Finds(ns, "Mittleres Leder", LEATHER))
suite.check("the server left Wool Cloth out", not Finds(ns, "Wollstoff", WOOL))
suite.check("the lists are told, not once a name", told >= 1 and told < 5, told)
local toldBefore = told

-- The retry asks again for what the server left out.
RunTimers()
suite.check("Wool Cloth asked for again", asks[WOOL] == 2, asks[WOOL])
suite.check("Wollstoff is Wool Cloth", Finds(ns, "Wollstoff", WOOL))
suite.check("a part of the name finds it", Finds(ns, "wollst", WOOL))
suite.check("named items are not asked again", asks[TIN] == 1, asks[TIN])
suite.check("the late name tells the lists too", told > toldBefore, told)
suite.check("the client's name is kept", DB:ClientName(DB:GetItem("Wool Cloth")) == "Wollstoff")
suite.check("English still finds it", Finds(ns, "Wool Cloth", WOOL))

-- An item the server never names stops being asked after a few passes.
local never = DB:GetItem("Linen Cloth")
suite.check("an item never named is asked a few times only",
    never and asks[never.id] == DB.NAMES_PASSES, never and asks[never.id])

-- The Search tab runs again when names come in.
local UI = ns.UI
suite.check("the search listens for names", type(DB.namesWatchers.search) == "function")
UI.frame = UI.frame or { IsShown = function() return false end }
UI.list = UI.list or {}
UI.lastQuery, UI.searchStale = "Wollstoff", nil
local shown = UI.frame.IsShown
UI.frame.IsShown = function() return false end
DB.namesWatchers.search()
suite.check("out of sight, the search is marked to run again", UI.searchStale == true)
local rendered = 0
local render, chips = UI.Render, UI.BuildChips
UI.Render = function() rendered = rendered + 1 end
UI.BuildChips = function() end
UI.frame.IsShown = function() return true end
UI.tab = "search"
DB.namesWatchers.search()
suite.check("on screen, the search runs again", rendered == 1, rendered)
UI.lastQuery = ""
DB.namesWatchers.search()
suite.check("an empty search box is left alone", rendered == 1, rendered)
UI.Render, UI.BuildChips, UI.frame.IsShown = render, chips, shown

-- Back to an English client for the suites after this one.
_G.GetLocale = nil

suite.done()
