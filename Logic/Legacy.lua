-- Blackthornes Farmer -- Logic/Legacy.lua
-- The Legacy perks that change what you gather and catch (the owner said
-- build it, 2026-10-22).
--
-- Forever's Legacy trees give each character perks of its own choosing. Two
-- of them change what a gather or a cast gives:
--
-- - Bountiful Harvest: more of the scarce materials from herbs, veins and
--   skins;
-- - Luremaster: extra fish while a lure is on the pole.
--
-- A player with them records bigger yields than one without, and those
-- records are what the shipped rates are made from. So the ranks the
-- character has set are read here, and every gather, skin or cast made with
-- one is noted beside the record it went into (`boosted`, the record's own
-- count fields). The player's own numbers stay as they are: what they got
-- is what they got. Only what leaves the save as a rate (the export the
-- shipped data is made from, and every share) leaves the boosted ones out
-- (Legacy.Without, Share's CreditsFor).
--
-- Read only, always: nothing here spends a point or suggests one. Every
-- call is inside a pcall. A client that will not say, or a character
-- whose perks can't be read, has no rank (nil), and everything records as
-- it always has.
--
-- Legacy is a trait config, like the class talents. Its tree is found once a
-- session: by a trait system the client names Legacy, else by looking for
-- the trees that hold its nodes (NODE_FIRST to NODE_LAST), a few trees a
-- frame and never in a fight. The perks are told apart by name, so only an
-- English client reads them for now; another client keeps today's records.

local _, ns = ...

local Legacy = ns.NewModule("Legacy")

-- The perks read, by the English name of their spell.
Legacy.PERKS = {
    harvest = "Bountiful Harvest",
    lure = "Luremaster",
}

-- Where the Legacy trees' nodes sit in the client's numbering.
Legacy.NODE_FIRST = 110284
Legacy.NODE_LAST = 110319
-- Trees looked at for them, how many a frame, and how far past the last one
-- found the look goes on.
Legacy.TREE_LAST = 3000
Legacy.BUDGET = 40
Legacy.TREE_GAP = 50
-- Quiet this long after a talent event before the ranks are read again.
Legacy.SETTLE = 1

-- [perk key] = rank, read last; nil until read.
Legacy.ranks = nil

local function Traits()
    return type(C_Traits) == "table" and C_Traits or nil
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    if ok then return a end
    return nil
end

-- A plain number off the client, or nil (a secret value raises when compared).
local function Number(value)
    if type(value) ~= "number" then return nil end
    local ok, fine = pcall(function() return value == value and value >= 0 end)
    return ok and fine and value or nil
end

local function Text(value)
    if type(value) ~= "string" then return nil end
    local ok, fine = pcall(function() return value ~= "" end)
    return ok and fine and value or nil
end

local function InCombat()
    local ok, fighting = pcall(InCombatLockdown)
    return ok and fighting == true
end

local function InRange(nodeID)
    return type(nodeID) == "number" and nodeID >= Legacy.NODE_FIRST and nodeID <= Legacy.NODE_LAST
end

--------------------------------------------------------------------------------
-- Finding the config
--------------------------------------------------------------------------------

--- The config by a trait system the client calls Legacy, or nil.
function Legacy:ConfigBySystem()
    local traits = Traits()
    local systems = type(Enum) == "table" and type(Enum.TraitSystem) == "table" and Enum.TraitSystem
    if not (traits and systems) then return nil end

    for name, systemID in pairs(systems) do
        if type(name) == "string" and name:lower():find("legacy", 1, true) and type(systemID) == "number" then
            local configID = Number(Call(traits.GetConfigIDBySystemID, systemID))
            if configID and configID > 0 then return configID end
        end
    end
    return nil
end

--- Does tree `treeID` hold a Legacy node?
local function HoldsLegacy(traits, treeID)
    local nodes = Call(traits.GetTreeNodes, treeID)
    if type(nodes) ~= "table" then return false end
    for _, nodeID in ipairs(nodes) do
        if InRange(nodeID) then return true end
    end
    return false
end

--- Look for the Legacy trees a few a frame, then call `done(trees)`.
function Legacy:FindTrees(done)
    local traits = Traits()
    if not (traits and type(traits.GetTreeNodes) == "function") then
        done({})
        return
    end

    local trees, treeID, lastFound = {}, 1, nil
    local function Step()
        if InCombat() then C_Timer.After(2, Step) return end
        local stop = math.min(Legacy.TREE_LAST, treeID + Legacy.BUDGET - 1)
        while treeID <= stop do
            if HoldsLegacy(traits, treeID) then
                trees[#trees + 1] = treeID
                lastFound = treeID
            end
            treeID = treeID + 1
        end
        local finished = treeID > Legacy.TREE_LAST
            or (lastFound and treeID > lastFound + Legacy.TREE_GAP)
        if finished then done(trees) else C_Timer.After(0, Step) end
    end
    Step()
end

--------------------------------------------------------------------------------
-- Reading the ranks
--------------------------------------------------------------------------------

--- The name of the perk a node holds, or nil.
local function NodeName(traits, configID, info)
    local entryID = type(info.activeEntry) == "table" and Number(info.activeEntry.entryID)
    if not entryID and type(info.entryIDs) == "table" then entryID = Number(info.entryIDs[1]) end
    if not entryID then return nil end

    local entry = Call(traits.GetEntryInfo, configID, entryID)
    local definitionID = type(entry) == "table" and Number(entry.definitionID)
    if not definitionID then return nil end

    local definition = Call(traits.GetDefinitionInfo, definitionID)
    if type(definition) ~= "table" then return nil end

    local name = Text(definition.overrideName)
    local spellID = Number(definition.spellID)
    if not name and spellID then
        if type(C_Spell) == "table" then name = Text(Call(C_Spell.GetSpellName, spellID)) end
        if not name then name = Text(Call(GetSpellInfo, spellID)) end
    end
    return name
end

--- How many ranks a node has bought, or nil.
local function NodeRank(info)
    return Number(info.currentRank) or Number(info.activeRank) or Number(info.ranksPurchased)
end

--- The ranks of every perk in PERKS from one config: { [key] = rank } with a
--- 0 for a perk read and not taken, or nil when no Legacy node could be read.
-- `nodes` are the node IDs to look at (NODE_FIRST to NODE_LAST when nil).
function Legacy:ReadConfig(configID, nodes)
    local traits = Traits()
    if not (traits and configID and type(traits.GetNodeInfo) == "function") then return nil end

    if not nodes then
        nodes = {}
        for nodeID = Legacy.NODE_FIRST, Legacy.NODE_LAST do nodes[#nodes + 1] = nodeID end
    end

    local wanted = {}
    for key, name in pairs(Legacy.PERKS) do wanted[name:lower()] = key end

    local ranks, readAny = {}, false
    for _, nodeID in ipairs(nodes) do
        local info = Call(traits.GetNodeInfo, configID, nodeID)
        if type(info) == "table" then
            local name = NodeName(traits, configID, info)
            local rank = NodeRank(info)
            if name and rank then
                readAny = true
                local key = wanted[name:lower()]
                if key then ranks[key] = math.max(ranks[key] or 0, rank) end
            end
        end
    end
    if not readAny then return nil end

    for key in pairs(Legacy.PERKS) do ranks[key] = ranks[key] or 0 end
    return ranks
end

--- Read the ranks again now (the config and trees found already).
function Legacy:Refresh()
    if not self.configs then return end
    local merged
    for _, found in ipairs(self.configs) do
        local ranks = self:ReadConfig(found.configID, found.nodes)
        if ranks then
            merged = merged or {}
            for key, rank in pairs(ranks) do merged[key] = math.max(merged[key] or 0, rank) end
        end
    end
    self.ranks = merged
end

--- Find the Legacy config, then read it. `done` is called once it is read
--- or known not to be there.
function Legacy:Find(done)
    local function Finish()
        self:Refresh()
        if done then pcall(done) end
    end

    local configID = self:ConfigBySystem()
    if configID then
        self.configs = { { configID = configID, nodes = self:NodesIn(configID) } }
        Finish()
        return
    end

    self:FindTrees(function(trees)
        local traits = Traits()
        self.configs = {}
        for _, treeID in ipairs(trees) do
            local id = traits and Number(Call(traits.GetConfigIDByTreeID, treeID))
            if id and id > 0 then
                self.configs[#self.configs + 1] = { configID = id, nodes = Call(traits.GetTreeNodes, treeID) }
            end
        end
        Finish()
    end)
end

--- Every node of a config's trees, or nil to look at the usual range.
function Legacy:NodesIn(configID)
    local traits = Traits()
    local info = traits and Call(traits.GetConfigInfo, configID)
    if type(info) ~= "table" or type(info.treeIDs) ~= "table" then return nil end

    local nodes = {}
    for _, treeID in ipairs(info.treeIDs) do
        local list = Call(traits.GetTreeNodes, treeID)
        if type(list) == "table" then
            for _, nodeID in ipairs(list) do nodes[#nodes + 1] = nodeID end
        end
    end
    return #nodes > 0 and nodes or nil
end

--- A talent event: read the ranks again once things settle.
function Legacy:Changed()
    if not self.configs or self.waiting then return end
    self.waiting = true
    C_Timer.After(Legacy.SETTLE, function()
        self.waiting = false
        self:Refresh()
    end)
end

--------------------------------------------------------------------------------
-- What the rest of the addon asks
--------------------------------------------------------------------------------

--- The rank the character has in a perk ("harvest" or "lure"), or nil when
--- it can't be read.
function Legacy:Rank(key)
    return self.ranks and self.ranks[key] or nil
end

--- Is a lure on the fishing pole? Nil when the client won't say.
function Legacy.LureOn()
    if type(GetWeaponEnchantInfo) ~= "function" then return nil end
    local ok, hasMainHand = pcall(GetWeaponEnchantInfo)
    if not ok then return nil end
    local readable, on = pcall(function() return hasMainHand == true or hasMainHand == 1 end)
    if not readable then return nil end
    return on
end

--- The perk rank behind a gather of `kind` ("herb", "ore" or "skin"), or
--- nil when none: a boosted gather is one made with Bountiful Harvest.
function Legacy:GatherBoost(kind)
    if kind ~= "herb" and kind ~= "ore" and kind ~= "skin" then return nil end
    local rank = self:Rank("harvest")
    return rank and rank > 0 and rank or nil
end

--- The perk rank behind a cast, or nil: Luremaster with a lure on. A pole
--- the client won't read counts as having one, so nothing boosted slips in.
function Legacy:CastBoost()
    local rank = self:Rank("lure")
    if not (rank and rank > 0) then return nil end
    if Legacy.LureOn() == false then return nil end
    return rank
end

--------------------------------------------------------------------------------
-- Noting it on a record
--
-- `boosted` has the record's own shape for the field that counts samples
-- (corpses, gathers or casts): { [field] = n, items = { [name] = { [field],
-- count } }, rank = the highest rank seen }. That is the shape Share takes
-- off what it sends (CreditsFor), so a boosted sample never leaves the save
-- as someone else's rate.
--------------------------------------------------------------------------------

--- The record's boosted tally, made if missing.
function Legacy.Boosted(record, field)
    local boosted = record.boosted
    if type(boosted) ~= "table" then
        boosted = { items = {} }
        record.boosted = boosted
    end
    boosted[field] = tonumber(boosted[field]) or 0
    if type(boosted.items) ~= "table" then boosted.items = {} end
    return boosted
end

--- Note one boosted sample: `items` names (each once), `quantities` how
--- many of each.
function Legacy.Note(record, field, items, quantities, rank)
    local boosted = Legacy.Boosted(record, field)
    boosted[field] = boosted[field] + 1
    if rank then boosted.rank = math.max(tonumber(boosted.rank) or 0, rank) end

    for _, name in ipairs(items or {}) do
        local item = boosted.items[name]
        if type(item) ~= "table" then
            item = { [field] = 0, count = 0 }
            boosted.items[name] = item
        end
        item[field] = (tonumber(item[field]) or 0) + 1
        item.count = (tonumber(item.count) or 0) + (quantities and quantities[name] or 1)
    end
end

--- `record` with its boosted samples taken out, for what leaves the save as
--- a rate: a copy when it has any, else the record itself.
function Legacy.Without(record, field)
    local boosted = type(record) == "table" and record.boosted
    if type(boosted) ~= "table" then return record end

    local copy = {}
    for key, value in pairs(record) do copy[key] = value end
    copy.boosted = nil
    copy[field] = math.max(0, (tonumber(record[field]) or 0) - (tonumber(boosted[field]) or 0))

    local items = {}
    for name, entry in pairs(type(record.items) == "table" and record.items or {}) do
        local taken = type(boosted.items) == "table" and boosted.items[name]
        if type(entry) == "table" and type(taken) == "table" then
            local clean = {}
            for key, value in pairs(entry) do clean[key] = value end
            clean[field] = math.max(0, (tonumber(entry[field]) or 0) - (tonumber(taken[field]) or 0))
            clean.count = math.max(0, (tonumber(entry.count) or 0) - (tonumber(taken.count) or 0))
            if clean[field] > 0 then items[name] = clean end
        else
            items[name] = entry
        end
    end
    copy.items = items
    return copy
end

--- A whole store (name -> record) with the boosted samples taken out, and
--- records left with no samples dropped. The store itself when none is
--- boosted.
function Legacy.WithoutAll(store, field)
    local any = false
    for _, record in pairs(store or {}) do
        if type(record) == "table" and type(record.boosted) == "table" then any = true break end
    end
    if not any then return store end

    local out = {}
    for key, record in pairs(store) do
        local clean = Legacy.Without(record, field)
        if type(clean) ~= "table" or (tonumber(clean[field]) or 0) > 0 then out[key] = clean end
    end
    return out
end

--- One line for /farm gathering check.
function Legacy:CheckLine()
    if not self.configs then return "Legacy perks: not looked for yet" end
    if not self.ranks then
        return ("Legacy perks: can't be read (%d configs found)"):format(#self.configs)
    end
    return ("Legacy perks: Bountiful Harvest %d, Luremaster %d, lure on: %s"):format(
        self.ranks.harvest or 0, self.ranks.lure or 0, tostring(Legacy.LureOn()))
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Legacy:OnEnable()
    local function Changed() Legacy:Changed() end
    for _, event in ipairs { "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED", "TRAIT_CONFIG_LIST_UPDATED" } do
        ns.RegisterEvent(self, event, Changed)
    end

    -- A while after login, so it never adds to the loading.
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(10, function() Legacy:Find() end)
    end
end
