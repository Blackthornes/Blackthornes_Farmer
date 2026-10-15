-- The Open button for clams, sacks and lockboxes, and opening after loot.
--
-- What must hold:
--   1. Only slots with loot are offered, never what is kept on purpose: a
--      goal's item, the craft queue's, Butler's Always keep list, a quest
--      item, a locked lockbox, a locked slot.
--   2. An icon on the Kills & Loot panel's title bar, "Open" on hover,
--      aimed at one slot just before the click and at nothing after.
--   3. Never in a fight (and off the panel then), nor at a vendor.
--   4. Opening after loot runs only when ticked and the test said it works,
--      and leaves alone one that stayed shut.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("openbutton")

-- The secure button records its attributes, scripts and parent.
local realCreate = _G.CreateFrame
local function Create(kind, name, parent, template)
    local frame = realCreate(kind, name, parent, template)
    if name == "BlackthornesFarmerOpen" then
        frame._attrs = {}
        frame._parent = parent
        frame.SetAttribute = function(self, key, value) self._attrs[key] = value end
        frame.GetAttribute = function(self, key) return self._attrs[key] end
        frame.HookScript = function(self, script, fn) self._scripts[script] = fn end
        frame.SetParent = function(self, value) self._parent = value end
        frame.GetParent = function(self) return self._parent end
    end
    return frame
end

local ns = env.Load({ ui = true })
_G.CreateFrame = Create

local function Link(item)
    return ("|cffffffff|Hitem:%d::::::::|h[%s]|h|r"):format(item.id, item.name)
end

local bag = {
    [1] = { id = 7973, name = "Big-mouth Clam", count = 3, loot = true },
    [2] = { id = 2589, name = "Linen Cloth", count = 5, loot = true },  -- a goal's
    [3] = { id = 5523, name = "Small Barnacled Clam", loot = true },
    [4] = { id = 4632, name = "Ornate Bronze Lockbox", loot = true },   -- still locked
    [5] = { id = 5524, name = "Thick-shelled Clam", loot = true, quest = true },
    [6] = { id = 2592, name = "Wool Cloth", count = 20 },
}
_G.NUM_BAG_SLOTS = 4
local used = {}
_G.C_Container = {
    GetContainerNumSlots = function(b) return b == 0 and 16 or 0 end,
    GetContainerNumFreeSlots = function(b) return b == 0 and 10 or 0, 0 end,
    GetContainerItemInfo = function(b, slot)
        local item = b == 0 and bag[slot]
        if not item then return nil end
        return { itemID = item.id, hyperlink = Link(item), stackCount = item.count or 1, quality = 1,
            isLocked = item.locked or false, hasLoot = item.loot or false, iconFileID = 1000 + item.id }
    end,
    GetContainerItemQuestInfo = function(b, slot)
        local item = b == 0 and bag[slot]
        return { isQuestItem = item and item.quest or false, isActive = false }
    end,
}
_G.LOCKED = "Locked"
_G.C_TooltipInfo = { GetBagItem = function(b, slot)
    if b == 0 and slot == 4 then return { lines = { { leftText = "Ornate Bronze Lockbox" }, { leftText = "Locked" } } } end
    return { lines = {} }
end }

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end
local handler = _G.BlackthornesFarmerEventFrame:GetScript("OnEvent")
local function Fire(event, ...) handler(_G.BlackthornesFarmerEventFrame, event, ...) end

local Open = ns.OpenButton
ns.Butler.Advise = function(_, id)
    if id == 2589 then return { goal = "Linen Cloth", have = 5, target = 20, need = 15 } end
end
Fire("BAG_UPDATE_DELAYED")

-- 1.
local function Offered()
    local ids = {}
    for _, entry in ipairs(Open.queue) do ids[#ids + 1] = entry.itemID end
    return table.concat(ids, ",")
end
suite.check("clams with loot, not the goal's, the locked box or the quest item", Offered() == "7973,5523", Offered())
suite.check("counting every one in a stack", Open.total == 4, Open.total)

_G.BlackthornesTS = { Butler = { Advise = function(_, id) if id == 5523 then return { mailCount = 2 } end end } }
Fire("BAG_UPDATE_DELAYED")
suite.check("what an alt's queued craft needs stays shut", Offered() == "7973", Offered())
_G.BlackthornesTS = nil

_G.BlackthornesButler = { Verdicts = { Choice = function(_, id) if id == 7973 then return "keep" end end } }
Fire("BAG_UPDATE_DELAYED")
suite.check("Butler's Always keep list keeps it shut", Offered() == "5523", Offered())
_G.BlackthornesButler = { Verdicts = { Choice = function() return "sell" end } }
Fire("BAG_UPDATE_DELAYED")
suite.check("Always sell is no reason to keep it shut", Offered() == "7973,5523", Offered())
_G.BlackthornesButler = nil

-- 2.
local button = Open.button
local header = ns.TrackerUI.header
suite.check("the button shows", button and button:IsShown())
suite.check("on the panel's title bar", button:GetParent() == header)
suite.check("left of the X", button._point and button._point[2] == ns.TrackerUI.closeButton)
suite.check("how many in its corner", button.count:GetText() == "4", button.count:GetText())
local said
GameTooltip.SetText = function(_, text) said = text end
button._scripts.OnEnter(button)
suite.check("Open on hover", said == "Open", tostring(said))

button._scripts.PreClick(button)
suite.check("a click uses the first clam", button:GetAttribute("type") == "macro"
    and button:GetAttribute("macrotext") == "/use 0 1", button:GetAttribute("macrotext"))
button._scripts.PostClick(button)
suite.check("nothing left aimed after", button:GetAttribute("type") == nil and button:GetAttribute("macrotext") == nil)

bag[1] = { id = 2592, name = "Wool Cloth" }
button._scripts.PreClick(button)
suite.check("a slot holding something else now is skipped", button:GetAttribute("macrotext") == "/use 0 3",
    button:GetAttribute("macrotext"))
button._scripts.PostClick(button)
bag[1] = { id = 7973, name = "Big-mouth Clam", count = 3, loot = true }

-- 3.
_G.InCombatLockdown = function() return true end
Fire("PLAYER_REGEN_DISABLED")
suite.check("a fight hides it", not button:IsShown())
suite.check("and takes it off the panel, so the panel can still move", button:GetParent() == UIParent)
_G.InCombatLockdown = nil
Fire("PLAYER_REGEN_ENABLED")
suite.check("back on the panel after", button:IsShown() and button:GetParent() == header)

Fire("MERCHANT_SHOW")
suite.check("hidden at a vendor, where a click would sell", not button:IsShown())
button._scripts.PreClick(button)
suite.check("and a click there aims at nothing", button:GetAttribute("macrotext") == nil)
Fire("MERCHANT_CLOSED")
suite.check("back when the vendor closes", button:IsShown())

ns.HandleSlash("openbutton off")
suite.check("/farm openbutton off hides it", not button:IsShown() and ns.db.openButton == false)
ns.HandleSlash("openbutton on")
suite.check("and on brings it back", button:IsShown())

-- 4.
_G.C_Container.UseContainerItem = function(b, slot)
    used[#used + 1] = b .. ":" .. slot
    local item = bag[slot]
    if item then
        item.count = (item.count or 1) - 1
        if item.count < 1 then bag[slot] = nil end
    end
end
ns.HandleSlash("openbutton test")
suite.check("the test opens one from addon code", used[1] == "0:1", tostring(used[1]))
suite.check("and keeps what it found", ns.db.openTest and ns.db.openTest.result == "works")

used = {}
Fire("LOOT_CLOSED")
suite.check("nothing opens by itself while unticked", #used == 0)

ns.HandleSlash("openbutton auto on")
suite.check("/farm openbutton auto on ticks it", ns.db.autoOpen == true)
Fire("LOOT_CLOSED")
suite.check("ticked, the next one opens after loot", used[1] == "0:1", tostring(used[1]))

used = {}
Fire("MERCHANT_SHOW")
Fire("LOOT_CLOSED")
suite.check("never at a vendor", #used == 0)
Fire("MERCHANT_CLOSED")

_G.InCombatLockdown = function() return true end
Fire("LOOT_CLOSED")
suite.check("never in a fight", #used == 0)
_G.InCombatLockdown = nil

-- One that stays shut is left for the session.
_G.C_Container.UseContainerItem = function(b, slot) used[#used + 1] = b .. ":" .. slot end
used = {}
Open.last = nil
Fire("LOOT_CLOSED")
suite.check("it tries the next", used[1] == "0:1", tostring(used[1]))
Fire("LOOT_CLOSED")
suite.check("one that stayed shut is left, the next is tried", used[2] == "0:3", tostring(used[2]))

ns.db.openTest = { result = "blocked" }
used = {}
Open.tried = {}
Fire("LOOT_CLOSED")
suite.check("a blocked test means nothing opens by itself", #used == 0)

-- Leave nothing behind for the next suite.
_G.CreateFrame = realCreate
_G.C_TooltipInfo, _G.LOCKED, _G.InCombatLockdown = nil, nil, nil

suite.done()
