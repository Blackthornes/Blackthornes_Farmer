-- Blackthornes Farmer -- Logic/Containers.lua
-- What clams and other things you open give.
--
-- Two kinds. A clam, a lockbox or a sack you right-click in your bags opens a
-- loot window that is nobody's corpse, so the harvester and the kill tally
-- never saw it, or, with a looted corpse still targeted and a client that
-- would not say where the loot came from, could put a pearl down as that
-- mob's drop. And a Giant Clam or a chest out in the world opens one too.
--
-- A bag item counts when its window opens within OPEN_SECONDS of the click
-- and the client says it holds loot (or, when it won't say, the window names
-- an item as its source). With no click seen, a window that names an item in
-- the bags as its source, and no creature, is that item's. Each opening is one, kept by the
-- item's name in `containers.opened`, account wide, with how many of the
-- openings gave each item and how many came out. Nothing says where a clam
-- was opened, which says nothing about where it came from: Where? reads the
-- places the clam itself drops (Spots:Candidates).
--
-- A world object counts only when the loot window names a GameObject and no
-- creature, and its name is known from the object in front of you, the
-- tooltip just shown, or the cast that opened it. It goes in the gathering record
-- as a "container", where it is, so Where? lists it like a herb you picked.
-- No name, nothing recorded: never a guess.
--
-- A disenchant opens a loot window that names the item broken as its source
-- too, so it looked just like a clam. It is not one: gear is never a
-- container, and a window that opens just after your own Disenchant is the
-- spell's. Those windows are still kept off the corpse you have targeted,
-- and nothing is counted. Gear counted as opened before this is left in the
-- save as it is, and never read.
--
-- Everything is kept in saved variables. Nothing is sent anywhere.

local _, ns = ...

local Containers = ns.NewModule("Containers")

-- How long after the click on a bag item its loot window may open. Opening a
-- clam is quick; a corpse looted later is not the clam's.
Containers.OPEN_SECONDS = 3

-- How long a cast's target or a tooltip names the object opened after it.
Containers.NAME_SECONDS = 5

-- How long after your Disenchant goes through its loot window may open.
Containers.BREAK_SECONDS = 5

-- Spells that break an item into its parts: Disenchant.
Containers.BREAK_SPELLS = { [13262] = true }

--- The client's clock in seconds, or nil if it will not say.
local function Now()
    if type(GetTime) ~= "function" then return nil end
    local ok, now = pcall(GetTime)
    return ok and ns.Harvest.ReadableNumber(now) or nil
end

local function Recent(at, seconds)
    local now = Now()
    return at ~= nil and now ~= nil and now - at >= 0 and now - at <= seconds
end

--- A spell's name in the client's language, or nil.
local function SpellName(spellID)
    if type(C_Spell) == "table" and type(C_Spell.GetSpellName) == "function" then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        local text = ok and ns.Harvest.Readable(name) or nil
        if text then return text end
    end

    if type(GetSpellInfo) == "function" then
        local ok, name = pcall(GetSpellInfo, spellID)
        return ok and ns.Harvest.Readable(name) or nil
    end
end

--- Is this spell one that breaks an item, such as Disenchant? By its ID, or
--- by its name matching one of theirs, in case the client gives another ID.
function Containers.IsBreakSpell(spellID)
    local id = ns.Harvest.ReadableNumber(spellID)
    if not id then return false end
    if Containers.BREAK_SPELLS[id] then return true end

    local name = SpellName(id)
    if not name then return false end
    for known in pairs(Containers.BREAK_SPELLS) do
        if SpellName(known) == name then return true end
    end
    return name == "Disenchant"
end

--- Is this item a weapon or armour? Gear is never a clam or a sack, so a
--- window it opens is a disenchant. False when the client will not say.
function Containers.IsGear(id)
    local WorldDrops = ns.WorldDrops
    if not (id and WorldDrops and WorldDrops.IsGear) then return false end
    local ok, gear = pcall(WorldDrops.IsGear, id)
    return ok and gear == true
end

--------------------------------------------------------------------------------
-- The record
--------------------------------------------------------------------------------

--- Every bag item opened: [name] = { id, opens, items = { [name] = { opens, count, id } } }.
function Containers:Store()
    local db = ns.db

    if type(db.containers) ~= "table" then db.containers = {} end
    if type(db.containers.opened) ~= "table" then db.containers.opened = {} end

    return db.containers.opened
end

--- One opened item's entry, or nil. Gear counted before disenchants were
--- told apart is skipped, never deleted.
function Containers:Entry(name)
    local entry = name and self:Store()[name]
    if type(entry) ~= "table" or Containers.IsGear(entry.id) then return nil end
    return entry
end

--- Count one opening of `name`. `items` are names, each once; `quantities`
--- how many of each came out.
function Containers:Record(name, id, items, quantities)
    local store = self:Store()
    local entry = store[name]

    if type(entry) ~= "table" then
        entry = {}
        store[name] = entry
    end

    entry.opens = (tonumber(entry.opens) or 0) + 1
    entry.id = entry.id or id
    -- The search reads openings again when this moves.
    Containers.changes = (Containers.changes or 0) + 1
    if type(entry.items) ~= "table" then entry.items = {} end

    for _, item in ipairs(items or {}) do
        local got = entry.items[item]

        if type(got) ~= "table" then
            got = { opens = 0, count = 0 }
            entry.items[item] = got
        end

        got.opens = (tonumber(got.opens) or 0) + 1
        got.count = (tonumber(got.count) or 0) + (quantities and quantities[item] or 1)
        got.id = got.id or ns.Tracker:LookOf(item).id
    end

    return entry
end

--- Every bag item opened that gave `itemName`: { name, opens, got }, most
--- opened first.
function Containers:Holding(itemName)
    local list = {}

    for name, entry in pairs(self:Store()) do
        local got = type(entry) == "table" and type(entry.items) == "table" and entry.items[itemName]
        local times = type(got) == "table" and tonumber(got.opens) or 0
        if times > 0 and Containers.IsGear(entry.id) then times = 0 end
        if times > 0 then
            list[#list + 1] = { name = name, opens = tonumber(entry.opens) or 0, got = times }
        end
    end

    table.sort(list, function(a, b)
        if a.opens ~= b.opens then return a.opens > b.opens end
        return a.name < b.name
    end)

    return list
end

--------------------------------------------------------------------------------
-- A bag item opened
--------------------------------------------------------------------------------

--- The item in a bag slot: id, name, and whether the client says it holds
--- loot (nil when it will not say).
function Containers.SlotItem(bag, slot)
    if type(C_Container) == "table" and type(C_Container.GetContainerItemInfo) == "function" then
        local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
        if ok and type(info) == "table" then
            local link = ns.Harvest.Readable(info.hyperlink)
            local hasLoot
            pcall(function()
                if info.hasLoot == true then hasLoot = true
                elseif info.hasLoot == false then hasLoot = false end
            end)
            return ns.Harvest.ReadableNumber(info.itemID),
                link and link:match("%[(.-)%]"), hasLoot
        end
    end

    if type(GetContainerItemInfo) == "function" then
        local ok, _, _, _, _, _, lootable, link, _, _, id = pcall(GetContainerItemInfo, bag, slot)
        if ok then
            link = ns.Harvest.Readable(link)
            local hasLoot
            pcall(function()
                if lootable == true or lootable == 1 then hasLoot = true
                elseif lootable == false then hasLoot = false end
            end)
            return ns.Harvest.ReadableNumber(id), link and link:match("%[(.-)%]"), hasLoot
        end
    end
end

--- You used something in your bags. Remembered unless the client says it
--- holds no loot; one it would not say about (`unsure`) counts only when the
--- loot window names an item as its source.
function Containers:OnUsed(bag, slot)
    local id, name, hasLoot = Containers.SlotItem(bag, slot)
    if hasLoot == false or not name or Containers.IsGear(id) then return end

    self.opening = { id = id, name = name, at = Now(), unsure = hasLoot ~= true }
end

-- The bags looked through for the item a loot window names: the backpack,
-- the four bags and the reagent bag.
Containers.BAGS = { 0, 1, 2, 3, 4, 5 }

--- The bag item with this guid: id and name, or nil.
function Containers.ItemByGuid(guid)
    if not (type(C_Item) == "table" and type(C_Item.GetItemGUID) == "function"
        and type(ItemLocation) == "table" and type(ItemLocation.CreateFromBagAndSlot) == "function"
        and type(C_Container) == "table" and type(C_Container.GetContainerNumSlots) == "function") then
        return nil
    end

    for _, bag in ipairs(Containers.BAGS) do
        local gotSlots, slots = pcall(C_Container.GetContainerNumSlots, bag)
        slots = gotSlots and ns.Harvest.ReadableNumber(slots) or 0
        for slot = 1, slots do
            local ok, found = pcall(function()
                return C_Item.GetItemGUID(ItemLocation:CreateFromBagAndSlot(bag, slot))
            end)
            if ok and ns.Harvest.Readable(found) == guid then
                local id, name = Containers.SlotItem(bag, slot)
                if name then return id, name end
            end
        end
    end
end

--- Did this loot window come from something other than a corpse or a node?
local function SourceKinds()
    local kinds = {}
    for _, guid in ipairs(ns.Harvest:LootSources()) do
        local kind = type(guid) == "string" and guid:match("^(%a+)%-") or nil
        if kind then kinds[kind] = true end
    end
    return kinds
end

--- The bag item the window names as its source, found by its guid, when
--- no creature is named with it. Kept for the window.
function Containers:FromSource()
    local itemGuid
    for _, guid in ipairs(ns.Harvest:LootSources()) do
        local kind = type(guid) == "string" and guid:match("^(%a+)%-") or nil
        if kind == "Creature" then return nil end
        if kind == "Item" then itemGuid = itemGuid or guid end
    end
    if not itemGuid then return nil end

    if self.sourced and self.sourced.guid == itemGuid then return self.sourced end

    local id, name = Containers.ItemByGuid(itemGuid)
    if not name then return nil end

    self.sourced = { id = id, name = name, guid = itemGuid, broken = Containers.IsGear(id) }
    return self.sourced
end

--- Did your Disenchant (or another spell that breaks an item) just go
--- through, and does this window name an item and no creature?
function Containers:IsBreaking()
    local kinds = SourceKinds()
    if kinds.Creature then return false end

    local breaking = self.breaking
    if breaking and (breaking.looted or Recent(breaking.at, Containers.BREAK_SECONDS)) then
        return true
    end

    local sourced = kinds.Item and self:FromSource() or nil
    return sourced ~= nil and sourced.broken == true
end

--- The bag item this window is from, or nil. Never a disenchant.
function Containers:Opening()
    local opening = self.opening
    if opening and opening.looted then return opening end

    if self:IsBreaking() then
        if self.breaking then self.breaking.looted = true end
        return nil
    end

    if opening and Recent(opening.at, Containers.OPEN_SECONDS) then
        -- The client says where the loot came from: a corpse is a corpse.
        local kinds = SourceKinds()
        if not (kinds.Creature and not kinds.Item) and (kinds.Item or not opening.unsure) then
            return opening
        end
    end

    -- No click seen (the game's bag button may not go through the call we
    -- watch): the window's own source, when it names an item in the bags.
    local sourced = self:FromSource()
    if sourced and sourced.broken then return nil end
    return sourced
end

--------------------------------------------------------------------------------
-- An object in the world opened
--------------------------------------------------------------------------------

--- The cast that may open an object: what it named. A Disenchant is only
--- noted, so its window is not taken for a clam.
function Containers:OnCastSent(unit, target, _, spellID)
    if ns.Harvest.Readable(unit) ~= "player" then return end
    if Containers.IsBreakSpell(spellID) then
        self.breaking = { at = Now() }
        self.cast = nil
        return
    end
    local name = ns.Harvest.Readable(target)
    self.cast = name and { name = name, at = Now() } or nil
end

--- A cast went through: a Disenchant's window opens next.
function Containers:OnCastSucceeded(unit, _, spellID)
    if ns.Harvest.Readable(unit) ~= "player" then return end
    if Containers.IsBreakSpell(spellID) then self.breaking = { at = Now() } end
end

--- The name of the object this window is from, or nil.
function Containers:ObjectName()
    -- The object in front of you, when the client calls it one.
    if type(UnitGUID) == "function" and type(UnitName) == "function" then
        local ok, guid = pcall(UnitGUID, "softinteract")
        guid = ok and ns.Harvest.Readable(guid) or nil
        if guid and guid:match("^GameObject%-") then
            local gotName, name = pcall(UnitName, "softinteract")
            name = gotName and ns.Harvest.Readable(name) or nil
            if name then return name end
        end
    end

    local hovered = ns.Gathering and ns.Gathering.hovered
    if hovered and Recent(hovered.at, Containers.NAME_SECONDS) then return hovered.name end

    local cast = self.cast
    if cast and Recent(cast.at, Containers.NAME_SECONDS) then return cast.name end
end

--- Is this window an object's in the world (a Giant Clam, a chest)?
function Containers:IsObject()
    local kinds = SourceKinds()
    return kinds.GameObject == true and not kinds.Creature
end

--------------------------------------------------------------------------------
-- The loot window
--------------------------------------------------------------------------------

--- Is the open loot window something opened, not a corpse? The harvester
--- and the kill tally ask, as they ask about nodes (Harvest:IsNodeLoot).
function Containers:Claims()
    if self:Opening() then return true end
    -- A disenchant is no corpse's loot either; it is just not counted.
    if self:IsBreaking() then return true end
    if ns.Gathering and ns.Gathering:IsGathering() then return false end
    return self:IsObject()
end

function Containers:OnLoot()
    if ns.db.harvestPaused then return end
    if ns.Fishing and ns.Fishing:IsCatch() then return end
    if ns.Gathering and ns.Gathering:IsGathering() then return end

    local opening = self:Opening()
    if opening then
        -- One window is one opening.
        if opening.looted then return end
        opening.looted = true

        local items, quantities = ns.Tracker:LootedItems(true)
        local entry = self:Record(opening.name, opening.id, items, quantities)
        if ns.OpenNote then
            pcall(ns.OpenNote.Show, ns.OpenNote, opening.name, entry.id or opening.id, entry.opens)
        end
        return entry
    end

    if not self:IsObject() or self.objectLooted then return end

    local name = self:ObjectName()
    if not name then return end
    self.objectLooted = true
    self.cast = nil

    local zone, location = ns.Harvest:Where()
    local items, quantities = ns.Tracker:LootedItems(true)
    local mapID, x, y = ns.Harvest:PlayerMapPosition()

    return ns.Gathering:Record(zone, location, name, "container", items, quantities,
        mapID and { x * 100, y * 100 } or nil)
end

function Containers:OnLootClosed()
    if self.opening and self.opening.looted then self.opening = nil end
    if self.sourced and self.sourced.looted then self.sourced = nil end
    if self.sourced and self.sourced.broken then self.sourced = nil end
    if self.breaking and self.breaking.looted then self.breaking = nil end
    self.objectLooted = nil
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Containers:OnEnable()
    if not ns.Harvest:Capabilities().usable then return end

    ns.OnLootWindow(self, function() Containers:OnLoot() end)
    ns.RegisterEvent(self, "LOOT_CLOSED", function() Containers:OnLootClosed() end)

    ns.RegisterPlayerEvent(self, "UNIT_SPELLCAST_SENT", function(_, _, ...)
        Containers:OnCastSent(...)
    end)
    ns.RegisterPlayerEvent(self, "UNIT_SPELLCAST_SUCCEEDED", function(_, _, ...)
        Containers:OnCastSucceeded(...)
    end)

    -- A post-hook: it runs after the game's own call and changes nothing.
    if type(hooksecurefunc) == "function" then
        local function Used(bag, slot) pcall(Containers.OnUsed, Containers, bag, slot) end
        if type(C_Container) == "table" and type(C_Container.UseContainerItem) == "function" then
            pcall(hooksecurefunc, C_Container, "UseContainerItem", Used)
        end
        if type(UseContainerItem) == "function" then
            pcall(hooksecurefunc, "UseContainerItem", Used)
        end
    end
end
