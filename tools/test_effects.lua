-- The kill panel's effects (Trent, 2026-09-26: "dopamine hits as you're
-- killing stuff"), and the addon's own sounds.
--
-- What matters: the first redraw (login, or the panel shown again) only takes
-- note, a later one moves exactly
-- what went up, the value line gets its "+" for a few seconds, loot floats,
-- a green-or-better drop plays the rare sound (once, and only if it is on),
-- Subtle and Off do less, a hidden panel starts over, an effect never draws
-- on a row that now shows another line, and a failing effect never costs a
-- kill.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("effects")

local ns = env.Load({ ui = true })
local Tracker = ns.Tracker
local TUI = ns.TrackerUI
local FX = ns.TrackerFX

local played = {}
_G.PlaySoundFile = function(path, channel)
    played[#played + 1] = { path = path, channel = channel }
    return true
end

local VENDOR = { [2589] = 13, [5637] = 50, [4690] = 900 }
_G.C_Item = {
    GetItemInfo = function(id)
        return "item", nil, 1, 1, 1, "", "", 1, "", "", VENDOR[id] or 0
    end,
}

TUI:OnEnable()

local serial = 0
local function Loot(mob, items)
    serial = serial + 1
    env.world.target = { name = mob, level = 8, dead = true, guid = "FX-" .. serial }
    env.world.loot = items
    Tracker:OnLoot()
end

local function Shown(key)
    -- The gathered value is drawn in the title bar, not a column row.
    if key == "total" then return TUI.titleLine, TUI.titleRow end
    for index, line in ipairs(TUI.shown or {}) do
        if line.key == key then return line, TUI.lines[index] end
    end
end

local function Settle()
    for _ = 1, 100 do FX:Step(0.1) end
end

--- An item's icon on an open card, and the slot drawing it.
local function Icon(name)
    for index, line in ipairs(TUI.shown or {}) do
        for at, icon in ipairs(line.icons or {}) do
            if icon.item == name then return icon, TUI.lines[index].slots[at] end
        end
    end
end

local function Moving(frame, part)
    for _, effect in ipairs(FX.effects) do
        if effect.row == frame and (part == nil or effect.slot == part) then return true end
    end
    return false
end

local WOOL = { name = "Wool Cloth", id = 2589, quantity = 2 }
local FANG = { name = "Large Fang", id = 5637 }
local CLOAK = { name = "Scouting Cloak", id = 4690 }
local COINS = { name = "38 Silver", money = true }

-- The cloak is green. The test client's links are all white, and the colour
-- kept first is the one that stays.
ns.db.tracker = ns.db.tracker or {}
ns.db.tracker.looks = ns.db.tracker.looks or {}
ns.db.tracker.looks["Scouting Cloak"] = { color = "ff1eff00" }

suite.check("green is rare", FX.QualityOf("Scouting Cloak") == 2, FX.QualityOf("Scouting Cloak"))
suite.check("white is not", FX.QualityOf("Nothing Seen") == nil)

--------------------------------------------------------------------------------
-- Login only takes note; the session's first kill already moves
--------------------------------------------------------------------------------

suite.check("the empty panel at login starts nothing", #FX.effects == 0, #FX.effects)
suite.check("but is where the counts start", FX.seen ~= nil)

Loot("Mangy Wolf", { FANG })
suite.check("the first kill moves", #FX.effects > 0, #FX.effects)
suite.check("and remembers the counts", FX.seen["mob:Mangy Wolf"].count == 1)
suite.check("and plays no sound", #played == 0, #played)
Settle()

--------------------------------------------------------------------------------
-- The next one moves what went up
--------------------------------------------------------------------------------

Loot("Mangy Wolf", { COINS, WOOL, FANG })
suite.check("effects start", #FX.effects > 0, #FX.effects)
suite.check("the clock runs", FX.driver and FX.driver:IsShown())

local band, bandRow = Shown("mob:Mangy Wolf")
suite.check("the wolf's band is shown", band ~= nil)
suite.check("and glows", bandRow and FX.FlashOf(bandRow) ~= nil)

local total, totalRow = Shown("total")
suite.check("value line carries the gain", total and total.badge == "+" .. ns.Value.Coins(3800 + 26 + 50),
    total and total.badge)
suite.check("and the title bar shows it", totalRow.badge:IsShown()
    and totalRow.badge:GetText() == total.badge, totalRow.badge:GetText())

local floated = {}
for _, label in ipairs(FX.floats or {}) do
    if FX.Floating(label) then floated[#floated + 1] = ns.Util.StripColor(label:GetText()) end
end
table.sort(floated)
suite.check("two things float", #floated == 2, #floated)
suite.check("the fang", floated[1] == "+1 Large Fang", floated[1])
suite.check("and the cloth, stack and all", floated[2] == "+2 Wool Cloth", floated[2])
suite.check("nothing white chimes", #played == 0, #played)

-- Partway through, the value is between the two.
FX:Step(0.2)
local middle = totalRow.right:GetText()
suite.check("value is counting up", middle ~= ns.Value.Coins(total.count), middle)

Settle()
suite.check("everything ends", #FX.effects == 0, #FX.effects)
suite.check("the clock stops", not FX.driver:IsShown())
suite.check("value lands on the total", totalRow.right:GetText() == ns.Value.Coins(total.count),
    totalRow.right:GetText())
suite.check("the + goes", not totalRow.badge:IsShown())
suite.check("floats land", not FX.Floating(FX.floats[1]))

-- A redraw with nothing new moves nothing.
TUI:Refresh()
suite.check("no change, no effect", #FX.effects == 0, #FX.effects)
local again = Shown("total")
suite.check("and the + stays gone", again.badge == nil, again.badge)

--------------------------------------------------------------------------------
-- Rare drops
--------------------------------------------------------------------------------

Loot("Mangy Wolf", { CLOAK })
suite.check("green chimes", #played == 1, #played)
suite.check("our own sound", played[1] and played[1].path == Tracker.SOUNDS.rare, played[1] and played[1].path)
suite.check("on the master channel", played[1] and played[1].channel == "Master")

local cloak, cloakSlot = Icon("Scouting Cloak")
suite.check("the cloak's icon is there", cloak ~= nil)
suite.check("and lights up", cloakSlot and Moving(cloakSlot))
suite.check("with NEW on it, the wolf's first", cloakSlot and Moving(cloakSlot, cloakSlot.tag))

-- A redraw mid-pop, then another pop on the same icon: it still lands where
-- the panel put it.
FX:Step(0.05)
TUI:Refresh()
FX:Step(0.05)
if cloakSlot then FX:SlotGained(cloakSlot, { icon = cloak, new = true }, "full") end
Settle()
local _, _, _, landedX, landedY = cloakSlot:GetPoint(1)
suite.check("the popped icon lands back in its place",
    landedX == cloakSlot.baseX and landedY == cloakSlot.baseY, tostring(landedX) .. "," .. tostring(landedY))

-- A second fang is not new: its count goes up and says so.
Settle()
Loot("Mangy Wolf", { FANG })
local _, fangSlot = Icon("Large Fang")
suite.check("an icon whose count went up lights up", fangSlot and Moving(fangSlot))
suite.check("and says by how many", fangSlot and fangSlot.gain:GetText() == "+1",
    fangSlot and fangSlot.gain:GetText())
suite.check("but it is not new", fangSlot and not Moving(fangSlot, fangSlot.tag))

-- On the Loot tab, the cloak's own line washes in its colour.
Settle()
TUI:SetTab("loot")
Loot("Mangy Wolf", { CLOAK })
local _, cloakRow = Shown("loot:Scouting Cloak")
suite.check("the cloak's Loot line washes", cloakRow and FX.FlashOf(cloakRow) ~= nil)
TUI:SetTab("farm")
Settle()
played = {}

-- Two in the same breath: one chime.
Loot("Mangy Wolf", { CLOAK })
Loot("Mangy Wolf", { CLOAK })
suite.check("not twice at once", #played == 1, #played)

Settle()
FX.rareAt = nil
Loot("Mangy Wolf", { CLOAK })
suite.check("again once it has played out", #played == 2, #played)

ns.HandleSlash("raresound off")
Settle()
FX.rareAt = nil
Loot("Mangy Wolf", { CLOAK })
suite.check("switched off, silent", #played == 2, #played)
ns.HandleSlash("raresound on")
suite.check("back on", FX.RareSoundOn())

-- The panel hidden: the chime has its own switch and still plays.
ns.db.trackerHidden = true
TUI:Refresh()
FX.rareAt = nil
Loot("Mangy Wolf", { CLOAK })
suite.check("hidden panel, green still chimes", #played == 3, #played)
FX.rareAt = nil
Loot("Mangy Wolf", { WOOL })
suite.check("hidden panel, white stays quiet", #played == 3, #played)
ns.db.trackerHidden = false
TUI:Refresh()
played = { 1, 2 }

--------------------------------------------------------------------------------
-- Subtle and Off
--------------------------------------------------------------------------------

Settle()
ns.HandleSlash("effects subtle")
suite.check("subtle saved", ns.db.trackerEffects == "subtle", ns.db.trackerEffects)

Loot("Mangy Wolf", { WOOL })
local busy = 0
for _, label in ipairs(FX.floats or {}) do if FX.Floating(label) then busy = busy + 1 end end
suite.check("subtle: nothing floats", busy == 0, busy)
suite.check("subtle: still glows", #FX.effects > 0, #FX.effects)

Settle()
ns.HandleSlash("effects off")
Loot("Mangy Wolf", { WOOL })
suite.check("off: nothing moves", #FX.effects == 0, #FX.effects)
local quiet = Shown("total")
suite.check("off: no +", quiet.badge == nil, quiet.badge)

Settle()
Loot("Mangy Wolf", { CLOAK })
suite.check("off still chimes (its own switch)", #played == 3, #played)

ns.HandleSlash("effects")
suite.check("no word steps round to full", FX.Level() == "full", FX.Level())

--------------------------------------------------------------------------------
-- Hidden, then shown again
--------------------------------------------------------------------------------

Settle()
ns.HandleSlash("tracker off")
suite.check("hidden forgets", FX.seen == nil)
Loot("Mangy Wolf", { WOOL })
ns.HandleSlash("tracker on")
suite.check("shown again starts nothing", #FX.effects == 0, #FX.effects)

--------------------------------------------------------------------------------
-- A row handed another line
--------------------------------------------------------------------------------

Loot("Mangy Wolf", { COINS })
local _, row = Shown("total")
suite.check("value counting", #FX.effects > 0)
row.right:SetText("Somebody else")
row.line = { key = "loot:Wool Cloth" }
FX:Step(0.1)
suite.check("never draws on another line", row.right:GetText() == "Somebody else", row.right:GetText())
Settle()
TUI:Refresh()

--------------------------------------------------------------------------------
-- A broken effect never costs a kill
--------------------------------------------------------------------------------

local prepare = FX.Prepare
FX.Prepare = function() error("boom") end
local before = Tracker:Store()["Mangy Wolf"].kills
local ok, err = pcall(Loot, "Mangy Wolf", { WOOL })
suite.check("the loot handler survives", ok, err)
suite.check("and the kill counts", Tracker:Store()["Mangy Wolf"].kills == before + 1)
FX.Prepare = prepare

FX:Start({ duration = 1, apply = function() error("boom") end })
local stepped = pcall(FX.Step, FX, 0.1)
suite.check("an effect that fails is dropped", stepped and #FX.effects == 0, #FX.effects)

--------------------------------------------------------------------------------
-- The unlock fanfare
--------------------------------------------------------------------------------

local ids = {}
_G.PlaySound = function(id) ids[#ids + 1] = id return true end

played = {}
Tracker:Fanfare("unlocked", nil)
suite.check("our fanfare first", played[1] and played[1].path == Tracker.SOUNDS.unlock,
    played[1] and played[1].path)
suite.check("and not the built-in one too", #ids == 0, #ids)

-- Before a restart the game has not found the file yet and refuses it.
_G.PlaySoundFile = function() return false end
Tracker:Fanfare("unlocked", nil)
suite.check("falls back to the built-in chime", ids[1] == 12891, ids[1])

_G.PlaySoundFile = function() error("no such file") end
suite.check("an error is a refusal", Tracker.PlayFile(Tracker.SOUNDS.unlock) == false)

_G.PlaySoundFile = nil
_G.PlaySound = nil

suite.done()
