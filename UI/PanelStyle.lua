--------------------------------------------------------------------------------
-- UI/PanelStyle.lua
--
-- Panel Style (the owner said build it, 2026-11-21, from the mockup
-- ui-pass-3-quest-list-look; he approved the words): Kills & Loot and the
-- goals panel can drop their box and read like the game's own quest list.
-- "Panel Style:" on the WINDOWS page, Boxed (the default) or Like Quest List.
--
-- Like Quest List: no glass, rim, glow or row lines; every word gets a black
-- shadow; the heading turns the game's yellow with a thin yellow line under
-- it; the heading's buttons (sort, fold, close and the rest) show only while
-- the mouse is on the panel. Icons, bars and cheers stay. A panel never
-- dragged lines up under the game's quest list, the goals panel under Kills
-- & Loot, closing up when one hides; a dragged panel keeps its spot.
--
-- The game's quest list is only read, inside a pcall: never moved, hidden,
-- hooked or changed. Saved account wide as `panelStyle` ("boxed" or
-- "quest", nil reads as boxed), never rename it.
--------------------------------------------------------------------------------

local _, ns = ...

local PanelStyle = ns.NewModule("PanelStyle")

local Theme = ns.Theme

PanelStyle.STYLES = { "boxed", "quest" }
--- The game's yellow for headings (its NORMAL_FONT_COLOR).
PanelStyle.YELLOW = { 1, 0.82, 0 }
--- How strong the line under the heading is.
PanelStyle.LINE_ALPHA = 0.55
--- How often the mouse is looked for while the buttons wait to show.
PanelStyle.LOOK = 0.1
--- How often the quest list's bottom is read, to follow it as it grows.
PanelStyle.FOLLOW = 1
--- Space under the quest list.
PanelStyle.GAP = 10
--- The game's quest list, newest first. Read only.
PanelStyle.QUEST_LIST = { "ObjectiveTrackerFrame", "QuestWatchFrame", "WatchFrame" }
--- The panels this style covers, by their see-through id.
PanelStyle.COVERS = { goals = true }

-- Each panel handed over: { frame, chrome, title, line, buttons, refresh,
-- hidden, watch, haloRest }.
PanelStyle.panels = PanelStyle.panels or {}

--- The style's names as a player reads them, by index into STYLES.
function PanelStyle.Names()
    local L = ns.L
    return { L["Boxed"], L["Like Quest List"] }
end

function PanelStyle:Style()
    local style = ns.db and ns.db.panelStyle
    if style == "quest" then return "quest" end
    return "boxed"
end

function PanelStyle:IsQuest()
    return self:Style() == "quest"
end

--- The style as an index into STYLES, for the Settings drop-down.
function PanelStyle:Index()
    return self:IsQuest() and 2 or 1
end

--- Whether a see-through panel (UI/SeeThrough.lua) is bare right now.
function PanelStyle:Covers(id)
    return PanelStyle.COVERS[id] == true and self:IsQuest()
end

--------------------------------------------------------------------------------
-- The look
--------------------------------------------------------------------------------

--- Every texture in `frame` right now: its box, taken before the words and
--- buttons go on it.
function PanelStyle.Chrome(frame, into)
    into = into or {}
    if type(frame) ~= "table" or type(frame.GetRegions) ~= "function" then return into end
    local regions = { pcall(frame.GetRegions, frame) }
    for i = 2, #regions do
        local region = regions[i]
        local ok, kind = pcall(function() return region:GetObjectType() end)
        if ok and kind == "Texture" then into[#into + 1] = region end
    end
    return into
end

--- Add a list of textures (a Theme.Border's edges) to `into`.
function PanelStyle.Add(into, list)
    if type(list) ~= "table" then return into end
    for _, texture in ipairs(list) do into[#into + 1] = texture end
    return into
end

local function MouseOn(frame)
    if not frame or type(frame.IsMouseOver) ~= "function" then return false end
    local ok, over = pcall(frame.IsMouseOver, frame)
    return ok and over == true
end

local function SetButtons(panel, shown)
    panel.buttonsShown = shown
    local list = panel.buttons and panel.buttons() or {}
    for _, button in ipairs(list) do
        if button then pcall(button.SetAlpha, button, shown and 1 or 0) end
    end
end

--- Hand a panel over once it is built. `spec`: frame, chrome (textures of
--- its box), title (the heading), lineAnchor and lineRight (where the thin
--- line goes), buttons (a function giving the frames shown on hover) and
--- refresh(on) (the panel puts its glass, shadows and cards in step).
function PanelStyle:Register(id, spec)
    spec.hidden = {}
    local parent = spec.lineParent or spec.frame
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    local y = PanelStyle.YELLOW
    line:SetColorTexture(y[1], y[2], y[3], PanelStyle.LINE_ALPHA)
    line:SetPoint("TOPLEFT", spec.title, "BOTTOMLEFT", 0, -3)
    line:SetPoint("RIGHT", parent, "RIGHT", -(spec.lineRight or 8), 0)
    line:Hide()
    spec.line = line
    spec.watch = CreateFrame("Frame", nil, spec.frame)
    spec.watch.wait = 0
    self.panels[id] = spec
    self:Apply(id)
end

--- Put one panel in step with the style.
function PanelStyle:Apply(id)
    local panel = self.panels[id]
    if not panel then return end
    local on = self:IsQuest()
    local frame = panel.frame

    -- The box: hidden, and only what was showing comes back.
    for _, texture in ipairs(panel.chrome or {}) do
        if on then
            local ok, shown = pcall(texture.IsShown, texture)
            if ok and shown then
                panel.hidden[texture] = true
                pcall(texture.Hide, texture)
            end
        elseif panel.hidden[texture] then
            panel.hidden[texture] = nil
            pcall(texture.Show, texture)
        end
    end

    -- The glow round the edge: with no rest, nothing flares it.
    if on then
        if frame.haloRest then panel.haloRest = frame.haloRest end
        -- False, not nil: every flare asks for it first and stops.
        frame.haloRest = false
        if ns.Motion then pcall(ns.Motion.Stop, ns.Motion, frame, "halo") end
        Theme.SetHalo(frame, 0)
    elseif panel.haloRest then
        frame.haloRest = panel.haloRest
        Theme.SetHalo(frame, panel.haloRest)
    end

    -- The heading in the game's yellow, the thin line under it.
    if panel.title then
        if on then
            local y = PanelStyle.YELLOW
            panel.title:SetTextColor(y[1], y[2], y[3])
        else
            panel.title:SetTextColor(Theme.Unpack(panel.titleColor or "accent"))
        end
    end
    panel.line:SetShown(on)

    -- The buttons show while the mouse is on the panel.
    if on then
        SetButtons(panel, MouseOn(frame))
        panel.watch:SetScript("OnUpdate", function(watch, elapsed)
            watch.wait = watch.wait - (tonumber(elapsed) or 0)
            if watch.wait > 0 then return end
            watch.wait = PanelStyle.LOOK
            local over = MouseOn(frame)
            if over ~= panel.buttonsShown then SetButtons(panel, over) end
        end)
    else
        panel.watch:SetScript("OnUpdate", nil)
        SetButtons(panel, true)
    end

    if panel.refresh then pcall(panel.refresh, on) end
end

--- Pick a style: "boxed" or "quest", or an index into STYLES.
function PanelStyle:Set(style)
    if type(style) == "number" then style = PanelStyle.STYLES[style] end
    if style ~= "boxed" and style ~= "quest" then return false end
    if not ns.db then return false end
    ns.db.panelStyle = style
    for id in pairs(self.panels) do self:Apply(id) end
    self:Follow()
    self:PlacePanels()
    return true
end

--------------------------------------------------------------------------------
-- Under the game's quest list
--------------------------------------------------------------------------------

-- The lowest bottom of the frames showing inside `frame`, a few levels
-- down: the last line the quest list draws. A frame with nothing showing
-- inside counts by its own bottom.
local function LowestShowing(frame, depth)
    local children = { frame:GetChildren() }
    local low
    if depth > 0 then
        for _, child in ipairs(children) do
            if child:IsVisible() and (tonumber(child:GetHeight()) or 0) > 1 then
                local bottom = LowestShowing(child, depth - 1)
                if type(bottom) == "number" and (not low or bottom < low) then low = bottom end
            end
        end
    end
    if low then return low end
    local bottom = frame:GetBottom()
    if type(bottom) == "number" then return bottom end
end

--- The quest list's right edge and the bottom of what it shows, in screen
--- pixels, or nil when the client will not say. While it shows nothing,
--- its top, where its first line would be.
function PanelStyle.QuestListEdge()
    for _, name in ipairs(PanelStyle.QUEST_LIST) do
        local list = rawget(_G, name)
        if type(list) == "table" then
            local ok, right, bottom = pcall(function()
                local scale = list:GetEffectiveScale()
                local r, t = list:GetRight(), list:GetTop()
                -- Compared here, inside the pcall: a secret value raises on it.
                if not (type(scale) == "number" and scale > 0
                    and type(r) == "number" and type(t) == "number") then return end
                local low
                if list:IsVisible() then low = LowestShowing(list, 3) end
                if type(low) ~= "number" or low > t then low = t end
                return r * scale, low * scale
            end)
            if ok and type(right) == "number" and type(bottom) == "number" then
                return right, bottom
            end
        end
    end
end

--- Put `frame` under the quest list, its right edge on the list's. True
--- when placed; false (the panel's own first spot then) when the style is
--- boxed or the client will not say where the list is.
function PanelStyle:PlaceUnderQuestList(frame)
    if not frame or not self:IsQuest() then return false end
    local right, bottom = PanelStyle.QuestListEdge()
    if not right then return false end
    local ok = pcall(function()
        local own = frame:GetEffectiveScale()
        if type(own) ~= "number" or own <= 0 then own = 1 end
        frame:ClearAllPoints()
        frame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right / own, bottom / own - PanelStyle.GAP)
    end)
    if ok then self.lastRight, self.lastBottom = right, bottom end
    return ok
end

--- Place the two panels again, each by its own rules.
function PanelStyle:PlacePanels()
    local tracker = ns.TrackerUI
    if tracker and tracker.frame and tracker.Place then pcall(tracker.Place, tracker) end
    -- Never pulled out from under a drag (Kills & Loot's Place asks too).
    local goals = ns.GoalsUI
    if goals and goals.frame and goals.Place and not goals.dragging then pcall(goals.Place, goals) end
end

--- Whether Kills & Loot or the goals panel is on screen.
function PanelStyle.AnyShown()
    for _, module in ipairs({ ns.TrackerUI, ns.GoalsUI }) do
        local frame = module and module.frame
        if frame and frame.IsShown and frame:IsShown() then return true end
    end
    return false
end

--- While the style is on, read where the quest list ends once a second and
--- place the panels again only when it moved (a quest watched or done).
function PanelStyle:Follow()
    if not self.follower then
        self.follower = CreateFrame("Frame", nil, UIParent)
        self.follower.wait = 0
    end
    local follower = self.follower
    if not self:IsQuest() then
        follower:SetScript("OnUpdate", nil)
        return
    end
    follower:SetScript("OnUpdate", function(watch, elapsed)
        watch.wait = watch.wait - (tonumber(elapsed) or 0)
        if watch.wait > 0 then return end
        watch.wait = PanelStyle.FOLLOW
        if not PanelStyle.AnyShown() then return end
        local right, bottom = PanelStyle.QuestListEdge()
        if not right then return end
        if PanelStyle.lastRight and math.abs(right - PanelStyle.lastRight) < 0.5
            and math.abs(bottom - PanelStyle.lastBottom) < 0.5 then
            return
        end
        PanelStyle.lastRight, PanelStyle.lastBottom = right, bottom
        PanelStyle:PlacePanels()
    end)
end

function PanelStyle:OnEnable()
    self:Follow()
end
