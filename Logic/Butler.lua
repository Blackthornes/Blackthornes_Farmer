-- Blackthornes Farmer -- Logic/Butler.lua
-- One answer for Blackthornes Butler (2026-10-10), the sister addon that
-- tells the player what to do with each item in the bags.
--
-- Butler asks, inside a pcall and read only, whether a goal of the
-- character playing needs an item:
--
--     _G.BlackthornesFarmer.Butler:Advise(itemID)
--
-- and gets { goal, have, target, need }, or nil when no goal of this
-- character is for that item. A goal saved before goals had owners counts
-- for everyone, as Goals:Find has it. It never raises and never writes.
--
-- Butler asks once per bag item when it judges the bags, a hundred times in
-- a burst, so the goals are laid out once as a lookup by item ID and by
-- name, and kept until a goal is set, changed or taken off (Goals.version)
-- or the character's name comes in. Only an item that has a goal reads its
-- count from the client. Butler's side is its Logic/Sisters.lua.

local _, ns = ...

local Butler = ns.NewModule("Butler")

-- Item ID -> its name, as the client said it. Only what it said is kept: an
-- item it has not loaded yet is asked again next time.
Butler.names = {}

--- The name the client gives an item ID, or nil while it will not say.
function Butler:NameOf(itemID)
    local known = self.names[itemID]
    if known then return known end

    local name
    if type(C_Item) == "table" and type(C_Item.GetItemInfo) == "function" then
        local ok, value = pcall(C_Item.GetItemInfo, itemID)
        name = ok and value or nil
    elseif type(GetItemInfo) == "function" then
        local ok, value = pcall(GetItemInfo, itemID)
        name = ok and value or nil
    end

    name = name and ns.Harvest.Readable(name)
    if type(name) ~= "string" or name == "" then return nil end

    self.names[itemID] = name
    return name
end

--- This character's goals by item ID and by name (lower case), built again
--- only when the goals or the character changed.
function Butler:Lookup()
    local Goals = ns.Goals
    local list = Goals:Store().list
    local owner = Goals:Owner()
    local key = table.concat({ tostring(Goals.version), tostring(owner), tostring(list), #list }, "|")

    if self.lookup and self.lookupKey == key then return self.lookup end

    local byID, byName = {}, {}
    for _, goal in ipairs(Goals:List()) do
        if type(goal.item) == "string" then
            local name = goal.item:lower()
            byName[name] = byName[name] or goal
            local id = ns.Value and ns.Value:ItemID(goal.item)
            if id and not byID[id] then byID[id] = goal end
        end
    end

    self.lookup = { byID = byID, byName = byName }
    self.lookupKey = key
    return self.lookup
end

local function Advise(self, itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end

    local lookup = self:Lookup()
    -- No goals here: nothing to ask the client.
    if next(lookup.byName) == nil then return nil end

    local goal = lookup.byID[itemID]
    if not goal then
        local name = self:NameOf(itemID)
        goal = name and lookup.byName[name:lower()]
    end
    if not goal then return nil end

    local target = math.max(0, math.floor(tonumber(goal.target) or 0))
    local have = ns.Goals:Have(goal.item, itemID) or tonumber(goal.have) or 0

    return {
        goal = goal.item,
        have = have,
        target = target,
        need = math.max(0, target - have),
    }
end

--- What this character's goal for `itemID` still needs: { goal, have,
--- target, need }, or nil for no goal. Never raises.
function Butler:Advise(itemID)
    local ok, answer = pcall(Advise, self, itemID)
    if ok then return answer end
    return nil
end
