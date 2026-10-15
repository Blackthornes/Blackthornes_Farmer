-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.35.0", lines = {
        "Thanks Manthieus, seancool_com and their communities for the ideas and feedback! Catch their streams at twitch.tv/Manthieus and twitch.tv/seancool_com.",
        "An Open button on the kills panel opens your clams, sacks and lockboxes. Turn on Open after loot in Settings to open them as you go.",
        "Clams and sacks count for what's inside them, and a small note shows each one you open.",
        "A notice shows when your bags are full.",
        "Search finds items you looted, gathered or fished yourself, and plurals like \"crates\" work.",
        "Mobs show your kill count beside their nameplate.",
        "Material tooltips say when crafting pays more than selling.",
        "Tooltips and Settings descriptions are shorter and easier to read.",
    } },
    { version = "0.34.0", lines = {
        "After an auction house scan, your top 15 farms pop up and show how they moved. A new best farm gets its own sound.",
        "Mobs in Forever's new dungeons get their names, and you can name any that are still numbers.",
        "The Rankings tab has a box that hides mobs found only in dungeons.",
    } },
    { version = "0.33.0", lines = {
        "The Grind tab now shows Leather, Ore and Herbs too, with what each is worth and which nodes you can gather.",
        "A mob's tooltip lists the three drops that add the most to a kill.",
    } },
}
