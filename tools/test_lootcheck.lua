-- The loot check (asked 2026-10-10, after a dungeon recorded nothing).
--
-- What matters: /farm harvest check waits for the next loot window and runs
-- there once; a secret name or guid is reported as such and never raises;
-- a player's name is never printed; and the lines are kept as lastProbe.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("lootcheck")

local ns = env.Load()
local Harvest = ns.Harvest

for _, module in ipairs(ns.moduleOrder) do
    if module.OnEnable then module:OnEnable() end
end

local function Lines() return table.concat(ns.db.lastProbe and ns.db.lastProbe.lines or {}, "\n") end

suite.check("a plain value is its text", Harvest.Describe("Defias Thug") == "Defias Thug")
suite.check("nil says so", Harvest.Describe(nil) == "nil")
suite.check("a secret value is unreadable, without raising",
    Harvest.Describe(env.Secret("string")):find("unreadable", 1, true) ~= nil,
    Harvest.Describe(env.Secret("string")))

_G.issecretvalue = function(value) return type(value) == "table" end
suite.check("where the client can tell, it says secret",
    Harvest.Describe(env.Secret("string")) == "secret", Harvest.Describe(env.Secret("string")))
_G.issecretvalue = nil

ns.db.lastProbe = nil
ns.HandleSlash("harvest check")
suite.check("asking only readies it", ns.db.lastProbe == nil and Harvest.checkArmed == true)

-- A dungeon corpse: the name and guid come back secret.
local realName, realGuid = _G.UnitName, _G.UnitGUID
_G.UnitName = function() return env.Secret("string") end
_G.UnitGUID = function() return env.Secret("string") end
env.world.loot = { { name = "Linen Cloth", count = 2 } }

Harvest:NotePicked()
_G.GetInstanceInfo = function() return "Ragefire Chasm", "party" end
local ok, err = pcall(Harvest.RunArmedCheck, Harvest)
suite.check("a dungeon corpse does not raise", ok, err)
suite.check("it ran once and is kept", ns.db.lastProbe and ns.db.lastProbe.check == "harvest check")
suite.check("it names the dungeon it ran in",
    Lines():find("loot check in Ragefire Chasm (party)", 1, true), Lines())
_G.GetInstanceInfo = nil
suite.check("and is no longer ready", not Harvest.checkArmed)
suite.check("the name is reported unreadable", Lines():find("target name: unreadable", 1, true), Lines())
suite.check("the loot slot is described", Lines():find("slot 1 info", 1, true), Lines())
suite.check("a hidden name when picked says so",
    Lines():find("target name when picked: hidden then too", 1, true), Lines())
suite.check("and the harvest's verdict", Lines():find("would be skipped", 1, true), Lines())

ns.db.lastProbe = nil
Harvest:RunArmedCheck()
suite.check("the next loot window does not run it again", ns.db.lastProbe == nil)

-- A name that read when the target was picked is reported.
_G.UnitName = function() return "Ragefire Trogg" end
Harvest:NotePicked()
_G.UnitName = function() return env.Secret("string") end
Harvest.checkArmed = true
Harvest:RunArmedCheck()
suite.check("the name as picked is reported",
    Lines():find("target name when picked: Ragefire Trogg", 1, true), Lines())
suite.check("an empty loot window says so", Lines():find("this window was empty", 1, true)
    or #env.world.loot > 0, Lines())

-- A player under the target is left out.
_G.UnitName, _G.UnitGUID = realName, realGuid
local realPlayer = _G.UnitIsPlayer
_G.UnitIsPlayer = function() return true end
_G.UnitName = function() return "Bob" end
Harvest.checkArmed = true
Harvest:RunArmedCheck()
suite.check("a player's name is never printed", not Lines():find("Bob", 1, true), Lines())
suite.check("it says a player instead", Lines():find("a player (left out)", 1, true), Lines())
_G.UnitIsPlayer, _G.UnitName = realPlayer, realName

suite.done()
