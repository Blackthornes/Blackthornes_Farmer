-- Blackthornes Farmer -- Logic/SavedFarms.lua
-- Saved Farms (a player asked on Discord, the owner said build it from a
-- mockup, 2026-11-16): save a farm once and run it again with one click. A
-- farm is an item, where you farm it, how many you want and how (the arrow
-- to a spot, a gather route, a kill goal or the goal alone). Start sets the
-- goal, points the arrow and starts the session timer if you use it; when
-- the run ends it is kept, so the Farms tab shows what each farm made and
-- about what it makes an hour at today's prices.
--
-- On unless unticked ("Saved Farms:" on the Goals page, `savedFarms`;
-- false once unticked, nil means never touched).
-- Only your own play, never shared, never guild data. Saved, account wide
-- (never rename any of these once shipped):
--
--   farmList = { { id, name, item, zone, mob, amount, how, page, daily } }
--              at most MAX farms; how is "spot", "route", "kills" or "goal",
--              page the Grind page a route runs on (herbs, ore, skinning).
--   farmRuns[guid] = the newest KEEP_RUNS runs, newest first:
--              { id, name, at, seconds, got, copper, itemsCopper, items }
--   farmToday[guid] = { day, done = { [id] = true }, added = { [id] = true } }
--   lastFarmOnSearch = false hides the Last Farm strip on Search (nil: on).
--
-- One key per character: runs and today's list are kept under the GUID
-- (Goals:Owner), and a GUID the client won't read writes nothing.

local _, ns = ...
local L = ns.L

local SavedFarms = ns.NewModule("SavedFarms")

local Util = ns.Util

SavedFarms.MAX = 20         -- farms in the list
SavedFarms.KEEP_RUNS = 10   -- runs kept for each character
SavedFarms.MIN_SECONDS = 30 -- a run shorter than this with nothing got is not kept
SavedFarms.RATE_SECONDS = 60 -- runs under this long in all give no An Hour
SavedFarms.CACHE = 60       -- seconds an An Hour is kept before working it out again
SavedFarms.DEFAULT_AMOUNT = 20

SavedFarms.HOWS = { "spot", "route", "kills", "goal" }

-- The Grind page a gathered item's route runs on, by its category.
SavedFarms.PAGES = { Herbalism = "herbs", Mining = "ore", Leatherworking = "skinning" }

-- Bumped whenever a farm, a run or today's list changes, so the tab redraws.
SavedFarms.version = 0

-- The run under way, in memory only: { id, guid, started, clock, have,
-- kills, copper, banked, timer }. A /reload or logging out ends it.
SavedFarms.run = nil

local function Now()
    return type(time) == "function" and time() or os.time()
end

local function Day(at)
    local fn = type(date) == "function" and date or os.date
    local ok, value = pcall(fn, "%Y-%m-%d", at)
    return ok and value or "?"
end
SavedFarms.Day = Day

local function Number(value)
    return ns.Harvest and ns.Harvest.ReadableNumber(value) or tonumber(value)
end

local function Say(text)
    ns.PrintRaw(("|c%sBlackthornes Farmer:|r %s"):format(ns.COLORS.accent, text))
end

local function Changed()
    SavedFarms.version = SavedFarms.version + 1
    SavedFarms.rates = nil
    if ns.SavedFarmsUI and ns.SavedFarmsUI.Changed then pcall(ns.SavedFarmsUI.Changed, ns.SavedFarmsUI) end
end
SavedFarms.Changed = Changed

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

function SavedFarms.On()
    return ns.db ~= nil and ns.db.savedFarms ~= false
end

function SavedFarms:SetOn(on)
    ns.db.savedFarms = on and true or false
    if not on and self.run then self:End("off") end
    if ns.UI and ns.UI.RefreshTabs then pcall(ns.UI.RefreshTabs, ns.UI) end
    Changed()
end

--- The Last Farm strip on the Search tab: on unless unticked, and only
--- while Saved Farms is on.
function SavedFarms.LastOnSearch()
    return SavedFarms.On() and ns.db.lastFarmOnSearch ~= false
end

function SavedFarms:SetLastOnSearch(on)
    if on then ns.db.lastFarmOnSearch = nil else ns.db.lastFarmOnSearch = false end
    Changed()
end

--------------------------------------------------------------------------------
-- Saved state
--------------------------------------------------------------------------------

--- The character playing, or nil while the client won't say.
function SavedFarms.Me()
    return ns.Goals and ns.Goals:Owner() or nil
end

--- The saved farms, in the order they were saved.
function SavedFarms:List()
    local db = ns.db
    if type(db.farmList) ~= "table" then return {} end
    local list = {}
    for _, farm in ipairs(db.farmList) do
        if type(farm) == "table" and farm.id ~= nil then list[#list + 1] = farm end
    end
    return list
end

function SavedFarms:Find(id)
    if id == nil then return nil end
    for index, farm in ipairs(type(ns.db.farmList) == "table" and ns.db.farmList or {}) do
        if type(farm) == "table" and farm.id == id then return farm, index end
    end
    return nil
end

--- A new id: one past the highest any farm or run has, so a removed
--- farm's runs never pass to a new one.
function SavedFarms:NextID()
    local high = 0
    for _, farm in ipairs(type(ns.db.farmList) == "table" and ns.db.farmList or {}) do
        if type(farm) == "table" then high = math.max(high, tonumber(farm.id) or 0) end
    end
    for _, runs in pairs(type(ns.db.farmRuns) == "table" and ns.db.farmRuns or {}) do
        if type(runs) == "table" then
            for _, run in ipairs(runs) do
                if type(run) == "table" then high = math.max(high, tonumber(run.id) or 0) end
            end
        end
    end
    return high + 1
end

--- This character's runs, newest first. `make` makes the list.
function SavedFarms:Runs(make)
    local guid = self.Me()
    if not guid then return make and nil or {} end
    if type(ns.db.farmRuns) ~= "table" then
        if not make then return {} end
        ns.db.farmRuns = {}
    end
    local runs = ns.db.farmRuns[guid]
    if type(runs) ~= "table" then
        if not make then return {} end
        runs = {}
        ns.db.farmRuns[guid] = runs
    end
    return runs
end

--- This character's day: what is done and what was added. Starts fresh
--- each day. Nil while the client won't say who is playing.
function SavedFarms:Today(make)
    local guid = self.Me()
    if not guid then return nil end
    if type(ns.db.farmToday) ~= "table" then
        if not make then return nil end
        ns.db.farmToday = {}
    end
    local today = ns.db.farmToday[guid]
    if type(today) ~= "table" then
        if not make then return nil end
        today = {}
        ns.db.farmToday[guid] = today
    end
    if today.day ~= Day() then
        if not make then return nil end
        today.day, today.done, today.added = Day(), {}, {}
    end
    if type(today.done) ~= "table" then today.done = {} end
    if type(today.added) ~= "table" then today.added = {} end
    return today
end

--------------------------------------------------------------------------------
-- Saving, changing and removing
--------------------------------------------------------------------------------

local function Clean(text)
    if type(text) ~= "string" then return nil end
    text = Util.Trim(text)
    if text == "" then return nil end
    return text
end

--- The Grind page for an item's route: herbs, ore or skinning, else nil.
function SavedFarms.PageFor(item)
    local found = type(item) == "string" and ns.DB and ns.DB:GetItem(item)
    return found and SavedFarms.PAGES[found.category] or nil
end

--- How a new farm for `item` starts out: a route for herbs, ore and
--- leather, else the arrow to the spot.
function SavedFarms.DefaultHow(item)
    if SavedFarms.PageFor(item) then return "route" end
    return "spot"
end

--- A farm made from what the Save Farm box holds. Returns the farm, or nil
--- and why.
local function Shape(fields, farm)
    farm = farm or {}
    local how = fields.how
    local known = false
    for _, key in ipairs(SavedFarms.HOWS) do
        if key == how then known = true end
    end
    if not known then how = "goal" end

    local item = Clean(fields.item)
    if item and ns.Goals and ns.Goals.ResolveItem then
        item = ns.Goals:ResolveItem(item) or item
    end
    local name = Clean(fields.name) or item or Clean(fields.mob)
    if not name then return nil, L["no item named"] end
    if how ~= "kills" and how ~= "route" and not item then return nil, L["no item named"] end

    local amount = math.floor(tonumber(fields.amount) or 0)
    if how ~= "route" and amount < 1 then return nil, L["the amount has to be 1 or more"] end
    if amount > 99999 then return nil, L["that is more than anyone could carry"] end

    farm.name = name
    farm.item = item
    farm.zone = Clean(fields.zone)
    farm.mob = Clean(fields.mob)
    farm.amount = amount > 0 and amount or nil
    farm.how = how
    farm.page = how == "route" and (fields.page or SavedFarms.PageFor(item) or farm.page) or nil
    farm.daily = fields.daily and true or nil
    return farm
end

--- Save a new farm. Returns it, or nil and why.
function SavedFarms:Save(fields)
    if not self.On() then
        Say(L["Turn on Saved Farms in Settings first."])
        return nil
    end
    if #self:List() >= SavedFarms.MAX then
        Say(L.Format("You can save up to %d farms.", SavedFarms.MAX))
        return nil
    end
    local farm, why = Shape(fields or {})
    if not farm then return nil, why end
    farm.id = self:NextID()
    if type(ns.db.farmList) ~= "table" then ns.db.farmList = {} end
    table.insert(ns.db.farmList, farm)
    Say(L.Format("Saved %s to your farms.", Util.ColorItemOr("accent", farm.item or farm.name, nil, farm.name)))
    Changed()
    return farm
end

--- Change a saved farm. Returns it, or nil and why.
function SavedFarms:Edit(id, fields)
    local farm = self:Find(id)
    if not farm then return nil end
    local copy = {}
    for key, value in pairs(farm) do copy[key] = value end
    local shaped, why = Shape(fields or {}, copy)
    if not shaped then return nil, why end
    for key in pairs(farm) do farm[key] = nil end
    for key, value in pairs(shaped) do farm[key] = value end
    farm.id = id
    Changed()
    return farm
end

--- Take a farm off the list. Its runs stay, so nothing farmed is lost.
function SavedFarms:Remove(id)
    local farm, index = self:Find(id)
    if not farm then return false end
    table.remove(ns.db.farmList, index)
    local today = self:Today()
    if today then today.added[id] = nil end
    Changed()
    return true
end

--------------------------------------------------------------------------------
-- Today's list
--------------------------------------------------------------------------------

--- Is `farm` on today's list: ticked Every Day, or added today.
function SavedFarms:OnToday(farm)
    if type(farm) ~= "table" then return false end
    if farm.daily then return true end
    local today = self:Today()
    return today ~= nil and today.added[farm.id] == true
end

function SavedFarms:DoneToday(farm)
    local today = type(farm) == "table" and self:Today()
    return today and today.done[farm.id] == true or false
end

--- Add to Today, or take it back off when it was added by hand.
function SavedFarms:ToggleToday(id)
    local farm = self:Find(id)
    local today = farm and self:Today(true)
    if not today then return false end
    today.added[id] = (not today.added[id]) and true or nil
    Changed()
    return true
end

--- Today's farms, in the saved order, and how many are done.
function SavedFarms:TodayList()
    local list, done = {}, 0
    for _, farm in ipairs(self:List()) do
        if self:OnToday(farm) then
            list[#list + 1] = farm
            if self:DoneToday(farm) then done = done + 1 end
        end
    end
    return list, done
end

--- Mark a farm done for today.
function SavedFarms:MarkDone(farm)
    local today = farm and self:Today(true)
    if not today or today.done[farm.id] then return false end
    today.done[farm.id] = true
    if self:OnToday(farm) then
        Say(L.Format("%s is done for today.", Util.ColorItemOr("accent", farm.item or farm.name, nil, farm.name)))
    end
    Changed()
    return true
end

--------------------------------------------------------------------------------
-- Gold an hour
--------------------------------------------------------------------------------

local function UnitPrice(item)
    if type(item) ~= "string" or not ns.Value then return nil end
    local id = ns.Value:ItemID(item)
    return id and ns.Value:UnitPrice(id) or nil
end
SavedFarms.UnitPrice = UnitPrice

--- What a run is worth at today's prices: its item repriced, the rest of
--- what it gathered as it was.
function SavedFarms.WorthNow(run, item)
    local copper = tonumber(run.copper) or 0
    local got = tonumber(run.got) or 0
    if run.kills or not item or got <= 0 then return copper end
    local unit = UnitPrice(item)
    if not unit then return copper end
    local then_ = tonumber(run.itemsCopper) or 0
    return math.max(0, copper - then_) + unit * got
end

--- Copper an hour for one run, or nil when it was too short to say.
function SavedFarms.RunRate(run, item)
    local seconds = tonumber(run.seconds) or 0
    if seconds < SavedFarms.RATE_SECONDS then return nil end
    return SavedFarms.WorthNow(run, item) / seconds * 3600
end

--- Every character's runs of farm `id`.
function SavedFarms:RunsOf(id)
    local found = {}
    for _, runs in pairs(type(ns.db.farmRuns) == "table" and ns.db.farmRuns or {}) do
        if type(runs) == "table" then
            for _, run in ipairs(runs) do
                if type(run) == "table" and run.id == id then found[#found + 1] = run end
            end
        end
    end
    return found
end

--- About what `farm` makes an hour, in copper, and where it came from
--- ("runs" or "pace"), or nil. Your own runs at today's prices; before the
--- first run, how fast you got the item before times its price. Kill farms
--- only ever from their runs. Kept CACHE seconds, or until a farm moves.
function SavedFarms:AnHour(farm)
    if type(farm) ~= "table" then return nil end
    local now = Now()
    local rates = self.rates
    if not rates or now - (rates.at or 0) > SavedFarms.CACHE then
        rates = { at = now, by = {} }
        self.rates = rates
    end
    local cached = rates.by[farm.id]
    if cached then return cached.copper, cached.from end

    local copper, from
    local seconds, worth = 0, 0
    for _, run in ipairs(self:RunsOf(farm.id)) do
        local s = tonumber(run.seconds) or 0
        if s > 0 then
            seconds = seconds + s
            worth = worth + SavedFarms.WorthNow(run, farm.how ~= "kills" and farm.item or nil)
        end
    end
    if seconds >= SavedFarms.RATE_SECONDS then
        copper, from = worth / seconds * 3600, "runs"
    elseif farm.how ~= "kills" and farm.item and ns.Pace then
        local pace = ns.Pace:ForItem(farm.item)
        local unit = UnitPrice(farm.item)
        if pace and unit and (tonumber(pace.seconds) or 0) > 0 then
            copper, from = 3600 / pace.seconds * unit, "pace"
        end
    end
    rates.by[farm.id] = { copper = copper, from = from }
    return copper, from
end

--- The newest run of farm `id` on this character, or nil.
function SavedFarms:LastRunOf(id)
    for _, run in ipairs(self:Runs()) do
        if type(run) == "table" and run.id == id then return run end
    end
    return nil
end

--- How long ago `at` was, in the Farms tab's words.
function SavedFarms.When(at, now)
    at = tonumber(at)
    if not at then return L["Never"] end
    now = now or Now()
    local days = 0
    local today, that = Day(now), Day(at)
    if today ~= that then
        days = math.max(1, math.floor((now - at) / 86400 + 0.5))
        if days == 0 then days = 1 end
    end
    if days == 0 then return L["Today"] end
    if days == 1 then return L["Yesterday"] end
    if days < 7 then return L.Format("%d days ago", days) end
    return L["Last week"]
end

--- "26 min", "1 hr 5 min".
function SavedFarms.Duration(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local minutes = math.floor(seconds / 60 + 0.5)
    if minutes < 60 then return L.Format("%d min", minutes) end
    return L.Format("%d hr %d min", math.floor(minutes / 60), minutes % 60)
end

--------------------------------------------------------------------------------
-- Running a farm
--------------------------------------------------------------------------------

local function SessionCopper()
    local ok, copper = pcall(function() return ns.Value:Session() end)
    return ok and tonumber(copper) or 0
end

local function KillsNow()
    local goal = ns.KillGoal and ns.KillGoal:Current()
    return goal and tonumber(goal.have) or 0
end

--- Start `id`: set the goal, point the arrow or run the route, and start
--- the session timer if you use it. Returns true when it started.
function SavedFarms:Start(id)
    if not self.On() then
        Say(L["Turn on Saved Farms in Settings first."])
        return false
    end
    local farm = self:Find(id)
    local guid = self.Me()
    if not (farm and guid) then return false end

    if self.run then self:End("switch") end

    local amount = tonumber(farm.amount) or 0
    local have = farm.item and ns.Goals and ns.Goals:Have(farm.item) or 0

    if farm.how == "kills" then
        local goal, why = ns.KillGoal:Start(amount > 0 and amount or 100, farm.mob)
        if not goal then
            if why then Say(L.Format("Couldn't start it: %s.", why)) end
            return false
        end
    elseif farm.item and amount > 0 then
        local goal, why = ns.Goals:Set(farm.item, have + amount)
        if not goal then
            if why then Say(L.Format("Couldn't start it: %s.", why)) end
            return false
        end
    end

    if farm.how == "spot" and farm.item and ns.Arrow then
        if farm.mob and farm.zone then
            pcall(ns.Arrow.Aim, ns.Arrow, farm.item, { name = farm.mob, zone = farm.zone }, true)
        elseif farm.zone and ns.Arrow.AimZone then
            -- Any Mob: the closest spot in the zone, then the next one there.
            pcall(ns.Arrow.AimZone, ns.Arrow, farm.item, farm.zone)
        else
            pcall(ns.Arrow.Follow, ns.Arrow, farm.item)
        end
    elseif farm.how == "route" then
        self:StartRoute(farm)
    end

    local timer = false
    local T = ns.SessionTimer
    if T and T.On() and T.state == "ready" then timer = T:Start() and true or false end

    self.run = {
        id = farm.id, guid = guid, started = Now(), have = have,
        kills = KillsNow(), copper = SessionCopper(), timer = timer,
    }
    Say(L.Format("Started your %s farm.", Util.ColorItemOr("accent", farm.item or farm.name, nil, farm.name)))
    if ns.GoalsUI and ns.GoalsUI.Show and farm.how ~= "route" then pcall(ns.GoalsUI.Show, ns.GoalsUI) end
    Changed()
    return true
end

--- A route farm: the Grind tab on its page, Route Mode on and the route
--- walked, when the Gather Route is on in Settings; else just the page.
function SavedFarms:StartRoute(farm)
    local page = farm.page
    if not page then return false end
    local Grinding, Route = ns.Grinding, ns.GatherRoute
    if Grinding and Grinding.SetGives then pcall(Grinding.SetGives, Grinding, page) end
    local started = false
    if Route and Route.IsOn() and Route.PAGES[page] then
        if not Route.RouteMode(page) then Route:SetRouteMode(page, true) end
        Route:SetPage(Route.PAGES[page])
        local ok, did = pcall(Route.Start, Route)
        started = ok and did and true or false
    end
    if ns.UI and ns.UI.ShowTab then
        pcall(function()
            if not (ns.UI.frame and ns.UI.frame:IsShown()) then ns.UI:Show() end
            ns.UI:ShowTab("grind")
        end)
    end
    return started
end

--- Repeat: start the farm of this character's newest run again.
function SavedFarms:Repeat()
    local last = self:LastFarm()
    if not last then return false end
    return self:Start(last.farm.id)
end

--- This character's newest run whose farm is still saved: { farm, run }.
function SavedFarms:LastFarm()
    for _, run in ipairs(self:Runs()) do
        local farm = type(run) == "table" and self:Find(run.id)
        if farm then return { farm = farm, run = run } end
    end
    return nil
end

--- The farm running now, or nil.
function SavedFarms:Running()
    local run = self.run
    if not run then return nil end
    return self:Find(run.id)
end

--- End the run under way and keep it. `reached` marks it done for today.
--- Returns the run kept, or nil.
function SavedFarms:End(why, reached)
    local active = self.run
    if not active then return nil end
    self.run = nil
    local farm = self:Find(active.id)

    local seconds = math.max(0, Now() - (active.started or Now()))
    local T = ns.SessionTimer
    if active.timer and T and T.state ~= "ready" then seconds = T:Seconds() end

    local got, kills = 0, nil
    if farm and farm.how == "kills" then
        got = math.max(0, KillsNow() - (active.kills or 0))
        kills = true
    elseif farm and farm.item then
        local have = ns.Goals and ns.Goals:Have(farm.item) or nil
        got = have and math.max(0, have - (active.have or 0)) or 0
    end

    local unit = farm and not kills and UnitPrice(farm.item)
    local itemsCopper = unit and unit * got or 0
    local copper = (active.banked or 0) + SessionCopper() - (active.copper or 0)
    if copper < itemsCopper then copper = itemsCopper end

    -- The run is kept only on the character it started on.
    local runs = active.guid == self.Me() and self:Runs(true)
    if not farm or not runs or (seconds < SavedFarms.MIN_SECONDS and got <= 0) then
        Changed()
        return nil
    end

    local run = {
        id = farm.id, name = farm.name, at = Now(), seconds = math.floor(seconds),
        got = got, copper = math.floor(copper), itemsCopper = math.floor(itemsCopper),
        kills = kills,
    }
    if farm.item and not kills then run.items = { [farm.item] = got } end
    table.insert(runs, 1, run)
    while #runs > SavedFarms.KEEP_RUNS do table.remove(runs) end

    local amount = tonumber(farm.amount) or 0
    if reached or (farm.how == "route" and seconds >= SavedFarms.RATE_SECONDS)
        or (amount > 0 and got >= amount) then
        self:MarkDone(farm)
    end
    Changed()
    return run
end

--- Clear panel is about to empty the counts (Session:Clear): what the run
--- gathered so far is set aside, and it counts on from an empty panel.
function SavedFarms:PanelClearing()
    local active = self.run
    if not active then return end
    active.banked = (active.banked or 0) + math.max(0, SessionCopper() - (active.copper or 0))
    active.copper = 0
end

--------------------------------------------------------------------------------
-- When a run ends by itself
--------------------------------------------------------------------------------

--- Its goal is done: the run ends, done for today.
function SavedFarms:GoalDone(goal)
    local farm = self:Running()
    if not (farm and type(goal) == "table") then return end
    if goal.kills then
        if farm.how == "kills" then self:End("goal", true) end
    elseif type(goal.item) == "string" and farm.item and goal.item:lower() == farm.item:lower() then
        self:End("goal", true)
    end
end

function SavedFarms:OnEnable()
    -- Goals, the kill goal and the session timer say when a run ends; each
    -- is wrapped once and calls through first, so nothing they do changes.
    local Goals, KillGoal, T = ns.Goals, ns.KillGoal, ns.SessionTimer
    if Goals and not Goals.savedFarmsWrapped then
        local finished = Goals.Finished
        Goals.Finished = function(goals, goal, ...)
            local result = finished(goals, goal, ...)
            pcall(SavedFarms.GoalDone, SavedFarms, goal)
            return result
        end
        Goals.savedFarmsWrapped = true
    end
    if KillGoal and not KillGoal.savedFarmsWrapped then
        local finished = KillGoal.Finished
        KillGoal.Finished = function(killGoal, goal, ...)
            local result = finished(killGoal, goal, ...)
            pcall(SavedFarms.GoalDone, SavedFarms, goal)
            return result
        end
        KillGoal.savedFarmsWrapped = true
    end
    if T and not T.savedFarmsWrapped then
        local stop = T.Stop
        T.Stop = function(timer, ...)
            local active = SavedFarms.run
            if active and active.timer then pcall(SavedFarms.End, SavedFarms, "timer") end
            -- Your Run offers Save This Farm only for a run that was no
            -- saved farm.
            SavedFarms.justEnded = active ~= nil and active.timer or nil
            local results = { stop(timer, ...) }
            SavedFarms.justEnded = nil
            return unpack(results)
        end
        T.savedFarmsWrapped = true
    end
    ns.RegisterEvent(self, "PLAYER_LOGOUT", self.PLAYER_LOGOUT)
end

--- Logging out (or a /reload) ends the run under way.
function SavedFarms:PLAYER_LOGOUT()
    if SavedFarms.run then pcall(SavedFarms.End, SavedFarms, "logout") end
end

--------------------------------------------------------------------------------
-- /farm farms [on|off] and /farm repeat
--------------------------------------------------------------------------------

ns.RegisterCommand("farms", L["Turns Saved Farms on or off."], function(rest)
    local argument = Util.Trim(rest or ""):lower()
    local on
    if argument == "on" then on = true
    elseif argument == "off" then on = false
    else on = not SavedFarms.On() end
    SavedFarms:SetOn(on)
    ns.Print(L["Saved Farms:"] .. " " .. (on and L["On"] or L["Off"]))
    if ns.SettingsUI and ns.SettingsUI.Refresh then pcall(ns.SettingsUI.Refresh, ns.SettingsUI) end
end)

ns.RegisterCommand("repeat", L["Starts your last farm again."], function()
    if not SavedFarms.On() then
        Say(L["Turn on Saved Farms in Settings first."])
        return
    end
    if not SavedFarms:Repeat() and not SavedFarms:LastFarm() then
        Say(L["Your runs show here once you finish one."])
    end
end)
