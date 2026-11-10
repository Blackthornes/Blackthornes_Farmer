-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.12.0", lines = {
        "There is a new little gold gem on the world map. One click hides all of Farmer's marks, and another brings them back.",
        "Right-click the gem to choose which marks to hide.",
        "Camp swords now only show while the Grind tab is open.",
    } },
    { version = "1.11.0", lines = {
        "Pick a sound for when you find a node. Your character can call out, a peon can say he is ready to work, or you can get a little ping.",
        "It starts off, so you only hear it if you choose it.",
    } },
    { version = "1.10.0", lines = {
        "Loot Beacons put a beam over the body in front of you while it still has loot. You can pick the color and size. Turn it on in Settings, on the Loot page.",
    } },
}
