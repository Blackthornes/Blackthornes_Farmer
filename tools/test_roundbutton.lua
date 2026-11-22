-- The round button in Farmer (UI/FoldWindow.lua, the owner said build it,
-- 2026-11-22): Kills & Loot and Goals fold into a round button from their
-- fold gem, with this session's kills, or goals done out of goals set,
-- under it; a click opens the panel again. The panel folded draws nothing.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("roundbutton")

local ns = env.Load({ ui = true })
local L = ns.L
local FoldWindow = ns.FoldWindow
local TrackerUI = ns.TrackerUI

-- Kills & Loot.
ns.db.trackerHidden = false
TrackerUI:Refresh()
local frame = TrackerUI.frame
suite.check("the panel is up", frame and frame:IsShown())
frame._left, frame._top = 100, 600
TrackerUI.gems.fold:GetScript("OnClick")(TrackerUI.gems.fold)
suite.check("the fold gem folds it into a round button", FoldWindow:IsFolded(frame) and TrackerUI:IsFoldedAway())
local key = "Blackthornes_Farmer:KillsAndLoot"
local round = FoldWindow.rounds[key]
suite.check("its button shows", round and round.button:IsShown())
suite.check("kept through a /reload", FoldWindow.SavedFolded(key))
suite.check("no number before a kill", not round.pill:IsShown())

ns.Tracker.session = { ["Test Wolf"] = 3 }
TrackerUI:Refresh(true)
local kills = ns.Tracker:SessionKills()
suite.check("a kill counted", kills >= 1, kills)
suite.check("the kills under the button", round.pill:IsShown() and round.pillText == tostring(kills), round.pillText)
suite.check("the tooltip line names kills and loot",
    TrackerUI:FoldedLine():find(L.Format("This session: %s, ", ns.Util.Plural(kills, L["kill"], L["kills"])), 1, true) == 1,
    TrackerUI:FoldedLine())

round.button:GetScript("OnClick")(round.button)
suite.check("a click opens it again", not FoldWindow:IsFolded(frame) and not round.button:IsShown())
suite.check("and the save is cleared", not FoldWindow.SavedFolded(key))

-- Goals.
local GoalsUI = ns.GoalsUI
GoalsUI:Build()
local done, total = 0, 0
local real = GoalsUI.List
GoalsUI.List = function() return { { done = true }, { done = false }, { done = false } } end
done, total = GoalsUI:DoneCount()
suite.check("goals done out of goals set", done == 1 and total == 3)
local host = FoldWindow.hosts["Blackthornes_Farmer:Goals"]
suite.check("the goals button reads 1/3", host and host.pill() == "1/3")
suite.check("and its tooltip", host.line() == L.Format("%d of %d goals done.", 1, 3))
GoalsUI.List = real

-- The one window says which addon it opens to.
local options = ns.SharedWindow.FoldOptions()
suite.check("the one window keeps one key for every addon", options.shared and options.key == "BlackthornesOneWindow")

suite.done()
