-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.31.0", lines = {
        "When a mob climbs into your top 15, a little card pops up and shows it moving up the list.",
        "The Kills & Loot panel starts empty each time you log in again. All your data is still kept.",
        "Fixed the ADDON BLOCKED error on your 20th catch.",
    } },
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
}
