-- Off, Shift or Always for each tooltip line (UI/TooltipShift.lua).
--
-- What matters: a save that never touched it reads as it did (on is Always,
-- off is Off) and nothing new is written; Shift keeps a line back until
-- Shift is held and says "Hold Shift for more." once; Off and Always go
-- back cleanly; and the real material and mob tooltips follow it, the line
-- coming back on a tooltip rebuilt with Shift down.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("tooltipshift")

local ns = env.Load({ ui = true })
local Shift = ns.TooltipShift
local ItemTooltip, KillTooltip = ns.ItemTooltip, ns.KillTooltip

local now = 1000
_G.GetTime = function() return now end

local shiftDown = false
_G.IsShiftKeyDown = function() return shiftDown end

local function Tooltip()
    local tooltip = {
        _lines = {}, _cleared = {},
        AddLine = function(self, text) self._lines[#self._lines + 1] = text end,
        AddDoubleLine = function(self, left, right) self._lines[#self._lines + 1] = left .. "  " .. right end,
        NumLines = function(self) return #self._lines end,
        Show = function() end,
        IsShown = function() return true end,
        HookScript = function(self, script, fn)
            if script == "OnTooltipCleared" then self._cleared[#self._cleared + 1] = fn end
        end,
    }
    -- The tooltip's own clear, as RefreshData does before it rebuilds.
    function tooltip:Clear()
        self._lines = {}
        for _, fn in ipairs(self._cleared) do fn(self) end
        ItemTooltip.Forget(self)
        KillTooltip.Forget(self)
    end
    _G.GameTooltip = tooltip
    return tooltip
end

local function Has(tooltip, text)
    for _, line in ipairs(tooltip._lines) do
        if line:find(text, 1, true) then return true end
    end
    return false
end

local function Count(tooltip, text)
    local n = 0
    for _, line in ipairs(tooltip._lines) do
        if line == text then n = n + 1 end
    end
    return n
end

--------------------------------------------------------------------------------
-- Nobody's settings move
--------------------------------------------------------------------------------

suite.check("the four lines are known", #Shift.KEYS == 4, #Shift.KEYS)
for _, key in ipairs({ "whereToFarm", "craftOrSell", "killCount", "bestDrops" }) do
    suite.check(key .. " on reads as Always", Shift:Mode(true, key) == Shift.ALWAYS)
    suite.check(key .. " off reads as Off", Shift:Mode(false, key) == Shift.OFF)
    suite.check(key .. " shows as it always did", Shift:Shows(key))
end
suite.check("nothing is written for a player who never picks", ns.db.tooltipShift == nil)
suite.check("no line is on Shift", not Shift:AnyShift())

ns.SettingsUI:Show()
local controls = ns.SettingsUI.controls
suite.check("Where to Farm shows Always", controls.itemTooltip:GetValue() == 2)
suite.check("Kill Count shows Always", controls.killTooltip:GetValue() == 2)
ns.db.killTooltipDrops = false
ns.SettingsUI:Refresh()
suite.check("a line turned off shows Off", controls.killTooltipDrops:GetValue() == 0)
suite.check("and still nothing written", ns.db.tooltipShift == nil)
ns.db.killTooltipDrops = true
ns.SettingsUI:Refresh()

--------------------------------------------------------------------------------
-- Shift, Off and Always
--------------------------------------------------------------------------------

controls.itemTooltip:SetValue(1)
suite.check("Shift is kept", ns.db.tooltipShift and ns.db.tooltipShift.whereToFarm == true)
suite.check("the line stays on", ns.db.itemTooltip == true)
suite.check("it reads as Shift", Shift:Mode(ns.db.itemTooltip, "whereToFarm") == Shift.SHIFT)
suite.check("held back with Shift up", not Shift:Shows("whereToFarm"))
shiftDown = true
suite.check("shown with Shift down", Shift:Shows("whereToFarm"))
shiftDown = false
suite.check("a line is on Shift now", Shift:AnyShift() and Shift.shared.AnyShift())

local hint = Tooltip()
Shift:Held(hint)
Shift:Held(hint)
suite.check("the hint goes on once", Count(hint, "Hold Shift for more.") == 1, #hint._lines)
hint:Clear()
Shift:Held(hint)
suite.check("and again once the tooltip is cleared", Count(hint, "Hold Shift for more.") == 1)

controls.itemTooltip:SetValue(0)
suite.check("Off turns the line off", ns.db.itemTooltip == false)
suite.check("Off reads as Off", Shift:Mode(ns.db.itemTooltip, "whereToFarm") == Shift.OFF)
controls.itemTooltip:SetValue(2)
suite.check("Always turns it back on", ns.db.itemTooltip == true)
suite.check("and clears Shift", ns.db.tooltipShift.whereToFarm == nil)
suite.check("it reads as Always", Shift:Mode(true, "whereToFarm") == Shift.ALWAYS)
controls.itemTooltip:SetValue(1)
controls.itemTooltip:SetValue(0)
controls.itemTooltip:SetValue(1)
suite.check("Off and back to Shift keeps Shift", Shift:Mode(ns.db.itemTooltip, "whereToFarm") == Shift.SHIFT)
ns.SettingsUI:Refresh()
suite.check("Settings shows Shift after a refresh", controls.itemTooltip:GetValue() == 1)
ns.SettingsUI:Hide()

--------------------------------------------------------------------------------
-- The material tooltip
--------------------------------------------------------------------------------

local CLASS = { [2770] = 7 }
_G.C_Item = {
    GetItemNameByID = function(id) return id == 2770 and "Copper Ore" or nil end,
    GetItemInfoInstant = function(id) return id, nil, nil, nil, nil, CLASS[id] end,
    GetItemCount = function() return 0 end,
}
env.world.zone = "Westfall"

local tip = Tooltip()
ItemTooltip:OnTooltip(tip, { id = 2770 })
suite.check("with Shift up the farming line waits", not Has(tip, "Farm: "), tip._lines[1])
suite.check("and the hint says so", Count(tip, "Hold Shift for more.") == 1)
ItemTooltip:OnTooltip(tip, { id = 2770 })
suite.check("a redraw adds no second hint", Count(tip, "Hold Shift for more.") == 1)

shiftDown = true
tip:Clear()
ItemTooltip:OnTooltip(tip, { id = 2770 })
suite.check("rebuilt with Shift down the line comes", Has(tip, "Farm: "), tip._lines[1])
suite.check("with no hint", not Has(tip, "Hold Shift"))
shiftDown = false

ns.db.tooltipShift.whereToFarm = nil
tip = Tooltip()
ItemTooltip:OnTooltip(tip, { id = 2770 })
suite.check("on Always it shows with Shift up", Has(tip, "Farm: ") and not Has(tip, "Hold Shift"))

--------------------------------------------------------------------------------
-- The mob tooltip
--------------------------------------------------------------------------------

local hovered = { name = "Shift Test Kobold", guid = "Creature-0-1-2-3-4321-00000001" }
local realName, realGuid = _G.UnitName, _G.UnitGUID
_G.UnitName = function(unit) if unit == "mouseover" then return hovered.name end return realName(unit) end
_G.UnitGUID = function(unit) if unit == "mouseover" then return hovered.guid end return realGuid(unit) end
_G.UnitCanAttack = function(_, unit) return unit == "mouseover" end
_G.UnitIsPlayer = function() return false end
_G.UnitPlayerControlled = function() return false end
_G.UnitCreatureType = function() return "Humanoid" end

local function MobTooltip()
    local t = Tooltip()
    t.GetUnit = function() return hovered.name, "mouseover" end
    return t
end

Shift:Apply(Shift.SHIFT, "killCount", true, function(on) KillTooltip:SetEnabled(on) end)
local mob = MobTooltip()
KillTooltip:OnTooltip(mob, { guid = hovered.guid })
suite.check("the kill count waits for Shift", not Has(mob, "Kills: "), mob._lines[1])
suite.check("with the hint", Count(mob, "Hold Shift for more.") == 1)
shiftDown = true
mob:Clear()
KillTooltip:OnTooltip(mob, { guid = hovered.guid })
suite.check("and shows with Shift down", Has(mob, "Kills: 0/20"), mob._lines[1])
shiftDown = false
Shift:Apply(Shift.ALWAYS, "killCount", true, function(on) KillTooltip:SetEnabled(on) end)
mob = MobTooltip()
KillTooltip:OnTooltip(mob, { guid = hovered.guid })
suite.check("on Always it shows with Shift up", Has(mob, "Kills: 0/20") and not Has(mob, "Hold Shift"))

--------------------------------------------------------------------------------
-- Shift redraws the tooltip only when its lines can be read
--------------------------------------------------------------------------------

local shared = _G.BlackthornesTooltipShift
Shift:Apply(Shift.SHIFT, "killCount", true, function(on) KillTooltip:SetEnabled(on) end)
suite.check("a line is on Shift for the redraw", shared.AnyShift())

local lines
local savedTooltipInfo = _G.C_TooltipInfo
_G.C_TooltipInfo = { GetUnit = function() return { lines = lines } end }

local function RedrawTooltip()
    local tooltip = Tooltip()
    tooltip._refreshed = 0
    tooltip.GetPrimaryTooltipInfo = function() return { getterName = "GetUnit", getterArgs = { "mouseover" } } end
    tooltip.RefreshData = function(self) self._refreshed = self._refreshed + 1 end
    return tooltip
end

local plain = { GetRGB = function() return 1, 1, 1 end }
lines = { { leftColor = plain }, { leftColor = plain, rightColor = plain } }
local redraw = RedrawTooltip()
shared.OnModifier("LSHIFT")
suite.check("plain lines are redrawn on Shift", redraw._refreshed == 1, redraw._refreshed)
shared.OnModifier("LCTRL")
suite.check("another key redraws nothing", redraw._refreshed == 1)

lines = { { leftColor = plain }, { leftColor = env.Secret("a secret color") } }
redraw = RedrawTooltip()
local ok = pcall(shared.OnModifier, "RSHIFT")
suite.check("a secret color raises nothing", ok)
suite.check("and the tooltip is left as it is", redraw._refreshed == 0, redraw._refreshed)

lines = { { leftColor = plain, rightColor = env.Secret("a secret color") } }
redraw = RedrawTooltip()
ok = pcall(shared.OnModifier, "LSHIFT")
suite.check("a secret right color too", ok and redraw._refreshed == 0)

redraw = RedrawTooltip()
redraw.GetPrimaryTooltipInfo = function() return nil end
shared.OnModifier("LSHIFT")
suite.check("a tooltip with no info is left alone", redraw._refreshed == 0)

lines = { { leftColor = plain } }
redraw = RedrawTooltip()
redraw.GetPrimaryTooltipInfo = nil
redraw.infoList = { { getterName = "GetUnit", getterArgs = { "mouseover" } } }
shared.OnModifier("LSHIFT")
suite.check("an older client's info list reads the same", redraw._refreshed == 1)

Shift:Apply(Shift.ALWAYS, "killCount", true, function(on) KillTooltip:SetEnabled(on) end)
redraw = RedrawTooltip()
shared.OnModifier("LSHIFT")
suite.check("with no line on Shift nothing is redrawn", redraw._refreshed == 0)

-- An older copy of this file, loaded after, writes its handler plainly.
local newest = shared.OnModifier
shared.OnModifier = function() error("the old handler ran") end
suite.check("an older copy cannot put its handler back", shared.OnModifier == newest)
suite.check("the newest copy's version is kept", shared.handlers.version == Shift.FILE_VERSION)
suite.check("nor an older AnyShift", shared.AnyShift ~= nil and shared.AnyShift() == false)
suite.check("the frame still finds the handler", _G.BlackthornesTooltipShift.OnModifier == newest)

_G.C_TooltipInfo = savedTooltipInfo

suite.done()
