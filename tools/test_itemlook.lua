-- Tests for the quality ring and the corner count (UI/ItemLook.lua) and the
-- coin columns (UI/Coins.lua): the ring takes the quality's colour and
-- follows the icon, plain grey and white are softer, the count shows only
-- for more than one, and money splits into gold, silver and copper columns.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("itemlook")

local ns = env.Load({ ui = true })
local Look, Coins = ns.ItemLook, ns.Coins
suite.check("both files load", Look ~= nil and Coins ~= nil)

local function Icon()
    local parent = env.Stub()
    local made = {}
    function parent:CreateTexture()
        local t = env.Stub()
        function t:SetColorTexture(r, g, b, a) self._fill = { r, g, b, a } end
        made[#made + 1] = t
        return t
    end
    local icon = env.Stub({ _parent = parent })
    return icon, made
end

-- 1. The ring.
do
    local icon = Icon()
    Look.Attach(icon)
    local ring = Look.RingOf(icon)
    suite.check("an icon gets a ring", ring ~= nil)
    suite.check("hidden until it has a quality", not ring:IsShown())
    icon:Show()
    Look.SetQuality(icon, 3)
    suite.check("shown for a blue", ring:IsShown() and Look.QualityShown(icon) == 3)
    local r, g, b = Look.Color(3)
    suite.check("in the blue colour", ring._fill[1] == r and ring._fill[2] == g and ring._fill[3] == b)
    suite.check("at full strength", ring._fill[4] == Look.ALPHA)
    icon:Hide()
    suite.check("hidden with the icon", not ring:IsShown())
    icon:SetShown(true)
    suite.check("back with the icon", ring:IsShown())
    Look.SetQuality(icon, 1)
    suite.check("white is softer", ring._fill[4] == Look.PLAIN_ALPHA)
    Look.SetQuality(icon, 0)
    suite.check("grey is softer", ring._fill[4] == Look.PLAIN_ALPHA)
    Look.SetQuality(icon, nil)
    suite.check("nil takes it away", not ring:IsShown() and Look.QualityShown(icon) == nil)
    suite.check("Attach twice keeps one ring", Look.Attach(icon) ~= nil and Look.RingOf(icon) == ring)
end

-- 2. Quality by item.
do
    _G.C_Item = { GetItemQualityByID = function(id) return id == 2589 and 1 or nil end }
    suite.check("quality from the client", Look.QualityOf(2589) == 1)
    suite.check("nil while not loaded", Look.QualityOf(9999) == nil)
    local icon = Icon()
    icon:Show()
    suite.check("SetItem takes the caller's quality", Look.SetItem(icon, 9999, 4) == 4)
    suite.check("a quality with no colour is no ring", (function()
        Look.SetQuality(icon, 42); return Look.QualityShown(icon) == nil end)())
end

-- 3. The corner count.
do
    local icon = Icon()
    icon:Show()
    Look.SetCount(icon, 1)
    suite.check("one shows no count", Look.CountShown(icon) == nil)
    Look.SetCount(icon, 20)
    local text = Look.CountOf(icon)
    suite.check("20 shows", Look.CountShown(icon) == 20 and text and text:GetText() == "20")
    suite.check("in the corner", text and text._point and text._point[1] == "BOTTOMRIGHT")
    suite.check("and is shown", text:IsShown())
    icon:Hide()
    suite.check("hidden with the icon", not text:IsShown())
    icon:Show()
    Look.SetCount(icon, nil)
    suite.check("nil takes it away", not text:IsShown() and Look.CountShown(icon) == nil)
end

-- 4. Coins.
do
    local g, s, c = Coins.Split(12345)
    suite.check("split", g == 1 and s == 23 and c == 45)
    local parts = Coins.Parts(400)
    suite.check("4s leaves gold and copper out", parts.silver == 4 and not parts.gold and not parts.copper)
    suite.check("0 shows as 0 copper", Coins.Parts(0).copper == 0)
    suite.check("nil is no amount", Coins.Parts(nil) == nil and Coins.Text(nil) == "")
    local parent = env.Stub()
    local coins = Coins.Create(parent)
    suite.check("three columns", coins.gold and coins.silver and coins.copper)
    suite.check("shown for 1s 60c", Coins.Set(coins, 160) and coins.silver:IsShown()
        and coins.copper:IsShown() and not coins.gold:IsShown())
    suite.check("white numbers", coins.silver._color[1] == 1 and coins.silver._color[3] == 1)
    suite.check("each a coin of its own", coins.silver:GetText():find("UI%-SilverIcon") ~= nil
        and coins.copper:GetText():find("^60") ~= nil)
    suite.check("nil hides them", not Coins.Set(coins, nil) and not coins.copper:IsShown()
        and not Coins.Shown(coins))
    suite.check("has a width", Coins.Width(coins) > 0)
end

suite.done()
