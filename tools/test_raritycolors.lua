-- Item names in their rarity colour.
--
-- What matters: a name shows in its quality's colour, white for common and
-- green for uncommon; a name the game has not loaded yet shows as it is,
-- is asked for once, and takes its colour when the item arrives (the lists
-- that name items are told); the goal cards, the hidden list, the clam note
-- and the chat line for a goal show it; hiding an item keeps its plain name.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("raritycolors")

local ns = env.Load({ ui = true })
local Util = ns.Util
Util.ForgetRarity()

local LINEN, GREEN, LATE = 2589, 990101, 990102
local quality = { [LINEN] = 1, [GREEN] = 2 }
local asked = {}
_G.C_Item = {
    GetItemInfo = function(id)
        if quality[id] == nil then return nil end
        return "item", nil, quality[id], 1, 1, "", "", 1, "", "", 1
    end,
    RequestLoadItemDataByID = function(id) asked[id] = (asked[id] or 0) + 1 end,
}

suite.check("a common item is white", Util.ColorItem("Linen Cloth", LINEN) == "|cffffffffLinen Cloth|r",
    Util.ColorItem("Linen Cloth", LINEN))
suite.check("by its name too, through the data's ID", Util.ColorItem("Linen Cloth") == "|cffffffffLinen Cloth|r",
    Util.ColorItem("Linen Cloth"))
suite.check("an uncommon item is green", Util.ColorItem("Lucky Charm", GREEN) == "|cff1eff00Lucky Charm|r",
    Util.ColorItem("Lucky Charm", GREEN))
suite.check("the colour stands in for another text", Util.ColorItem("Lucky Charm", GREEN, "x") == "|cff1eff00x|r")

-- Not loaded yet: shown as it is, asked for once.
suite.check("not loaded: plain", Util.ColorItem("Late Gem", LATE) == "Late Gem")
Util.ColorItem("Late Gem", LATE)
suite.check("asked for once, not every draw", asked[LATE] == 1, asked[LATE])
suite.check("plain with a fallback colour", Util.ColorItemOr("accent", "Late Gem", LATE)
    == ("|c%sLate Gem|r"):format(ns.COLORS.accent))

local told = 0
Util.OnRarity("test", function() told = told + 1 end)
quality[LATE] = 3
local fire = ns.eventFrame:GetScript("OnEvent")
fire(ns.eventFrame, "GET_ITEM_INFO_RECEIVED", LATE, true)
suite.check("the lists hear when it arrives", told == 1, told)
suite.check("and it shows blue", Util.ColorItem("Late Gem", LATE) == "|cff0070ddLate Gem|r",
    Util.ColorItem("Late Gem", LATE))
Util.OnRarity("test", nil)

-- The loot link's colour wins over asking.
ns.Tracker:Looks()["Shiny Gem"] = { color = "ffa335ee", id = 990103 }
suite.check("a kept loot link's colour", Util.ColorItem("Shiny Gem") == "|cffa335eeShiny Gem|r",
    Util.ColorItem("Shiny Gem"))

-- The clam note.
suite.check("the clam note names it in colour",
    ns.OpenNote.Text("Linen Cloth", 3, LINEN) == "|cffffffffLinen Cloth|r: 3 of 10 opened",
    ns.OpenNote.Text("Linen Cloth", 3, LINEN))

-- The hidden list: the row in colour, the kept key plain.
local row = { tag = ns.Theme.CreateLabel(UIParent, "small", "text"),
    name = ns.Theme.CreateLabel(UIParent, "small", "text") }
ns.HiddenUI:UpdateRow(row, { kind = "item", name = "Linen Cloth" })
suite.check("a hidden item's row in colour", row.name:GetText() == "|cffffffffLinen Cloth|r", row.name:GetText())
ns.HiddenUI:UpdateRow(row, { kind = "source", name = "Mangy Wolf" })
suite.check("a hidden mob's row as it is", row.name:GetText() == "Mangy Wolf")
local kept = ns.DB:Hide("item", "Linen Cloth")
suite.check("hiding keeps the plain name", kept == "Linen Cloth"
    and ns.db.hiddenItems["linen cloth"] == "Linen Cloth", kept)
ns.DB:Unhide("item", "Linen Cloth")

-- A goal set in chat names the item in its colour.
env.chat = {}
ns.HandleSlash("goal Linen Cloth 20")
local said = table.concat(env.chat, "\n")
suite.check("the goal's chat line names it in colour", said:find("|cffffffffLinen Cloth|r", 1, true) ~= nil, said)
local goal = ns.Goals:Find("Linen Cloth")
suite.check("the goal keeps its plain name", goal and goal.item == "Linen Cloth", goal and goal.item)
ns.Goals:Remove("Linen Cloth")

_G.C_Item = nil
Util.ForgetRarity()
suite.done()
