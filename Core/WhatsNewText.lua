-- Core/WhatsNewText.lua
-- Written by tools/make_whatsnew.py from NEWS.md. Never edit it by hand:
-- change NEWS.md and run the tool. UI/WhatsNew.lua shows it.

local _, ns = ...

ns.WHATS_NEW = {
    { version = "0.31.0", lines = {
        "When a kill moves a mob into or up your top 15, the list pops up beside the Kills & Loot panel and shows it climbing.",
    } },
    { version = "0.30.0", lines = {
        "Zones show their German names on a Deutsch client, and Forever's new zones are known.",
        "Blue drops and finished goals play a voice line.",
        "Export your loot, kills, gathering and fishing to a spreadsheet.",
    } },
    { version = "0.29.0", lines = {
        "Without Tradeskills, Farmer prices your loot from TradeSkillMaster or Auctionator.",
    } },
}
