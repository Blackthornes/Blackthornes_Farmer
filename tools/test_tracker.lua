-- The kill tracker.
--
-- What matters: a kill is counted once however many times its corpse is
-- opened, no percentage appears before MIN_KILLS, the rate is corpses that held
-- the item over kills, chat stays quiet unless asked, and the tally survives a
-- reload while the session count does not.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("tracker")

local ns = env.Load({ ui = true })
local Tracker = ns.Tracker

-- PLAYER_LOGIN: registers LOOT_OPENED for both the harvester and the tracker.
ns.Harvest:OnEnable()
Tracker:OnEnable()
ns.TrackerUI:Build()

local fire = ns.eventFrame:GetScript("OnEvent")

local serial = 0

--- Open one corpse through the real event, as the client would.
local function Loot(mob, items, guid)
    if guid == nil then
        serial = serial + 1
        guid = "Creature-0-1-2-3-" .. serial
    end

    env.world.target = { name = mob, level = 8, dead = true, isPlayer = false,
        guid = guid or nil }
    env.world.loot = items or {}
    fire(ns.eventFrame, "LOOT_OPENED")
end

local function ChatSince(mark)
    local lines = {}
    for index = mark + 1, #env.chat do lines[#lines + 1] = env.chat[index] end
    return table.concat(lines, "\n")
end

local BOAR = "Mottled Boar"
local SCRAPS = { name = "Ruined Leather Scraps", id = 2934 }
local MEAT = { name = "Chunk of Boar Meat", id = 769 }
local COINS = { name = "12 Copper", money = true }

--------------------------------------------------------------------------------
-- Counting
--------------------------------------------------------------------------------

Loot(BOAR, { SCRAPS, COINS })
Loot(BOAR, { MEAT })
Loot(BOAR, {})

local summary = Tracker:Summary(BOAR)
suite.check("three corpses are three kills", summary.kills == 3, summary.kills)
suite.check("all three this session", summary.session == 3, summary.session)
suite.check("coins are not an item", #summary.items == 2, #summary.items)
suite.check("no rates before the threshold", summary.rated == false)
suite.check("it says how many more are needed", summary.needed == 17, summary.needed)

suite.check("the harvester still records alongside it",
    ns.Harvest:CountCorpses() == 3, ns.Harvest:CountCorpses())

-- Skin the last one: same corpse, same guid, a new item.
local skinned = "Creature-0-1-2-3-skin"
Loot(BOAR, { SCRAPS }, skinned)
local before = Tracker:Summary(BOAR).kills
Loot(BOAR, { { name = "Light Leather", id = 2318 } }, skinned)

summary = Tracker:Summary(BOAR)
suite.check("opening a corpse twice is one kill", summary.kills == before, summary.kills)

local leather
for _, item in ipairs(summary.items) do
    if item.name == "Light Leather" then leather = item end
end
suite.check("what the second opening found is counted", leather and leather.corpses == 1)

-- And coming back for the same scraps does not count them twice.
Loot(BOAR, { SCRAPS }, skinned)
for _, item in ipairs(Tracker:Summary(BOAR).items) do
    if item.name == SCRAPS.name then
        suite.check("an item counts once per corpse", item.corpses == 2, item.corpses)
    end
end

-- No guid (an instance can refuse it): every opening counts, rather than none.
local noGuid = Tracker:Summary(BOAR).kills
Loot(BOAR, {}, false)
Loot(BOAR, {}, false)
suite.check("without a guid each opening is a kill",
    Tracker:Summary(BOAR).kills == noGuid + 2, Tracker:Summary(BOAR).kills)

--------------------------------------------------------------------------------
-- The panel before the threshold
--------------------------------------------------------------------------------

local UI = ns.TrackerUI

suite.check("the panel appears on a kill", UI.frame:IsShown())
suite.check("it names the mob", UI.title:GetText() == BOAR, UI.title:GetText())
suite.check("it shows the tally", UI.tally:GetText():find("6 kills", 1, true) ~= nil,
    UI.tally:GetText())
suite.check("items show as counts, not percentages",
    UI.rows[1].value:GetText():find("%", 1, true) == nil, UI.rows[1].value:GetText())
suite.check("the footer says how many more",
    UI.footer:GetText() == "14 more kills for drop rates", UI.footer:GetText())

--------------------------------------------------------------------------------
-- Chat is quiet by default
--------------------------------------------------------------------------------

suite.check("reporting starts off", ns.db.trackerReport == false)

local mark = #env.chat
Loot(BOAR, { SCRAPS })
suite.check("a kill says nothing in chat when reporting is off", #env.chat == mark,
    ChatSince(mark))

ns.HandleSlash("report on")
suite.check("/farm report on turns it on", ns.db.trackerReport == true)

mark = #env.chat
Loot(BOAR, { MEAT })
local said = ChatSince(mark)
suite.check("a kill is reported", said:find("kill 8", 1, true) ~= nil, said)
suite.check("before the threshold it says how many more",
    said:find("12 more for drop rates", 1, true) ~= nil, said)
suite.check("before the threshold it gives no percentage",
    said:find("%", 1, true) == nil, said)

-- Opening the same corpse again is not a kill, so it is not reported.
Loot(BOAR, { SCRAPS }, "Creature-report")
mark = #env.chat
Loot(BOAR, { MEAT }, "Creature-report")
suite.check("a second opening is not reported", #env.chat == mark, ChatSince(mark))

--------------------------------------------------------------------------------
-- Past the threshold
--------------------------------------------------------------------------------

ns.HandleSlash("report off")

-- Take the boar tally to exactly 19 kills, then look at a clean mob instead
-- where the arithmetic is easy to check by hand.
local WOLF = "Mangy Wolf"
local FANG = { name = "Wolf Fang" }
local HIDE = { name = "Ruined Leather Scraps" }

-- 20 kills: fang on 5 of them, scraps on 1.
for index = 1, 19 do
    Loot(WOLF, index <= 5 and { FANG } or {})
end

summary = Tracker:Summary(WOLF)
suite.check("19 kills is not enough", summary.rated == false)

ns.HandleSlash("report on")
mark = #env.chat
Loot(WOLF, { HIDE })

summary = Tracker:Summary(WOLF)
suite.check("20 kills is enough", summary.rated == true)
suite.check("the best-seen item comes first", summary.items[1].name == "Wolf Fang")
suite.check("the rate is corpses over kills", summary.items[1].chance == 25,
    summary.items[1].chance)

said = ChatSince(mark)
suite.check("the report on the 20th kill has rates",
    said:find("Wolf Fang", 1, true) ~= nil and said:find("25%", 1, true) ~= nil, said)
suite.check("and names the rarer drop too", said:find("5%", 1, true) ~= nil, said)

suite.check("the panel switches to percentages",
    UI.rows[1].value:GetText() == "25%", UI.rows[1].value:GetText())
suite.check("and drops the countdown", not UI.footer:IsShown())

ns.HandleSlash("report off")

suite.check("FormatChance: under one percent", Tracker.FormatChance(0.4) == "<1%")
suite.check("FormatChance: one decimal under ten", Tracker.FormatChance(7.5) == "7.5%")
suite.check("FormatChance: no trailing .0", Tracker.FormatChance(5) == "5%",
    Tracker.FormatChance(5))
suite.check("FormatChance: whole above ten", Tracker.FormatChance(42.6) == "43%")

--------------------------------------------------------------------------------
-- What is not a kill
--------------------------------------------------------------------------------

local kills = Tracker:Summary(WOLF).kills

env.world.fishing = true
Loot(WOLF, { FANG })
env.world.fishing = false
suite.check("fishing is not a kill", Tracker:Summary(WOLF).kills == kills)

env.world.target = { name = "Blackthornes", dead = true, isPlayer = true, guid = "Player-1" }
env.world.loot = { FANG }
fire(ns.eventFrame, "LOOT_OPENED")
suite.check("a player corpse is not a kill", Tracker:Summary("Blackthornes") == nil)

-- Instances: a secret guid is a kill we cannot recognise again, and a secret
-- item name loses only that item. Neither is an error.
env.world.target = { name = WOLF, level = 8, dead = true, guid = env.Secret("guid") }
env.world.loot = { { name = env.Secret("item") }, FANG }

local ok, err = pcall(fire, ns.eventFrame, "LOOT_OPENED")
suite.check("secret values do not raise", ok, err)
suite.check("a secret guid still counts the kill",
    Tracker:Summary(WOLF).kills == kills + 1, Tracker:Summary(WOLF).kills)

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

mark = #env.chat
ns.HandleSlash("kills mangy")
said = ChatSince(mark)
suite.check("/farm kills finds a mob by prefix", said:find("Mangy Wolf", 1, true) ~= nil, said)

mark = #env.chat
ns.HandleSlash("kills nobody")
said = ChatSince(mark)
suite.check("/farm kills says when it has nothing", said:find("no kills of nobody", 1, true), said)

ns.HandleSlash("tracker")
suite.check("/farm tracker hides the panel", ns.db.trackerHidden and not UI.frame:IsShown())

Loot(WOLF, {})
suite.check("a hidden panel stays hidden on the next kill", not UI.frame:IsShown())

ns.HandleSlash("tracker")
suite.check("/farm tracker brings it back", not ns.db.trackerHidden and UI.frame:IsShown())

--------------------------------------------------------------------------------
-- Across a reload
--------------------------------------------------------------------------------

local saved = BlackthornesFarmerDB
local wolfKills = Tracker:Summary(WOLF).kills

ns = env.Load({ ui = true })
BlackthornesFarmerDB = saved
ns.LoadSavedVariables()

summary = ns.Tracker:Summary(WOLF)
suite.check("the tally survives a reload", summary and summary.kills == wolfKills,
    summary and summary.kills)
suite.check("the session count starts again", summary.session == 0, summary.session)
suite.check("so do the corpses it remembers", next(ns.Tracker.corpses) == nil)

--------------------------------------------------------------------------------
-- Reset
--------------------------------------------------------------------------------

ns.HandleSlash("tracker reset")
suite.check("reset alone asks for confirmation", ns.Tracker:Summary(WOLF) ~= nil)

local harvested = ns.Harvest:CountCorpses()

ns.HandleSlash("tracker reset confirm")
suite.check("reset confirm clears it", ns.Tracker:Summary(WOLF) == nil)
suite.check("and leaves the harvest alone", ns.Harvest:CountCorpses() == harvested,
    ns.Harvest:CountCorpses())

suite.done()
