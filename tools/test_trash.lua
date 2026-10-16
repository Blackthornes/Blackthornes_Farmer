-- The trash can: while the bags are full, a small can sits on the stack
-- worth least by Farmer's prices (the owner asked 2026-10-13, for Butler and
-- Farmer both).
--
-- What must hold:
--   1. Nothing while the bags have room, or while no bag window is open.
--   2. Full bags: the can sits on the cheapest stack, never a goal's item,
--      a quest item, gear that could be worn or a locked slot.
--   3. Its tooltip says what it is worth.
--   4. A click only picks the item up; Farmer never deletes anything.
--   5. A slot that changed, or a cursor already holding something, is left.
--   6. Hidden in combat, at a vendor and while Butler draws its own can.
--   7. Settings and /farm trash turn it off and on.
--   8. A trade good only wins when it is well under the junk (MATERIAL_LEAN).
--   9. Two short stacks of one item that fit together: the can says to
--      stack them, and a click joins them; nothing is picked up to throw.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("trash")

local ns = env.Load({ ui = true })

local function Link(item)
    return ("|cff9d9d9d|Hitem:%d::::::::|h[%s]|h|r"):format(item.id, item.name)
end

-- Backpack of 16: a fang stack, a pelt, a quest letter, a locked rock, a
-- worn-able grey-free sword, and linen a goal counts. The rest is full.
local bag = {
    [1] = { id = 701, name = "Broken Fang", quality = 0, price = 12, count = 3 },
    [2] = { id = 702, name = "Ruined Pelt", quality = 0, price = 5 },
    [3] = { id = 703, name = "Old Letter", quality = 0, price = 1, quest = true },
    [4] = { id = 704, name = "Shiny Rock", quality = 0, price = 2, locked = true },
    [5] = { id = 705, name = "Rusty Sword", quality = 1, price = 1, equipLoc = "INVTYPE_WEAPON" },
    [6] = { id = 2589, name = "Linen Cloth", quality = 1, price = 1 },
}
local items = {}
for _, item in pairs(bag) do items[item.id] = item end
local freeSlots = 10

_G.NUM_BAG_SLOTS = 4
_G.C_Container = {
    GetContainerNumSlots = function(b) return b == 0 and 16 or 0 end,
    GetContainerNumFreeSlots = function(b) return b == 0 and freeSlots or 0, 0 end,
    GetContainerItemInfo = function(b, slot)
        local item = b == 0 and bag[slot]
        if not item then return nil end
        return { itemID = item.id, hyperlink = Link(item), stackCount = item.count or 1,
            quality = item.quality, isLocked = item.locked or false, hasNoValue = false, isBound = false }
    end,
    GetContainerItemQuestInfo = function(b, slot)
        local item = b == 0 and bag[slot]
        return { isQuestItem = item and item.quest or false, isActive = false }
    end,
}
local picked, deleted = {}, 0
_G.C_Container.PickupContainerItem = function(b, slot) picked[#picked + 1] = b .. ":" .. slot end
_G.DeleteCursorItem = function() deleted = deleted + 1 end
_G.C_Item = {
    GetItemInfo = function(id)
        local item = items[id]
        if not item then return nil end
        return item.name, Link(item), item.quality, 1, 1, "Misc", "Misc", item.stack or 20, item.equipLoc or "", 134400, item.price
    end,
    GetItemInfoInstant = function(id)
        local item = items[id]
        return id, "Misc", "Misc", item and item.equipLoc or "", 134400, item and item.class or 15, 0
    end,
}
local holding = nil
_G.GetCursorInfo = function() return holding end

-- Retail's one bag window, listing its buttons.
_G.NUM_CONTAINER_FRAMES = 0
local buttons = {}
for slot = 1, 16 do
    buttons[slot] = env.Stub({
        GetBagID = function() return 0 end,
        GetID = function() return slot end,
        IsVisible = function() return true end,
        _width = 37,
    })
end
local bagWindow = env.Stub({ _shown = false })
bagWindow.EnumerateValidItems = function()
    local i = 0
    return function()
        i = i + 1
        if buttons[i] then return i, buttons[i] end
    end
end
bagWindow.HookScript = function(self, script, fn) self._scripts[script] = fn end
_G.ContainerFrameCombinedBags = bagWindow

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end
local handler = _G.BlackthornesFarmerEventFrame:GetScript("OnEvent")
local function Fire(event, ...) handler(_G.BlackthornesFarmerEventFrame, event, ...) end

local Trash = ns.Trash
-- Linen Cloth is a goal of this character's.
ns.Goals:Set("Linen Cloth", 20)
Fire("PLAYER_ENTERING_WORLD")

local function Showing()
    return Trash.can ~= nil and Trash.can:IsShown()
end

-- 1.
bagWindow._shown = true
Fire("BAG_UPDATE_DELAYED")
suite.check("no can while the bags have room", not Showing())

freeSlots = 1
bagWindow._shown = true
Fire("BAG_UPDATE_DELAYED")
suite.check("one free slot is not full, no can", not Showing())

freeSlots = 0
bagWindow._shown = false
Fire("BAG_UPDATE_DELAYED")
suite.check("no can while no bag window is open", not Showing())

-- 2.
bagWindow._shown = true
bagWindow._scripts.OnShow()
suite.check("full bags show the can", Showing())
local point = Trash.can._point
suite.check("on the cheapest stack", point and point[2] == buttons[2], point and tostring(point[2]))
suite.check("not the quest item, the locked rock, the sword or the goal's linen",
    Trash.pick and Trash.pick.itemID == 702)
suite.check("the goal's linen may never go", Trash.slots["0:6"] and Trash.slots["0:6"].worth == nil)
suite.check("nor the sword", Trash.slots["0:5"] and Trash.slots["0:5"].worth == nil)

-- 3.
GameTooltip._lines = {}
Trash.can:GetScript("OnEnter")(Trash.can)
local lines = table.concat(GameTooltip._lines, "\n")
suite.check("the tooltip says to throw it away", lines:find("Throw away to make room", 1, true) ~= nil, lines)
suite.check("and what it is worth", lines:find("5c", 1, true) ~= nil, lines)

-- 5. Something on the cursor already.
holding = "item"
Trash.can:GetScript("OnClick")(Trash.can)
suite.check("a full cursor is left alone", #picked == 0)
holding = nil

-- 4.
env.chat = {}
Trash.can:GetScript("OnClick")(Trash.can)
suite.check("a click picks the item up", picked[1] == "0:2", tostring(picked[1]))
suite.check("and nothing is deleted", deleted == 0)
suite.check("chat says how to throw it away",
    (env.chat[1] or ""):find("game will ask before it is destroyed", 1, true) ~= nil, env.chat[1])
holding = "item"
Fire("CURSOR_CHANGED")
suite.check("the can waits while the item is on the cursor", not Showing())
holding = nil
Fire("CURSOR_CHANGED")
suite.check("and comes back once it is put down", Showing())

-- A goal set since the can was placed keeps that item.
ns.Goals:Set("Ruined Pelt", 5)
local beforeGoal = #picked
Trash:Take()
suite.check("an item that became a goal is not picked up", #picked == beforeGoal)
Fire("BAG_UPDATE_DELAYED")
suite.check("and the can moves off it", not (Trash.pick and Trash.pick.itemID == 702))
ns.Goals:Remove("Ruined Pelt")
Fire("BAG_UPDATE_DELAYED")
suite.check("removing the goal puts it back", Trash.pick and Trash.pick.itemID == 702)

-- 5. The slot changed under the can.
local pelt = bag[2]
bag[2] = { id = 706, name = "Pristine Pelt", quality = 1, price = 500 }
items[706] = bag[2]
local before = #picked
Trash:Take()
suite.check("a changed slot is not picked up", #picked == before)
bag[2] = pelt
Fire("BAG_UPDATE_DELAYED")
suite.check("and the can comes back once the bags are read", Showing())

-- 6.
Fire("PLAYER_REGEN_DISABLED")
suite.check("hidden in a fight", not Showing())
Fire("PLAYER_REGEN_ENABLED")
suite.check("back after it", Showing())
Fire("MERCHANT_SHOW")
suite.check("hidden at a vendor", not Showing())
Fire("MERCHANT_CLOSED")
suite.check("back when the vendor closes", Showing())

_G.BlackthornesButler = { Trash = {} }
Fire("BAG_UPDATE_DELAYED")
suite.check("Butler's can shows instead while Butler is loaded", not Showing())
_G.BlackthornesButler = nil
Fire("BAG_UPDATE_DELAYED")
suite.check("and Farmer's comes back without it", Showing())

bagWindow._shown = false
bagWindow._scripts.OnHide()
suite.check("closing the bags hides it", not Showing())
bagWindow._shown = true
bagWindow._scripts.OnShow()

-- 7.
ns.HandleSlash("trash")
suite.check("/farm trash turns it off", ns.db.trashCan == false and not Showing())
ns.SettingsUI:Show()
local box = ns.SettingsUI.controls.trashCan
suite.check("the Settings box shows it off", box ~= nil and not box:GetChecked())
box:GetScript("OnClick")(box)
suite.check("ticking it turns it back on", ns.db.trashCan == true and Showing())

-- 8. A grey trade good a little cheaper than the pelt leaves the pelt.
bagWindow._shown = true
if bagWindow._scripts.OnShow then bagWindow._scripts.OnShow() end
local function Put(slot, item)
    bag[slot] = item
    if item then items[item.id] = item end
    Fire("BAG_UPDATE_DELAYED")
end
ns.db.trashCan = true
Put(7, { id = 710, name = "Frayed Cloth", quality = 0, price = 2, count = 2, class = 7 })
suite.check("cloth worth 4 against a pelt worth 5 leaves the pelt", Trash.pick and Trash.pick.itemID == 702,
    tostring(Trash.pick and Trash.pick.itemID))
Put(7, { id = 710, name = "Frayed Cloth", quality = 0, price = 2, count = 1, class = 7 })
suite.check("cloth worth well under it is picked", Trash.pick and Trash.pick.itemID == 710,
    tostring(Trash.pick and Trash.pick.itemID))
Put(7, nil)

-- 9. A second Broken Fang stack that the first fits on.
Put(8, { id = 701, name = "Broken Fang", quality = 0, price = 12, count = 4 })
suite.check("two short stacks: the can says to stack them", Trash.pick and Trash.pick.merge == true)
suite.check("on the smaller stack", Trash.can._point and Trash.can._point[2] == buttons[1])
GameTooltip._lines = {}
Trash.can:GetScript("OnEnter")(Trash.can)
lines = table.concat(GameTooltip._lines, "\n")
suite.check("the tooltip says to stack them", lines:find("Stack these to make room", 1, true) ~= nil, lines)
suite.check("and never to throw away", lines:find("Throw away", 1, true) == nil, lines)
picked = {}
Trash.can:GetScript("OnClick")(Trash.can)
suite.check("a click picks up the small stack and drops it on the other",
    picked[1] == "0:1" and picked[2] == "0:8", table.concat(picked, ","))
suite.check("and nothing is deleted", deleted == 0)
Put(8, { id = 701, name = "Broken Fang", quality = 0, price = 12, count = 18 })
suite.check("stacks that don't fit together are left", Trash.pick and not Trash.pick.merge
    and Trash.pick.itemID == 702, tostring(Trash.pick and Trash.pick.itemID))

suite.done()
