-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.22.0", lines = {
        "New Marker Size choice makes the marks on your maps smaller or bigger.",
        "Blackthornes now has one button on your addon bar.",
        "Settings pages sit in the same order in every Blackthornes addon.",
        "At a vendor, the window opens on Butler.",
        "Various bug fixes for Farmer.",
    } },
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
}
