-- The translations: on a German client the windows and settings speak
-- Deutsch, on any other they speak English, and a word with no German line
-- falls back to its English key. L.Format puts values named by place
-- ("%2$s ... %1$d") in order, which the tests' Lua 5.1 cannot do itself.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("locale")

--- Every row label on every settings page, as one lookup.
local function SettingsLabels(ns)
    for _, module in ipairs(ns.moduleOrder) do
        if module.OnEnable then module:OnEnable() end
    end
    ns.SettingsUI:Show()
    local labels = {}
    for _, page in pairs(ns.SettingsUI.pages.pages) do
        for _, row in ipairs(page.rows or {}) do
            if row.labelText then labels[row.labelText] = true end
        end
    end
    return labels
end

-- English first.
local ns = env.Load()
local L = ns.L
suite.check("English shows English", L["Feed"] == "Feed")
suite.check("and formats as before", L.Format("Feed %s", "Bread") == "Feed Bread")
_G.UnitClass = function() return "Hunter", "HUNTER" end
ns.UI:Show()
suite.check("the pets window in English", ns.UI.subtitle:GetText() == "Hunter", ns.UI.subtitle:GetText())
suite.check("with no pet, in English", ns.UI.emptyLabel:GetText() == "No pet out.")
suite.check("the settings rows in English", SettingsLabels(ns)["Feed warning"] == true)

-- A German client.
ns = env.Load("deDE")
L = ns.L
_G.UnitClass = function() return "Jäger", "HUNTER" end
ns.UI:Show()
suite.check("the pets window speaks Deutsch", ns.UI.subtitle:GetText() == "Jäger", ns.UI.subtitle:GetText())
suite.check("with no pet out", ns.UI.emptyLabel:GetText() == "Kein Begleiter draußen.",
    ns.UI.emptyLabel:GetText())
local labels = SettingsLabels(ns)
suite.check("the settings rows speak Deutsch", labels["Futterwarnung"] == true)
suite.check("and none is left in English", labels["Feed warning"] == nil)
suite.check("the diet words", ns.PetFood.Label("Cheese") == "Käse")
suite.check("the key binding's name", _G["BINDING_NAME_" .. ns.FeedKey.BINDING]
    == "Begleiterpflege (rufen, wiederbeleben, füttern oder heilen)")
suite.check("a word with no German line falls back to English",
    L["A string nobody translated"] == "A string nobody translated")
suite.check("and formats in English", L.Format("%d wolves, %s", 3, "grey") == "3 wolves, grey")
suite.check("values named by place go where German puts them",
    L.Format("Only %d food left that %s will eat.", 4, "Eber") == "Für Eber ist nur noch 4 Futter übrig.",
    L.Format("Only %d food left that %s will eat.", 4, "Eber"))
suite.check("a %% stays a percent sign",
    L.Format("%s (%d%% damage)", "Glücklich", 25) == "Glücklich (25% Schaden)")
suite.check("yards are metres", L.Format("%d,%03d yd", 1, 250) == "1.250 m")

-- Another language that has no file shows English.
ns = env.Load("frFR")
suite.check("a client in a language with no file shows English", ns.L["Feed"] == "Feed")

_G.UnitClass, _G.GetLocale = nil, nil
suite.done()
