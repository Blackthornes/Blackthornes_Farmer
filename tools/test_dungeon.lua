-- Things that used to raise inside a dungeon (asked 2026-09-26).
--
-- What matters: hovering a mob whose name is secret never errors and still
-- counts as "a unit is under the mouse"; a fishing flag the client will not
-- let us read is not taken as fishing, so the corpse is still recorded; and
-- the unlock /emote is never sent from inside an instance.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("dungeon")

local ns = env.Load({ ui = true })
local Harvest = ns.Harvest

-- Hovering a mob in a dungeon: GetUnit hands back a secret name.
local tip = {
    GetUnit = function() return env.Secret("string"), "mouseover" end,
    GetItem = function() return nil end,
}
local ok, shown = pcall(Harvest.TooltipShowsUnitOrItem, tip)
suite.check("a secret mob name on the tooltip does not raise", ok, shown)
suite.check("and still counts as a unit under the mouse", ok and shown == true, shown)

-- env.Secret cannot make `name ~= nil` raise (Lua only asks __eq of two
-- tables), and that exact comparison is what raised in game. So check the
-- source: the presence test must go through type(), never compare the name.
local handle = io.open(lfs_cwd .. "/Logic/Harvest.lua", "r")
local source = handle:read("*a")
handle:close()
local body = source:match("function Harvest%.TooltipShowsUnitOrItem.-\nend\n") or ""
suite.check("the tooltip check never compares the name itself",
    body ~= "" and not body:find("name%s*[~=]=") and body:find("Present%(name%)") ~= nil,
    body)

-- A fishing flag that cannot be read. Treating it as true skipped the corpse.
local real = _G.IsFishingLoot
_G.IsFishingLoot = function() return env.Secret("boolean") end
local okNode, node = pcall(Harvest.IsNodeLoot, Harvest)
suite.check("an unreadable fishing flag does not raise", okNode, node)
suite.check("and is not taken for fishing", okNode and node == false, node)
_G.IsFishingLoot = real

-- The unlock emote.
local sent = {}
_G.SendChatMessage = function(text, chatType)
    sent[#sent + 1] = { text = text, chatType = chatType }
end

_G.IsInInstance = function() return false, "none" end
suite.check("outside an instance the emote goes out",
    ns.Tracker:Announce("hello") and #sent == 1, #sent)

_G.IsInInstance = function() return true, "party" end
suite.check("inside a dungeon it is not sent",
    ns.Tracker:Announce("hello") == false and #sent == 1, #sent)

_G.IsInInstance = function() error("refused") end
local okSecret, result = pcall(ns.Tracker.Announce, ns.Tracker, "hello")
suite.check("a client that will not say counts as inside, without raising",
    okSecret and result == false and #sent == 1, result)

_G.IsInInstance = nil
suite.done()
