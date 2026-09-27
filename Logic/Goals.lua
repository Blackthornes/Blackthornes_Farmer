-- Blackthornes Farmer -- Logic/Goals.lua
-- Gathering goals (Trent, 2026-09-27): pick a material and a number, and the
-- Goals panel counts you toward it.
--
-- A goal is "have this many", counted from your bags (and your bank, if you
-- tick it), not "loot this many from now": 6 Copper Ore already in the bags
-- count toward 40. So the count is read from the client whenever the bags
-- change, and never kept by hand.
--
-- Only a rise out in the world counts as gathering. With the bank, a mailbox,
-- a vendor, the auction house or a trade open the count still follows the
-- bags, but that change is not loot: it floats nothing and does not feed the
-- pace.
--
-- The pace is worked out from the gathering itself: how many came in, over
-- the time between one loot and the next, with any gap over five minutes
-- counted as five (a break, not slow farming).
--
-- Goals live in BlackthornesFarmerDB.goals. They are your plan, not recorded
-- loot, so removing one removes nothing the addon measured.

local _, ns = ...

local Goals = ns.NewModule("Goals")

local Util = ns.Util

-- The most goals at once. The panel is a column down the side of the screen,
-- and more than this stops being a goal and becomes a shopping list.
Goals.MAX = 6

-- Where the milestones sit, and what each one says.
Goals.MILESTONES = {
    { at = 0.25, tag = "25%" },
    { at = 0.50, tag = "HALFWAY" },
    { at = 0.75, tag = "75%" },
}

-- The last stretch: this share of the goal or less left, and the bar turns
-- green and counts down "3 more!".
Goals.FINAL = 0.1

-- A gap between two loots longer than this is a break; it counts as this.
local BREAK = 300

-- Enough to call it a pace: this many gathered over at least this long.
local PACE_ITEMS = 3
local PACE_SECONDS = 20

-- Windows that move items without looting them: the event that opens each,
-- and the one that closes it.
local AWAY = {
    { open = "BANKFRAME_OPENED", close = "BANKFRAME_CLOSED", kind = "bank" },
    { open = "MAIL_SHOW", close = "MAIL_CLOSED", kind = "mail" },
    { open = "MERCHANT_SHOW", close = "MERCHANT_CLOSED", kind = "vendor" },
    { open = "AUCTION_HOUSE_SHOW", close = "AUCTION_HOUSE_CLOSED", kind = "auction" },
    { open = "TRADE_SHOW", close = "TRADE_CLOSED", kind = "trade" },
}

Goals.away = {}

-- For a few seconds after login, a /reload or a loading screen the bags are
-- still being filled in, and a count going from 0 to 23 is not loot.
local SETTLE = 5
Goals.quietUntil = 0

--------------------------------------------------------------------------------
-- Saved state
--------------------------------------------------------------------------------

function Goals:Store()
    local db = ns.db
    if type(db.goals) ~= "table" then db.goals = {} end

    local store = db.goals
    if type(store.list) ~= "table" then store.list = {} end
    if type(store.today) ~= "table" then store.today = {} end
    return store
end

function Goals:List()
    return self:Store().list
end

--- The goal for `name`, and where it is in the list.
function Goals:Find(name)
    if type(name) ~= "string" then return nil end
    local wanted = Util.Trim(name):lower()

    for index, goal in ipairs(self:List()) do
        if type(goal) == "table" and type(goal.item) == "string"
            and goal.item:lower() == wanted then
            return goal, index
        end
    end

    return nil
end

--- Whether the bank counts toward goals. Off unless asked for.
function Goals:CountsBank()
    return self:Store().bank == true
end

function Goals:SetCountsBank(on)
    self:Store().bank = on and true or false
    self:Update(true)
end

--------------------------------------------------------------------------------
-- The clock and the calendar
--------------------------------------------------------------------------------

local function Now()
    if type(GetTime) == "function" then
        local ok, value = pcall(GetTime)
        if ok and type(value) == "number" then return value end
    end
    return os.time()
end

Goals.Now = Now

--- Today, as the goal-a-day count keys it.
local function Today()
    local fn = type(date) == "function" and date or os.date
    local ok, value = pcall(fn, "%Y-%m-%d")
    return ok and value or "?"
end

--- Goals finished today.
function Goals:DoneToday()
    local today = self:Store().today
    if today.day ~= Today() then return 0 end
    return tonumber(today.count) or 0
end

local function NoteDoneToday(self)
    local today = self:Store().today
    if today.day ~= Today() then
        today.day = Today()
        today.count = 0
    end
    today.count = (tonumber(today.count) or 0) + 1
end

--------------------------------------------------------------------------------
-- Counting
--------------------------------------------------------------------------------

--- How many of `name` you have, or nil when the client will not say.
--
-- Read inside a pcall and made into a plain number there: in an instance
-- the client can hand back a value that raises when it is compared.
function Goals:Have(name)
    local id = ns.Value and ns.Value:ItemID(name)
    local bank = self:CountsBank()

    local fn
    if type(C_Item) == "table" and type(C_Item.GetItemCount) == "function" then
        fn = C_Item.GetItemCount
    elseif type(GetItemCount) == "function" then
        fn = GetItemCount
    end
    if not fn then return nil end

    local ok, count = pcall(function()
        local value = fn(id or name, bank)
        return ns.Harvest.ReadableNumber(value)
    end)

    if not ok or type(count) ~= "number" then return nil end
    return math.max(0, math.floor(count))
end

--------------------------------------------------------------------------------
-- Setting and removing
--------------------------------------------------------------------------------

--- The item a typed name means: the database's own spelling when it knows
--- it, else what you typed, as long as it looks like a name.
function Goals:ResolveItem(text)
    text = Util.Trim(Util.StripColor(text or ""))

    -- An item link: [Copper Ore] out of it.
    local linked = text:match("%[(.-)%]")
    if linked then text = linked end

    if text == "" then return nil end

    local item = ns.DB:GetItem(text)
    if item then return item.name end

    -- Close enough: an alias, or the one item whose name starts with it.
    local wanted = text:lower()
    local matches = {}
    for entry in ns.DB:Iterate() do
        for _, alias in ipairs(entry.aliases or {}) do
            if alias:lower() == wanted then return entry.name end
        end
        if entry.name:lower():sub(1, #wanted) == wanted then
            matches[#matches + 1] = entry.name
        end
    end
    if #matches == 1 then return matches[1] end

    -- Something the database has never heard of can still be a goal: the
    -- bags know it by name.
    return text
end

--- Set (or change) a goal. Returns the goal, or nil and why not.
function Goals:Set(name, target)
    name = self:ResolveItem(name)
    target = math.floor(tonumber(target) or 0)

    if not name then return nil, "no item named" end
    if target < 1 then return nil, "the amount has to be 1 or more" end
    if target > 99999 then return nil, "that is more than anyone could carry" end

    local have = self:Have(name) or 0
    if have >= target then
        return nil, ("you already have %d %s"):format(have, name)
    end

    local goal = self:Find(name)
    local list = self:List()

    if not goal then
        -- A finished goal still on the panel makes room for a new one.
        if #list >= Goals.MAX then
            for index = #list, 1, -1 do
                if list[index].done then table.remove(list, index) break end
            end
        end
        if #list >= Goals.MAX then
            return nil, ("%d goals is the most at once"):format(Goals.MAX)
        end

        goal = { item = name }
        list[#list + 1] = goal
    end

    goal.target = target
    goal.have = have
    goal.start = have
    goal.done = nil
    goal.doneIn = nil
    goal.gained = 0
    goal.loots = 0
    goal.active = 0
    goal.lastGain = nil
    goal.milestone = Goals.MilestoneFor(have / target)

    if ns.GoalsUI then ns.GoalsUI:Refresh() end
    return goal
end

function Goals:Remove(name)
    local goal, index = self:Find(name)
    if not goal then return false end

    table.remove(self:List(), index)
    if ns.GoalsUI then ns.GoalsUI:Refresh() end
    return true
end

--- Take finished goals off the panel.
function Goals:ClearDone()
    local list = self:List()
    local removed = 0
    for index = #list, 1, -1 do
        if list[index].done then
            table.remove(list, index)
            removed = removed + 1
        end
    end
    if removed > 0 and ns.GoalsUI then ns.GoalsUI:Refresh() end
    return removed
end

--------------------------------------------------------------------------------
-- Reading a goal
--------------------------------------------------------------------------------

--- The last milestone at or below `fraction`: 0 for none yet, else its index.
function Goals.MilestoneFor(fraction)
    local reached = 0
    for index, milestone in ipairs(Goals.MILESTONES) do
        if fraction >= milestone.at then reached = index end
    end
    return reached
end

function Goals.Fraction(goal)
    local target = tonumber(goal.target) or 0
    if target <= 0 then return 0 end
    return math.max(0, math.min(1, (tonumber(goal.have) or 0) / target))
end

function Goals.Left(goal)
    return math.max(0, (tonumber(goal.target) or 0) - (tonumber(goal.have) or 0))
end

--- In the last stretch: a few left, and the bar goes green.
function Goals.Final(goal)
    if goal.done then return false end
    local left = Goals.Left(goal)
    return left > 0 and left <= math.max(1, math.floor((goal.target or 0) * Goals.FINAL))
end

--- Seconds to finish at the pace so far, or nil until there is a pace.
function Goals.Eta(goal)
    local gained = tonumber(goal.gained) or 0
    local active = tonumber(goal.active) or 0
    if gained < PACE_ITEMS or active < PACE_SECONDS then return nil end

    return Goals.Left(goal) / (gained / active)
end

--- "18 min 42s", "about 9 min", and so on.
function Goals.Duration(seconds, rough)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))

    if rough then
        if seconds < 60 then return "under a minute" end
        local minutes = math.floor(seconds / 60 + 0.5)
        if minutes < 60 then return ("about %d min"):format(minutes) end
        return ("about %d hr %d min"):format(math.floor(minutes / 60), minutes % 60)
    end

    if seconds < 60 then return ("%ds"):format(seconds) end
    local minutes = math.floor(seconds / 60)
    if minutes < 60 then return ("%d min %ds"):format(minutes, seconds % 60) end
    return ("%d hr %d min"):format(math.floor(minutes / 60), minutes % 60)
end

--- The best place the database knows for an item: the highest drop rate,
--- else the source nearest your level. Nil when it knows none.
function Goals:BestSpot(name)
    local item = ns.DB:GetItem(name)
    if not (item and item.sources and #item.sources > 0) then return nil end

    local best
    for _, source in ipairs(item.sources) do
        if source.chance and (not best or not best.chance or source.chance > best.chance) then
            best = source
        end
    end

    if not best then
        local level = 1
        if type(UnitLevel) == "function" then
            local ok, value = pcall(UnitLevel, "player")
            level = ok and ns.Harvest.ReadableNumber(value) or level
        end

        for _, source in ipairs(ns.Search:SortedSources(item)) do
            local low = source.minLevel or 0
            if not best or low <= level then best = source end
        end
    end

    return best
end

--------------------------------------------------------------------------------
-- Keeping up
--------------------------------------------------------------------------------

--- What each goal's count did since it was last read. `quiet` reads the
--- counts without calling anything gathered (login, the bank tick box).
--
-- Returns a list of { goal, from, to, gathered, milestone, done } for the
-- goals whose count moved, which is what the panel animates.
function Goals:Update(quiet)
    local changes = {}
    local away = next(self.away) ~= nil
    local now = Now()
    if now < (self.quietUntil or 0) then quiet = true end

    for _, goal in ipairs(self:List()) do
        if type(goal) == "table" and not goal.done then
            local have = self:Have(goal.item)
            local was = tonumber(goal.have) or 0

            if have and have ~= was then
                local change = { goal = goal, from = was, to = have }
                goal.have = have

                if have > was and not quiet and not away then
                    change.gathered = have - was
                    goal.gained = (tonumber(goal.gained) or 0) + change.gathered
                    goal.loots = (tonumber(goal.loots) or 0) + 1

                    if goal.lastGain then
                        goal.active = (tonumber(goal.active) or 0)
                            + math.min(BREAK, math.max(0, now - goal.lastGain))
                    end
                    goal.lastGain = now
                end

                -- A milestone once, on the way up; dropping back under one
                -- (crafting, selling) quietly lowers the mark.
                local reached = Goals.MilestoneFor(Goals.Fraction(goal))
                if reached > (goal.milestone or 0) and not quiet then
                    change.milestone = Goals.MILESTONES[reached]
                end
                goal.milestone = reached

                if have >= (tonumber(goal.target) or math.huge) then
                    goal.done = true
                    goal.doneIn = goal.active or 0
                    if not quiet then
                        change.done = true
                        change.milestone = nil
                        NoteDoneToday(self)
                    end
                end

                changes[#changes + 1] = change
            end
        end
    end

    if #changes > 0 and ns.GoalsUI then ns.GoalsUI:Changed(changes) end

    for _, change in ipairs(changes) do
        if change.done then self:Finished(change.goal) end
    end

    return changes
end

--- The recap for a finished goal: { loots, perLoot, worth }. Worth is nil
--- without a price.
function Goals:Recap(goal)
    local loots = tonumber(goal.loots) or 0
    local gained = tonumber(goal.gained) or 0

    local recap = { loots = loots, gained = gained }
    if loots > 0 then recap.perLoot = gained / loots end

    local id = ns.Value:ItemID(goal.item)
    local unit = id and ns.Value:UnitPrice(id)
    if unit then recap.worth = unit * (tonumber(goal.target) or 0) end

    return recap
end

--- A goal just reached its number: a line in chat, and the fanfare.
function Goals:Finished(goal)
    local line = ("Goal done: %s %s!"):format(
        Util.Colored("good", tostring(goal.target)), Util.Colored("accent", goal.item))

    if (tonumber(goal.doneIn) or 0) >= 1 then
        line = line .. (" %s of gathering."):format(Goals.Duration(goal.doneIn))
    end

    ns.PrintRaw(("|c%sBlackthornes Farmer:|r %s"):format(ns.COLORS.accent, line))

    -- The drop-rates-unlocked sound: the one Trent picked for big moments.
    if ns.Tracker and not ns.Tracker.PlayFile(ns.Tracker.SOUNDS.unlock)
        and type(PlaySound) == "function" then
        pcall(PlaySound, 888, "Master")
    end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function Goals:OnEnable()
    self.quietUntil = Now() + SETTLE
    self:Update(true)

    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        Goals.quietUntil = Now() + SETTLE
    end)

    local function Changed() Goals:Update() end
    -- Once per burst of bag changes where the client has it; each change
    -- on a client that does not.
    if not ns.RegisterEvent(self, "BAG_UPDATE_DELAYED", Changed) then
        ns.RegisterEvent(self, "BAG_UPDATE", Changed)
    end

    for _, window in ipairs(AWAY) do
        ns.RegisterEvent(self, window.open, function() Goals.away[window.kind] = true end)
        ns.RegisterEvent(self, window.close, function()
            Goals.away[window.kind] = nil
            -- Whatever moved while it was open is already counted; read the
            -- bags once more so the next loot is measured from here.
            Goals:Update(true)
        end)
    end
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local function PrintGoals()
    local list = Goals:List()
    if #list == 0 then
        ns.Print("no goals yet. /farm goal Copper Ore 40, or the Goal button on a search result.")
        return
    end

    ns.Print("your goals:")
    for _, goal in ipairs(list) do
        local state = goal.done and Util.Colored("good", "done")
            or ("%d left"):format(Goals.Left(goal))
        ns.PrintRaw(("  %s  %d / %d  %s"):format(
            Util.Colored("accent", goal.item), goal.have or 0, goal.target or 0,
            Util.Colored("muted", state)))
    end
end

ns.RegisterCommand("goal", "set a gathering goal: /farm goal Copper Ore 40 (remove, bank on/off)", function(rest)
    rest = Util.Trim(rest)
    local word, after = rest:match("^(%S+)%s*(.*)$")
    word = word and word:lower()

    if rest == "" then
        PrintGoals()
        if ns.GoalsUI then ns.GoalsUI:Show() end
        return
    end

    if word == "remove" or word == "clear" then
        if word == "clear" and after == "" then
            ns.Print(("took %s off the panel."):format(
                Util.Plural(Goals:ClearDone(), "finished goal")))
            return
        end

        local name = Goals:ResolveItem(after)
        if name and Goals:Remove(name) then
            ns.Print(("goal for %s removed."):format(Util.Colored("accent", name)))
        else
            ns.Print(("no goal for %s."):format(after ~= "" and after or "that"))
        end
        return
    end

    if word == "bank" then
        local on = after:lower()
        if on == "on" then Goals:SetCountsBank(true)
        elseif on == "off" then Goals:SetCountsBank(false)
        else Goals:SetCountsBank(not Goals:CountsBank()) end

        ns.Print(Goals:CountsBank()
            and "goals count your bank too."
            or "goals count your bags only.")
        return
    end

    -- "Copper Ore 40", or "40 Copper Ore".
    local name, amount = rest:match("^(.-)%s+(%d+)$")
    if not name then amount, name = rest:match("^(%d+)%s+(.+)$") end

    if not (name and amount) then
        ns.Print("give it a number: /farm goal Copper Ore 40")
        return
    end

    local goal, why = Goals:Set(name, amount)
    if not goal then
        ns.Print(("no goal set: %s."):format(why))
        return
    end

    ns.Print(("goal set: %s %s. You have %d, %d to go."):format(
        Util.Colored("good", tostring(goal.target)), Util.Colored("accent", goal.item),
        goal.have, Goals.Left(goal)))
    if ns.GoalsUI then ns.GoalsUI:Show() end
end)
