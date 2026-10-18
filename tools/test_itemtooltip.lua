-- The farming line on a material's tooltip.
--
-- What matters: a material gets one line naming the best spot from where you
-- stand, the same pick Where? makes; gear and greys get nothing; the line goes
-- on once however often the tooltip redraws; the setting and /farm tooltip
-- turn it off; and an item the client will not describe costs the line, never
-- a Lua error.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("itemtooltip")

local ns = env.Load({ ui = true })
local ItemTooltip = ns.ItemTooltip

local now = 1000
_G.GetTime = function() return now end

-- Item classes the way the client files them: 7 trade goods, 15 junk.
local CLASS = { [2770] = 7, [9001] = 15, [9002] = 7 }
local NAMES = { [2770] = "Copper Ore", [9001] = "Broken Fang", [9002] = "Gritty Test Meat" }
_G.C_Item = {
    GetItemNameByID = function(id) return NAMES[id] end,
    GetItemInfoInstant = function(id) return id, nil, nil, nil, nil, CLASS[id] end,
    GetItemCount = function() return 0 end,
}

-- Two harvested drops filed under Misc: a grey, and meat.
ns.DB:RegisterItem({ name = "Broken Fang", id = 9001, sources = {
    { name = "Mangy Wolf", zone = "Elwynn Forest", minLevel = 1, maxLevel = 2, provenance = "forever" },
} })
ns.DB:RegisterItem({ name = "Gritty Test Meat", id = 9002, sources = {
    { name = "Mangy Wolf", zone = "Elwynn Forest", minLevel = 1, maxLevel = 2, chance = 30, provenance = "forever" },
} })

local function Tooltip()
    local tooltip = {
        _lines = {},
        AddLine = function(self, text) self._lines[#self._lines + 1] = text end,
        NumLines = function(self) return #self._lines end,
        Show = function() end,
    }
    _G.GameTooltip = tooltip
    return tooltip
end

local function Hover(tooltip, id)
    return ItemTooltip:OnTooltip(tooltip, { id = id })
end

env.world.zone = "Westfall"

--------------------------------------------------------------------------------
-- A material
--------------------------------------------------------------------------------

local tooltip = Tooltip()
suite.check("copper ore gets a line", Hover(tooltip, 2770) == "added")
local line = tooltip._lines[1] or ""
suite.check("it says farm", line:find("Farm: ", 1, true) ~= nil, line)
suite.check("at the vein in the zone you are in", line:find("Copper Vein (10-20), Westfall", 1, true) ~= nil, line)
suite.check("and that you are there", line:find("you are here", 1, true) ~= nil, line)
local best = ns.Spots:For("Copper Ore")[1]
suite.check("the same pick as Where?", best.zone == "Westfall", best.zone)

suite.check("a redraw does not add it twice", Hover(tooltip, 2770) == "duplicate")
suite.check("still one line", #tooltip._lines == 1, #tooltip._lines)

-- The game clears the tooltip and shows it again.
tooltip._lines = {}
suite.check("a fresh showing gets it again", Hover(tooltip, 2770) == "added")

-- Moving changes the answer once the kept one goes stale.
env.world.zone = "Durotar"
now = now + 30
tooltip = Tooltip()
Hover(tooltip, 2770)
suite.check("from Durotar it is Durotar's vein",
    (tooltip._lines[1] or ""):find("Durotar", 1, true) ~= nil, tooltip._lines[1])

--------------------------------------------------------------------------------
-- Not materials
--------------------------------------------------------------------------------

tooltip = Tooltip()
suite.check("a grey a mob dropped gets nothing", Hover(tooltip, 9001) == "quiet")
suite.check("so no line", #tooltip._lines == 0)

tooltip = Tooltip()
suite.check("meat a mob dropped gets one", Hover(tooltip, 9002) == "added")
suite.check("naming the mob and its rate",
    (tooltip._lines[1] or ""):find("Mangy Wolf (1-2), Elwynn Forest, ~30%", 1, true) ~= nil, tooltip._lines[1])

tooltip = Tooltip()
suite.check("an item the database does not know gets nothing", Hover(tooltip, 12345) == "quiet")

tooltip = Tooltip()
suite.check("an item with no id is no item", ItemTooltip:OnTooltip(tooltip, {}) == "noitem")

-- Some other tooltip (a comparison one, another addon's) is left alone.
local other = { _lines = {}, AddLine = function(self, t) self._lines[#self._lines + 1] = t end }
suite.check("only the game's own tooltips", ItemTooltip:OnTooltip(other, { id = 2770 }) == "quiet")

--------------------------------------------------------------------------------
-- Trouble
--------------------------------------------------------------------------------

-- An id the client hands over as something that raises when read.
local secret = setmetatable({}, { __add = function() error("secret") end,
    __concat = function() error("secret") end })
tooltip = Tooltip()
suite.check("a secret id costs the line, not an error",
    ItemTooltip:OnTooltip(tooltip, { id = secret }) == "noitem")

local realFor = ns.Spots.For
ns.Spots.For = function() error("boom") end
ItemTooltip.ForgetKept()
tooltip = Tooltip()
suite.check("a failure while ranking is swallowed", Hover(tooltip, 2770) == "noitem")
suite.check("and nothing was half written", #tooltip._lines == 0)
suite.check("nor left marked as writing", not ItemTooltip.writing)
ns.Spots.For = realFor

--------------------------------------------------------------------------------
-- Switching it off
--------------------------------------------------------------------------------

suite.check("on by default", ns.DEFAULTS.itemTooltip == true)

ns.HandleSlash("tooltip")
suite.check("/farm tooltip turns it off", ns.db.itemTooltip == false)
tooltip = Tooltip()
suite.check("and then nothing is added", Hover(tooltip, 2770) == "quiet")
ns.HandleSlash("tooltip")
suite.check("and on again", ns.db.itemTooltip == true)

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then pcall(module.OnEnable, module) end
end
ns.SettingsUI:Show()
suite.check("the settings page shows it on (Always)", ns.SettingsUI.controls.itemTooltip:GetValue() == 2)
ns.db.itemTooltip = false
ns.SettingsUI:Refresh()
suite.check("and follows the saved value", ns.SettingsUI.controls.itemTooltip:GetValue() == 0)
ns.db.itemTooltip = true
ns.SettingsUI:Hide()

--------------------------------------------------------------------------------
-- Craft or sell, from Tradeskills
--------------------------------------------------------------------------------

local function Doubles()
    local tooltip = Tooltip()
    tooltip._doubles = {}
    tooltip.AddDoubleLine = function(self, left, right)
        self._doubles[#self._doubles + 1] = { left, right }
        self._lines[#self._lines + 1] = left
    end
    return tooltip
end

suite.check("without Tradeskills, no craft lines", ItemTooltip:CraftLines(2770) == nil)

local asked
_G.BlackthornesTS = { CraftOrFarm = { ForMaterial = function(_, id)
    asked = id
    if id == 2770 then
        return { name = "Copper Bar", recipeID = 2657, perHour = 20000, rawPerHour = 15000 }
    end
end } }
ItemTooltip.ForgetKept()
tooltip = Doubles()
Hover(tooltip, 2770)
suite.check("Tradeskills is asked by item", asked == 2770)
suite.check("sold as it is, an hour", tooltip._doubles[1] and tooltip._doubles[1][1] == "Sold as it is"
    and tooltip._doubles[1][2]:find("an hour", 1, true) ~= nil, tooltip._doubles[1] and tooltip._doubles[1][2])
suite.check("then the craft", tooltip._doubles[2] and tooltip._doubles[2][1] == "As Copper Bar")
suite.check("under the farming line", (tooltip._lines[1] or ""):find("Farm: ", 1, true) ~= nil)

ns.db.itemTooltip = false
tooltip = Doubles()
Hover(tooltip, 2770)
suite.check("the craft lines show with the farming line off", #tooltip._doubles == 2 and #tooltip._lines == 2)
ns.db.itemTooltip = true

ns.HandleSlash("tooltip craft off")
suite.check("/farm tooltip craft off", ns.db.itemTooltipCraft == false)
tooltip = Doubles()
Hover(tooltip, 2770)
suite.check("then no craft lines", #tooltip._doubles == 0)
ns.HandleSlash("tooltip craft")
suite.check("and on again", ns.db.itemTooltipCraft == true)
suite.check("on by default too", ns.DEFAULTS.itemTooltipCraft == true)

_G.BlackthornesTS = { CraftOrFarm = { ForMaterial = function() error("boom") end } }
tooltip = Doubles()
suite.check("a raising Tradeskills costs only its lines", Hover(tooltip, 2770) == "added" and #tooltip._doubles == 0)
_G.BlackthornesTS = nil

suite.done()
