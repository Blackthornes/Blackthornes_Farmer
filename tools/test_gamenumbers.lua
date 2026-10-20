-- Farmer's damage numbers were taken out (2026-10-20). What matters: the
-- game's own numbers come back at login with the player's own value,
-- never in a fight (it waits for the fight to end), and nothing is
-- touched when nothing was kept.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("gamenumbers")

local cvars = {}
_G.C_CVar = { SetCVar = function(name, value) cvars[name] = value return true end }
local fighting = true
_G.InCombatLockdown = function() return fighting end

local ns = env.Load({ ui = true })
local GN = ns.GameNumbers
suite.check("the damage numbers are gone", ns.DamageNumbers == nil)

ns.db.damageNumbersCVars = { floatingCombatTextCombatDamage_v2 = "1" }
suite.check("never in a fight", GN:Restore() == false and cvars.floatingCombatTextCombatDamage_v2 == nil)
fighting = false
GN:Restore()
suite.check("after the fight the player's value goes back", cvars.floatingCombatTextCombatDamage_v2 == "1")
suite.check("and leaves the list", next(ns.db.damageNumbersCVars) == nil)

cvars = {}
ns.db.damageNumbersCVars = nil
suite.check("nothing kept, nothing touched", GN:Restore() == true and next(cvars) == nil)

_G.C_CVar, _G.InCombatLockdown = nil, nil
suite.done()
