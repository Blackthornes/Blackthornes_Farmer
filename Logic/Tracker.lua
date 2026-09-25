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

    -- Coin and amounts, with how many kills and corpses they were counted
    -- over. A kill's worth needs amounts, not just how often something drops,
    -- and an average is only right over the kills that recorded it.
    --
    -- Coin and amounts were first kept without that count, so they were
    -- divided by every kill, including all the ones from before: coin per
    -- kill came out a fraction of the real thing. A tally from then has no
    -- `coinKills`; its coin and amounts are set aside under old* rather than
    -- deleted, and counting starts clean from this kill.
    if mob.coinKills == nil then
        if (tonumber(mob.copper) or 0) > 0 then
            mob.oldCopper = (tonumber(mob.oldCopper) or 0) + tonumber(mob.copper)
        end
        if type(mob.qty) == "table" and next(mob.qty) then mob.oldQty = mob.qty end

        mob.copper = 0
        mob.qty = {}
        mob.stacks = {}
        mob.coinKills = 0
    end

    if type(mob.qty) ~= "table" then mob.qty = {} end
    if type(mob.stacks) ~= "table" then mob.stacks = {} end
    mob.copper = tonumber(mob.copper) or 0
    mob.coinKills = tonumber(mob.coinKills) or 0

    return mob
end

--- Count one opened corpse. Returns true if it was a new kill.
--
-- `guid` may be nil -- the client can refuse it inside an instance -- and then
-- the corpse cannot be recognised a second time, so every opening counts. That
-- over-counts a skinned corpse, which is the lesser harm next to dropping it.
function Tracker:Record(mobName, guid, items, quantities, copper)
    local mob = self:GetMob(mobName)
    local corpse = guid and self.corpses[guid]
    local newKill = not corpse

    if newKill then
        corpse = {}
        if guid then self.corpses[guid] = corpse end

        mob.kills = mob.kills + 1
        self.session[mobName] = (self.session[mobName] or 0) + 1

        -- Coin is taken on the first opening; a second window on the same
        -- corpse is skinning or leftovers, never more coin. A kill with none
        -- still counts toward the average: that is what "per kill" means.
        mob.copper = mob.copper + (tonumber(copper) or 0)
        mob.coinKills = mob.coinKills + 1
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
            mob.qty[name] = (tonumber(mob.qty[name]) or 0) + quantity
            mob.stacks[name] = (tonumber(mob.stacks[name]) or 0) + 1
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

    -- The kill that unlocks drop rates gets a fanfare.
    if newKill and mob.kills == MIN_KILLS then
        self:Celebrate(mobName)
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

--- Average coin per kill, over the kills that recorded coin; nil before any.
function Tracker:CoinPerKill(mobName)
    local mob = mobName and self:Store()[mobName]
    if type(mob) ~= "table" then return nil end

    local kills = tonumber(mob.coinKills) or 0
    if kills <= 0 then return nil end

    return (tonumber(mob.copper) or 0) / kills
end

--- How many of an item one corpse that held it gave, on average. 1 for an
--- item whose amounts were never recorded.
function Tracker:StackSize(mobName, itemName)
    local mob = mobName and self:Store()[mobName]
    if type(mob) ~= "table" or mob.coinKills == nil then return 1 end

    local qty = type(mob.qty) == "table" and tonumber(mob.qty[itemName])
    local corpses = type(mob.stacks) == "table" and tonumber(mob.stacks[itemName])
    if not (qty and corpses and corpses > 0) then return 1 end

    return qty / corpses
end

--- A mob's whole loot table: its summary, with how many of each item it has
--- given in all and its coin per kill. Nil for a mob never killed.
--
-- Each item gains `perCorpse`, its average stack, and `amount`: corpses that
-- held it times that.
-- `coinPerKill` is nil until a kill has recorded coin.
function Tracker:LootTable(mobName)
    local summary = self:Summary(mobName)
    if not summary then return nil end

    for _, item in ipairs(summary.items) do
        item.perCorpse = self:StackSize(mobName, item.name)
        item.amount = math.floor(item.corpses * item.perCorpse + 0.5)
    end

    summary.coinPerKill = self:CoinPerKill(mobName)
    summary.coinKills = tonumber(self:Store()[mobName].coinKills) or 0

    return summary
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
    return ns.Harvest:CorpseID()
end

--------------------------------------------------------------------------------
-- How an item looks
--
-- The panel draws each item with its icon and in its quality colour, the way
-- the bags do. Both come off the loot window the first time an item is seen
-- and are kept, so the panel can draw them long after the window closed.
--------------------------------------------------------------------------------

-- Quality colours, for links that name a quality rather than spell a colour.
local QUALITY = {
    [0] = "ff9d9d9d", [1] = "ffffffff", [2] = "ff1eff00", [3] = "ff0070dd",
    [4] = "ffa335ee", [5] = "ffff8000", [6] = "ffe6cc80",
}

Tracker.QUALITY = QUALITY

function Tracker:Looks()
    local db = ns.db
    if type(db.tracker) ~= "table" then db.tracker = {} end
    if type(db.tracker.looks) ~= "table" then db.tracker.looks = {} end
    return db.tracker.looks
end

--- An icon as the client gives it: a file id (a number) or a texture path.
local function ReadableIcon(value)
    return ns.Harvest.ReadableNumber(value) or ns.Harvest.Readable(value)
end

--- "ff1eff00" out of an item link, whichever way the link spells its colour.
function Tracker.LinkColor(link)
    if type(link) ~= "string" then return nil end

    local hex = link:match("^|c(%x%x%x%x%x%x%x%x)")
    if hex then return hex:lower() end

    -- Newer clients write |cnIQ2:...| and leave the colour to the client.
    local quality = tonumber(link:match("^|cnIQ(%d)"))
    if quality then return QUALITY[quality] end

    return nil
end

function Tracker:NoteLook(slot, name, icon)
    local looks = self:Looks()
    local look = looks[name]

    if type(look) ~= "table" then
        look = {}
        looks[name] = look
    end

    look.icon = look.icon or ReadableIcon(icon)

    if (not look.color or not look.id) and GetLootSlotLink then
        local ok, link = pcall(GetLootSlotLink, slot)
        local text = ok and ns.Harvest.Readable(link) or nil

        look.color = look.color or Tracker.LinkColor(text)

        -- The item id is what prices are kept by.
        if not look.id and text then
            look.id = tonumber(text:match("item:(%d+)"))
        end
    end
end

function Tracker:LookOf(name)
    local look = self:Looks()[name]
    if type(look) ~= "table" then return {} end
    return look
end

--- Copper in a coin slot's name: "1 Gold 2 Silver 3 Copper" is 10203.
-- Nil for anything that is not plainly coin.
local COIN_VALUE = { Gold = 10000, Silver = 100, Copper = 1 }

function Tracker.CoinCopper(name)
    if not ns.Harvest:NameLooksLikeMoney(name) then return nil end

    local copper = 0
    for amount, unit in name:gmatch("(%d+)%s+(%a+)") do
        copper = copper + tonumber(amount) * (COIN_VALUE[unit] or 0)
    end

    return copper
end

--- The items in the open loot window, each once, coins left out, and how
--- many of each (two slots of one item add up). Third: the coin, in copper.
function Tracker:LootedItems()
    local names, quantities, copper = {}, {}, 0

    local gotCount, lootCount = pcall(GetNumLootItems)
    local count = gotCount and ns.Harvest.ReadableNumber(lootCount) or nil
    if not count then return names, quantities, copper end

    for slot = 1, count do
        local ok, slotIcon, slotName, slotQuantity = pcall(GetLootSlotInfo, slot)
        local name = ok and ns.Harvest.Readable(slotName) or nil

        if name and ns.Harvest:IsMoney(slot, name) then
            copper = copper + (Tracker.CoinCopper(name) or 0)
        elseif name then
            if not quantities[name] then
                names[#names + 1] = name
                quantities[name] = 0
                self:NoteLook(slot, name, slotIcon)
            end

            local quantity = ok and ns.Harvest.ReadableNumber(slotQuantity) or nil
            quantities[name] = quantities[name] + (quantity or 1)
        end
    end

    return names, quantities, copper
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

    local items, quantities, copper = self:LootedItems()

    return self:Record(mobName, self:CorpseID(), items, quantities, copper)
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

-- Sounds to try for the fanfare, best first: the achievement toast, then the
-- level-up chime, which every client has. Ids, since this client's SOUNDKIT
-- names are not known.
local FANFARE = { 12891, 888 }

--- Drop rates just unlocked for `mobName`: a sound and a line in chat.
--
-- Trent asked for it (2026-09-25). The line goes to your own chat window,
-- like every other line from the addon; nothing is said where anyone else can
-- see it. `/farm celebrate off` turns it off.
function Tracker:Celebrate(mobName)
    if ns.db.trackerCelebrate == false then return end

    local summary = self:Summary(mobName)
    if not summary then return end

    local line = ("Drop rates unlocked for %s! %d kills in."):format(
        Util.Colored("accent", summary.mob), summary.kills)

    local best = summary.items[1]
    if best then
        line = line .. (" Best drop: %s %s."):format(best.name,
            Util.Colored("good", Tracker.FormatChance(best.chance)))
    else
        line = line .. " Nothing has dropped yet."
    end

    ns.PrintRaw(("|c%sBlackthornes Farmer:|r %s"):format(ns.COLORS.accent, line))

    if type(PlaySound) == "function" then
        for _, sound in ipairs(FANFARE) do
            local ok, willPlay = pcall(PlaySound, sound, "Master")
            if ok and willPlay ~= false then break end
        end
    end
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

ns.RegisterCommand("celebrate", "sound and cheer when a mob reaches 20 kills (on/off)",
    function(rest)
        local argument = Util.Trim(rest):lower()

        if argument == "on" then
            ns.db.trackerCelebrate = true
        elseif argument == "off" then
            ns.db.trackerCelebrate = false
        else
            ns.db.trackerCelebrate = ns.db.trackerCelebrate == false
        end

        ns.Print(ns.db.trackerCelebrate
            and "a fanfare when a mob's drop rates unlock at 20 kills. /farm celebrate off to stop."
            or "no fanfare when drop rates unlock. /farm celebrate on to bring it back.")
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
