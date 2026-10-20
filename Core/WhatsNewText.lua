-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.44.0", lines = {
        "Loot Feed shows what you loot in a small list, with the coin and what it's all worth. It's off until you tick it on the Loot page of Settings.",
        "The trash can in your bags now puts a red glow round the item it picked. It's on the Loot page, under Trash Can When Full.",
    } },
    { version = "0.43.0", lines = {
        "Each tooltip line Farmer adds can be Off, Shift or Always. You pick under Tooltips on the Map & goals page of Settings.",
        "Kill count on nameplates has a Counter Position choice. It can sit above, below, left or right of the name.",
    } },
    { version = "0.42.0", lines = {
        "Farmer speaks Simplified Chinese, French, Spanish and Russian now if your game is in one of those.",
    } },
}
