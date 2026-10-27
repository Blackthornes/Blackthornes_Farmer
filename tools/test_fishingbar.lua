-- The Fishing window: Cast and Add Lure while a fishing pole is held.
--
-- What must hold:
--   1. Off unless ticked; shown only with a fishing pole in the main hand.
--   2. Cast casts Fishing; each lure in the bags, best first, puts itself
--      on the pole with one click, and a lure the skill is short for does
--      nothing.
--   3. The lure line says what is on and how long it has left, or that
--      none is on (Add Lure glows), or that the bags have none.
--   4. Hidden in a fight and at a vendor, back after; the close gem holds
--      until the pole comes off.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("fishingbar")

-- Its secure buttons record their attributes.
local ns = env.Load({ ui = true })
local realCreate = _G.CreateFrame
_G.CreateFrame = function(kind, name, parent, template)
    local frame = realCreate(kind, name, parent, template)
    if type(name) == "string" and name:find("^BlackthornesFarmerFishing") then
        frame._attrs = {}
        frame.SetAttribute = function(self, key, value) self._attrs[key] = value end
        frame.GetAttribute = function(self, key) return self._attrs[key] end
    end
    return frame
end

local held = nil              -- item in the main hand
local bags = {}               -- [itemID] = count
local lure = { false }        -- GetWeaponEnchantInfo's answer
local fighting = false
local skill, cap = 120, 150

_G.GetInventoryItemID = function(_, slot) if slot == 16 then return held end end
_G.C_Item = _G.C_Item or {}
_G.C_Item.GetItemInfoInstant = function(id)
    if id == 6256 then return id, "Weapon", "Fishing Pole", "INVTYPE_2HWEAPON", 132932, 2, 20 end
    if id == 2489 then return id, "Weapon", "Two-Handed Swords", "INVTYPE_2HWEAPON", 135321, 2, 8 end
    return id, "Trade Goods", "Parts", "", 134400, 7, 1
end
_G.C_Item.GetItemCount = function(id) return bags[id] or 0 end
local unpackAll = table.unpack or unpack
_G.GetWeaponEnchantInfo = function() return unpackAll(lure) end
_G.InCombatLockdown = function() return fighting end
_G.ITEM_MIN_SKILL = "Requires %s (%d)"
_G.C_TooltipInfo = { GetItemByID = function(id)
    if id == 6533 then return { lines = { { leftText = "Aquadynamic Fish Attractor" }, { leftText = "Requires Fishing (100)" } } } end
    if id == 6532 then return { lines = { { leftText = "Bright Baubles" }, { leftText = "Requires Fishing (200)" } } } end
    return { lines = { { leftText = "Shiny Bauble" } } }
end }
ns.GatherToCap.ReadSkill = function() return skill, cap end

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end
local handler = _G.BlackthornesFarmerEventFrame:GetScript("OnEvent")
local function Fire(event, ...) handler(_G.BlackthornesFarmerEventFrame, event, ...) end

local Bar = ns.FishingBar
local function Up() return Bar.frame ~= nil and Bar.frame:IsShown() end

-- 1.
held = 6256
Fire("PLAYER_EQUIPMENT_CHANGED")
suite.check("off unless ticked", ns.db.fishingBar == false and not Up())

Bar:SetEnabled(true)
suite.check("shows with a fishing pole", Up())
local cast = _G.BlackthornesFarmerFishingCast
suite.check("Cast casts Fishing", cast and cast:GetAttribute("type") == "spell"
    and cast:GetAttribute("spell") ~= nil, cast and tostring(cast:GetAttribute("type")))

held = 2489
Fire("PLAYER_EQUIPMENT_CHANGED")
suite.check("hidden with a sword in hand", not Up())
held = nil
Fire("UNIT_INVENTORY_CHANGED", "player")
suite.check("hidden with nothing in hand", not Up())
held = 6256
Fire("PLAYER_EQUIPMENT_CHANGED")
suite.check("back with the pole", Up())

-- 3. (no lures yet)
local text, color, glow = Bar:LureText(Bar:Lures(skill))
suite.check("no lures says so", text == "No lures in your bags" and color == "warn" and not glow, text)

-- 2.
bags = { [6529] = 3, [6533] = 1, [6532] = 2 }
Fire("BAG_UPDATE_DELAYED")
local lures = Bar:Lures(skill)
local order = {}
for _, entry in ipairs(lures) do order[#order + 1] = entry.id end
suite.check("best lure first", table.concat(order, ",") == "6533,6532,6529", table.concat(order, ","))
suite.check("counts from the bags", lures[1].count == 1 and lures[3].count == 3)
suite.check("a lure needing more skill can't be used", lures[2].usable == false and lures[2].need == 200)
suite.check("one the skill reaches can", lures[1].usable == true and lures[3].usable == true)
-- The gold plaques: the best lure and how many on Add Lure, the skill on Cast.
local lureLine = Bar.lureButton.second:GetText()
suite.check("Add Lure names the best lure and how many",
    Bar.lureButton.first:GetText() == "Add Lure" and lureLine == "Aquadynamic Fish Attractor, 1 left", tostring(lureLine))
suite.check("Cast shows the Fishing skill", Bar.cast.first:GetText() == "Cast"
    and Bar.cast.second:GetText() == "Fishing 120 / 150", tostring(Bar.cast.second:GetText()))
suite.check("Add Lure glows while none is on", Bar.lureGlowing == true)
suite.check("a catch flashes the Cast plaque without an error", pcall(Bar.Caught, Bar))

Bar:ToggleList()
suite.check("Add Lure opens the list", Bar.list and Bar.list:IsShown())
local first = _G.BlackthornesFarmerFishingLure1
local second = _G.BlackthornesFarmerFishingLure2
suite.check("a click puts the lure on the pole", first:GetAttribute("type") == "macro"
    and first:GetAttribute("macrotext") == "/use item:6533\n/use 16", tostring(first:GetAttribute("macrotext")))
suite.check("a lure too high does nothing", second:GetAttribute("type") == nil and second:GetAttribute("macrotext") == nil)

-- 3.
text, color, glow = Bar:LureText(lures)
suite.check("none on says so and Add Lure glows", text == "None on" and color == "warn" and glow == true, text)
lure = { true, 522000, 1, 266 }
text, color, glow = Bar:LureText(lures)
suite.check("what is on and how long it has left", text == "+100, 8:42 left" and color == "good" and not glow, text)
suite.check("the clock", Bar.Clock(522) == "8:42" and Bar.Clock(3725) == "1:02:05", Bar.Clock(522))

-- 4.
Fire("PLAYER_REGEN_DISABLED")
fighting = true
suite.check("hidden in a fight", not Up() and not Bar.list:IsShown())
Fire("BAG_UPDATE_DELAYED")
suite.check("stays hidden while fighting", not Up())
fighting = false
Fire("PLAYER_REGEN_ENABLED")
suite.check("back after the fight", Up())

Fire("MERCHANT_SHOW")
suite.check("hidden at a vendor", not Up())
Fire("MERCHANT_CLOSED")
suite.check("back after the vendor", Up())

Bar:Close()
suite.check("the close gem hides it", not Up())
Fire("BAG_UPDATE_DELAYED")
suite.check("and it stays closed", not Up())
held = nil
Fire("PLAYER_EQUIPMENT_CHANGED")
held = 6256
Fire("PLAYER_EQUIPMENT_CHANGED")
suite.check("back once the pole comes off and on again", Up())

-- The command.
ns.commands.fishbar.fn("off")
suite.check("/farm fishbar off", ns.db.fishingBar == false and not Up())
ns.commands.fishbar.fn("")
suite.check("/farm fishbar toggles", ns.db.fishingBar == true and Up())

suite.done()
