-- The see-through Kills & Loot panel (the owner, 2026-10-16).
--
-- What matters: it is off unless ticked, so the panel looks as it always
-- has; ticked, the dark glass thins to the level picked while the open
-- card keeps more of its gold, every word gets a shadow, and the cut-edge
-- fades stay out; the glass comes back while the mouse is on the panel and
-- goes again when it leaves; lines made later follow; the command and
-- Settings write the same saved keys; and unticking puts it all back.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("seethrough")

local ns = env.Load({ ui = true })
local TUI = ns.TrackerUI

TUI:OnEnable()
TUI:Build()

local function Near(a, b) return type(a) == "number" and math.abs(a - b) < 0.001 end

-- Every piece of glass remembers the alpha it was given.
local function Track(part)
    local texture = part.texture
    if rawget(texture, "_tracked") then return end
    texture._tracked = true
    texture.SetAlpha = function(self, value) self._alpha = value end
end
local function TrackAll() for _, part in ipairs(TUI.glassParts) do Track(part) end end

local function Settle() ns.Motion:FinishAll() end

local over = false
TUI.frame.IsMouseOver = function() return over end

local function Look()
    local watch = TUI.seeThroughWatch
    local tick = watch:GetScript("OnUpdate")
    if tick then tick(watch, 1) end
    Settle()
end

suite.check("off unless ticked", ns.db.trackerSeeThrough == false and not TUI:SeeThroughOn())
suite.check("More is the level picked at first", TUI:SeeThroughLevel() == 2)
suite.check("the panel, title bar, tabs and toolbar are glass", #TUI.glassParts >= 4, #TUI.glassParts)
suite.check("the watcher sleeps while it is off", TUI.seeThroughWatch:GetScript("OnUpdate") == nil)

TrackAll()
TUI:SetSeeThrough(true)
Settle()
TrackAll()

local keep = TUI.SEE_THROUGH_LEVELS[2]
local thin, floored = true, false
for _, part in ipairs(TUI.glassParts) do
    local want = math.max(keep, part.floor)
    if not Near(part.texture._alpha, want) then thin = false end
    if part.floor > keep then floored = true end
end
suite.check("ticked, every piece of glass thins to the level", thin)
suite.check("the watcher runs", TUI.seeThroughWatch:GetScript("OnUpdate") ~= nil)

-- A line made now starts see-through and its open-card gold keeps more.
local row = TUI:CreateLine(TUI.frame, 99)
local band, live
for _, part in ipairs(TUI.glassParts) do
    if part.texture == row.band then band = part end
    if part.texture == row.live then live = part end
end
suite.check("a new line is glass too", band ~= nil and live ~= nil)
suite.check("and the open card keeps more of its gold", live and live.floor > keep)
floored = floored or (live and live.floor > keep)
suite.check("so something keeps a floor", floored)

-- Words get a shadow while see-through.
local label = TUI.frame:CreateFontString()
local shadow
label.GetObjectType = function() return "FontString" end
label.SetShadowOffset = function(_, x, y) shadow = { x, y } end
TUI.ShadeAll({ GetRegions = function() return label end }, true)
suite.check("words get a shadow", shadow and shadow[1] == 1 and shadow[2] == -1)
TUI.ShadeAll({ GetRegions = function() return label end }, false)
suite.check("and lose it after", shadow and shadow[1] == 0 and shadow[2] == 0)

-- The fades at the cut edges are the panel's dark colour: left out.
TUI:Refresh()
suite.check("no dark fade at the cut edges", not (TUI.fadeTop and TUI.fadeTop:IsShown())
    and not (TUI.fadeBottom and TUI.fadeBottom:IsShown()))

-- The mouse on the panel brings the glass back; away, it goes again.
TrackAll()
over = true
Look()
suite.check("the glass comes back under the mouse", Near(TUI.glassShown, 1))
over = false
Look()
suite.check("and goes when the mouse leaves", Near(TUI.glassShown, keep))

-- Most clear.
TUI:SetSeeThroughLevel(3)
Settle()
suite.check("Most keeps less glass", Near(TUI.glassShown, TUI.SEE_THROUGH_LEVELS[3]))
suite.check("saved", ns.db.trackerSeeThroughLevel == 3)
TUI:SetSeeThroughLevel(9)
suite.check("a level not on the list is ignored", ns.db.trackerSeeThroughLevel == 3)

-- Unticked, everything is back.
TUI:SetSeeThrough(false)
local solid = true
for _, part in ipairs(TUI.glassParts) do
    if not Near(part.texture._alpha, 1) then solid = false end
end
suite.check("unticked, the glass is solid again", solid and Near(TUI.glassShown, 1))
suite.check("and the watcher sleeps", TUI.seeThroughWatch:GetScript("OnUpdate") == nil)

-- The command writes the same keys.
ns.HandleSlash("tracker seethrough on")
suite.check("/farm tracker seethrough on", ns.db.trackerSeeThrough == true)
ns.HandleSlash("tracker seethrough off")
suite.check("/farm tracker seethrough off", ns.db.trackerSeeThrough == false)
ns.HandleSlash("tracker seethrough some")
suite.check("/farm tracker seethrough some picks the level and turns it on",
    ns.db.trackerSeeThroughLevel == 1 and ns.db.trackerSeeThrough == true)
ns.HandleSlash("tracker seethrough")
suite.check("alone it flips", ns.db.trackerSeeThrough == false)
ns.HandleSlash("tracker clear")
suite.check("tracker clear still clears the panel, not the look", ns.db.trackerSeeThrough == false)

suite.done()
