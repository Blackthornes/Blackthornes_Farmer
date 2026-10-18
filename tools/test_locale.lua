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
suite.check("the search window in English", ns.UI.emptyLine:GetText() == "Search for something to farm",
    ns.UI.emptyLine:GetText())
local labels = SettingsLabels(ns)
suite.check("the settings rows in English", labels["Hide Skinning:"] == true)
suite.check("a creature type shows in English", ns.Grinding.TypeLabel("Beast") == "Beast")

-- A German client.
ns = env.Load({ ui = true, locale = "deDE" })
L = ns.L
ns.UI:Show()
suite.check("the search window speaks Deutsch", ns.UI.emptyLine:GetText() == "Such etwas zum Farmen",
    ns.UI.emptyLine:GetText())
labels = SettingsLabels(ns)
suite.check("the settings rows speak Deutsch", labels["Kürschnerei ausblenden:"] == true)
suite.check("and none is left in English", labels["Hide Skinning:"] == nil)
suite.check("the hide menu's line", L.Format("Hide %s", "Kobold") == "Kobold ausblenden")
suite.check("a creature type shows in Deutsch, kept in English",
    ns.Grinding.TypeLabel("Beast") == "Wildtier" and ns.Grinding.EnglishType("Beast") == "Beast",
    ns.Grinding.TypeLabel("Beast"))
suite.check("a word with no German line falls back to English",
    L["A string nobody translated"] == "A string nobody translated")
suite.check("and formats in English", L.Format("%d kobolds, %s", 3, "grey") == "3 kobolds, grey")
-- A line of the test's own, since no shipped one needs the order turned yet.
L["%s after %d kills"] = "nach %2$d Kills: %1$s"
suite.check("values named by place go where German puts them",
    L.Format("%s after %d kills", "Kobold", 50) == "nach 50 Kills: Kobold")
suite.check("a %% stays a percent sign", L.Format("%d%%", 25) == "25%")

-- A Simplified Chinese client.
ns = env.Load({ ui = true, locale = "zhCN" })
L = ns.L
ns.UI:Show()
suite.check("the search window speaks Simplified Chinese", ns.UI.emptyLine:GetText() == "搜索要刷的东西",
    ns.UI.emptyLine:GetText())
labels = SettingsLabels(ns)
suite.check("the settings rows speak Simplified Chinese", labels["隐藏剥皮："] == true)
suite.check("and none is left in English (Simplified Chinese)", labels["Hide Skinning:"] == nil)
suite.check("the hide menu's line (Simplified Chinese)", L.Format("Hide %s", "Kobold") == "隐藏 Kobold")
suite.check("a creature type is kept in English (Simplified Chinese)", ns.Grinding.EnglishType("Beast") == "Beast")
suite.check("a word with no Simplified Chinese line falls back to English",
    L["A string nobody translated"] == "A string nobody translated")

-- A French client.
ns = env.Load({ ui = true, locale = "frFR" })
L = ns.L
ns.UI:Show()
suite.check("the search window speaks French", ns.UI.emptyLine:GetText() == "Cherche quelque chose à farmer",
    ns.UI.emptyLine:GetText())
labels = SettingsLabels(ns)
suite.check("the settings rows speak French", labels["Cacher le dépeçage :"] == true)
suite.check("and none is left in English (French)", labels["Hide Skinning:"] == nil)
suite.check("the hide menu's line (French)", L.Format("Hide %s", "Kobold") == "Cacher Kobold")
suite.check("a creature type is kept in English (French)", ns.Grinding.EnglishType("Beast") == "Beast")
suite.check("a word with no French line falls back to English",
    L["A string nobody translated"] == "A string nobody translated")

-- A Spanish (Spain) client.
ns = env.Load({ ui = true, locale = "esES" })
L = ns.L
ns.UI:Show()
suite.check("the search window speaks Spanish (Spain)", ns.UI.emptyLine:GetText() == "Busca algo para farmear",
    ns.UI.emptyLine:GetText())
labels = SettingsLabels(ns)
suite.check("the settings rows speak Spanish (Spain)", labels["Ocultar desuello:"] == true)
suite.check("and none is left in English (Spanish (Spain))", labels["Hide Skinning:"] == nil)
suite.check("the hide menu's line (Spanish (Spain))", L.Format("Hide %s", "Kobold") == "Ocultar Kobold")
suite.check("a creature type is kept in English (Spanish (Spain))", ns.Grinding.EnglishType("Beast") == "Beast")
suite.check("a word with no Spanish (Spain) line falls back to English",
    L["A string nobody translated"] == "A string nobody translated")

-- A Spanish (Latin America) client.
ns = env.Load({ ui = true, locale = "esMX" })
L = ns.L
ns.UI:Show()
suite.check("the search window speaks Spanish (Latin America)", ns.UI.emptyLine:GetText() == "Busca algo para farmear",
    ns.UI.emptyLine:GetText())
labels = SettingsLabels(ns)
suite.check("the settings rows speak Spanish (Latin America)", labels["Ocultar desuello:"] == true)
suite.check("and none is left in English (Spanish (Latin America))", labels["Hide Skinning:"] == nil)
suite.check("the hide menu's line (Spanish (Latin America))", L.Format("Hide %s", "Kobold") == "Ocultar Kobold")
suite.check("a creature type is kept in English (Spanish (Latin America))", ns.Grinding.EnglishType("Beast") == "Beast")
suite.check("a word with no Spanish (Latin America) line falls back to English",
    L["A string nobody translated"] == "A string nobody translated")

-- A Russian client.
ns = env.Load({ ui = true, locale = "ruRU" })
L = ns.L
ns.UI:Show()
suite.check("the search window speaks Russian", ns.UI.emptyLine:GetText() == "Найди, что пофармить",
    ns.UI.emptyLine:GetText())
labels = SettingsLabels(ns)
suite.check("the settings rows speak Russian", labels["Скрыть снятие шкур:"] == true)
suite.check("and none is left in English (Russian)", labels["Hide Skinning:"] == nil)
suite.check("the hide menu's line (Russian)", L.Format("Hide %s", "Kobold") == "Скрыть Kobold")
suite.check("a creature type is kept in English (Russian)", ns.Grinding.EnglishType("Beast") == "Beast")
suite.check("a word with no Russian line falls back to English",
    L["A string nobody translated"] == "A string nobody translated")

-- Another language that has no file shows English.
ns = env.Load({ locale = "itIT" })
suite.check("a client in a language with no file shows English", ns.L["Hide skinning"] == "Hide skinning")

_G.GetLocale = nil
suite.done()
