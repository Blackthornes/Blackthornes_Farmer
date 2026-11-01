-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.4.3", lines = {
        "Map markers now show only the nodes your character can gather.",
    } },
    { version = "1.4.0", lines = {
        "One key can now put on a lure, cast and reel in your line.",
        "The Grind tab shows what each camp earns you an hour.",
        "Item icons look nicer, with quality rings and counts in the corner.",
    } },
    { version = "1.3.0", lines = {
        "All your Blackthornes addons share one window. A strip down the left has a button for each addon you have, and the tabs of the one you pick sit beside it. At the auction house, mailbox, vendor and trainer it sits next to the game's window, and it goes back when you close that one. Turn it off with One Window on the General page.",
    } },
}
