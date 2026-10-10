-- Checks kept for Claude (the owner asked 2026-10-10): a check prints to chat
-- as before, and what it printed is also saved as lastProbe in the account
-- save, so it can be read from the saved file after a /reload.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("keepcheck")

local ns = env.Load()

local function ChatText() return table.concat(env.chat, "\n") end

_G.date = function() return "2026-10-10 12:00:00" end

env.chat = {}
ns.KeepCheck("test", function()
    ns.Print("|cffc8a44dheading|r")
    ns.PrintRaw("  |cff7a8089has|r  a, b")
    ns.Warn("|Hitem:2589|h[Linen Cloth]|h missing")
end)

local saved = ns.db.lastProbe
suite.check("the lines are saved", type(saved) == "table" and type(saved.lines) == "table")
suite.check("with which check it was", saved.check == "test", saved.check)
suite.check("when", saved.at == "2026-10-10 12:00:00", saved.at)
suite.check("and the version", saved.version == ns.VERSION, saved.version)
suite.check("one line each", #saved.lines == 3, #saved.lines)
suite.check("colours are taken out", not saved.lines[1]:find("|c", 1, true), saved.lines[1])
suite.check("and the text kept", saved.lines[2] == "  has  a, b", saved.lines[2])
suite.check("links keep their name", saved.lines[3]:find("[Linen Cloth] missing", 1, true), saved.lines[3])
suite.check("chat still shows the check", ChatText():find("heading", 1, true), ChatText())
suite.check("and says it was kept",
    ChatText():find("Saved for Claude, /reload to write it.", 1, true), ChatText())

env.chat = {}
ns.Print("after the check")
suite.check("lines after the check are not kept", #ns.db.lastProbe.lines == 3, #ns.db.lastProbe.lines)

_G.issecretvalue = function(value) return value == "  secret" end
ns.KeepCheck("secret", function() ns.PrintRaw("  secret") end)
_G.issecretvalue = nil
suite.check("a secret value never reaches the save",
    ns.db.lastProbe.lines[1] == "(secret)", ns.db.lastProbe.lines[1])

local ok = pcall(ns.KeepCheck, "broken", function()
    ns.Print("half way")
    error("kaboom", 0)
end)
suite.check("a failing check still fails", not ok)
suite.check("and keeps what it printed and why",
    ns.db.lastProbe.lines[1]:find("half way", 1, true)
    and ns.db.lastProbe.lines[2] == "error: kaboom", table.concat(ns.db.lastProbe.lines, " / "))

env.chat = {}
ns.HandleSlash("arrow check")
suite.check("arrow check is kept", ns.db.lastProbe.check == "arrow check", ns.db.lastProbe.check)
suite.check("with its lines", #ns.db.lastProbe.lines > 1, #ns.db.lastProbe.lines)

suite.done()
