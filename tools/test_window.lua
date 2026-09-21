-- The window, built against a stub client.
--
-- It cannot prove anything about how the frames look, but it does prove the
-- wiring: that typing reaches the search, that results reach the rows, and
-- that scrolling stops at both ends instead of running off into blank space.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("window")

local ns = env.Load({ ui = true })
local UI = ns.UI
local Util = ns.Util

UI:Build()

suite.check("the window starts hidden", not UI.frame:IsShown())
suite.check("it has a search box", UI.searchBox ~= nil)
suite.check("it has a result list", UI.list ~= nil)

--------------------------------------------------------------------------------
-- Searching through the window
--------------------------------------------------------------------------------

UI:Search("copper ore")

suite.check("searching shows the window", UI.frame:IsShown())
suite.check("the search box holds the query",
    UI.searchBox:GetText() == "copper ore", UI.searchBox:GetText())
suite.check("results reach the list", #UI.list.lines > 1, #UI.list.lines)
suite.check("the first row has text", UI.list.rows[1]:GetText() ~= "")

suite.check("the summary counts the matches",
    Util.StripColor(UI.summary:GetText()):find("matching", 1, true) ~= nil,
    UI.summary:GetText())

-- Typing must not rewrite the box underneath the cursor.
UI.searchBox:SetText("mith")
UI:Search("mith", true)
suite.check("typing leaves the box alone", UI.searchBox:GetText() == "mith")

-- An empty box is not a failed search; it is the resting state.
UI:Search("")
suite.check("an empty query clears the list", #UI.list.lines == 0)
suite.check("an empty query still says what is loaded",
    Util.StripColor(UI.summary:GetText()):find("loaded", 1, true) ~= nil,
    UI.summary:GetText())

--------------------------------------------------------------------------------
-- Scrolling
--------------------------------------------------------------------------------

local lines = {}
for index = 1, 100 do lines[index] = "line " .. index end

UI.list:SetLines(lines)
suite.check("a fresh list starts at the top", UI.list.offset == 0)

UI.list:Scroll(-1)
suite.check("the wheel scrolls down", UI.list.offset == 3, UI.list.offset)

UI.list:Scroll(1)
suite.check("the wheel scrolls back up", UI.list.offset == 0, UI.list.offset)

UI.list:Scroll(5)
suite.check("scrolling stops at the top", UI.list.offset == 0, UI.list.offset)

UI.list:Scroll(-500)
suite.check("scrolling stops at the end",
    UI.list.offset == UI.list:MaxOffset(), UI.list.offset)

suite.check("the last page is full, not blank",
    UI.list.rows[1]:GetText() ~= "", UI.list.rows[1]:GetText())

-- A list shorter than the window does not scroll at all.
UI.list:SetLines({ "one", "two" })
UI.list:Scroll(-10)
suite.check("a short list does not scroll", UI.list.offset == 0, UI.list.offset)

--------------------------------------------------------------------------------
-- Showing and hiding
--------------------------------------------------------------------------------

UI:Hide()
suite.check("hiding hides", not UI.frame:IsShown())

UI:Toggle()
suite.check("toggle opens", UI.frame:IsShown())

UI:Toggle()
suite.check("toggle closes", not UI.frame:IsShown())

--------------------------------------------------------------------------------
-- Position is remembered
--------------------------------------------------------------------------------

UI:SavePosition()
suite.check("the position is saved", ns.db.point == "CENTER", ns.db.point)

ns.db.x, ns.db.y = 120, -60
UI:RestorePosition()
suite.check("a saved position survives a restore", ns.db.x == 120)

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

local run = SlashCmdList["BLACKTHORNESFARMER"]
suite.check("the slash command is registered", type(run) == "function")

local function ChatSince(fn)
    local before = #env.chat
    fn()
    return #env.chat - before
end

suite.check("/farm help prints", ChatSince(function() run("help") end) > 0)
suite.check("/farm stats prints", ChatSince(function() run("stats") end) > 0)
suite.check("/farm data prints", ChatSince(function() run("data") end) > 0)
suite.check("/farm list prints", ChatSince(function() run("list") end) > 0)
suite.check("/farm chat prints results",
    ChatSince(function() run("chat copper ore") end) > 1)

-- The point of the router: a material name is not an unknown command.
run("mithril")
suite.check("/farm <query> searches",
    UI.searchBox:GetText() == "mithril", UI.searchBox:GetText())

-- A two-word query whose first word is not a command must not be mistaken for
-- one, and must not lose the rest of the words.
run("linen cloth")
suite.check("/farm <two word query> keeps both words",
    UI.searchBox:GetText() == "linen cloth", UI.searchBox:GetText())

suite.done()
