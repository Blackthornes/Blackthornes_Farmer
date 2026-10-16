-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.37.0", lines = {
        "The Kills & Loot panel can be see-through. It's off until you turn it on, and you pick how clear.",
        "Tradeskills can tell which items you looted, gathered or fished yourself.",
        "When your bags are full, the trash can points at two short stacks you can join first, so nothing gets thrown away.",
    } },
    { version = "0.36.0", lines = {
        "A mob with the same name in another zone gets its own line.",
        "Tradeskills can show which of your kills drop items that break into an enchanting material.",
    } },
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
}
