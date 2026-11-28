-- Move Windows (the owner said yes to the mockup, 2026-11-26): one screen
-- with a stand-in box for every Farmer piece, to drag each into place.
--
-- What must hold:
--   1. /farm move opens it with a box for each piece, Escape can close it,
--      and Done closes it.
--   2. It won't open in a fight, and a fight starting closes it.
--   3. A dropped box saves its piece's own spot (lootFeedX, rankUpX,
--      arrowX, xpBarX, goalsX, windowSpots) and moves the piece; boxes
--      left alone save nothing.
--   4. Run Recap and the note stack get a spot of their own, and use it.
--   5. Boxes snap to the screen's middle lines and to each other's edges,
--      and stay on screen.
--   6. Put Everything Back asks to Confirm, then puts every window back.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("movewindows")

local ns = env.Load({ ui = true })
local MoveWindows = ns.MoveWindows
UIParent._width = 1920
-- Signed up as at login, so window spots go in the save.
ns.SharedWindow:Join({ key = "farmer", order = 1, name = "Farmer", db = function() return ns.db end })
UIParent._height = 1080

local fighting = false
_G.InCombatLockdown = function() return fighting end
local fire = ns.eventFrame:GetScript("OnEvent")

local function Drop(key, left, top)
    local box = MoveWindows:BoxFor(key)
    box._left, box._top = left, top
    box:GetScript("OnDragStop")(box)
    return box
end

local function Before()
    local copy = {}
    for k, v in pairs(ns.db) do copy[k] = v end
    return copy
end

--------------------------------------------------------------------------------
-- 1. Opens with every piece
--------------------------------------------------------------------------------

ns.HandleSlash("move")
suite.check("/farm move opens it", MoveWindows:IsOpen())
suite.check("a box for each of the ten pieces", #MoveWindows.boxes == 10, #MoveWindows.boxes)
local names = {}
for _, box in ipairs(MoveWindows.boxes) do names[box.label:GetText()] = true end
for _, name in ipairs({ "Goal Arrow", "Notes", "Run Recap", "Rank Up", "Kills & Loot", "Goals",
        "Loot Feed", "Fishing Panel", "Zone Board", "XP Bar" }) do
    suite.check("a box for " .. name, names[name])
end
local escape = false
for _, name in ipairs(UISpecialFrames) do
    if name == "BlackthornesFarmerMoveWindows" then escape = true end
end
suite.check("Escape closes it", escape)
suite.check("the bar says what to do", MoveWindows.bar ~= nil)

MoveWindows.doneButton:Click()
suite.check("Done closes it", not MoveWindows:IsOpen())

--------------------------------------------------------------------------------
-- 2. Never in a fight
--------------------------------------------------------------------------------

fighting = true
env.chat = {}
suite.check("it won't open in a fight", MoveWindows:Open() == false and not MoveWindows:IsOpen())
suite.check("and says so", env.chat[#env.chat] and env.chat[#env.chat]:find("after the fight", 1, true))
fighting = false
MoveWindows:Open()
fire(ns.eventFrame, "PLAYER_REGEN_DISABLED")
suite.check("a fight starting closes it", not MoveWindows:IsOpen())
MoveWindows:Open()

--------------------------------------------------------------------------------
-- 3. A drop saves the piece's own spot, and only that
--------------------------------------------------------------------------------

-- Snapping is checked on its own below; here drops land where they fall.
MoveWindows.SNAP = 0
local was = Before()
Drop("lootfeed", 300, 700)
suite.check("the loot feed keeps its new spot", ns.db.lootFeedX == 300 and ns.db.lootFeedY == 700,
    tostring(ns.db.lootFeedX) .. "," .. tostring(ns.db.lootFeedY))
local changed = {}
for k, v in pairs(ns.db) do
    if was[k] ~= v and k ~= "lootFeedX" and k ~= "lootFeedY" then changed[#changed + 1] = k end
end
suite.check("nothing else is saved", #changed == 0, table.concat(changed, ", "))

ns.LootFeed:Build()
Drop("lootfeed", 320, 720)
local p = ns.LootFeed.frame._point
suite.check("a built loot feed moves there", p and p[1] == "TOPLEFT" and p[4] == 320 and p[5] == 720)

Drop("rankup", 1000, 500)
suite.check("Rank Up keeps its spot", ns.db.rankUpX == 1000 and ns.db.rankUpY == 500, tostring(ns.db.rankUpX) .. "," .. tostring(ns.db.rankUpY))

local arrow = MoveWindows:BoxFor("arrow")
local aw, ah = arrow.rect[3], arrow.rect[4]
Drop("arrow", 700, 900)
suite.check("the arrow keeps its middle", ns.db.arrowX == 700 + aw / 2 and ns.db.arrowY == 900 - ah / 2)

Drop("xpbar", 400, 60)
suite.check("the XP bar keeps its spot", ns.db.xpBarPoint == "TOPLEFT" and ns.db.xpBarRelPoint == "BOTTOMLEFT"
    and ns.db.xpBarX == 400 and ns.db.xpBarY == 60)

Drop("goals", 1500, 400)
suite.check("Goals keeps its spot", ns.db.goalsX == 1500 and ns.db.goalsY == 400)

Drop("zoneboard", 200, 300)
local zone = MoveWindows.Spot("farmer.zoneboard")
suite.check("the Zone Board keeps its window spot", zone and zone.x == 200 and zone.y == 300)

--------------------------------------------------------------------------------
-- 4. Run Recap and the notes have a spot of their own
--------------------------------------------------------------------------------

Drop("recap", 600, 650)
local recap = MoveWindows.Spot(MoveWindows.RECAP_KEY)
suite.check("Run Recap keeps a spot", recap and recap.x == 600 and recap.y == 650)
ns.RecapUI:Build()
ns.RecapUI:Place()
p = ns.RecapUI.frame._point
suite.check("and shows there", p and p[1] == "TOPLEFT" and p[3] == "BOTTOMLEFT" and p[4] == 600 and p[5] == 650)

local notes = MoveWindows:BoxFor("notes")
local nw = notes.rect[3]
Drop("notes", 100, 1000)
local spot = ns.Notice.Spot()
suite.check("the notes keep a spot", spot and spot.x == 100 + nw / 2 and spot.y == 1000)
ns.Notice:Show("Your bags are full.", { key = "test" })
local card = _G.BlackthornesNotice.cards[1]
p = card and card._point
suite.check("and a note shows there", p and p[1] == "TOP" and p[3] == "BOTTOMLEFT" and p[4] == 100 + nw / 2 and p[5] == 1000)

--------------------------------------------------------------------------------
-- 5. Snapping
--------------------------------------------------------------------------------

MoveWindows.SNAP = 12
local l, t = MoveWindows.Snap(905, 600, 100, 50, {})
suite.check("snaps to the middle line", l == 910, l)
l, t = MoveWindows.Snap(300, 600, 100, 50, { { 405, 900, 100, 100 } })
suite.check("snaps beside another box", l == 305, l)
l, t = MoveWindows.Snap(300, 795, 100, 50, { { 600, 900, 100, 100 } })
suite.check("snaps under another box", t == 800, t)
l, t = MoveWindows.Snap(-50, 2000, 100, 50, {})
suite.check("stays on screen", l == 0 and t == 1080, l .. "," .. t)

--------------------------------------------------------------------------------
-- 6. Put Everything Back
--------------------------------------------------------------------------------

-- Every piece with a spot of its own goes back too, built or not (a bug
-- pass, 2026-11-28: the rank-up pop-up, the XP bar, the Fishing Buttons and
-- an unbuilt goals panel kept theirs).
ns.db.rankUpX, ns.db.rankUpY = 500, 600
ns.db.xpBarPoint, ns.db.xpBarRelPoint, ns.db.xpBarX, ns.db.xpBarY = "TOP", "TOP", 10, -20
ns.db.fishingBarX, ns.db.fishingBarY = 700, 400
ns.db.goalsX, ns.db.goalsY = 300, 300
local goalsFrame = ns.GoalsUI and ns.GoalsUI.frame
if ns.GoalsUI then ns.GoalsUI.frame = nil end

MoveWindows.backButton:Click()
suite.check("the first click asks to Confirm", MoveWindows.backButton.label:GetText() == "Confirm"
    and ns.db.lootFeedX == 320)
MoveWindows.backButton:Click()
suite.check("the second puts every window back", ns.db.lootFeedX == nil
    and MoveWindows.Spot(MoveWindows.RECAP_KEY) == nil and ns.Notice.Spot() == nil,
    tostring(ns.db.lootFeedX) .. " " .. tostring(MoveWindows.Spot(MoveWindows.RECAP_KEY)) .. " " .. tostring(ns.Notice.Spot()))
suite.check("the rank-up pop-up goes back", ns.db.rankUpX == nil and ns.db.rankUpY == nil, tostring(ns.db.rankUpX))
suite.check("the XP bar goes back", ns.db.xpBarPoint == nil and ns.db.xpBarRelPoint == nil
    and ns.db.xpBarX == nil and ns.db.xpBarY == nil, tostring(ns.db.xpBarX))
suite.check("the Fishing Buttons go back", ns.db.fishingBarX == nil and ns.db.fishingBarY == nil,
    tostring(ns.db.fishingBarX))
suite.check("an unbuilt goals panel goes back", ns.db.goalsX == nil and ns.db.goalsY == nil, tostring(ns.db.goalsX))
if ns.GoalsUI then ns.GoalsUI.frame = goalsFrame end
suite.check("and the screen stays open", MoveWindows:IsOpen())

MoveWindows:Close()
suite.done()
