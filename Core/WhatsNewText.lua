-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.14.0", lines = {
        "There is a new box that mutes every sound from all the Blackthornes addons at once. It starts off, so nothing changes until you tick it.",
    } },
    { version = "1.13.0", lines = {
        "Pick where the quest count sits next to a mob's name: above, below, left or right.",
        "The quest count is bigger and brighter, so it is easier to read.",
        "It still starts on the right, so nothing moves unless you pick a new spot.",
    } },
    { version = "1.12.0", lines = {
        "There is a new little gold gem on the world map. One click hides all of Farmer's marks, and another brings them back.",
        "Right-click the gem to choose which marks to hide.",
        "Camp swords now only show while the Grind tab is open.",
    } },
}
