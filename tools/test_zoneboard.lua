-- The Zone Board (the owner said build it, 2026-11-18, from a mockup whose
-- words he approved, option A: own mobs only, no coin hint).
--
-- What matters: it is off until ticked and nothing opens while off; the
-- zone's list holds the mobs the drop list and your loot put here, never
-- rares, bosses, town guards, critters, dungeon mobs or another zone's;
-- kills count on the zone's line; FINISH counts what is unlocked and leaves
-- finished mobs out unless asked; BEST ranks only mobs with 20 of your own
-- kills here and shows every other one as a mystery with kills to go and no
-- worth; Skip puts a mob away for the zone; a hunt aims the arrow, moves on
-- at the 20th kill and ends when the zone is done; the 20th kill turns the
-- card, a new top mob gets its banner, the last one the Zone Done banner,
-- a chat line and a stamp, and every sound asks Mute All Sounds first; the
-- windows, Settings rows, Kills & Loot button and /farm zone follow it.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("zoneboard")
local check = suite.check

local ns = env.Load({ ui = true })
local L = ns.L
local ZoneBoard, UI, FX = ns.ZoneBoard, ns.ZoneBoardUI, ns.ZoneBoardFX
local Tracker = ns.Tracker

check("the modules load", ZoneBoard and UI and FX)
check("no hunt window: the hunt lives in the board", ns.ZoneHunt == nil)
check("the command is there", type(ns.commands.zone) == "table")

-- Prices, so a kill has a worth.
local VENDOR = {}
_G.C_Item = { GetItemInfo = function(id) return "item", nil, 1, 1, 1, "", "", 1, "", "", VENDOR[id] or 0 end }
local AUCTION = { [99101] = 40, [99102] = 400 }
_G.BlackthornesTS = { Prices = { GetValue = function(_, id) return AUCTION[id] end } }

local ZONE = "Testwood Vale"
env.world.zone = ZONE

local function Mob(item, id, name, zone, location, level, coords)
    ns.DB:RegisterItem({ name = item, id = id, category = "misc",
        sources = { { name = name, zone = zone, location = location, minLevel = level, maxLevel = level + 1,
            chance = 10, coords = coords, provenance = "forever" } } })
end
Mob("Wolf Pelt Test", 99101, "Test Wolf", ZONE, "North Tide", 10, { 40, 30 })
Mob("Spider Silk Test", 99102, "Test Spider", ZONE, "Fenris Isle", 12, { 60, 70 })
Mob("Bear Claw Test", 99103, "Test Bear", ZONE, "Olsen's Farthing", 30, { 50, 50 })
Mob("Rabbit Foot Test", 99104, "Test Rabbit", ZONE, "North Tide", 1, { 41, 31 })
Mob("Rare Fang Test", 99105, "Gorefang Test", ZONE, "Fenris Isle", 14, { 61, 71 })
Mob("Guard Badge Test", 99106, "Deathguard Tester", ZONE, "The Sepulcher", 55, { 45, 42 })
Mob("Ghoul Rag Test", 99107, "Test Ghoul", ZONE, "Shadowfang Keep", 20, { 44, 67 })
Mob("Boar Tusk Test", 99108, "Elsewhere Boar", "Elwynn Forest", "Goldshire", 5, { 40, 60 })
ns.db.creatureTypes = { ["Test Rabbit"] = "Critter" }

local serial = 0
local function Loot(mob, items, zone)
    serial = serial + 1
    env.world.zone = zone or ZONE
    env.world.target = { name = mob, level = 10, dead = true, guid = "Z-" .. serial }
    env.world.loot = items or {}
    Tracker:OnLoot()
    env.world.zone = ZONE
end
local COINS = { name = "12 Copper", money = true }
local PELT = { name = "Wolf Pelt Test", id = 99101 }
local SILK = { name = "Spider Silk Test", id = 99102 }

-- Off until ticked ------------------------------------------------------------
check("on by default", ZoneBoard.IsOn() == true and ns.db.zoneBoard == nil)
check("the banner is on unless unticked", ZoneBoard.BannerOn())
ZoneBoard:SetOn(false)
check("the window will not open while off", UI:Show() == false and not UI:Shown())
env.chat = {}
ns.commands.zone.fn("")
check("/farm zone says to turn it on", (env.chat[#env.chat] or ""):find(L["Turn on Zone Board in Settings first."], 1, true) ~= nil,
    env.chat[#env.chat])
check("nothing is learned while off", (function()
    _G.UnitClassification = function() return "rare" end
    ZoneBoard:Learn("target", "Gorefang Test")
    return ns.db.zoneBoardLeftOut == nil
end)())

-- Kills: 20 wolves (unlocked), 19 spiders, nothing on the bear. A wolf
-- killed in Elwynn too makes its line split by zone.
for i = 1, 20 do Loot("Test Wolf", { COINS, i <= 10 and PELT or nil }) end
for _ = 1, 19 do Loot("Test Spider", { COINS, SILK }) end
Loot("Test Wolf", { COINS }, "Elwynn Forest")

ZoneBoard:SetOn(true)
check("ticking saves nothing", ns.db.zoneBoard == nil and ZoneBoard.IsOn())
ZoneBoard:Learn("target", "Gorefang Test")
check("a rare is learned in game", ns.db.zoneBoardLeftOut["Gorefang Test"] == "rare")
_G.UnitClassification = function() return "normal" end
_G.UnitFactionGroup = function() return "Horde" end
ZoneBoard:Learn("target", "Some Town Grunt")
check("a mob of the Horde or Alliance is a guard", ns.db.zoneBoardLeftOut["Some Town Grunt"] == "faction")
-- Forever gives some wild camps a side: Dalaran's mobs at Ambermill read as
-- Alliance, yet a Horde player fights them (the owner's screenshot,
-- 2026-11-24). A mob you can attack is never a guard of your town.
_G.UnitCanAttack = function() return true end
ZoneBoard:Learn("target", "Dalaran Watcher")
check("a side's mob you can fight stays on the board", ns.db.zoneBoardLeftOut["Dalaran Watcher"] == nil)
ns.db.zoneBoardLeftOut["Dalaran Wizard"] = "faction"
local before = ZoneBoard.version
ZoneBoard:Learn("target", "Dalaran Wizard")
check("one learned as a guard before comes back once seen", ns.db.zoneBoardLeftOut["Dalaran Wizard"] == nil
    and ZoneBoard.version ~= before)
_G.UnitClassification = function() return "rare" end
ZoneBoard:Learn("target", "Dalaran Rare Test")
check("a rare you can fight is still left out", ns.db.zoneBoardLeftOut["Dalaran Rare Test"] == "rare")
_G.UnitClassification = function() return "normal" end
_G.UnitCanAttack = function() return false end
ZoneBoard:Learn("target", "Another Town Grunt")
check("a side's mob you cannot fight is a guard", ns.db.zoneBoardLeftOut["Another Town Grunt"] == "faction")
_G.UnitCanAttack = function() error("secret") end
ZoneBoard:Learn("target", "Unread Grunt")
check("an unreadable answer keeps the old way", ns.db.zoneBoardLeftOut["Unread Grunt"] == "faction")
_G.UnitCanAttack = nil
_G.UnitFactionGroup = function() return nil end
ZoneBoard:Learn("target", "Plain Wolf")
check("a wild mob is not written", ns.db.zoneBoardLeftOut["Plain Wolf"] == nil)
_G.UnitClassification, _G.UnitFactionGroup = nil, nil

-- The zone's list ---------------------------------------------------------------
local list = ZoneBoard:List(ZONE, true)
local names = {}
for _, entry in ipairs(list.entries) do names[entry.name] = true end
check("the zone's mobs are on it", names["Test Wolf"] and names["Test Spider"] and names["Test Bear"])
check("a critter is left out", not names["Test Rabbit"] and list.leftOut["Test Rabbit"] == "critter")
check("a rare is left out", not names["Gorefang Test"] and list.leftOut["Gorefang Test"] == "rare")
check("a town guard is left out", not names["Deathguard Tester"])
check("a dungeon mob is left out", not names["Test Ghoul"] and list.leftOut["Test Ghoul"] == "dungeon")
check("another zone's mob is not here", not names["Elsewhere Boar"])
check("guard names: a town's guard", ZoneBoard.IsGuardName("Southshore Guard") and ZoneBoard.IsGuardName("Orgrimmar Grunt"))
check("guard names: a wild one is not", not ZoneBoard.IsGuardName("Dalaran Shield Guard")
    and not ZoneBoard.IsGuardName("Syndicate Watchman"))
check("the list is kept", ZoneBoard:List(ZONE) == list)

local kills, key = ZoneBoard.Kills("Test Wolf", ZONE)
check("kills count on the zone's line", kills == 20, kills)
check("a split name ranks by the zone's key", key == Tracker.ZoneKey("Test Wolf", ZONE), key)

-- FINISH ------------------------------------------------------------------------
local rows, unlocked, total = ZoneBoard:Rows(list)
check("one of three unlocked", unlocked == 1 and total == 3, unlocked .. "/" .. total)
check("finished mobs stay out of the list", #rows == 2)
ZoneBoard:SetShowDone(true)
check("Show Finished brings them back", #ZoneBoard:Rows(list) == 3)
ZoneBoard:SetShowDone(false)
check("the head lines", select(1, UI.HeadLines(1, 3)) == L.Format("%d of %d mobs unlocked", 1, 3)
    and select(2, UI.HeadLines(1, 3)) == L.Format("%d to go. Each one opens its drop list.", 2))
ZoneBoard:SetNearFirst(false)
check("unticked Near Me First saves false", ns.db.zoneBoardNear == false)
ZoneBoard.Order(rows, nil)
check("closest to 20 first", rows[1].name == "Test Spider" and rows[2].name == "Test Bear")
ZoneBoard:SetNearFirst(true)
local bear
for _, entry in ipairs(list.entries) do if entry.name == "Test Bear" then bear = entry end end
check("a mob well above you reads orange", ZoneBoard.LevelColor(bear, 25) == "orange")
check("a mob near you does not", ZoneBoard.LevelColor({ minLevel = 24 }, 25) ~= "orange")

-- BEST: own unlocked mobs only ------------------------------------------------
local best = ZoneBoard:Best(list)
check("only the unlocked mob is ranked", #best.ranked == 1 and best.ranked[1].entry.name == "Test Wolf")
check("its worth is Rankings' own", best.ranked[1].value == ns.Rankings:Entry(key).value)
check("the rest are mysteries", #best.mysteries == 2 and best.mysteries[1].name == "Test Spider")
check("a mystery carries no worth", best.mysteries[1].value == nil)
check("the foot counts mysteries", UI.BestFoot(2):find(L.Format("%d mobs here are still a mystery.", 2), 1, true) ~= nil)
check("BEST is kept until something moves", ZoneBoard:Best(list) == best)

-- Skip ----------------------------------------------------------------------------
ZoneBoard:Skip(ZONE, "Test Bear")
check("Skip saves it for the zone", ns.db.zoneBoardSkips[ZONE]["Test Bear"] == true)
check("a skipped mob leaves the count", select(3, ZoneBoard:Rows(ZoneBoard:List(ZONE, true))) == 2)
ZoneBoard:Unskip(ZONE)
list = ZoneBoard:List(ZONE, true)
check("Unskip brings it back", select(3, ZoneBoard:Rows(list)) == 3)

-- The window ------------------------------------------------------------------------
check("the window opens when on", UI:Show() and UI:Shown())
check("the title names the zone", UI.Title(ZONE) == L["ZONE BOARD"] .. " " .. ZONE)
check("FINISH shows first", ZoneBoard.Tab() == "finish")
check("its first row is a mob to finish", UI.rows[1]:IsShown() and UI.rows[1].data
    and UI.rows[1].data.name == "Test Spider", UI.rows[1].data and UI.rows[1].data.name)
check("ALMOST at 19 kills", UI.rows[1].tag:IsShown())
check("the count reads 19/20", UI.rows[1].count:GetText() == "19/20", UI.rows[1].count:GetText())
check("the foot says who is left out", UI.foot:GetText() == L["Rare mobs, bosses and town guards are left out."])
ZoneBoard:SetTab("best")
UI:Draw()
check("BEST draws the crown on the top mob", UI.rows[1].data.name == "Test Wolf"
    and UI.rows[1].rank:GetText() == ns.TrackerUI.CROWN)
check("a mystery row says kills to go", UI.rows[2].sub:GetText() == L.Format("%d more kills to find out", 1)
    and UI.rows[2].right:GetText() == "???", UI.rows[2].sub:GetText())
check("Save Farm shows on BEST", UI.save:IsShown() and not UI.skip:IsShown())
ZoneBoard:SetTab("finish")
UI:Draw()

-- The Kills & Loot button and Settings -----------------------------------------------
local TrackerUI = ns.TrackerUI
if not TrackerUI.toolbar then TrackerUI:BuildToolbar(CreateFrame("Frame")) end
TrackerUI:DrawToolbar()
check("the Kills & Loot button shows while on", TrackerUI.toolbar.zone:IsShown())
ns.HandleSlash("settings")
local controls = ns.SettingsUI.controls
check("the Settings rows are there", controls.zoneBoard and controls.zoneBoardBanner
    and controls.zoneBoardLeftOut and controls.zoneBoardShow and controls.zoneBoardReset)
check("no Hunt Window box", controls.zoneBoardHunt == nil)
ns.SettingsUI:Refresh()
check("the Settings box reads on", controls.zoneBoard:GetChecked() == true)
check("Left Out names who", controls.zoneBoardLeftOut:GetText() == L["Rare mobs, bosses, town guards, critters"])

-- The hunt ---------------------------------------------------------------------------
ns.db.muteSounds = nil
local played = {}
_G.PlaySoundFile = function(path) played[#played + 1] = path; return true end
UI:Show()
ZoneBoard:SetTab("finish")
UI:Draw()
check("before a hunt: Take Me There and Skip", UI.go:IsShown() and UI.skip:IsShown()
    and not UI.nextMob:IsShown() and not UI.stop:IsShown())
local target = ZoneBoard:StartHunt()
check("Take Me There hunts the mob closest to done", target and target.name == "Test Spider", target and target.name)
check("the arrow follows its camp", ns.Arrow.grind and ns.Arrow.grind.zoneBoard and ns.Arrow.grind.location == "Fenris Isle")
local one, two = UI.rows[1], UI.rows[2]
check("the mob hunted tops the board", one:IsShown() and one.data and one.data.name == "Test Spider"
    and one.role == "target")
check("with the gold arrow and picked", one.pointer:IsShown() and not one.rank:IsShown() and one.picked)
check("then the next mob", two:IsShown() and two.name:GetText() == L.Format("Then: %s", "Test Bear"))
check("Next Mob and Stop where Take Me There and Skip sit", UI.nextMob:IsShown() and UI.stop:IsShown()
    and not UI.go:IsShown() and not UI.skip:IsShown())
UI:Pick("Test Bear")
check("picking another row brings Take Me There back", UI.go:IsShown() and UI.skip:IsShown()
    and not UI.nextMob:IsShown() and not UI.stop:IsShown())
UI:Pick("Test Spider")
check("and the hunted mob brings Next Mob back", UI.nextMob:IsShown() and UI.stop:IsShown())
ns.FoldWindow:Fold(UI.frame)
check("folded it names the mob", UI.trim.plate.title and UI.FoldTitle(ZONE, target) == L["FINISH"] .. " Test Spider 19/20")
ns.FoldWindow:Unfold(UI.frame)
check("unfolded the rows come back", UI.rows[1]:IsShown() and UI.rows[1].role == "target")

-- The 20th spider: the card turns, it tops the board, the hunt moves on.
env.chat = {}
Loot("Test Spider", { COINS, SILK })
-- One placard: the unlock and the crown line together, never two frames.
local placard = FX.placard
check("one placard for the unlock, glowing", placard and placard:IsShown() and placard.glow:IsShown()
    and FX.shown and FX.shown.kind == "unlock")
check("it names the mob under the ribbon", placard.title:GetText() == "Test Spider"
    and placard.ribbon.text:GetText() == L["Unlocked!"], placard.title:GetText())
check("its best drop is named", (placard.drop.text:GetText() or ""):find("Spider Silk Test", 1, true) ~= nil)
check("a new best joins the same placard", (placard.line:GetText() or ""):find(
    L.Format("New Best in %s!", ZONE), 1, true) ~= nil, placard.line:GetText())
check("it says what it beat, with no coins", placard.foot:GetText() == L.Format("Beats %s.", "Test Wolf"),
    placard.foot:GetText())
check("the rank-up sound plays once", (function()
    local n = 0
    for _, path in ipairs(played) do if path == FX.SOUND_BEST then n = n + 1 end end
    return n == 1
end)())
check("no old banner frame is made", FX.banner == nil and FX.card == nil
    and _G.BlackthornesFarmerZoneBanner == nil and _G.BlackthornesFarmerZoneCard == nil)
check("nothing waits behind it", #(FX.queue or {}) == 0)
check("the hunt moved on by itself", ZoneBoard.hunt and ZoneBoard.hunt.target == "Test Bear")
check("the worth was worked out again", ZoneBoard:Best().ranked[1].entry.name == "Test Spider")

-- Skipping the last one finishes the zone.
played = {}
env.chat = {}
ZoneBoard:Skip(ZONE, "Test Bear")
check("Zone Done waits while the placard shows", FX.shown.kind == "unlock" and #FX.queue == 1
    and FX.queue[1].kind == "done" and #played == 0)
FX:Close()
check("the zone is stamped done", ns.db.zoneBoardDone and ns.db.zoneBoardDone[ZONE] ~= nil)
check("one chat line for you", (function()
    for _, line in ipairs(env.chat) do
        if line:find(L.Format("%s done! All %d mobs unlocked.", ZONE, 2), 1, true) then return true end
    end
end)())
check("then Zone Done shows on the same placard", FX.shown.kind == "done"
    and placard.title:GetText() == L.Format("%s Done!", ZONE)
    and placard.ribbon.text:GetText() == L["Zone Done"], placard.title:GetText())
check("it names the best farm, with no coins", placard.foot:GetText() == L.Format("Best farm here: %s.", "Test Spider"),
    placard.foot:GetText())
check("with its own sound", played[#played] == FX.SOUND_DONE, played[#played])
check("the hunt stopped", ZoneBoard.hunt == nil)
check("its buttons go back", UI.go:IsShown() and not UI.nextMob:IsShown() and not (UI.rows[1]:IsShown() and UI.rows[1].pointer:IsShown()))
check("the arrow let the camp go", ns.Arrow.grind == nil)
env.chat = {}
ZoneBoard:CheckDone(ZONE)
check("a done zone cheers only once", #env.chat == 0)

-- Mute All Sounds quiets it.
ns.db.zoneBoardDone = nil
ns.db.muteSounds = true
if ns.SharedChoices and ns.SharedChoices.SetMute then ns.SharedChoices:SetMute(true) end
played = {}
FX:Close()
ZoneBoard:CheckDone(ZONE)
check("Mute All Sounds quiets the zone sound", #played == 0)
if ns.SharedChoices and ns.SharedChoices.SetMute then ns.SharedChoices:SetMute(false) end
ns.db.muteSounds = nil

-- Banner off: no banner, still the chat line.
ns.db.zoneBoardDone = nil
ZoneBoard:SetBanner(false)
check("unticked banner saves false", ns.db.zoneBoardBanner == false)
FX:Close()
FX.queue = {}
ZoneBoard:CheckDone(ZONE)
check("no banner while unticked", not FX.showing and #FX.queue == 0)
ZoneBoard:SetBanner(true)

-- Effects Off: no turn, no glow, and it shows then goes by itself.
ns.db.zoneBoardDone = nil
ns.db.trackerEffects = "off"
FX:Close()
FX.queue = {}
ZoneBoard:CheckDone(ZONE)
check("Effects Off: no glow on the placard", not FX.placard.glow:IsShown())
check("and it goes by itself after its hold", not FX.showing and not FX.placard:IsShown())
ns.db.trackerEffects = nil

-- A hunt ends when you leave the zone.
ZoneBoard:Unskip(ZONE)
ZoneBoard:List(ZONE, true)
ZoneBoard:StartHunt("Test Bear")
check("a hunt for a mob by name", ZoneBoard.hunt and ZoneBoard.hunt.target == "Test Bear")
ZoneBoard:OnEnable()
env.world.zone = "Elwynn Forest"
ns.eventFrame:GetScript("OnEvent")(ns.eventFrame, "ZONE_CHANGED_NEW_AREA")
check("leaving the zone ends the hunt", ZoneBoard.hunt == nil)
env.world.zone = ZONE

-- A kill below 20 moves one row only.
UI:Show()
ZoneBoard:SetTab("finish")
UI:Draw()
local drew = 0
local realDraw = UI.Draw
UI.Draw = function(self, ...) drew = drew + 1; return realDraw(self, ...) end
Loot("Test Bear", { COINS })
UI.Draw = realDraw
check("a kill does not redraw the window", drew == 0, drew)
local bearRow
for _, row in ipairs(UI.rows) do if row:IsShown() and row.data and row.data.name == "Test Bear" then bearRow = row end end
check("the bear's row reads 1/20", bearRow and bearRow.count:GetText() == "1/20", bearRow and bearRow.count:GetText())

-- In a fight: the count moves, nothing re-sorts, the hunt waits.
for _ = 1, 18 do Loot("Test Bear", { COINS }) end
ZoneBoard:StartHunt("Test Bear")
check("the bear is hunted at 19", ZoneBoard.hunt and ZoneBoard.hunt.target == "Test Bear"
    and ZoneBoard.Kills("Test Bear", ZONE) == 19)
ZoneBoard:Unskip(ZONE)
ns.db.zoneBoardDone = nil
_G.InCombatLockdown = function() return true end
ZoneBoard.waiting = nil
Loot("Test Bear", { COINS })
check("in a fight the hunt does not move yet", ZoneBoard.hunt == nil or ZoneBoard.hunt.target == "Test Bear")
check("the redraw waits for the fight to end", ZoneBoard.waiting == true)
_G.InCombatLockdown = nil
ns.eventFrame:GetScript("OnEvent")(ns.eventFrame, "PLAYER_REGEN_ENABLED")
check("after the fight it catches up", ZoneBoard.waiting == nil)

-- Turning it off -----------------------------------------------------------------------
ZoneBoard:StartHunt("Test Bear")
ZoneBoard:SetOn(false)
check("off stops the hunt and saves false", ZoneBoard.hunt == nil and ns.db.zoneBoard == false)
check("off hides the window", not UI:Shown())

-- /farm zone -------------------------------------------------------------------------------
ns.commands.zone.fn("on")
check("/farm zone on", ZoneBoard.IsOn())
ns.db.windowSpots = { ["farmer.zoneboard"] = { x = 1, y = 2 }, ["farmer.zonehunt"] = { x = 3, y = 4 },
    ["farmer.export"] = { x = 5, y = 6 } }
ns.db.zoneBoardScale = 120
ns.commands.zone.fn("reset")
check("reset puts the board back", ns.db.windowSpots["farmer.zoneboard"] == nil
    and ns.db.windowSpots["farmer.export"] ~= nil
    and ns.db.zoneBoardScale == nil)
ns.commands.zone.fn("")
check("/farm zone opens it", UI:Shown())
ns.commands.zone.fn("")
check("and closes it", not UI:Shown())
ns.commands.zone.fn("off")
check("/farm zone off", not ZoneBoard.IsOn())

suite.done()
