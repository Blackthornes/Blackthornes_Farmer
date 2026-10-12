-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.30.1", lines = {
        "The Kills & Loot panel scrolls smoothly now.",
        "Gold per hour keeps counting after a reload.",
        "Grey items are always priced at what a vendor pays.",
        "Fixes for sharing, importing, map clicks and Deutsch clients.",
    } },
    { version = "0.30.0", lines = {
        "A new What's New window shows what changed after each update.",
        "Zones show their German names on a Deutsch client, and Forever's new zones are in.",
        "Blue drops and finished goals now get a voice line.",
        "Export your loot, kills, gathering and fishing as a spreadsheet.",
        "The Kills & Loot and Goals panels got the new dark look.",
    } },
    { version = "0.29.0", lines = {
        "No Tradeskills? Farmer can price your loot with TradeSkillMaster or Auctionator now.",
    } },
}
