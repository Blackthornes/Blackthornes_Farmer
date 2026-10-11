-- Hide skinning: drops only.
--
-- What matters: on by default (the owner asked), so a new player sees drops
-- only; while it is on, the search, Rankings' worth, the Grind tab, a mob's drops and
-- the tooltip line leave out every skinning spot and every item that comes
-- from skinning; nothing recorded is touched, so ticking it again puts it
-- all back when it is turned off; and the command and the Settings box
-- write the same setting.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("showskinning")

local ns = env.Load({ ui = true, hideSkinning = true })
local DB, Search, Tracker, Value = ns.DB, ns.Search, ns.Tracker, ns.Value

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

_G.C_Item = { GetItemInfo = function() return "item", nil, 1, 1, 1, "", "", 1, "", "", 10 end }

local function Names(results)
    local names = {}
    for _, result in ipairs(results) do names[result.item.name] = true end
    return names
end

local function AnySkinning(results)
    for _, result in ipairs(results) do
        if DB:FromSkinning(result.item) then return true end
        for _, source in ipairs(result.sources or result.item.sources) do
            if source.kind == "skinning" then return true end
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Left out from the start, then shown
--------------------------------------------------------------------------------

suite.check("skinning is left out by default", not DB:ShowsSkinning())
suite.check("saved as Hide skinning on", ns.db.hideSkinning == true and ns.DEFAULTS.hideSkinning == true)
suite.check("a fresh leather search finds nothing", not Names(Search:Run("light leather"))["Light Leather"])

ns.HandleSlash("skinning on")
suite.check("/farm skinning on shows it", DB:ShowsSkinning() and ns.db.hideSkinning == false)
suite.check("leather comes from skinning", DB:FromSkinning("Light Leather"))
suite.check("so do scraps", DB:FromSkinning("Ruined Leather Scraps"))
suite.check("cloth does not", not DB:FromSkinning("Linen Cloth"))
suite.check("nothing is hidden while it is on", not DB:HidesItem("Light Leather"))

suite.check("a search finds leather", Names(Search:Run("light leather"))["Light Leather"])
suite.check("Durotar turns up skinning", AnySkinning(Search:Run("durotar")))

-- Your own wolves, looted and skinned: a fang and leather each.
local serial = 0
local function Kill(mob, items)
    serial = serial + 1
    env.world.target = { name = mob, level = 8, dead = true, guid = "Creature-0-1-2-3-99-" .. serial }
    env.world.loot = items
    Tracker:OnLoot()
end
for _ = 1, 20 do
    Kill("Mangy Wolf", { { name = "Large Fang" }, { name = "Light Leather" } })
end

local function DropNames(mob)
    local names = {}
    for _, item in ipairs(Tracker:Summary(mob).items) do names[item.name] = true end
    return names
end

suite.check("the wolf's drops have the leather", DropNames("Mangy Wolf")["Light Leather"])
local before = Value:FromTally("Mangy Wolf")
suite.check("and its worth counts it", before and before > 0, before)

--------------------------------------------------------------------------------
-- Drops only
--------------------------------------------------------------------------------

local redrawn = 0
DB.skinningWatchers.test = function() redrawn = redrawn + 1 end

ns.HandleSlash("skinning")
suite.check("/farm skinning leaves it out", not DB:ShowsSkinning())
suite.check("saved as Hide skinning on", ns.db.hideSkinning == true)
suite.check("what lists it is redrawn", redrawn == 1, redrawn)

suite.check("a leather search finds nothing", not Names(Search:Run("light leather"))["Light Leather"])
suite.check("and says skinning is why", Search:NothingFoundText("light leather"):find("skinning", 1, true) ~= nil)
local durotar = Search:Run("durotar")
suite.check("Durotar turns up no skinning", not AnySkinning(durotar))
suite.check("but still turns up drops", #durotar > 0, #durotar)
suite.check("cloth is still found", Names(Search:Run("linen"))["Linen Cloth"])

local rows = Search:BuildRows("leather")
local leatherRow = false
for _, row in ipairs(rows) do
    if row.type == "item" and DB:FromSkinning(row.item) then leatherRow = true end
end
suite.check("the window's rows have no leather", not leatherRow)

local kinds = Search:KindsInResults("durotar")
local skinChip = false
for _, kind in ipairs(kinds) do if kind == "skinning" then skinChip = true end end
suite.check("and no Skinning chip", not skinChip)

local skinSource = false
for _, entries in pairs(DB:ByName()) do
    for _, entry in ipairs(entries) do
        if entry.source.kind == "skinning" or DB:FromSkinning(entry.item) then skinSource = true end
    end
end
suite.check("the mob index Rankings reads has no skinning", not skinSource)

suite.check("the wolf's drops leave the leather out", not DropNames("Mangy Wolf")["Light Leather"])
suite.check("but keep its fang", DropNames("Mangy Wolf")["Large Fang"])
local after, details = Value:FromTally("Mangy Wolf")
suite.check("its worth leaves the leather out", after and after < before, after)
local listed = false
for _, entry in ipairs(details.priced) do if entry.name == "Light Leather" then listed = true end end
for _, name in ipairs(details.unpriced) do if name == "Light Leather" then listed = true end end
suite.check("and does not list it", not listed)

suite.check("the tally itself is untouched",
    Tracker:Store()["Mangy Wolf"].items["Light Leather"] == 20)

ns.db.grindGives = "skinning"
suite.check("a picked Skinning chip on Grind lets go", ns.Grinding:Gives() == nil)
local leatherDrop, skinMob = false, false
for _, mob in pairs(ns.Grinding:Mobs().all) do
    if mob.skinning then skinMob = true end
    for name in pairs(mob.drops) do
        if DB:FromSkinning(name) then leatherDrop = true end
    end
end
suite.check("no camp is there for skinning", not skinMob)
suite.check("no mob's drops on Grind are leather", not leatherDrop)

local leather = DB:GetItem("Light Leather")
suite.check("leather's tooltip says nothing", ns.ItemTooltip:LineFor(leather, ns.Spots:Player()) == nil)

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

ns.SettingsUI:Show()
local box = ns.SettingsUI.controls.hideSkinning
suite.check("the Hide skinning box is ticked", box:GetChecked() == true)
box:GetScript("OnClick")(box)
suite.check("unticking it shows skinning again", DB:ShowsSkinning() and ns.db.hideSkinning == false)
suite.check("Grind's Skinning comes back", ns.Grinding:Gives() == "skinning")
ns.SettingsUI:Hide()

suite.check("leather is found again", Names(Search:Run("light leather"))["Light Leather"])
suite.check("the wolf's leather is back", DropNames("Mangy Wolf")["Light Leather"])
suite.check("and its worth", Value:FromTally("Mangy Wolf") == before)

ns.HandleSlash("skinning off")
suite.check("/farm skinning off", not DB:ShowsSkinning())
ns.HandleSlash("skinning off")
suite.check("says off twice, stays off", not DB:ShowsSkinning())
ns.HandleSlash("skinning on")
suite.check("/farm skinning on", DB:ShowsSkinning())

-- Every redraw runs clean, with the windows built and a search shown.
ns.UI:Show()
ns.UI:Search("leather")
ns.UI.filterKind = "skinning"
for name, redraw in pairs(DB.skinningWatchers) do
    local ok, err = pcall(redraw)
    suite.check("the " .. name .. " redraw runs", ok, err)
end
DB:SetShowSkinning(false)
suite.check("a picked Skinning chip in the search lets go", ns.UI.filterKind == nil)
DB:SetShowSkinning(true)
ns.UI:Hide()

DB.skinningWatchers.test = nil
ns.db.grindGives = nil

return suite
