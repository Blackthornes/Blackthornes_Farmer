-- Add Lure on a German client, with Nightcrawlers ("Nachtkriecher").
--
-- A player on a German client moved from "Secret" Bait (no skill needed)
-- to Nightcrawlers (Fishing 50) and Add Lure would not put it on: the row
-- stayed grey and did nothing, though the game's own tooltip line said the
-- skill was enough. What must hold:
--   1. A lure whose "Benötigt Angeln (50)" line is not red can be used,
--      whatever the skill read said, from the list and from One Key
--      Fishing; its row carries the lure macro.
--   2. A line the game paints red still greys the row, and so does a short
--      skill when the line's colour can't be read.
--   3. The skill read skips an empty line (0) and takes the highest of the
--      lines named for Fishing in the client's language.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("fishingbar_german")

local ns = env.Load({ ui = true, locale = "deDE" })
local realCreate = _G.CreateFrame
_G.CreateFrame = function(kind, name, parent, template)
    local frame = realCreate(kind, name, parent, template)
    if type(name) == "string" and name:find("^BlackthornesFarmer") then
        frame._attrs = {}
        frame.SetAttribute = function(self, key, value) self._attrs[key] = value end
        frame.GetAttribute = function(self, key) return self._attrs[key] end
    end
    return frame
end

local WHITE = { r = 1, g = 1, b = 1 }
local RED = { r = 1, g = 0.125, b = 0.125 }
local lineColor = WHITE

local bags = { [6530] = 20 }
_G.GetInventoryItemID = function(_, slot) if slot == 16 then return 6256 end end
_G.C_Item = _G.C_Item or {}
_G.C_Item.GetItemInfoInstant = function(id)
    if id == 6256 then return id, "Waffe", "Angelrute", "INVTYPE_2HWEAPON", 132932, 2, 20 end
    return id, "Handwerkswaren", "Teile", "", 134400, 7, 1
end
_G.C_Item.GetItemCount = function(id) return bags[id] or 0 end
_G.C_Item.GetItemNameByID = function(id) if id == 6530 then return "Nachtkriecher" end end
_G.GetWeaponEnchantInfo = function() return false end
_G.InCombatLockdown = function() return false end
_G.ITEM_MIN_SKILL = "Benötigt %s (%d)"
_G.C_TooltipInfo = { GetItemByID = function(id)
    if id == 6530 then
        return { lines = {
            { leftText = "Nachtkriecher", leftColor = WHITE },
            { leftText = "Benötigt Angeln (50)", leftColor = lineColor },
            { leftText = "Benutzen: Befestigt einen Köder an Eurer Angel.", leftColor = { r = 0, g = 1, b = 0 } },
        } }
    end
    return { lines = { { leftText = "?" } } }
end }
_G.C_Spell = { GetSpellName = function(id) if id == 7620 then return "Angeln" end end }

-- The skill lines as a German client lists them: an empty Angeln line
-- before the real one, as a skill shown on its old and new line can be.
local skillLines = {
    { "Berufe", true },
    { "Kürschnerei", false, nil, 120, nil, nil, 150 },
    { "Sekundäre Fertigkeiten", true },
    { "Angeln", false, nil, 0, nil, nil, 0 },
    { "Angeln", false, nil, 87, nil, nil, 150 },
}
_G.GetProfessions, _G.GetProfessionInfo = nil, nil
_G.GetNumSkillLines = function() return #skillLines end
_G.GetSkillLineInfo = function(index) return unpack(skillLines[index]) end

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local Bar = ns.FishingBar
local GatherToCap = ns.GatherToCap

-- 3. The skill read, in German.
local skill, most = GatherToCap.ReadSkill("Fishing")
suite.check("Angeln is read past its empty line", skill == 87 and most == 150,
    tostring(skill) .. " / " .. tostring(most))

-- 1. The game says the need is met, though the skill read comes back short.
local realRead = GatherToCap.ReadSkill
GatherToCap.ReadSkill = function() return 1, 75 end
local lures = Bar:Lures(1)
suite.check("Nachtkriecher is found in the bags", #lures == 1 and lures[1].id == 6530
    and lures[1].name == "Nachtkriecher" and lures[1].need == 50)
suite.check("a white Benötigt line lets it on", lures[1].usable == true)

ns.db.fishingBar = true
Bar:Update()
Bar:ToggleList()
local row = _G.BlackthornesFarmerFishingLure1
suite.check("its row puts it on the pole", row and row:GetAttribute("type") == "macro"
    and row:GetAttribute("macrotext") == "/use item:6530\n/use 16",
    row and tostring(row:GetAttribute("macrotext")))

local One = ns.OneKeyFishing
if One and One.Action then
    ns.db.oneKeyFishing = true
    local enabled = One.Enabled
    One.Enabled = function() return true end
    local action, id = One:Action()
    suite.check("One Key Fishing puts it on too", action == "lure" and id == 6530,
        tostring(action) .. " " .. tostring(id))
    One.Enabled = enabled
end

-- 2. The game paints the line red: still grey, no macro.
lineColor = RED
lures = Bar:Lures(1)
suite.check("a red Benötigt line greys it", lures[1].usable == false and lures[1].need == 50)
Bar:DrawList()
suite.check("and the grey row does nothing", row:GetAttribute("macrotext") == nil)

lineColor = nil
lures = Bar:Lures(1)
suite.check("no colour to read: the skill read decides", lures[1].usable == false)
lures = Bar:Lures(60)
suite.check("a skill that reaches it lets it on", lures[1].usable == true)

GatherToCap.ReadSkill = realRead
_G.GetNumSkillLines, _G.GetSkillLineInfo, _G.GetLocale, _G.C_Spell = nil, nil, nil, nil
_G.C_TooltipInfo, _G.ITEM_MIN_SKILL = nil, nil
_G.CreateFrame = realCreate

suite.done()
