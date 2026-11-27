-- Blackthornes Farmer -- UI/RarePins.lua
-- Rare mobs and treasure chests on the world map (Logic/Rares.lua): a skull
-- in a gold ring at each spot a rare stands, a chest at each treasure, on
-- the map of their zone. Hover one for its level, what it can give and when
-- you last saw it; click it to point the arrow there.
--
-- "Rares on the Map:" and "Treasures on the Map:" in Settings (rarePins,
-- treasurePins) turn them on; both are off unless ticked. The world map's
-- gem (UI/MapToggle.lua) hides them with every other Farmer mark.
--
-- Drawn the way UI/GrindPins.lua draws its camps: plain frames on the map's
-- canvas, laid out again only when the map, its size or the log moved.

local _, ns = ...

local RarePins = ns.NewModule("RarePins")

local Theme = ns.Theme

local SIZE = 18
local STEP = 0.2
local ROUND = [[Interface\CharacterFrame\TempPortraitAlphaMask]]

--- The spots to draw on map `mapID`: { entry, spot } for each.
function RarePins.On(mapID)
    local out = {}
    local Rares = ns.Rares
    if not (Rares and mapID) then return out end
    for _, kind in ipairs({ "treasure", "rare" }) do
        if Rares.PinsOn(kind) then
            for _, entry in ipairs(Rares:Entries(kind)) do
                for _, spot in ipairs(entry.spots) do
                    if spot.map == mapID then out[#out + 1] = { entry = entry, spot = spot } end
                end
            end
        end
    end
    return out
end

local function ShowTooltip(pin)
    local entry = pin.entry
    if not (entry and GameTooltip and ns.RaresView) then return end
    pcall(GameTooltip.SetOwner, GameTooltip, pin, "ANCHOR_RIGHT")
    ns.RaresView.FillTooltip(GameTooltip, entry, pin.spot and pin.spot.zone)
    GameTooltip:Show()
end

local function CreatePin(parent)
    local pin = CreateFrame("Button", nil, parent)
    if ns.MapMarkers and ns.MapMarkers.Own then ns.MapMarkers.Own(pin) end
    pin:SetSize(SIZE, SIZE)

    local ring = pin:CreateTexture(nil, "BACKGROUND")
    ring:SetAllPoints(pin)
    ring:SetTexture(ROUND)
    ring:SetVertexColor(Theme.Unpack("accent"))

    local back = pin:CreateTexture(nil, "BORDER")
    back:SetPoint("TOPLEFT", 2, -2)
    back:SetPoint("BOTTOMRIGHT", -2, 2)
    back:SetTexture(ROUND)
    back:SetVertexColor(0.1, 0.08, 0.05)

    local icon = pin:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", -3, 3)
    pin.icon = icon
    if ns.MapMarkers and ns.MapMarkers.RoundIcon then ns.MapMarkers.RoundIcon(pin, icon) end

    pin:SetScript("OnEnter", ShowTooltip)
    pin:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    pin:SetScript("OnClick", function(self)
        if self.entry and ns.Rares then ns.Rares:ShowWay(self.entry, self.spot and self.spot.zone) end
    end)
    return pin
end

function RarePins:Draw()
    local view = ns.MapMarkers and ns.MapMarkers:WorldView()
    local pins = self.pins or {}
    self.pins = pins
    local Rares = ns.Rares
    local any = Rares and (Rares.PinsOn("rare") or Rares.PinsOn("treasure"))

    if not view or not any then
        if self.drawnKey ~= nil or not self.hiddenAll then
            for _, pin in ipairs(pins) do pin:Hide() end
            self.drawnKey = nil
            self.hiddenAll = true
        end
        return 0
    end
    self.hiddenAll = nil

    local key = ("%d:%s:%s:%s:%d"):format(view.mapID, view.scale, view.width, view.height, Rares.version)
    if key == self.drawnKey then return nil end
    self.drawnKey = key

    if self.parent ~= view.canvas then
        for _, pin in ipairs(pins) do pin:Hide() end
        pins = {}
        self.pins = pins
        self.parent = view.canvas
    end

    -- Over the gathered-node markers, under the Grind tab's camps.
    local level = ns.MapMarkers.BaseLevel(view.canvas) + 3
    local scale = 1 / view.scale
    local icons = ns.RaresView and ns.RaresView.ICONS or {}

    local used = 0
    for _, each in ipairs(RarePins.On(view.mapID)) do
        used = used + 1
        local pin = pins[used]
        if not pin then
            pin = CreatePin(view.canvas)
            pins[used] = pin
        end
        pin.entry, pin.spot = each.entry, each.spot
        pin.icon:SetTexture(icons[each.entry.kind])
        pin:SetScale(scale)
        pin:SetFrameLevel(level)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", view.canvas, "TOPLEFT",
            each.spot.x / 100 * view.width / scale, -each.spot.y / 100 * view.height / scale)
        pin:Show()
    end
    for index = used + 1, #pins do pins[index]:Hide() end

    return used
end

function RarePins:OnEnable()
    local driver = CreateFrame("Frame", nil, UIParent)
    driver.since = 0
    driver:SetScript("OnUpdate", function(selfDriver, elapsed)
        selfDriver.since = selfDriver.since + (elapsed or 0)
        if selfDriver.since < STEP then return end
        selfDriver.since = 0
        local ok, err = pcall(RarePins.Draw, RarePins)
        if not ok then ns.Debug("rare pins:", tostring(err)) end
    end)
    driver:Show()
    self.driver = driver
end
