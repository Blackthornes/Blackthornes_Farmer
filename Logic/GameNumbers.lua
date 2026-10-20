-- Blackthornes Farmer -- Logic/GameNumbers.lua
-- Puts the game's own damage numbers back.
--
-- Farmer had its own damage numbers for a short while (2026-10-19), and
-- while they were ticked the game setting that shows the game's numbers
-- (`floatingCombatTextCombatDamage`, or its `_v2`) was set to 0, the
-- player's value kept in `damageNumbersCVars`. The owner took the feature
-- out (2026-10-20), so at login every value kept there goes back, never
-- in a fight: it waits for the fight to end. A value put back is taken
-- off the list; the list itself and the other saved keys
-- (`damageNumbers`, `damageNumbersSize`, `damageNumbersCombo`) are kept
-- and never read.

local _, ns = ...

local GameNumbers = ns.NewModule("GameNumbers")

local function InCombat()
    if type(InCombatLockdown) ~= "function" then return false end
    local ok, value = pcall(InCombatLockdown)
    return ok and value == true
end

local function SetCVarValue(name, value)
    local cvar = _G.C_CVar
    local set = type(cvar) == "table" and cvar.SetCVar or _G.SetCVar
    if type(set) ~= "function" then return false end
    local ok, result = pcall(set, name, value)
    return ok and result ~= false
end

--- Put back every value Farmer kept. True once nothing is left to do.
function GameNumbers:Restore()
    local saved = ns.db and ns.db.damageNumbersCVars
    if type(saved) ~= "table" or next(saved) == nil then return true end
    if InCombat() then
        self.waiting = true
        return false
    end
    self.waiting = nil
    for name, value in pairs(saved) do
        if type(name) == "string" and type(value) == "string" and SetCVarValue(name, value) then
            saved[name] = nil
        end
    end
    return true
end

function GameNumbers:OnEnable()
    if self:Restore() then return end
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        if GameNumbers.waiting then GameNumbers:Restore() end
    end)
end
