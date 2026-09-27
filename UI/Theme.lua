-- Blackthornes Farmer -- UI/Theme.lua
-- Palette and panel construction.
--
-- The same palette as Blackthornes Tradeskills on purpose: the two addons are
-- worn together and should read as one set. Everything is built from plain
-- textures rather than Blizzard backdrops, which keeps the look consistent and
-- avoids depending on BackdropTemplate being present on this client.

local _, ns = ...

local Theme = {}
ns.Theme = Theme

Theme.colors = {
    window    = { 0.055, 0.063, 0.078 },   -- #0E1014 outermost shell
    panel     = { 0.086, 0.094, 0.114 },   -- #16181D
    header    = { 0.110, 0.122, 0.145 },
    row       = { 0.133, 0.145, 0.172 },   -- #22252C
    rowAlt    = { 0.106, 0.118, 0.141 },
    rowHover  = { 0.180, 0.200, 0.239 },
    rowActive = { 0.220, 0.190, 0.110 },   -- a gold-tinted row, as in Tradeskills

    border    = { 0.204, 0.224, 0.263 },
    borderLit = { 0.302, 0.333, 0.388 },

    accent    = { 0.784, 0.643, 0.302 },   -- #C8A44D
    good      = { 0.310, 0.820, 0.545 },   -- #4FD18B
    warn      = { 0.910, 0.757, 0.353 },
    loss      = { 0.898, 0.376, 0.310 },   -- #E5604F, a close button under the mouse

    text      = { 0.902, 0.910, 0.925 },   -- #E6E8EC
    muted     = { 0.478, 0.502, 0.541 },   -- #7A8089
    dim       = { 0.330, 0.350, 0.390 },
}

local FONT do
    local ok, path = pcall(function() return (GameFontNormal:GetFont()) end)
    FONT = (ok and path) or [[Fonts\FRIZQT__.TTF]]
end

Theme.FONT = FONT

Theme.sizes = {
    tiny = 10,
    small = 11,
    normal = 12,
    large = 14,
    title = 16,
}

function Theme.Unpack(key, alpha)
    local color = Theme.colors[key] or Theme.colors.text
    return color[1], color[2], color[3], alpha or 1
end

--- Flat filled texture covering a frame.
function Theme.Fill(frame, key, alpha, layer)
    local texture = frame:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetAllPoints(frame)
    texture:SetColorTexture(Theme.Unpack(key, alpha))
    return texture
end

--- One-pixel border drawn as four edge textures, so it stays crisp at any size.
function Theme.Border(frame, key, alpha)
    local r, g, b, a = Theme.Unpack(key or "border", alpha)
    local edges = {}

    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = frame:CreateTexture(nil, "BORDER")
        edge:SetColorTexture(r, g, b, a)

        if side == "TOP" then
            edge:SetPoint("TOPLEFT")
            edge:SetPoint("TOPRIGHT")
            edge:SetHeight(1)
        elseif side == "BOTTOM" then
            edge:SetPoint("BOTTOMLEFT")
            edge:SetPoint("BOTTOMRIGHT")
            edge:SetHeight(1)
        elseif side == "LEFT" then
            edge:SetPoint("TOPLEFT")
            edge:SetPoint("BOTTOMLEFT")
            edge:SetWidth(1)
        else
            edge:SetPoint("TOPRIGHT")
            edge:SetPoint("BOTTOMRIGHT")
            edge:SetWidth(1)
        end

        edges[#edges + 1] = edge
    end

    frame.borderTextures = edges
    return edges
end

--- Recolour a border drawn by Theme.Border.
function Theme.SetBorderColor(frame, key, alpha)
    if not frame.borderTextures then return end

    local r, g, b, a = Theme.Unpack(key, alpha)
    for _, edge in ipairs(frame.borderTextures) do
        edge:SetColorTexture(r, g, b, a)
    end
end

--- A panel: filled background plus a border.
function Theme.CreatePanel(parent, backgroundKey, borderKey)
    local panel = CreateFrame("Frame", nil, parent)
    panel.background = Theme.Fill(panel, backgroundKey or "panel")

    if borderKey ~= false then
        Theme.Border(panel, borderKey or "border")
    end

    return panel
end

--- A text label.
function Theme.CreateLabel(parent, size, colorKey, justify)
    local label = parent:CreateFontString(nil, "OVERLAY")
    label:SetFont(FONT, Theme.sizes[size] or size or Theme.sizes.normal, "")
    label:SetTextColor(Theme.Unpack(colorKey or "text"))
    label:SetJustifyH(justify or "LEFT")
    label:SetWordWrap(false)
    return label
end

-- One unanchored, unbounded label per size, for measuring text: a label
-- anchored at both ends reports the width it was given, not the width its
-- text wants.
local measures = {}

--- How wide `text` is in pixels at a label size, as the game draws it.
--
-- The game's font runs wider than any fixed width we could guess, which is
-- how "Loot a corpse and it shows up he..." happened. Measure instead.
function Theme.TextWidth(size, text)
    if type(text) ~= "string" or text == "" then return 0 end

    local label = measures[size]
    if not label then
        label = Theme.CreateLabel(UIParent, size, "text")
        label:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 0, -200)
        label:SetAlpha(0)
        measures[size] = label
    end

    label:SetText(text)

    -- The unbounded width where the client has it, else the plain one.
    local width
    for _, method in ipairs({ "GetUnboundedStringWidth", "GetStringWidth" }) do
        if not width and type(label[method]) == "function" then
            local ok, value = pcall(label[method], label)
            width = ok and tonumber(value) or nil
        end
    end

    return math.ceil(width or 0)
end

function Theme.CreateDivider(parent, key)
    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(Theme.Unpack(key or "border"))
    divider:SetHeight(1)
    return divider
end

--------------------------------------------------------------------------------
-- House trim, shared with Blackthornes Tradeskills
--
-- The same few touches Tradeskills' Theme.lua draws, so the two windows read as
-- one set: a gold stripe down the left of a header, a faint sheen along the
-- top of a raised surface, and item icons trimmed the way the bags draw them.
--------------------------------------------------------------------------------

--- A gold stripe down the left edge of a header or band.
function Theme.AccentStripe(frame, width, alpha)
    local stripe = frame:CreateTexture(nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT")
    stripe:SetPoint("BOTTOMLEFT")
    stripe:SetWidth(width or 3)
    stripe:SetColorTexture(Theme.Unpack("accent", alpha))
    return stripe
end

--- A faint lighter line along the top edge, so a flat fill reads as a raised
--- surface rather than a hole.
function Theme.TopSheen(frame, alpha)
    local sheen = frame:CreateTexture(nil, "BORDER")
    sheen:SetPoint("TOPLEFT", 1, -1)
    sheen:SetPoint("TOPRIGHT", -1, -1)
    sheen:SetHeight(1)
    sheen:SetColorTexture(1, 1, 1, alpha or 0.05)
    return sheen
end

--- A soft gold glow fading down from the top of a header, drawn as a
--- gradient where the client has one and left out where it does not.
function Theme.HeaderGlow(frame, height, alpha)
    local glow = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    glow:SetPoint("TOPLEFT")
    glow:SetPoint("TOPRIGHT")
    glow:SetHeight(height or 18)
    glow:SetColorTexture(1, 1, 1, 1)

    local r, g, b = Theme.Unpack("accent")
    local top, bottom = alpha or 0.10, 0

    local ok = false
    if type(CreateColor) == "function" and type(glow.SetGradient) == "function" then
        ok = pcall(glow.SetGradient, glow, "VERTICAL",
            CreateColor(r, g, b, bottom), CreateColor(r, g, b, top))
    end

    if not ok then glow:Hide() end
    return glow
end

local FALLBACK_ICON = [[Interface\Icons\INV_Misc_QuestionMark]]

--- An item's icon texture, or nil while the game has not sent it. Read in a
--- pcall: this is the client, and inside an instance it can hand back a
--- value that raises when touched.
function Theme.ItemIcon(itemID)
    if not itemID then return nil end

    local icon
    if type(C_Item) == "table" and type(C_Item.GetItemIconByID) == "function" then
        local ok, value = pcall(C_Item.GetItemIconByID, itemID)
        if ok then icon = value end
    end
    if not icon and type(GetItemIcon) == "function" then
        local ok, value = pcall(GetItemIcon, itemID)
        if ok then icon = value end
    end

    local readable = ns.Harvest and (ns.Harvest.ReadableNumber(icon) or ns.Harvest.Readable(icon))
    return readable or nil
end

--- A square item icon, trimmed of its built-in border.
function Theme.CreateItemIcon(parent, size)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size or 16, size or 16)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:Hide()
    return icon
end

--- Show an item's icon, or the question mark while the game has not sent it.
--- Hidden when there is no item at all.
function Theme.SetItemIcon(icon, itemID)
    if not icon then return end

    if not itemID then
        icon:Hide()
        return
    end

    icon:SetTexture(Theme.ItemIcon(itemID) or FALLBACK_ICON)
    icon:Show()
end
