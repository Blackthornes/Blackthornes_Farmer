-- Your counts as a spreadsheet (Logic/CSV.lua, asked 2026-10-12).
--
-- What matters: each sheet has its heading and one row per mob or spot and
-- item; fields with commas or quotes are quoted and formulas are defused;
-- what the player hides stays out; a big sheet comes in parts, each with the
-- heading; nothing is changed; and /farm export csv opens it.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("csv")

local ns = env.Load({ ui = true })
for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end
_G.InCombatLockdown = function() return false end

local CSV = ns.CSV
suite.check("the module is loaded", CSV ~= nil)

--------------------------------------------------------------------------------
-- Fields
--------------------------------------------------------------------------------

suite.check("plain text is as it is", CSV.Field("Defias Thug") == "Defias Thug")
suite.check("a comma is quoted", CSV.Field("Shore, North") == '"Shore, North"', CSV.Field("Shore, North"))
suite.check("a quote is doubled", CSV.Field('The "Big" One') == '"The ""Big"" One"', CSV.Field('The "Big" One'))
suite.check("a formula is defused", CSV.Field("=HYPERLINK(1)") == "'=HYPERLINK(1)", CSV.Field("=HYPERLINK(1)"))
suite.check("whole numbers stay whole", CSV.Field(12) == "12")
suite.check("fractions lose trailing zeros", CSV.Field(0.125) == "0.125", CSV.Field(0.125))
suite.check("nothing is an empty field", CSV.Field(nil) == "")

--------------------------------------------------------------------------------
-- Sheets
--------------------------------------------------------------------------------

ns.Harvest.records = {
    ["Defias Thug|Westfall|"] = {
        mob = "Defias Thug", zone = "Westfall", minLevel = 10, maxLevel = 12, corpses = 40,
        coords = { 45.25, 30.5 },
        items = {
            ["Linen Cloth"] = { name = "Linen Cloth", corpses = 10, count = 14, id = 2589 },
            ["Light Leather"] = { name = "Light Leather", corpses = 5, count = 5, id = 2318 },
        },
    },
    ["Murloc|Westfall|Shore, North"] = {
        mob = "Murloc", zone = "Westfall", location = "Shore, North", corpses = 3, items = {},
    },
}
ns.db.tracker = { mobs = {
    ["Defias Thug"] = { kills = 40, copper = 800, coinKills = 40, items = { ["Linen Cloth"] = 10 },
        qty = {}, stacks = {}, places = {} },
    ["Kobold"] = { kills = 3, copper = 30, coinKills = 3, items = {}, qty = {}, stacks = {}, places = {} },
} }
ns.db.gathering = { nodes = {
    ["Elwynn Forest||Peacebloom"] = { zone = "Elwynn Forest", node = "Peacebloom", kind = "herb", gathers = 8,
        items = { Peacebloom = { gathers = 8, count = 12, id = 2447 } } },
} }
ns.db.fishing = { spots = {
    ["Westfall||"] = { zone = "Westfall", school = "open water", casts = 20,
        items = { ["Raw Brilliant Smallfish"] = { casts = 15, count = 15, id = 6291 } } },
} }

local function Sheet(key)
    local got, rows
    CSV:Build(key, function(parts, count) got, rows = parts, count end)
    return got and got[1] or "", rows, got
end

local function Lines(text)
    local out = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do out[#out + 1] = line end
    return out
end

local loot, lootRows = Sheet("loot")
local lines = Lines(loot)
suite.check("the loot sheet has a heading", lines[1]:find("^Mob,Zone,") ~= nil, lines[1])
suite.check("a row per mob and item, and one for a mob with no items", lootRows == 3, lootRows)
suite.check("items are in order under their mob",
    lines[2]:find("^Defias Thug,Westfall,,10,12,45.3,30.5,40,Light Leather,2318,5,5,12.5,") ~= nil, lines[2])
suite.check("drop rate from corpses", lines[3]:find("Linen Cloth,2589,10,14,25,", 1, true) ~= nil, lines[3])
suite.check("a subzone with a comma is quoted", lines[4]:find('"Shore, North"', 1, true) ~= nil, lines[4])

local kills, killRows = Sheet("kills")
lines = Lines(kills)
suite.check("the kills sheet, most kills first", killRows == 2 and lines[2]:find("^Defias Thug,40,0.08,0.002") ~= nil, lines[2])
suite.check("a mob under 20 kills has no worth", lines[3]:find("^Kobold,3,0.003,0.001,$") ~= nil, lines[3])

local gathering = Sheet("gathering")
suite.check("the gathering sheet", Lines(gathering)[2]:find("^Peacebloom,herb,Elwynn Forest,,,,8,Peacebloom,2447,8,12,100,") ~= nil,
    Lines(gathering)[2])

local fishing = Sheet("fishing")
suite.check("the fishing sheet names open water", Lines(fishing)[2]:find("^open water,Westfall,,,,20,Raw Brilliant Smallfish,6291,15,15,75,") ~= nil,
    Lines(fishing)[2])

--------------------------------------------------------------------------------
-- Hidden things stay out, nothing changes
--------------------------------------------------------------------------------

ns.DB:Hide("item", "Light Leather")
ns.DB:Hide("source", "Kobold")
loot = Sheet("loot")
suite.check("a hidden item is left out", not loot:find("Light Leather", 1, true))
kills = Sheet("kills")
suite.check("a hidden mob is left out", not kills:find("Kobold", 1, true))
ns.DB:Unhide("item", "Light Leather")
ns.DB:Unhide("source", "Kobold")
suite.check("the records are unchanged", ns.Harvest.records["Defias Thug|Westfall|"].items["Light Leather"].corpses == 5
    and ns.db.tracker.mobs.Kobold.kills == 3)

--------------------------------------------------------------------------------
-- Parts
--------------------------------------------------------------------------------

local keep = CSV.PART_CHARS
CSV.PART_CHARS = 120
local _, _, parts = Sheet("loot")
CSV.PART_CHARS = keep
suite.check("a big sheet comes in parts", #parts > 1, #parts)
local headed = true
for _, part in ipairs(parts) do
    if not part:find("^Mob,Zone,") then headed = false end
end
suite.check("each with the heading", headed)

--------------------------------------------------------------------------------
-- The command and the window
--------------------------------------------------------------------------------

suite.check("sheet words", CSV.SheetFor("") == "loot" and CSV.SheetFor("kill") == "kills"
    and CSV.SheetFor("fish") == "fishing" and CSV.SheetFor("bogus") == nil)

ns.HandleSlash("export csv kills")
suite.check("/farm export csv kills opens it", ns.UI.exportFrame:IsShown()
    and (ns.UI.exportText or ""):find("^Mob,Kills,") ~= nil, ns.UI.exportText)
suite.check("with the sheets as tabs", ns.UI.exportSheets ~= nil and ns.UI.exportSheets:IsShown())

ns.UI.exportPick("fishing")
suite.check("picking a tab shows that sheet", (ns.UI.exportText or ""):find("^Spot,") ~= nil, ns.UI.exportText)

ns.HandleSlash("export")
suite.check("the plain export hides the tabs again", not ns.UI.exportSheets:IsShown())
suite.check("and is the data file", (ns.UI.exportText or ""):find("^%-%- Harvested") ~= nil)

suite.done()
