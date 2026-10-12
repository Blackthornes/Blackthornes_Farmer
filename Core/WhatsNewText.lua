-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.29.0", lines = {
        "No Tradeskills? Farmer can price your loot with TradeSkillMaster or Auctionator now.",
    } },
    { version = "0.28.0", lines = {
        "Farmer speaks Deutsch now if your game is in German.",
    } },
    { version = "0.27.1", lines = {
        "Right-click to hide something and the menu now pops up right where your mouse is.",
        "With skinning hidden, skins no longer count in your loot or gold per hour.",
    } },
}
