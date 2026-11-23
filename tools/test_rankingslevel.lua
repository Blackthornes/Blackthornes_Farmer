-- Rankings' "Near my level" (the owner, 2026-11-23).
--
-- What matters: off unless ticked, so the board is as it was; ticked, only
-- mobs from 3 levels below the character to 2 above stay, on the ranked
-- boards and the not-ranked-yet list, ranks count from #1 inside the band,
-- a mob with any level in the band stays, a level the client won't read
-- filters nothing, the rank-up order is left alone, and the tab's box,
-- Settings and /farm rankings level all write the same key.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("rankingslevel")

local ns = env.Load({ ui = true })
local Rankings = ns.Rankings
local Tracker = ns.Tracker

local playerLevel = 25
_G.UnitLevel = function(unit)
    if unit == "target" then return env.world.target and env.world.target.level or 0 end
    if playerLevel == "secret" then error("secret value") end
    return playerLevel
end

local serial = 0
local function Loot(mob, level, copper)
    serial = serial + 1
    env.world.zone, env.world.subZone = "Silverpine Forest", ""
    env.world.target = { name = mob, level = level, dead = true, guid = "Creature-0-1-2-3-" .. serial .. "-" .. serial }
    env.world.loot = { { name = copper .. " Copper", money = true } }
    ns.Harvest:RecordCorpse()
    Tracker:OnLoot()
end

-- Worth goes up as the level goes up, so the highest mob in the band is #1.
local MOBS = {
    { "Low Wolf", 20, 20 },     -- 5 below: out
    { "Edge Bat", 21, 30 },     -- met at 21 and 22: 22 is 3 below, in
    { "Near Bear", 23, 40 },    -- in
    { "Top Ogre", 27, 50 },     -- 2 above: in
    { "High Troll", 28, 90 },   -- 3 above: out, and the best of all
}
for _ = 1, 20 do
    for _, mob in ipairs(MOBS) do
        local level = mob[2]
        if mob[1] == "Edge Bat" then level = (serial % 2 == 0) and 21 or 22 end
        Loot(mob[1], level, mob[3])
    end
end
-- Two kills only: not ranked yet. One near, one far.
for _ = 1, 2 do
    Loot("Young Boar", 24, 5)
    Loot("Old Drake", 40, 5)
end

local function Find(list, mob)
    for _, entry in ipairs(list) do
        if entry.mob == mob then return entry end
    end
    return nil
end

suite.check("off by default", not Rankings.NearLevel())
local board = Rankings:Build()
suite.check("off, every mob is ranked", #board.measured == 5)
suite.check("off, the troll is first", Find(board.measured, "High Troll") and Find(board.measured, "High Troll").rank == 1)
suite.check("off, both new mobs wait", Find(board.pending, "Young Boar") ~= nil and Find(board.pending, "Old Drake") ~= nil)

local stamp = ns.RankUp.Stamp()
ns.HandleSlash("rankings level on")
suite.check("/farm rankings level on ticks it", Rankings.NearLevel() and ns.db.rankingsNearLevel == true)
suite.check("ticking it leaves the rank-up order alone", ns.RankUp.Stamp() == stamp)

board = Rankings:Build()
suite.check("ticked, three mobs are ranked", #board.measured == 3)
suite.check("ticked, 5 below is gone", Find(board.measured, "Low Wolf") == nil)
suite.check("ticked, 3 above is gone", Find(board.measured, "High Troll") == nil)
suite.check("ticked, a mob met at 3 below stays", Find(board.measured, "Edge Bat") ~= nil)
suite.check("ticked, the band's best is #1", Find(board.measured, "Top Ogre") and Find(board.measured, "Top Ogre").rank == 1)
suite.check("ticked, the ranks run 1 to 3", Find(board.measured, "Edge Bat") and Find(board.measured, "Edge Bat").rank == 3)
suite.check("ticked, the near new mob still waits", Find(board.pending, "Young Boar") ~= nil)
suite.check("ticked, the far new mob is gone", Find(board.pending, "Old Drake") == nil)

-- A ding moves the band.
playerLevel = 30
board = Rankings:Build()
suite.check("at 30, the troll is in", Find(board.measured, "High Troll") ~= nil)
suite.check("at 30, the bear is out", Find(board.measured, "Near Bear") == nil)

-- A level the client won't read filters nothing.
playerLevel = "secret"
board = Rankings:Build()
suite.check("an unreadable level shows every mob", #board.measured == 5)

-- No mob near: the board says so.
playerLevel = 55
board = Rankings:Build()
suite.check("at 55, nothing is near", #board.measured == 0)
ns.UI:Show()
ns.UI:ShowTab("rankings")
local said = false
for _, row in ipairs(ns.RankingsUI:Rows(board)) do
    if row.type == "note" and row.text == ns.L["No mobs near your level yet."] then said = true end
end
suite.check("an empty band says no mobs near your level", said)
playerLevel = 25

ns.HandleSlash("rankings level off")
suite.check("/farm rankings level off unticks it", not Rankings.NearLevel())
suite.check("off again, every mob is back", #Rankings:Build().measured == 5)

-- The tab's tick box and Settings say the same.
local box = ns.RankingsUI.near
suite.check("the tab has the box", box ~= nil)
suite.check("the tab's box shows it off", box and not box:GetChecked())
box:GetScript("OnClick")(box)
suite.check("ticking the tab's box turns it on", Rankings.NearLevel())
suite.check("the hover names the band",
    ns.RankingsUI.NearTip() == "Rankings show only mobs from 3 levels below you to 2 above.")
ns.HandleSlash("rankings level")
suite.check("/farm rankings level on its own toggles it", not Rankings.NearLevel())

suite.done()
