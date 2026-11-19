-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.27.0", lines = {
        "Every window has a gold gem on its title bar. Click it to switch between the one window and separate windows.",
    } },
    { version = "1.25.0", lines = {
        "The Kill Heat card starts smaller, and you can size it.",
        "A mob's card shows what you picked from its pockets.",
        "A new Exclude Rarity choice leaves rarities out of worth per kill.",
    } },
    { version = "1.22.0", lines = {
        "New Marker Size choice makes the marks on your maps smaller or bigger.",
        "Blackthornes now has one button on your addon bar.",
        "Settings pages sit in the same order in every Blackthornes addon.",
        "At a vendor, the window opens on Butler.",
        "Various bug fixes for Farmer.",
    } },
}
