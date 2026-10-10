-- The Blizzard window style (asked 2026-10-10), outside WoW. Adapted from
-- Tradeskills' test of the same file.
--
-- What must hold:
--   1. Titanforged stays the default: with nothing saved, or before the
--      saved settings are in, windows wear the house frame.
--   2. Picked, the palette is the game's, windows get the silver rim, a
--      title, the portrait and the game's close button, which closes.
--   3. Buttons wear the game's red, down while held, with a gold label even
--      on the main action; one with a face of its own keeps it.
--   4. Tick boxes, hanging tabs and scroll thumbs wear the game's art.
--   5. A client without a piece of art keeps that widget in the house look.
--   6. The choice is read once: changing it waits for /reload.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("blizzardlook")

local ns

-- Art the pretend client lacks.
local missing = {}

-- Tests share one Lua state, so the globals replaced here are put back.
local saved = { CreateFrame = CreateFrame, UIParent = UIParent, CreateColor = CreateColor,
    GameTooltip = GameTooltip }

local function Region(parent)
    local region = { shown = true, parent = parent, scripts = {}, points = {}, alpha = 1,
        width = 0, height = 0, events = {}, children = {} }

    region.Show = function(self)
        local was = self.shown
        self.shown = true
        if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    region.Hide = function(self)
        local was = self.shown
        self.shown = false
        if was and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    region.SetShown = function(self, on) if on then self:Show() else self:Hide() end end
    region.IsShown = function(self) return self.shown end
    region.IsVisible = function(self) return self.shown end
    region.SetAlpha = function(self, a) self.alpha = a end
    region.GetAlpha = function(self) return self.alpha end
    region.SetWidth = function(self, w) self.width = w end
    region.SetHeight = function(self, h) self.height = h end
    region.GetWidth = function(self) return self.width end
    region.GetHeight = function(self) return self.height end
    region.SetSize = function(self, w, h) self.width, self.height = w, h end
    region.SetColorTexture = function(self, r, g, b, a) self.color = { r, g, b, a or 1 } end
    region.SetGradient = function(self, orientation, from, to)
        self.gradient = { orientation, from, to }
    end
    region.SetTextColor = function(self, r, g, b, a) self.textColor = { r, g, b, a } end
    region.SetText = function(self, text) self.text = text end
    region.GetText = function(self) return self.text end
    region.GetStringWidth = function(self) return #(self.text or "") * 6 end
    region.SetScript = function(self, name, fn) self.scripts[name] = fn end
    region.GetScript = function(self, name) return self.scripts[name] end
    region.HookScript = function(self, name, fn)
        local old = self.scripts[name]
        self.scripts[name] = function(...)
            if old then old(...) end
            fn(...)
        end
    end

    -- As the game does: the short forms fill in the parent and the same
    -- point, and setting a point the region already has moves that one.
    region.SetPoint = function(self, point, a, b, c, d)
        local relativeTo, relativePoint, x, y
        if a == nil or type(a) == "number" then
            relativeTo, relativePoint, x, y = self.parent, point, a or 0, b or 0
        elseif type(b) == "string" then
            relativeTo, relativePoint, x, y = a, b, c or 0, d or 0
        else
            relativeTo, relativePoint, x, y = a, point, b or 0, c or 0
        end

        local anchor = { point, relativeTo, relativePoint, x, y }
        for index, existing in ipairs(self.points) do
            if existing[1] == point then
                self.points[index] = anchor
                return
            end
        end
        self.points[#self.points + 1] = anchor
    end
    region.ClearAllPoints = function(self) self.points = {} end
    region.GetNumPoints = function(self) return #self.points end
    region.GetPoint = function(self, index)
        local p = self.points[index or 1]
        if not p then return nil end
        return p[1], p[2], p[3], p[4], p[5]
    end
    region.IsMouseOver = function(self) return self.mouseOver == true end
    region.RegisterEvent = function(self, event) self.events[event] = true end
    region.UnregisterEvent = function(self, event) self.events[event] = nil end
    region.regions = {}
    region.CreateTexture = function(self)
        local texture = Region(self)
        self.regions[#self.regions + 1] = texture
        return texture
    end
    region.GetRegions = function(self) return unpack(self.regions) end
    region.GetTextureFileID = function(self)
        if self.texture == nil or missing[self.texture] then return nil end
        return 1
    end
    region.SetVertexColor = function(self, r, g, b, a) self.vertex = { r, g, b, a } end
    region.SetDesaturated = function(self, on) self.desaturated = on end
    region.CreateFontString = function(self) return Region(self) end
    region.GetParent = function(self) return self.parent end
    region.GetMinMaxValues = function(self) return self.min or 0, self.max or 0 end
    region.SetMinMaxValues = function(self, lo, hi) self.min, self.max = lo, hi end
    region.GetValue = function(self) return self.value or 0 end
    region.SetValue = function(self, v) self.value = v end
    region.SetTexture = function(self, path) self.texture = path end
    region.SetTexCoord = function(self, ...) self.coords = { ... } end
    region.SetRotation = function(self, radians) self.rotation = radians end
    region.SetBlendMode = function(self, mode) self.blend = mode end
    region.SetFrameLevel = function(self, level) self.level = level end
    region.GetFrameLevel = function(self) return self.level or 1 end

    -- Any other method does nothing. Fields read as nil, as on a real frame,
    -- so a button no one disabled is not taken for a disabled one.
    return setmetatable(region, { __index = function(_, key)
        if type(key) == "string" and key:match("^%u") then return function() end end
    end })
end

-- Frames remember their children, so a test can find the ones a widget keeps
-- to itself (a menu's entries).
local templates = {}
CreateFrame = function(_, _, parent, template)
    local frame = Region(parent)
    frame.template = template
    templates[#templates + 1] = template
    if type(parent) == "table" and rawget(parent, "children") then
        parent.children[#parent.children + 1] = frame
    end
    return frame
end
UIParent = Region()
CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
GameTooltip = Region()

--- A fresh load of the four files. Farmer keeps its settings flat in
--- ns.db, which arrives after the files load, as at ADDON_LOADED.
local function Fresh()
    ns = {}
    ns.TrackerFX = { Level = function() return "full" end }
    for _, path in ipairs({ "/UI/Theme.lua", "/UI/BlizzardLook.lua", "/UI/Widgets.lua", "/UI/Titanforged.lua" }) do
        local chunk = assert(loadfile(lfs_cwd .. path))
        chunk("Blackthornes_Farmer", ns)
    end
    return ns
end

local function check(label, got, want)
    suite.check(label, got == want, tostring(got))
end

local function Dress()
    local window = Region()
    window:SetSize(660, 458)
    local closed = { done = false }
    local trim = ns.Titanforged:Dress(window, {
        title = "Blackthornes Farmer", portrait = true,
        close = function() closed.done = true end,
    })
    return window, trim, closed
end

-- The default.

Fresh()
check("before the saved settings are in: Titanforged", ns.BlizzardLook.Style(), "titanforged")
ns.db = {}
check("nothing saved: Titanforged", ns.BlizzardLook.Style(), "titanforged")
local _, trim = Dress()
check("the house frame, corner gems and all", #trim.corners, 4)
check("not the Blizzard trim", trim.blizzard, nil)
check("the house gold kept", ns.Theme.colors.accent[1] < 0.9, true)
local houseLeft, _, houseTop = ns.Titanforged.Reach(trim)

-- Picked.

Fresh()
local houseGold = ns.Theme.colors.accent[3]
ns.db = { windowStyle = "blizzard" }
check("the Blizzard style is on", ns.BlizzardLook.On(), true)
check("the game's gold in the palette", ns.Theme.colors.accent[1] == 1 and ns.Theme.colors.accent[3] == 0, true)
check("which it was not before", houseGold > 0, true)

local window, btrim, closed = Dress()
check("the Blizzard trim", btrim.blizzard, true)
check("kept on the window", window.titan, btrim)
check("no corner gems", #btrim.corners, 0)
check("the name on the title", btrim.plate.label.text, "Blackthornes Farmer")
check("wide enough for it", btrim.plate.width >= #"Blackthornes Farmer" * 6 + 30, true)
check("a portrait in a silver ring", btrim.portrait ~= nil, true)
check("its emblem is Farmer's", btrim.portrait.regions[2].texture,
    [[Interface\AddOns\Blackthornes_Farmer\Media\Frame\Emblem]])
check("the game's close button", btrim.closeButton.template, "UIPanelCloseButton")
btrim.closeButton.scripts.OnClick(btrim.closeButton)
check("which closes the window", closed.done, true)
ns.Titanforged:Opened(window)
ns.Titanforged:StartGlint(window, 0)
check("no portrait light or glint to run", btrim.glint, nil)
local left, _, top = ns.Titanforged.Reach(btrim)
check("kept on screen like the house frame", left == houseLeft and top == houseTop, true)

-- Buttons.

local Widgets, ART = ns.Widgets, ns.BlizzardLook.ART
local button = Widgets.CreateButton(Region(), "Search", nil, { primary = true, width = 120 })
check("wears the game's red", button.blizzardFace ~= nil, true)
check("resting art", button.blizzardFace.pieces[2].texture, ART.button)
check("cut as the game cuts it", button.blizzardFace.pieces[1].coords[2], 0.09375)
check("the house face out of sight", button.background.alpha, 0)
check("its edges too", button.borderTextures[1].alpha, 0)
check("and its bevel", button.bevel[1].alpha == 0 and button.bevel[2].alpha == 0, true)
check("a gold label on the main action", button.label.textColor[3] == 0 and button.label.textColor[1] == 1, true)
button.scripts.OnEnter(button)
ns.Motion:FinishAll()
check("the house face stays out under the mouse", button.background.alpha, 0)
button.scripts.OnMouseDown(button)
check("down while held", button.blizzardFace.pieces[2].texture, ART.buttonDown)
button.scripts.OnMouseUp(button)
check("up again", button.blizzardFace.pieces[2].texture, ART.button)
button.scripts.OnMouseDown(button)
button:Hide()
check("let go when hidden mid-press", button.blizzardFace.pieces[2].texture, ART.button)
local overWorld = Widgets.CreateButton(Region(), "Loot", nil, { baseColor = { 0, 0, 0, 1 } })
check("a button over the game world keeps its face", overWorld.blizzardFace, nil)

-- Tick boxes, tabs and thumbs.

local box = Widgets.CreateCheckbox(Region(), "Show it", nil, false)
local stock, houseTick
for _, region in ipairs(box.box.regions) do
    if region.texture == ART.checkTick then stock = region end
    if region.color and region.texture == nil and region.width == 8 then houseTick = region end
end
check("the game's tick", stock ~= nil, true)
check("hidden while unticked", stock.shown, false)
box.scripts.OnClick(box)
ns.Motion:FinishAll()
check("shown when ticked", stock.shown, true)
check("the house tick out of sight", houseTick and houseTick.alpha, 0)
box:SetDisabled(true)
check("and kept out when disabled", houseTick.alpha, 0)
box:SetChecked(false)
check("unticked by code, the game's tick goes", stock.shown, false)

local strip = Widgets.CreateTabStrip(Region(), {
    { key = "a", text = "Search", width = 90 },
    { key = "b", text = "Goals", width = 90 },
}, nil, { hanging = true })
strip:Select("a")
check("the tab showing wears the active art", strip.tabs[1].blizzardFace.pieces[2].texture, ART.tabActive)
check("the others the resting art", strip.tabs[2].blizzardFace.pieces[2].texture, ART.tab)
check("its name white", strip.tabs[1].label.textColor[3], 1)
check("the others gold", strip.tabs[2].label.textColor[3], 0)
check("the house edges out of sight", strip.tabs[1].edges[1].alpha, 0)
check("no gliding gold line", strip.line.alpha, 0)
strip:Select("b")
check("picking another swaps them", strip.tabs[2].blizzardFace.pieces[2].texture, ART.tabActive)

local list = Widgets.CreateLineList(Region(), {})
local bar = list.scrollbar
local thumb = bar.thumb
check("the thumb is the game's knob", thumb.texture, ART.knob)
bar.scripts.OnEnter(bar)
ns.Motion:FinishAll()
check("lit by tint, still the knob", thumb.texture == ART.knob and thumb.vertex[3] < 1, true)
check("never painted over with a colour", thumb.color == nil or thumb.texture == ART.knob, true)
bar.scripts.OnLeave(bar)
ns.Motion:FinishAll()
check("and back to plain", thumb.vertex[3], 1)

-- A client without the art.

missing[ART.button] = true
Fresh()
ns.db = { windowStyle = "blizzard" }
local plain = ns.Widgets.CreateButton(Region(), "Max", nil, {})
check("the button keeps the house look", plain.blizzardFace, nil)
check("its face showing", plain.background.alpha, 1)
local lines = ns.BlizzardLook.ProbeLines()
check("the probe names what is missing", lines[2]:find("button", 1, true) ~= nil, true)
missing[ART.button] = nil

-- Changing it.

ns.db.windowStyle = "titanforged"
check("waits for /reload", ns.BlizzardLook.Style(), "blizzard")
check("the setting says what comes next", ns.BlizzardLook.Wanted(), "titanforged")
check("the probe says so", ns.BlizzardLook.ProbeLines()[1]:find("after /reload", 1, true) ~= nil, true)

ns.Motion:FinishAll()
for key, value in pairs(saved) do _G[key] = value end

suite.done()
