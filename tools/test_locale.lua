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
local ns = env.Load({ ui = true })
local L = ns.L
suite.check("English shows English", L["Hide skinning"] == "Hide skinning")
suite.check("and formats as before", L.Format("Hide %s", "Kobold") == "Hide Kobold")
ns.UI:Show()
suite.check("the search window in English", ns.UI.emptyLine:GetText() == "What are you farming?",
    ns.UI.emptyLine:GetText())
local labels = SettingsLabels(ns)
suite.check("the settings rows in English", labels["Hide skinning"] == true)
suite.check("a creature type shows in English", ns.Grinding.TypeLabel("Beast") == "Beast")

-- A German client.
ns = env.Load({ ui = true, locale = "deDE" })
L = ns.L
ns.UI:Show()
suite.check("the search window speaks Deutsch", ns.UI.emptyLine:GetText() == "Was farmst du?",
    ns.UI.emptyLine:GetText())
labels = SettingsLabels(ns)
suite.check("the settings rows speak Deutsch", labels["Kürschnerei ausblenden"] == true)
suite.check("and none is left in English", labels["Hide skinning"] == nil)
suite.check("the hide menu's line", L.Format("Hide %s", "Kobold") == "Kobold ausblenden")
suite.check("a creature type shows in Deutsch, kept in English",
    ns.Grinding.TypeLabel("Beast") == "Wildtier" and ns.Grinding.EnglishType("Beast") == "Beast",
    ns.Grinding.TypeLabel("Beast"))
suite.check("a word with no German line falls back to English",
    L["A string nobody translated"] == "A string nobody translated")
suite.check("and formats in English", L.Format("%d kobolds, %s", 3, "grey") == "3 kobolds, grey")
suite.check("values named by place go where German puts them",
    L.Format("unlocked drop rates for %s after %d kills! (Blackthornes Farmer)", "Kobold", 50)
        == "hat nach 50 Kills die Dropchancen für Kobold freigeschaltet! (Blackthornes Farmer)")
suite.check("a %% stays a percent sign", L.Format("%d%%", 25) == "25%")

-- Another language that has no file shows English.
ns = env.Load({ locale = "frFR" })
suite.check("a client in a language with no file shows English", ns.L["Hide skinning"] == "Hide skinning")

_G.GetLocale = nil
suite.done()
