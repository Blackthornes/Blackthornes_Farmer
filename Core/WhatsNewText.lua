-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.21.0", lines = {
        "Farmer has a new Farms tab. Save a farm and run it again with one click.",
        "Pick the zone and the mob you want, and the best drop chance shows first.",
    } },
    { version = "1.20.0", lines = {
        "Farmer's new Dock to the Map box lets Where to Farm sit beside the world map.",
        "Settings is sorted into clearer pages, with an All Addons page for what every addon shares.",
        "The window can dock in more places and you can resize it by hand.",
        "Small pieces line up on shelves instead of piling in one spot.",
    } },
    { version = "1.19.1", lines = {
        "There's a new Gather Route. It plans a short loop through the herb, ore and skinning spots you've mapped, and the arrow leads you stop to stop. Turn it on in the Map & goals page of Settings.",
        "The Grind tab has a Route Mode box on the Herbs, Ore and Leather pages that shows your route.",
        "A small Route Window can sit on your screen while you run a route. It has a Leveling Mode that puts spots that still give skill first.",
    } },
}
