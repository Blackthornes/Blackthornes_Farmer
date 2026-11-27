-- Names as you type (2026-11-26): under the search box the best few items,
-- mobs and zones that match what you typed show as you type, tagged with
-- what each is. A German player typed "Wollstoff" and thought Farmer only
-- knew English.
--
-- What matters: items match by the client's name and the English one, mobs
-- and zones match too, two letters start it and eight is the most, a hidden
-- item is never offered, the arrow keys and Enter open a line, Enter with
-- none picked does what it did before, the same word does not ask twice,
-- and the box on the Panels page turns it off.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("searchsuggest")
local check = suite.check

local WOOL = 2592

local function Login(german)
    local ns = env.Load({ ui = true })
    if german then
        _G.GetLocale = function() return "deDE" end
        _G.C_Item = {
            GetItemNameByID = function(id) if id == WOOL then return "Wollstoff" end end,
            GetItemInfo = function(item) if item == WOOL then return "Wollstoff" end end,
            RequestLoadItemDataByID = function() end,
        }
    end
    _G.BlackthornesFarmerDB = {}
    ns.LoadSavedVariables()
    ns.db.oneWindow = false
    return ns
end

local function Has(found, kind, name)
    for _, entry in ipairs(found) do
        if entry.kind == kind and (not name or entry.name == name) then return entry end
    end
    return nil
end

--------------------------------------------------------------------------------
-- What it finds
--------------------------------------------------------------------------------

local ns = Login(false)
local Search = ns.Search

check("on unless unticked", Search.SuggestOn())
check("one letter offers nothing", #Search:Suggest("w") == 0)

local found = Search:Suggest("wool")
check("an item by its name", Has(found, "item", "Wool Cloth"))
check("eight at most", #found <= Search.SUGGEST_MAX, #found)
check("a name that starts with it comes first",
    found[1] and found[1].name:lower():find("^wool") ~= nil, found[1] and found[1].name)
check("an item is tagged Item", Search.SuggestTag(Has(found, "item", "Wool Cloth")) == "Item")

found = Search:Suggest("defias")
local mob = Has(found, "mob")
check("mobs match", mob ~= nil)
check("a mob is tagged with its zone", mob and Search.SuggestTag(mob) == "Mob, " .. mob.zone,
    mob and Search.SuggestTag(mob))

found = Search:Suggest("westf")
local zone = Has(found, "zone", "Westfall")
check("zones match", zone ~= nil)
check("a zone is tagged Zone", zone and Search.SuggestTag(zone) == "Zone")
check("the same word does not ask twice", Search:Suggest("westf") == found)

check("a word in the middle of a name matches", Has(Search:Suggest("cloth"), "item", "Wool Cloth"))


ns.DB:Hide("item", "Wool Cloth")
check("a hidden item is never offered", not Has(Search:Suggest("wool"), "item", "Wool Cloth"))
ns.DB:Unhide("item", "Wool Cloth")
check("unhidden it is back", Has(Search:Suggest("wool"), "item", "Wool Cloth"))

--------------------------------------------------------------------------------
-- The list under the Search tab's box
--------------------------------------------------------------------------------

local UI = ns.UI
UI:Show()
UI:ShowTab("search")
local holder = UI.searchBox
local box = holder.editBox
local list = holder.suggest
check("the Search tab's box has the list", list ~= nil)

local function Type(text)
    box:SetText(text)
    box:GetScript("OnTextChanged")(box, true)
end

Type("wool")
check("typing shows the list", list:IsShown())
check("it shows a line for each name", list.rows[1] and list.rows[1]:IsShown()
    and list.rows[1].name:GetText() == list.state.found[1].name)
check("the hint is under the lines", list.hint:GetText() == "Arrow keys pick a line, Enter opens it.")
check("typing still searches as before", UI.lastQuery == "wool", UI.lastQuery)

local asked = 0
local Suggest = Search.Suggest
Search.Suggest = function(...) asked = asked + 1 return Suggest(...) end
Type("wool ")
check("the same word with a space is not drawn again", asked == 0, asked)
Search.Suggest = Suggest

local arrow = box:GetScript("OnArrowPressed")
arrow(box, "DOWN")
check("down picks the first line", list.state.picked == 1 and list.rows[1].state.picked)
arrow(box, "UP")
check("up from the first goes to the last", list.state.picked == #list.state.found)
arrow(box, "DOWN")
check("down from the last goes to the first", list.state.picked == 1)

local first = list.state.found[1].name
box:GetScript("OnEnterPressed")(box)
check("Enter opens the picked line", UI.lastQuery == first and holder:GetText() == first, UI.lastQuery)
check("and the list goes", not list:IsShown())

Type("wool")
check("typing again shows it again", list:IsShown())
box:GetScript("OnEscapePressed")(box)
check("Escape closes it", not list:IsShown())

Type("wool")
local row = list.rows[2] or list.rows[1]
row:Click()
check("a click opens a line", UI.lastQuery == row.state.entry.name, UI.lastQuery)
check("and the list goes after a click", not list:IsShown())

Type("wool")
box:GetScript("OnEnterPressed")(box)
check("Enter with no line picked searches what you typed", UI.lastQuery == "wool", UI.lastQuery)
check("and closes the list", not list:IsShown())

Type("wool")
Type("")
check("an empty box has no list", not list:IsShown())

Type("wool")
box:GetScript("OnEditFocusLost")(box)
check("clicking away closes it", not list:IsShown())

Search.SetSuggestOn(false)
check("unticked it is saved as false", ns.db.searchNames == false)
Type("westf")
check("unticked, typing shows no list", not list:IsShown())
check("unticked, typing still searches", UI.lastQuery == "westf")
Search.SetSuggestOn(true)
check("ticked again it is saved as unset", ns.db.searchNames == nil)

--------------------------------------------------------------------------------
-- A German client
--------------------------------------------------------------------------------

ns = Login(true)
ns.DB:LearnClientNames()
for _ = 1, 50 do
    if not ns.DB.learning then break end
    ns.DB:LearnClientNames()
end
-- Names are read a few a frame; read them all now.
if ns.DB.LearnAllNamesNow then ns.DB:LearnAllNamesNow() end
local wool = ns.DB:GetItem("Wool Cloth")
if not ns.DB:ClientName(wool) then
    ns.DB.clientNameOf[wool] = "Wollstoff"
    ns.DB.namesVersion = (ns.DB.namesVersion or 0) + 1
end

found = ns.Search:Suggest("wollst")
local german = Has(found, "item", "Wollstoff")
check("the client's name finds it", german ~= nil)
check("it shows the client's name", german and german.id == WOOL)
check("the English name still finds it", Has(ns.Search:Suggest("wool cl"), "item", "Wollstoff"))

suite.done()
