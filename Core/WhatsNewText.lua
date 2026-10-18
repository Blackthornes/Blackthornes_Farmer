-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.43.0", lines = {
        "Each tooltip line Farmer adds can be Off, Shift or Always. You pick under Tooltips on the Map & goals page of Settings.",
        "Kill count on nameplates has a Counter Position choice. It can sit above, below, left or right of the name.",
    } },
    { version = "0.42.0", lines = {
        "Farmer speaks Simplified Chinese, French, Spanish and Russian now if your game is in one of those.",
    } },
    { version = "0.41.0", lines = {
        "A heat map shows where you have killed on the world map and the minimap. It's off until you turn it on under Kill Heat on the Map & goals page of Settings. Then press Map beside a mob or item in the search, or on a mob's loot card.",
        "Rankings can leave Uncommon, Rare and Epic drops out of worth per kill. The tick box is on the Rankings tab.",
        "Quest items are marked Quest in the loot lists.",
    } },
}
