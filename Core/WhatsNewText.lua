-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "1.10.0", lines = {
        "Loot Beacons put a beam over the body in front of you while it still has loot. You can pick the color and size. Turn it on in Settings, on the Loot page.",
    } },
    { version = "1.9.0", lines = {
        "A new box in Settings, on the Map & goals page, called My Professions Only. Ticked, only the herbs, ore and fish your character can gather light up. It starts off.",
    } },
    { version = "1.8.0", lines = {
        "You can turn off the beam over your fishing bobber if it hides the bob. It is in Settings, on the Map & goals page, under Sparkles.",
    } },
}
