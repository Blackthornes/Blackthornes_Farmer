-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.3.0", lines = {
        "All your Blackthornes addons share one window. A strip down the left has a button for each addon you have, and the tabs of the one you pick sit beside it. At the auction house, mailbox, vendor and trainer it sits next to the game's window, and it goes back when you close that one. Turn it off with One Window on the General page.",
    } },
    { version = "1.2.0", lines = {
        "Drop Goals under Kills & Loot and it stays there. Drop Where to Farm under Goals and it opens there. You can turn this off with Snap Panels on the General page.",
        "Right-click a row and the thing you most likely want comes first, like Open Loot Table.",
    } },
    { version = "1.1.0", lines = {
        "One minimap button now covers every Blackthornes addon you have. Click it to pick one. Turn it off with Combine Addon Buttons on the Windows page.",
        "Show on Map in Where to farm puts a gold marker with the name on the spot.",
    } },
}
