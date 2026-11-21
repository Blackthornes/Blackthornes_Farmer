-- Item rows answer the game's item clicks (the owner, 2026-11-21): Shift-click
-- with a chat box open puts the item's link in it, Ctrl-click tries gear on,
-- and a row's own click is left alone otherwise (UI/Widgets.lua ItemClick,
-- CreateRowList's itemOf).

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("itemclicks")

local ns = env.Load({ ui = true })
local Widgets = ns.Widgets

local LINK = "|cff1eff00|Hitem:2034:::::|h[Slayer's Gloves]|h|r"
local keys, chatOpen, inserted, dressed, handled = {}, false, {}, {}, 0

local function Reset()
    keys, chatOpen, inserted, dressed, handled = {}, false, {}, {}, 0
end

_G.IsModifiedClick = function(kind)
    if kind == "CHATLINK" then return keys.shift and true or false end
    if kind == "DRESSUP" then return keys.ctrl and true or false end
    return false
end
_G.ChatEdit_GetActiveWindow = function() return chatOpen and {} or nil end
_G.ChatEdit_InsertLink = function(link)
    if not chatOpen then return false end
    inserted[#inserted + 1] = link
    return true
end
_G.DressUpItemLink = function(link) dressed[#dressed + 1] = link; return true end
_G.C_Item = { GetItemInfo = function(id)
    if id == 2034 then return "Slayer's Gloves", LINK end
end }

-- 1. The helper, with no game click handler.
do
    Reset()
    suite.check("a plain click is left to the row", Widgets.ItemClick(2034) == false)
    keys.shift = true
    suite.check("Shift with the chat box shut is left to the row", Widgets.ItemClick(2034) == false)
    suite.check("and nothing went in chat", #inserted == 0)
    chatOpen = true
    suite.check("Shift with the chat box open is taken", Widgets.ItemClick(2034) == true)
    suite.check("and puts the item's link in it", inserted[1] == LINK)
    suite.check("an item the game has not loaded is left alone", Widgets.ItemClick(99999) == false)
    keys.shift, chatOpen = false, false
    keys.ctrl = true
    suite.check("Ctrl tries the item on", Widgets.ItemClick(2034) == true and dressed[1] == LINK)
    suite.check("Ctrl tries on by number while the item loads",
        Widgets.ItemClick(99999) == true and dressed[2] == "item:99999")
    suite.check("no item, nothing to do", Widgets.ItemClick(nil) == false)
end

-- 2. The game's own click handler does the work where it is there.
do
    Reset()
    _G.HandleModifiedItemClick = function(link)
        handled = handled + 1
        if keys.shift then return _G.ChatEdit_InsertLink(link) end
        if keys.ctrl then return _G.DressUpItemLink(link) end
        return false
    end
    keys.shift, chatOpen = true, true
    suite.check("the game's handler takes the chat link",
        Widgets.ItemClick(2034) == true and handled == 1 and inserted[1] == LINK)
    chatOpen = false
    suite.check("and is not asked while the chat box is shut", Widgets.ItemClick(2034) == false and handled == 1)
    _G.HandleModifiedItemClick = function() error("secret") end
    keys.shift, keys.ctrl = false, true
    suite.check("a handler that raises falls back to trying on", Widgets.ItemClick(2034) == true and #dressed == 1)
    _G.HandleModifiedItemClick = nil
end

-- 3. A row list with itemOf: Shift and Ctrl go to the item, the rest to the row.
do
    Reset()
    local clicks = {}
    local list = Widgets.CreateRowList(UIParent, {
        rowHeight = 20,
        itemOf = function(data) return data.id end,
        onClick = function(data, button) clicks[#clicks + 1] = button end,
    })
    list:SetData({ { id = 2034 }, { text = "not an item" } })
    local row, plain = list.rows[1], list.rows[2]
    row:GetScript("OnClick")(row, "LeftButton")
    suite.check("a plain click reaches the row", clicks[1] == "LeftButton")
    keys.shift, chatOpen = true, true
    row:GetScript("OnClick")(row, "LeftButton")
    suite.check("Shift-click with the chat box open links it", inserted[1] == LINK and #clicks == 1)
    chatOpen = false
    row:GetScript("OnClick")(row, "LeftButton")
    suite.check("with the chat box shut the row keeps its click", #clicks == 2 and #inserted == 1)
    chatOpen = true
    plain:GetScript("OnClick")(plain, "LeftButton")
    suite.check("a row that is no item keeps its click", #clicks == 3 and #inserted == 1)
    row:GetScript("OnClick")(row, "RightButton")
    suite.check("a right-click is the row's", #clicks == 4)
end

-- 4. A goal card: Shift-click links with the chat box open, aims otherwise.
do
    Reset()
    local aimed = {}
    local savedArrow, savedItemID = ns.Arrow, ns.Util.ItemIDOf
    ns.Arrow = { Aim = function(_, item) aimed[#aimed + 1] = item end }
    ns.Util.ItemIDOf = function(name) return name == "Slayer's Gloves" and 2034 or nil end
    _G.IsShiftKeyDown = function() return keys.shift end
    local card = { goal = { item = "Slayer's Gloves", target = 1 } }
    keys.shift, chatOpen = true, true
    ns.GoalsUI:OnCardClick(card, "LeftButton")
    suite.check("a goal card links its item with the chat box open", inserted[1] == LINK and #aimed == 0)
    chatOpen = false
    ns.GoalsUI:OnCardClick(card, "LeftButton")
    suite.check("and still aims the arrow with it shut", aimed[1] == "Slayer's Gloves" and #inserted == 1)
    ns.Arrow, ns.Util.ItemIDOf = savedArrow, savedItemID
    _G.IsShiftKeyDown = nil
end

_G.IsModifiedClick, _G.ChatEdit_GetActiveWindow, _G.ChatEdit_InsertLink, _G.DressUpItemLink = nil, nil, nil, nil
_G.C_Item = nil

suite.done()
