-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.18.0", lines = {
        "There's a session timer for your Kills & Loot panel, with Start, Pause and Stop. You turn it on in the Kills page of Settings.",
        "Rankings can now price every drop at what a vendor pays. It's a box on the Rankings tab.",
        "Secret Bait shows up in the Add Lure list.",
        "Hover a row in the loot feed to see the item's tooltip.",
    } },
    { version = "1.17.0", lines = {
        "In a group, the quest count over a mob can now show only your own quests. It's a box on the Map & goals page.",
        "Gear that binds when worn can use its own TSM price. You pick it on the Loot page.",
    } },
    { version = "1.16.0", lines = {
        "You can pick which TSM price to use, on the Loot page. It starts on the recent price.",
        "In a group, only the loot you really got counts now.",
    } },
}
