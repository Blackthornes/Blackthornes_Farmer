-- The Rankings board built over a few frames.
--
-- Opening the Rankings tab held the game for a moment: the board priced
-- every drop of every rated mob in one go (the owner, 2026-11-26). What
-- matters: the board built a slice a frame is the very board built in one
-- go; one frame's slice stops when its time is up; opening the tab draws
-- the board from last time at once; a board that came out the same is not
-- drawn twice; and only the newest build calls back.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("rankingssoon")

local ns = env.Load({ ui = true })
local Rankings, RankingsUI, Tracker, UI = ns.Rankings, ns.RankingsUI, ns.Tracker, ns.UI

_G.C_Item = {
    GetItemInfo = function(id) return "item", nil, 1, 1, 1, "", "", 1, "", "", 7 end,
}
local price = 50
_G.BlackthornesTS = { Prices = { GetValue = function() return price end } }

-- Timers wait here until the test lets a frame pass, as the game's do.
local queue = {}
_G.C_Timer.After = function(_, fn) queue[#queue + 1] = fn end
local function Frame()
    local due = queue
    queue = {}
    for _, fn in ipairs(due) do fn() end
    return #due
end
local function Settle()
    local frames = 0
    while #queue > 0 and frames < 5000 do Frame() frames = frames + 1 end
    return frames
end

-- A clock that moves 1 ms each time it is read: a slice of SLICE_MS holds
-- about that many mobs.
local clock = 0
_G.debugprofilestop = function() clock = clock + 1 return clock end

local serial = 0
local function Loot(mob, items)
    serial = serial + 1
    env.world.target = { name = mob, level = 8, dead = true, guid = "S-" .. serial }
    env.world.loot = items
    Tracker:OnLoot()
end
-- A few hundred mobs the database rates, as the shipped data has.
for index = 1, 300 do
    ns.DB:RegisterItem({ name = "Soon Test Tooth " .. index, id = 880000 + index, category = "misc",
        sources = { { kind = "mob", name = "Soon Test Ogre " .. index, zone = "Nowhere",
            minLevel = 10, maxLevel = 12, chance = index % 50 + 1 } } })
end
for _ = 1, 20 do Loot("Soon Test Wolf", { { name = "12 Copper", money = true } }) end
Settle()

--------------------------------------------------------------------------------
-- The same board, a slice a frame
--------------------------------------------------------------------------------

local function Shape(board)
    local parts = {}
    for _, group in ipairs({ "measured", "estimate", "pending" }) do
        parts[#parts + 1] = group .. ":" .. #board[group]
        for _, entry in ipairs(board[group]) do
            parts[#parts + 1] = table.concat({ entry.mob, tostring(entry.value), tostring(entry.rank),
                tostring(entry.where), tostring(entry.level), tostring(entry.best and entry.best.name) }, "|")
        end
    end
    return table.concat(parts, "\n")
end

local whole = Rankings:Build()
local mobs = #Rankings:Names()
suite.check("the test has a board worth slicing", mobs > 100 and #whole.estimate > 20, mobs)

local soon
Rankings:BuildSoon(function(board) soon = board end)
suite.check("a long board is not ready in the first frame", soon == nil and Rankings:Building())
suite.check("the first slice stopped when its time was up",
    Rankings.job.at <= Rankings.SLICE_MS + 2, Rankings.job.at)
local frames = Settle()
suite.check("it took many frames", frames > 10, frames)
suite.check("and came out the board built in one go", soon and Shape(soon) == Shape(whole))
suite.check("nothing is left building", not Rankings:Building())

-- Only the newest build calls back.
local first, second
Rankings:BuildSoon(function() first = true end)
Rankings:BuildSoon(function() second = true end)
Settle()
suite.check("a newer build drops the one under way", second and not first)

-- No timer at all: the board in one go, as before.
local after = _G.C_Timer.After
_G.C_Timer.After = nil
local atOnce
Rankings:BuildSoon(function(board) atOnce = board end)
suite.check("without a timer the board is built at once", atOnce and Shape(atOnce) == Shape(whole))
_G.C_Timer.After = after

--------------------------------------------------------------------------------
-- Opening the tab
--------------------------------------------------------------------------------

local draws = 0
UI:Show()
UI:ShowTab("rankings")
local setData = RankingsUI.list.SetData
RankingsUI.list.SetData = function(...) draws = draws + 1 return setData(...) end

suite.check("the first opening holds nothing up: the board is still building",
    Rankings:Building() and RankingsUI.board == nil)
Settle()
suite.check("and is drawn when it is ready", draws == 1 and RankingsUI.board ~= nil, draws)
local firstBoard = RankingsUI.board

-- Away and back: the board from last time is there at once.
UI:ShowTab("search")
draws = 0
UI:ShowTab("rankings")
suite.check("opening it again draws the board kept, at once", draws == 1 and Rankings:Building(), draws)
suite.check("with the rows it had", #RankingsUI.list.data > 20, #RankingsUI.list.data)
Settle()
suite.check("the same board built again is not drawn twice", draws == 1, draws)
suite.check("what is drawn stays the board it came from", RankingsUI.board == firstBoard)

-- A price moved while the tab was up: the new board takes its place.
price = 90
draws = 0
RankingsUI:Render()
suite.check("a redraw waits for the new board", draws == 0, draws)
Settle()
suite.check("a board that changed is drawn", draws == 1, draws)

-- A chip answers at once from the board kept.
draws = 0
RankingsUI.group = "estimate"
RankingsUI:Render()
suite.check("a chip is drawn at once", draws == 1, draws)
Settle()
suite.check("and not again when nothing moved", draws == 1, draws)
RankingsUI.group = nil
RankingsUI:Render()
Settle()

-- Built while another tab was up: kept, not drawn.
draws = 0
RankingsUI:Render()
UI:ShowTab("search")
Settle()
suite.check("a board that lands on another tab is kept, not drawn", draws == 0, draws)

_G.debugprofilestop = nil

suite.done()
