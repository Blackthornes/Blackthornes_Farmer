-- The kill count on a mob's tooltip.
--
-- What matters: a mob you can attack shows 0/20 in red before its first kill
-- and counts up as corpses are opened; from 20 kills it shows the whole count
-- and what a kill is worth; friendly NPCs, players, pets and critters get
-- nothing until killed; the line goes on once however often the tooltip
-- redraws; hovering writes no tally; the setting and /farm killcount turn it
-- off; and a dungeon's secret name costs nothing worse than the line.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("killtooltip")

local ns = env.Load({ ui = true })
local KillTooltip = ns.KillTooltip

-- Off unless ticked (2026-10-15), with a What's New card that offers it.
suite.check("off by default", ns.DEFAULTS.killTooltip == false and not KillTooltip:IsEnabled())
local card
for _, tip in ipairs(ns.WHATS_NEW_TIPS or {}) do
    if tip.key == "killTooltip" then card = tip end
end
suite.check("What's New has a card for it", card ~= nil and type(card.paragraphs) == "table")
suite.check("the card is due while it is off", card and card.due() == true)
card.run()
suite.check("its button turns it on", ns.db.killTooltip == true and KillTooltip:IsEnabled())
suite.check("and then the card is not due", card.due() == false)

-- A save that had it on from the old default is turned off once, and a
-- choice made after that is left alone.
local saved = BlackthornesFarmerDB
BlackthornesFarmerDB = { killTooltip = true }
ns.LoadSavedVariables()
suite.check("an old save's default on goes off once", ns.db.killTooltip == false and ns.db.killTooltipOffOnce == true)
ns.db.killTooltip = true
ns.LoadSavedVariables()
suite.check("and is left on once ticked again", ns.db.killTooltip == true)
BlackthornesFarmerDB = saved
ns.LoadSavedVariables()
suite.check("back on for the rest of the tests", KillTooltip:IsEnabled())

local now = 1000
_G.GetTime = function() return now end

-- The mob under the mouse.
local hovered = {}
local targetName, targetGuid = _G.UnitName, _G.UnitGUID
_G.UnitName = function(unit)
    if unit == "mouseover" then return hovered.name end
    return targetName(unit)
end
_G.UnitGUID = function(unit)
    if unit == "mouseover" then return hovered.guid end
    return targetGuid(unit)
end
local isPlayer = _G.UnitIsPlayer
_G.UnitIsPlayer = function(unit)
    if unit == "mouseover" then return hovered.player == true end
    return isPlayer(unit)
end
_G.UnitPlayerControlled = function(unit) return unit == "mouseover" and hovered.pet == true end
_G.UnitCanAttack = function(_, unit) return unit == "mouseover" and hovered.friendly ~= true end
_G.UnitCreatureType = function(unit) return unit == "mouseover" and (hovered.kind or "Humanoid") or nil end

local function Tooltip()
    local tooltip = {
        _lines = {}, _colors = {},
        AddLine = function(self, text, r) self._lines[#self._lines + 1] = text; self._colors[#self._lines] = r end,
        NumLines = function(self) return #self._lines end,
        GetUnit = function() return hovered.name, "mouseover" end,
        Show = function() end,
    }
    _G.GameTooltip = tooltip
    return tooltip
end

local serial = 0
local function Hover(mob)
    hovered = mob
    serial = serial + 1
    if not mob.guid then
        mob.guid = ("Creature-0-1-2-3-%d-%08d"):format(mob.id or 1234, serial)
    end
    local tooltip = Tooltip()
    local outcome = KillTooltip:OnTooltip(tooltip, { guid = mob.guid })
    return outcome, tooltip._lines[1], tooltip._colors[1], tooltip
end

local corpses = 0
local function Kill(name, n)
    for _ = 1, n do
        corpses = corpses + 1
        env.world.target = { name = name, level = 10, dead = true, guid = "Creature-0-1-2-3-99-C" .. corpses }
        env.world.loot = { { name = "Copper Ore", id = 2770 } }
        ns.Tracker:OnLoot()
    end
end

--------------------------------------------------------------------------------
-- Before 20
--------------------------------------------------------------------------------

local outcome, line, red = Hover({ name = "Kobold Miner" })
suite.check("a mob never killed gets a line", outcome == "added", outcome)
suite.check("it reads 0/20", line == "Kills: 0/20", line)
suite.check("in red", red and math.abs(red - 0.898) < 0.01, red)
suite.check("hovering made no tally", ns.db.tracker == nil or ns.db.tracker.mobs == nil
    or ns.db.tracker.mobs["Kobold Miner"] == nil)

Kill("Kobold Miner", 7)
outcome, line = Hover({ name = "Kobold Miner" })
suite.check("it counts up with each kill", line == "Kills: 7/20", line)

local tooltip
outcome, line, red, tooltip = Hover({ name = "Kobold Miner", guid = "Creature-0-1-2-3-40-AAA" })
suite.check("a redraw does not add it twice",
    KillTooltip:OnTooltip(tooltip, { guid = "Creature-0-1-2-3-40-AAA" }) == "duplicate")
suite.check("still one line", #tooltip._lines == 1, #tooltip._lines)
tooltip._lines = {}
suite.check("a fresh showing gets it again",
    KillTooltip:OnTooltip(tooltip, { guid = "Creature-0-1-2-3-40-AAA" }) == "added")

--------------------------------------------------------------------------------
-- From 20
--------------------------------------------------------------------------------

-- Copper Ore sells for 1s 50c at a vendor.
local unitPrice = ns.Value.UnitPrice
ns.Value.UnitPrice = function() return 150, "vendor" end

Kill("Kobold Miner", 13)
outcome, line, red = Hover({ name = "Kobold Miner" })
suite.check("at 20 the count is whole", (line or ""):find("Kills: 20", 1, true) == 1, line)
suite.check("and no longer red", red and red > 0.9, red)
local worth, details = ns.Value:ForMob("Kobold Miner")
suite.check("from your own kills", details and details.basis == "tally")
suite.check("with the worth Farmer gives a kill",
    (line or ""):find(", worth " .. ns.Value.Coins(worth) .. " each", 1, true) ~= nil, line)
suite.check("which is 1s 50c", worth == 150, worth)

Kill("Kobold Miner", 1)
outcome, line = Hover({ name = "Kobold Miner" })
suite.check("and keeps counting", (line or ""):find("Kills: 21", 1, true) == 1, line)

ns.Value.UnitPrice = function() return nil end
KillTooltip.ForgetKept()
outcome, line = Hover({ name = "Kobold Miner" })
suite.check("with nothing priced it is the count alone", line == "Kills: 21", line)
ns.Value.UnitPrice = unitPrice

--------------------------------------------------------------------------------
-- Best drops
--------------------------------------------------------------------------------

-- A tooltip that takes two-sided lines, as the game's does.
local function DropsTip()
    local tip = Tooltip()
    tip._right = {}
    tip.AddDoubleLine = function(self, left, right)
        self._lines[#self._lines + 1] = left
        self._right[#self._lines] = right
    end
    return tip
end

local function HoverDrops(mob)
    hovered = mob
    serial = serial + 1
    mob.guid = mob.guid or ("Creature-0-1-2-3-%d-%08d"):format(1234, serial)
    local tip = DropsTip()
    KillTooltip:OnTooltip(tip, { guid = mob.guid })
    return tip
end

-- Gnoll Brutes drop four things, each its own worth.
local prices = { ["Linen Cloth"] = 120, ["Malachite"] = 600, ["Brute Tooth"] = 30, ["Ruined Pelt"] = 4 }
ns.Value.UnitPrice = function(_, id)
    for name, copper in pairs(prices) do
        if ns.Value:ItemID(name) == id then return copper, "vendor" end
    end
    return nil
end
local itemID = ns.Value.ItemID
local ids = { ["Linen Cloth"] = 2589, ["Malachite"] = 774, ["Brute Tooth"] = 9001, ["Ruined Pelt"] = 9002 }
ns.Value.ItemID = function(_, name) return ids[name] end

for i = 1, 20 do
    corpses = corpses + 1
    env.world.target = { name = "Gnoll Brute", level = 10, dead = true, guid = "Creature-0-1-2-3-77-G" .. corpses }
    local loot = { { name = "Linen Cloth", id = 2589 } }
    if i <= 2 then loot[#loot + 1] = { name = "Malachite", id = 774 } end
    if i <= 10 then loot[#loot + 1] = { name = "Brute Tooth", id = 9001 } end
    if i <= 1 then loot[#loot + 1] = { name = "Ruined Pelt", id = 9002 } end
    env.world.loot = loot
    ns.Tracker:OnLoot()
end
KillTooltip.ForgetKept()

local tip = HoverDrops({ name = "Gnoll Brute" })
suite.check("under the count comes Best drops", tip._lines[2] == "Best drops", tip._lines[2])
suite.check("the best first: linen every kill", (tip._lines[3] or ""):find("Linen Cloth", 1, true) ~= nil, tip._lines[3])
suite.check("with how often it drops", (tip._lines[3] or ""):find("100%", 1, true) ~= nil, tip._lines[3])
suite.check("and what it adds to a kill", tip._right[3] == ns.Value.Coins(120), tip._right[3])
suite.check("then malachite, 10% of 6s", (tip._lines[4] or ""):find("Malachite", 1, true) ~= nil
    and tip._right[4] == ns.Value.Coins(60), tip._lines[4])
suite.check("then the tooth", (tip._lines[5] or ""):find("Brute Tooth", 1, true) ~= nil, tip._lines[5])
suite.check("three at most", #tip._lines == 5, #tip._lines)

local drops = KillTooltip:Drops("Gnoll Brute", 20)
suite.check("the drops are kept with the worth", #drops == 3)

ns.HandleSlash("killcount drops off")
suite.check("/farm killcount drops off turns them off", ns.db.killTooltipDrops == false)
tip = HoverDrops({ name = "Gnoll Brute" })
suite.check("and only the count is left", #tip._lines == 1, #tip._lines)
suite.check("the count itself stays on", ns.db.killTooltip == true)
ns.HandleSlash("killcount drops on")
suite.check("and on again", ns.db.killTooltipDrops == true)

ns.SettingsUI:Show()
local box = ns.SettingsUI.controls.killTooltipDrops
suite.check("the settings page shows Best drops on", box:GetChecked())
box:GetScript("OnClick")(box)
suite.check("unticking it turns them off", ns.db.killTooltipDrops == false)
box:GetScript("OnClick")(box)
suite.check("ticking it brings them back", ns.db.killTooltipDrops == true)
ns.SettingsUI:Hide()
suite.check("on by default", ns.DEFAULTS.killTooltipDrops == true)

suite.check("a chance under 1% keeps a decimal", KillTooltip.Chance(0.4) == "0.4%", KillTooltip.Chance(0.4))
suite.check("a tiny one says so", KillTooltip.Chance(0.01) == "<0.1%")

ns.Value.UnitPrice = unitPrice
ns.Value.ItemID = itemID
KillTooltip.ForgetKept()

--------------------------------------------------------------------------------
-- Who gets nothing
--------------------------------------------------------------------------------

suite.check("a friendly NPC never killed gets nothing",
    Hover({ name = "Innkeeper Farley", friendly = true }) == "quiet")
suite.check("a player gets nothing",
    Hover({ name = "Somebody", guid = "Player-1-0000ABCD" }) == "nounit")
suite.check("a pet gets nothing", Hover({ name = "Wolf", pet = true }) == "quiet")
suite.check("a critter gets nothing", Hover({ name = "Rabbit", kind = "Critter" }) == "quiet")

ns.DB:Hide("source", "Kobold Miner")
suite.check("a mob on the hide list gets nothing", Hover({ name = "Kobold Miner" }) == "quiet")
ns.DB:Unhide("source", "Kobold Miner")

--------------------------------------------------------------------------------
-- Dungeons
--------------------------------------------------------------------------------

outcome, line = Hover({ name = env.Secret("string"), id = 11320 })
suite.check("a secret name never raises", outcome == "added" or outcome == "quiet", outcome)
suite.check("it names the mob by its ID instead",
    line == nil or line:find("Kills: 0/20", 1, true) == 1, line)

hovered = { name = "Kobold Miner" }
local secretTip = Tooltip()
suite.check("a secret guid never raises",
    KillTooltip:OnTooltip(secretTip, { guid = env.Secret("string") }) ~= nil)

--------------------------------------------------------------------------------
-- The setting
--------------------------------------------------------------------------------

ns.HandleSlash("killcount")
suite.check("/farm killcount turns it off", ns.db.killTooltip == false)
suite.check("and nothing is added", Hover({ name = "Kobold Miner" }) == "quiet")
ns.HandleSlash("killcount")
suite.check("and on again", ns.db.killTooltip == true)

ns.SettingsUI:Show()
suite.check("the settings page shows it on", ns.SettingsUI.controls.killTooltip:GetChecked())
ns.SettingsUI.controls.killTooltip:GetScript("OnClick")(ns.SettingsUI.controls.killTooltip)
suite.check("unticking it turns it off", ns.db.killTooltip == false)
ns.SettingsUI.controls.killTooltip:GetScript("OnClick")(ns.SettingsUI.controls.killTooltip)
suite.check("and ticking it back on", ns.db.killTooltip == true)
ns.SettingsUI:Hide()

suite.done()
