-- Blackthornes Farmer -- UI/Arrow.lua
-- The goal arrow's dial (2026-10-08): a gold ring with corner gems and a
-- glowing arrow that turns as you turn, pointing at the nearest place to
-- gather the goal it follows. Logic/Arrow.lua works out where and how far;
-- this file only draws it.
--
-- The goal and its count sit on a plate across the top of the ring, the
-- distance under it, then the place and why it is there. Click for the next
-- goal, right-click for the next place, drag to move. Once you are there the
-- arrow gives way to a green check. The glow breathes with the Window effects
-- setting: it pulses on Full, holds still on Subtle and Off.
--
-- Off until turned on (/farm arrow, the settings page, or Shift-click on a
-- goal or a Where? place), closed with its red gem, and hidden inside
-- dungeons and while no goal is open. With TomTom installed and used, the
-- place goes to TomTom instead and the dial stays hidden (Logic/TomTom.lua).

local ADDON, ns = ...

local ArrowUI = ns.NewModule("ArrowUI")

local Theme = ns.Theme

local MEDIA = ([[Interface\AddOns\%s\Media\]]):format(ADDON)
ArrowUI.RING = MEDIA .. [[Arrow\Ring]]
ArrowUI.ARROW = MEDIA .. [[Arrow\Arrow]]
ArrowUI.GLOW = MEDIA .. [[Frame\Glow]]
local CHECK = [[Interface\RaidFrame\ReadyCheck-Ready]]

local RING = 92
local ARROW = 50
local PLATE_HEIGHT = 22
local MIN_WIDTH = 170
local MAX_WIDTH = 320

-- Redrawn this often, seconds: smooth to the eye, cheap to run.
local STEP = 0.03

-- Gold while it points the way, green once you are there, pale blue when it
-- cannot point (the other continent, no position).
local TINTS = {
    point = { 1.00, 0.82, 0.32 },
    arrived = { 0.31, 0.95, 0.55 },
    rest = { 0.55, 0.65, 1.00 },
}

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

local function Additive(texture)
    pcall(texture.SetBlendMode, texture, "ADD")
    return texture
end

function ArrowUI:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesFarmerArrow", UIParent)
    frame:SetSize(MIN_WIDTH, RING + PLATE_HEIGHT + 56)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")

    -- The dial: a breathing glow behind the ring, the ring, then the arrow
    -- with its own glow.
    local dial = CreateFrame("Frame", nil, frame)
    dial:SetSize(RING, RING)
    dial:SetPoint("TOP", frame, "TOP", 0, -(PLATE_HEIGHT / 2 + 2))
    self.dial = dial

    local halo = Additive(dial:CreateTexture(nil, "BACKGROUND"))
    halo:SetTexture(ArrowUI.GLOW)
    halo:SetSize(RING * 1.6, RING * 1.6)
    halo:SetPoint("CENTER")
    self.halo = halo

    local ring = dial:CreateTexture(nil, "ARTWORK")
    ring:SetTexture(ArrowUI.RING)
    ring:SetAllPoints(dial)
    self.ring = ring

    local arrowGlow = Additive(dial:CreateTexture(nil, "OVERLAY", nil, 1))
    arrowGlow:SetTexture(ArrowUI.ARROW)
    arrowGlow:SetSize(ARROW * 1.35, ARROW * 1.35)
    arrowGlow:SetPoint("CENTER")
    self.arrowGlow = arrowGlow

    local arrow = dial:CreateTexture(nil, "OVERLAY", nil, 2)
    arrow:SetTexture(ArrowUI.ARROW)
    arrow:SetSize(ARROW, ARROW)
    arrow:SetPoint("CENTER")
    self.arrow = arrow

    local check = dial:CreateTexture(nil, "OVERLAY", nil, 3)
    check:SetTexture(CHECK)
    check:SetSize(40, 40)
    check:SetPoint("CENTER")
    check:Hide()
    self.check = check

    local mark = Theme.CreateLabel(dial, "title", "accentHi", "CENTER")
    pcall(mark.SetFont, mark, Theme.FONT, 30, "OUTLINE")
    mark:SetPoint("CENTER", 0, 1)
    mark:SetText("?")
    mark:Hide()
    self.mark = mark

    -- The plate across the ring's top: the goal and its count.
    local plate = CreateFrame("Frame", nil, frame)
    plate:SetHeight(PLATE_HEIGHT)
    plate:SetPoint("TOP", frame, "TOP", 0, 0)
    plate:SetFrameLevel(dial:GetFrameLevel() + 5)
    Theme.Fill(plate, "ink", 0.96)
    Theme.Border(plate, "accentHi")
    Theme.Halo(plate, 5, 0.18)
    self.plate = plate

    -- The house close gem, just past the plate's right end, clear of the
    -- goal's name: turns it off.
    if ns.Titanforged and ns.Titanforged.CloseGem then
        local close = ns.Titanforged.CloseGem(frame, function() ArrowUI:Close() end)
        close:SetSize(20, 20)
        close:ClearAllPoints()
        close:SetPoint("LEFT", plate, "RIGHT", 4, 0)
        close:SetFrameLevel(plate:GetFrameLevel() + 1)
        self.close = close
    end

    local title = Theme.CreateLabel(plate, "normal", "gilt", "CENTER")
    title:SetPoint("CENTER", 0, 0)
    self.title = title

    -- Under the ring: how far, where, and why.
    local distance = Theme.CreateLabel(frame, "large", "text", "CENTER")
    pcall(distance.SetFont, distance, Theme.FONT, 15, "OUTLINE")
    distance:SetPoint("TOP", dial, "BOTTOM", 0, -4)
    self.distance = distance

    local place = Theme.CreateLabel(frame, "small", "muted", "CENTER")
    pcall(place.SetFont, place, Theme.FONT, Theme.sizes.small, "OUTLINE")
    place:SetPoint("TOP", distance, "BOTTOM", 0, -3)
    self.place = place

    local note = Theme.CreateLabel(frame, "tiny", "good", "CENTER")
    pcall(note.SetFont, note, Theme.FONT, Theme.sizes.small, "OUTLINE")
    note:SetPoint("TOP", place, "BOTTOM", 0, -2)
    self.note = note

    frame:SetScript("OnDragStart", function(self)
        self.dragging = true
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        ArrowUI:SavePosition()
        -- The button coming up after a drag is not a click.
        self.dragged = true
    end)
    frame:SetScript("OnMouseUp", function(self, button)
        if self.dragged then
            self.dragged, self.dragging = nil, nil
            return
        end
        ArrowUI:OnClick(button)
    end)
    frame:SetScript("OnEnter", function(self) ArrowUI:ShowTooltip(self) end)
    frame:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    frame:SetScript("OnUpdate", function(_, elapsed) ArrowUI:Step(elapsed) end)

    self.frame = frame
    self:RestorePosition()
    frame:Hide()
    return frame
end

--------------------------------------------------------------------------------
-- Clicks and the tooltip
--------------------------------------------------------------------------------

function ArrowUI:OnClick(button)
    local Arrow = ns.Arrow
    if button == "RightButton" then
        local target = Arrow:NextSpot()
        if not target then ns.Print("no other place known for that goal.") end
    elseif Arrow.grind then
        -- Following a grinding camp: a click goes back to the goals.
        Arrow:StopGrind()
        ns.Print("back to your goals.")
    else
        local before = Arrow:Goal()
        local goal = Arrow:NextGoal()
        if goal and goal == before then ns.Print("that is your only open goal.") end
    end
    self.since = STEP
    self:Draw(true)
end

--- The close gem: the arrow off until turned on again.
function ArrowUI:Close()
    ns.Arrow:SetOn(false)
    ns.Print("goal arrow off. /farm arrow, or the settings page, brings it back.")
    if ns.SettingsUI then pcall(ns.SettingsUI.Refresh, ns.SettingsUI) end
end

function ArrowUI:ShowTooltip(owner)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Goal arrow")
    local state = self.state
    if state and state.count and state.count > 1 then
        GameTooltip:AddLine(("Place %d of %d"):format(state.index or 1, state.count), 1, 1, 1)
    end
    if ns.Arrow.grind then
        GameTooltip:AddLine("Click to go back to your goals.", 0.9, 0.9, 0.9)
    else
        GameTooltip:AddLine("Click for the next goal.", 0.9, 0.9, 0.9)
    end
    GameTooltip:AddLine("Right-click for the next place.", 0.9, 0.9, 0.9)
    GameTooltip:AddLine("Drag to move it. The red gem closes it.", 0.9, 0.9, 0.9)
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local function Clock()
    if type(GetTime) ~= "function" then return 0 end
    local ok, now = pcall(GetTime)
    return ok and tonumber(now) or 0
end

--------------------------------------------------------------------------------
-- One arrow at a time
--
-- Farmer, Equipment and Pets each have an arrow, and the owner asked
-- (2026-10-08) that only one be up at a time. They agree through one
-- global table, BlackthornesArrows, made by whichever loads first:
--   wants[addon]   true while that addon's arrow has something to show
--   claims[addon]  when the player last turned it on or aimed it (GetTime)
-- Of those wanting to show, the one with the latest claim is drawn; the
-- others wait hidden and come back once it is turned off or has nothing to
-- show. An addon on its own always wins. The same lines are in all three
-- addons; a change to them belongs in all three.
--------------------------------------------------------------------------------

local ME = "Farmer"

local function Shared()
    local shared = rawget(_G, "BlackthornesArrows")
    if type(shared) ~= "table" then
        shared = {}
        _G.BlackthornesArrows = shared
    end
    if type(shared.wants) ~= "table" then shared.wants = {} end
    if type(shared.claims) ~= "table" then shared.claims = {} end
    return shared
end

--- This arrow was turned on or aimed: it goes on top.
function ArrowUI:Claim()
    Shared().claims[ME] = Clock()
end

--- Say whether this arrow wants to show; true when it is the one shown.
function ArrowUI.Wins(wants)
    local shared = Shared()
    shared.wants[ME] = wants and true or nil
    if not wants then return false end
    local best, bestAt
    for name, wanting in pairs(shared.wants) do
        local at = tonumber(shared.claims[name]) or 0
        if wanting and (not best or at > bestAt or (at == bestAt and tostring(name) < best)) then
            best, bestAt = tostring(name), at
        end
    end
    return best == ME
end

--- The words for a state with nothing to point at.
function ArrowUI.Words(state)
    local mode = state.mode
    if mode == "none" then
        return "No goal yet", "Set a goal to follow", "/farm goal Copper Ore 40", "muted"
    end
    if mode == "blind" then
        return "Can't see you here", "The game won't say where you are", "/farm arrow check", "muted"
    end
    if mode == "nowhere" then
        return "No places known", "Farm it once and it learns", "", "muted"
    end
    return state.distance or "", state.place or "", state.note or "", state.noteColor or "muted"
end

--- Lay the labels out and size the frame to the widest, measured.
function ArrowUI:Fit()
    local widest = Theme.TextWidth("normal", self.title:GetText()) + 28
    self.plate:SetWidth(math.max(RING + 16, widest))

    for _, entry in ipairs({ { "large", self.distance }, { "small", self.place }, { "small", self.note } }) do
        widest = math.max(widest, Theme.TextWidth(entry[1], entry[2]:GetText()) + 16)
    end

    local width = math.min(MAX_WIDTH, math.max(MIN_WIDTH, math.ceil(widest)))
    self.frame:SetWidth(width)
    -- Wrapped rather than cut off when a long place name runs past the most.
    for _, label in ipairs({ self.distance, self.place, self.note }) do
        label:SetWidth(width - 8)
        label:SetWordWrap(true)
    end
end

--- Draw the state now. `force` relays the words even when they read the
--- same.
function ArrowUI:Draw(force)
    local frame = self.frame
    if not frame then return end

    local state = ns.Arrow:State(Clock())
    self.state = state

    -- No open goal: nothing to follow, so out of the way until one is set.
    if state.mode == "off" or state.mode == "inside" or state.mode == "none" then
        ArrowUI.Wins(false)
        ns.TomTom:Clear()
        frame:Hide()
        return
    end

    -- Another Blackthornes arrow was aimed more lately: wait, hidden.
    if not ArrowUI.Wins(true) then
        ns.TomTom:Clear()
        frame:Hide()
        return
    end

    -- TomTom installed and used: its arrow shows the way, so the dial hides
    -- and only one arrow is on screen. The driver below keeps it current.
    if ns.TomTom:Take(state) then
        frame:Hide()
        return
    end

    local goal = state.goal
    -- The plate carries a goal or nothing: never a name for the dial.
    local title = goal and ("%s  %d / %d"):format(goal.item, goal.have or 0, goal.target or 0) or ""
    -- A grinding camp has no count: its place is the plate.
    if goal and goal.grind then title = "Grind: " .. goal.item end
    self.plate:SetShown(title ~= "")
    local distance, place, note, noteColor = ArrowUI.Words(state)

    -- Joined by hand: a table here was one more for the collector 33 times
    -- a second.
    local key = title .. "\n" .. distance .. "\n" .. place .. "\n" .. note .. "\n" .. noteColor
    if force or key ~= self.drawnKey then
        self.drawnKey = key
        self.title:SetText(title)
        self.distance:SetText(distance)
        self.place:SetText(place)
        self.note:SetText(note)
        self.note:SetTextColor(Theme.Unpack(noteColor))
        self.distance:SetTextColor(Theme.Unpack(state.mode == "arrived" and "good" or "text"))
        self:Fit()
    end

    local pointing = state.mode == "point"
    local arrived = state.mode == "arrived"
    self.arrow:SetShown(pointing)
    self.arrowGlow:SetShown(pointing)
    self.check:SetShown(arrived)
    self.mark:SetShown(not pointing and not arrived)

    local tint = pointing and TINTS.point or arrived and TINTS.arrived or TINTS.rest
    self.arrow:SetVertexColor(tint[1], tint[2], tint[3])
    self.arrowGlow:SetVertexColor(tint[1], tint[2], tint[3])
    self.halo:SetVertexColor(tint[1], tint[2], tint[3])
    self.mark:SetTextColor(tint[1], tint[2], tint[3])

    if pointing and state.turn then
        self:Turn(state.turn)
    end

    frame:Show()
end

--- Turn the arrow toward `turn` (radians, anticlockwise). Eased on Full so
--- it swings rather than snaps; straight there otherwise.
function ArrowUI:Turn(turn)
    local shown = self.shownTurn
    if shown and ns.Motion.Level() == "full" then
        local gap = turn - shown
        while gap > math.pi do gap = gap - 2 * math.pi end
        while gap < -math.pi do gap = gap + 2 * math.pi end
        turn = shown + gap * 0.35
    end
    self.shownTurn = turn
    pcall(self.arrow.SetRotation, self.arrow, turn)
    pcall(self.arrowGlow.SetRotation, self.arrowGlow, turn)
end

--- The glow: breathing on Full, still otherwise, brighter once you are there.
function ArrowUI:Breathe(now)
    local level = ns.Motion.Level()
    local arrived = self.state and self.state.mode == "arrived"
    local rest = arrived and 0.55 or 0.32
    local alpha = rest
    if level == "full" then
        local speed = arrived and 5 or 2.2
        alpha = rest + 0.16 * math.sin(now * speed)
    elseif level == "off" then
        alpha = rest * 0.6
    end
    self.halo:SetAlpha(alpha)
    self.arrowGlow:SetAlpha(math.min(1, alpha + 0.25))
end

function ArrowUI:Step(elapsed)
    self.since = (self.since or 0) + (elapsed or 0)
    if self.since < STEP then return end
    self.since = 0

    local ok, err = pcall(self.Draw, self)
    if not ok then ns.Debug("goal arrow:", tostring(err)) end
    if self.frame:IsShown() then pcall(self.Breathe, self, Clock()) end
end

--- Show or hide it as the switch and the goals say. The driver keeps it
--- current while shown; a hidden dial is woken by its driver below.
function ArrowUI:Refresh()
    if not ns.db then return end
    if not ns.Arrow.IsOn() then
        -- Nothing to wake while it is off: the driver rests until it is on.
        if self.driver then self.driver:Hide() end
        ArrowUI.Wins(false)
        ns.TomTom:Clear()
        if self.frame then self.frame:Hide() end
        return
    end
    if self.driver then self.driver:Show() end
    self:Build()
    local ok, err = pcall(self.Draw, self, true)
    if not ok then ns.Debug("goal arrow:", tostring(err)) end
end

--------------------------------------------------------------------------------
-- Position
--------------------------------------------------------------------------------

function ArrowUI:SavePosition()
    local frame = self.frame
    local ok, x, y = pcall(function() return frame:GetCenter() end)
    if not (ok and type(x) == "number" and type(y) == "number") then return end

    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    ns.db.arrowX, ns.db.arrowY = x, y
end

function ArrowUI:RestorePosition()
    local frame = self.frame
    if not frame then return end
    frame:ClearAllPoints()
    if ns.db.arrowX and ns.db.arrowY then
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ns.db.arrowX, ns.db.arrowY)
    else
        -- Top middle, under where the game puts its own messages.
        frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
end

function ArrowUI:ResetPosition()
    ns.db.arrowX, ns.db.arrowY = nil, nil
    self:RestorePosition()
end

--------------------------------------------------------------------------------
-- Keeping up
--------------------------------------------------------------------------------

function ArrowUI:OnEnable()
    -- The dial's own OnUpdate stops while it is hidden, so a small driver
    -- wakes it: leaving a dungeon, or a goal set while it had none.
    local driver = CreateFrame("Frame", nil, UIParent)
    driver.since = 0
    driver:SetScript("OnUpdate", function(selfDriver, elapsed)
        selfDriver.since = selfDriver.since + (elapsed or 0)
        if selfDriver.since < 1 then return end
        selfDriver.since = 0
        if ns.Arrow.IsOn() and not (ArrowUI.frame and ArrowUI.frame:IsShown()) then
            ArrowUI:Refresh()
        end
    end)
    driver:Show()
    self.driver = driver

    self:Refresh()

    -- A goal's count changes the plate.
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function() ArrowUI:Refresh() end)
end

