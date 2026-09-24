-- Blackthornes Farmer -- Logic/Tracker.lua
-- A running tally of what you kill, and what they drop.
--
-- The harvester keeps the evidence for the data files. This is the view from
-- the saddle: loot a corpse and you see how many of that mob you have killed,
-- and once there are enough of them to mean something, how often each item
-- has turned up.
--
-- A kill is a corpse you opened. That is the only kill this addon can see with
-- its contents attached, and a drop rate needs both halves. One corpse opened
-- twice -- skinned after looting, or come back to for what was left -- is still
-- one kill, which is why each corpse is remembered by its guid for the session.
--
-- Below MIN_KILLS the panel shows counts, never percentages: three drops in
-- five kills is not a 60% drop rate, it is five kills.
--
-- Reporting to chat is off unless asked for, and it goes to your own chat
-- window only. Nothing is ever said on a channel anyone else can read.

local _, ns = ...

local Tracker = ns.NewModule("Tracker")

local Util = ns.Util

-- The harvester's export threshold, for the same reason.
local MIN_KILLS = 20

-- How many items a chat report names before it stops.
local REPORT_ITEMS = 4

Tracker.MIN_KILLS = MIN_KILLS

-- This session only: kills per mob, and every corpse opened, by guid, with the
-- items already counted from it.
Tracker.session = {}
Tracker.corpses = {}

-- Also this session only: how much of each item came off your kills, and the
-- order mobs were last killed in, so the panel can put the latest on top.
Tracker.sessionLoot = {}
Tracker.recent = {}
Tracker.clock = 0

--------------------------------------------------------------------------------
-- The tally
--------------------------------------------------------------------------------

--- Every mob's tally, kept in saved variables from one session to the next.
function Tracker:Store()
    local db = ns.db

    if type(db.tracker) ~= "table" then db.tracker = {} end
    if type(db.tracker.mobs) ~= "table" then db.tracker.mobs = {} end

    return db.tracker.mobs
end

function Tracker:GetMob(name)
    local mobs = self:Store()
    local mob = mobs[name]

    if type(mob) ~= "table" then
        mob = {}
        mobs[name] = mob
    end

    mob.kills = tonumber(mob.kills) or 0
    if type(mob.items) ~= "table" then mob.items = {} end

    return mob
end

--- Count one opened corpse. Returns true if it was a new kill.
--
-- `guid` may be nil -- the client can refuse it inside an instance -- and then
-- the corpse cannot be recognised a second time, so every opening counts. That
-- over-counts a skinned corpse, which is the lesser harm next to dropping it.
function Tracker:Record(mobName, guid, items, quantities)
    local mob = self:GetMob(mobName)
    local corpse = guid and self.corpses[guid]
    local newKill = not corpse

    if newKill then
        corpse = {}
        if guid then self.corpses[guid] = corpse end

        mob.kills = mob.kills + 1
        self.session[mobName] = (self.session[mobName] or 0) + 1
    end

    -- An item counts once per corpse, however many slots or visits it took.
    -- Leftovers seen again on a return visit add nothing to the loot total
    -- either: they were counted the first time the window showed them.
    for _, name in ipairs(items or {}) do
        if not corpse[name] then
            corpse[name] = true
            mob.items[name] = (tonumber(mob.items[name]) or 0) + 1

            local quantity = quantities and quantities[name] or 1
            self.sessionLoot[name] = (self.sessionLoot[name] or 0) + quantity
        end
    end

    self.current = mobName
    self.clock = self.clock + 1
    self.recent[mobName] = self.clock

    if ns.TrackerUI then
        ns.TrackerUI:Refresh()
    end

    if newKill and ns.db.trackerReport then
        self:Report(mobName)
    end

    return newKill
end

--- One mob's tally, items best-seen first.
function Tracker:Summary(mobName)
    local mob = mobName and self:Store()[mobName]
    if type(mob) ~= "table" then return nil end

    local kills = tonumber(mob.kills) or 0
    local items = {}

    for name, corpses in pairs(type(mob.items) == "table" and mob.items or {}) do
        corpses = tonumber(corpses) or 0
        items[#items + 1] = {
            name = name,
            corpses = corpses,
            chance = kills > 0 and math.min(100, corpses / kills * 100) or 0,
        }
    end

    table.sort(items, function(a, b)
        if a.corpses ~= b.corpses then return a.corpses > b.corpses end
        return a.name < b.name
    end)

    return {
        mob = mobName,
        kills = kills,
        session = self.session[mobName] or 0,
        rated = kills >= MIN_KILLS,
        needed = math.max(0, MIN_KILLS - kills),
        items = items,
    }
end

--- Every mob killed this session, most recent first, as summaries.
function Tracker:SessionMobs()
    local mobs = {}

    for name in pairs(self.session) do
        local summary = self:Summary(name)
        if summary then mobs[#mobs + 1] = summary end
    end

    table.sort(mobs, function(a, b)
        return (self.recent[a.mob] or 0) > (self.recent[b.mob] or 0)
    end)

    return mobs
end

--- This session's loot, most first: { name, count }.
function Tracker:SessionLoot()
    local loot = {}

    for name, count in pairs(self.sessionLoot) do
        loot[#loot + 1] = { name = name, count = count }
    end

    table.sort(loot, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)

    return loot
end

--- This session's kills, all mobs together.
function Tracker:SessionKills()
    local total = 0
    for _, kills in pairs(self.session) do total = total + kills end
    return total
end

--- "43%", "7.5%", "<1%": whole numbers once they are big enough not to care.
function Tracker.FormatChance(chance)
    if chance > 0 and chance < 1 then return "<1%" end
    if chance < 10 then
        return (("%.1f"):format(chance):gsub("%.0$", "")) .. "%"
    end
    return ("%d%%"):format(math.floor(chance + 0.5))
end

--- A mob named loosely, the way a person types it: exact, then a prefix.
function Tracker:ResolveMob(text)
    text = Util.Trim(text):lower()
    if text == "" then return self.current end

    local prefix

    for name in pairs(self:Store()) do
        local lowered = name:lower()
        if lowered == text then return name end
        if lowered:sub(1, #text) == text and (not prefix or name < prefix) then
            prefix = name
        end
    end

    return prefix
end

function Tracker:Reset()
    ns.db.tracker = nil
    self.session = {}
    self.corpses = {}
    self.sessionLoot = {}
    self.recent = {}
    self.current = nil

    if ns.TrackerUI then ns.TrackerUI:Refresh() end
end

--------------------------------------------------------------------------------
-- Reading the loot window
--------------------------------------------------------------------------------

--- The corpse's guid, if the client will say. Read, not compared, like every
--- other value off this client.
function Tracker:CorpseID()
    if not UnitGUID then return nil end

    local ok, guid = pcall(UnitGUID, "target")
    if not ok then return nil end

    return ns.Harvest.Readable(guid)
end

--- The items in the open loot window, each once, coins left out, and how
--- many of each (two slots of one item add up).
function Tracker:LootedItems()
    local names, quantities = {}, {}

    local gotCount, lootCount = pcall(GetNumLootItems)
    local count = gotCount and ns.Harvest.ReadableNumber(lootCount) or nil
    if not count then return names, quantities end

    for slot = 1, count do
        local ok, _, slotName, slotQuantity = pcall(GetLootSlotInfo, slot)
        local name = ok and ns.Harvest.Readable(slotName) or nil

        if name and not ns.Harvest:IsMoney(slot, name) then
            if not quantities[name] then
                names[#names + 1] = name
                quantities[name] = 0
            end

            local quantity = ok and ns.Harvest.ReadableNumber(slotQuantity) or nil
            quantities[name] = quantities[name] + (quantity or 1)
        end
    end

    return names, quantities
end

function Tracker:OnLoot()
    local caps = ns.Harvest:Capabilities()
    if not caps.usable then return end

    -- Fishing pools and chests are not kills.
    if caps.fishingLoot then
        local ok, fishing = pcall(IsFishingLoot)
        if ok and fishing then return end
    end

    -- Same rule as the harvester: if the target is not plainly the corpse,
    -- count nothing rather than count it against the wrong mob.
    local mobName = ns.Harvest:LootSource()
    if not mobName then return end

    local items, quantities = self:LootedItems()

    return self:Record(mobName, self:CorpseID(), items, quantities)
end

--------------------------------------------------------------------------------
-- Chat
--------------------------------------------------------------------------------

--- The one line a kill reports, or nil if the mob has no tally.
function Tracker:ReportLine(mobName)
    local summary = self:Summary(mobName)
    if not summary then return nil end

    local line = ("%s: kill %d (%d this session)"):format(
        Util.Colored("accent", summary.mob), summary.kills, summary.session)

    if not summary.rated then
        return line .. Util.Colored("muted",
            (", %d more for drop rates."):format(summary.needed))
    end

    if #summary.items == 0 then
        return line .. Util.Colored("muted", ", nothing dropped yet.")
    end

    local parts = {}

    for index = 1, math.min(#summary.items, REPORT_ITEMS) do
        local item = summary.items[index]
        parts[#parts + 1] = ("%s %s"):format(item.name,
            Util.Colored("good", Tracker.FormatChance(item.chance)))
    end

    return line .. ". " .. table.concat(parts, ", ")
end

function Tracker:Report(mobName)
    local line = self:ReportLine(mobName)
    if line then ns.Print(line) end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Tracker:OnEnable()
    if not ns.Harvest:Capabilities().usable then return end

    ns.RegisterEvent(self, "LOOT_OPENED", function() Tracker:OnLoot() end)
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

ns.RegisterCommand("tracker", "show or hide the kill and loot panel", function(rest)
    local argument = Util.Trim(rest):lower()

    if argument == "reset" then
        ns.Print("this clears every kill tally, for good. "
            .. "Type /farm tracker reset confirm to do it.")
        return
    end

    if argument == "reset confirm" then
        Tracker:Reset()
        ns.Print("kill tallies cleared.")
        return
    end

    if argument == "on" then
        ns.db.trackerHidden = false
    elseif argument == "off" then
        ns.db.trackerHidden = true
    else
        ns.db.trackerHidden = not ns.db.trackerHidden
    end

    if ns.TrackerUI then ns.TrackerUI:Refresh() end

    if ns.db.trackerHidden then
        ns.Print("kill and loot panel hidden. /farm tracker brings it back.")
    else
        ns.Print("kill and loot panel shown. /farm tracker hides it.")
    end
end)

ns.RegisterCommand("report", "report each kill's tally in chat (on/off)", function(rest)
    local argument = Util.Trim(rest):lower()

    if argument == "on" then
        ns.db.trackerReport = true
    elseif argument == "off" then
        ns.db.trackerReport = false
    else
        ns.db.trackerReport = not ns.db.trackerReport
    end

    if ns.db.trackerReport then
        ns.Print("reporting each kill in chat. Only you can see it. /farm report off to stop.")
    else
        ns.Print("kill reports off.")
    end
end)

ns.RegisterCommand("kills", "a mob's kill tally and drop rates", function(rest)
    local mobName = Tracker:ResolveMob(rest or "")
    local summary = mobName and Tracker:Summary(mobName)

    if not summary then
        local wanted = Util.Trim(rest or "")
        if wanted == "" then
            ns.Print("nothing killed yet. Loot something and try again.")
        else
            ns.Print(("no kills of %s yet."):format(wanted))
        end
        return
    end

    ns.Print(Tracker:ReportLine(mobName))

    -- The chat line names the top few; this names them all.
    if summary.rated and #summary.items > REPORT_ITEMS then
        for index = REPORT_ITEMS + 1, #summary.items do
            local item = summary.items[index]
            ns.PrintRaw(("  %s %s"):format(item.name,
                Util.Colored("muted", Tracker.FormatChance(item.chance))))
        end
    elseif not summary.rated then
        for _, item in ipairs(summary.items) do
            ns.PrintRaw(("  %s %s"):format(item.name,
                Util.Colored("muted", ("%d of %d"):format(item.corpses, summary.kills))))
        end
    end
end)
