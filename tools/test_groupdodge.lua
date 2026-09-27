-- The kills and loot panel in a party or raid.
--
-- Trent, 2026-09-27: the panel covered the group frames. In a group it now
-- steps to the right of whichever group frames are showing, and goes back to
-- its own spot on leaving. Dragging it while grouped picks a group spot and
-- leaves the solo spot alone. Nothing here may touch the tallies.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("groupdodge")

local ns = env.Load({ ui = true })
local TrackerUI = ns.TrackerUI

-- The screen: UIParent 1080 tall, bottom-left at 0,0.
local SCREEN_TOP = 1080

local grouped = false
_G.IsInGroup = function() return grouped end
_G.IsInRaid = function() return false end
_G.GetNumGroupMembers = nil

ns.Tracker:OnEnable()
TrackerUI:OnEnable()

local frame = TrackerUI.frame

-- The stub records anchors but has no layout; work out the panel's corner
-- from its anchor the way the client would.
function frame:GetLeft() return self._point[4] end
function frame:GetTop()
    local p = self._point
    if p[3] == "TOPLEFT" then return SCREEN_TOP + p[5] end
    return p[5]
end
function frame:GetWidth() return 236 end

--- Where the panel's top-left corner is on screen.
local function Corner()
    return frame:GetLeft(), frame:GetTop()
end

-- The party frames, just under the player frame on the left.
local party = env.Stub({ _visible = true })
function party:IsVisible() return self._visible end
function party:GetLeft() return 20 end
function party:GetRight() return 140 end
function party:GetTop() return 900 end
function party:GetBottom() return 600 end
_G.PartyFrame = party

local fire = ns.eventFrame:GetScript("OnEvent")

-- A tally to prove nothing below loses it.
ns.db.tracker = ns.db.tracker or {}
ns.db.tracker.mobs = ns.db.tracker.mobs or {}
ns.db.tracker.mobs["Defias Bandit"] = { kills = 25, items = {} }

suite.check("on by default", ns.db.trackerDodgeGroup == true, tostring(ns.db.trackerDodgeGroup))

local left, top = Corner()
suite.check("solo, it sits at its own spot", left == 8 and top == SCREEN_TOP - 190,
    tostring(left) .. "," .. tostring(top))

grouped = true
fire(ns.eventFrame, "GROUP_ROSTER_UPDATE")
left, top = Corner()
suite.check("joining a party moves it right of the party frames", left == 148,
    tostring(left))
suite.check("at the same height", top == SCREEN_TOP - 190, tostring(top))

grouped = false
fire(ns.eventFrame, "GROUP_ROSTER_UPDATE")
left = Corner()
suite.check("leaving the party puts it back", left == 8, tostring(left))

-- Group frames somewhere else entirely: nothing to dodge.
party.GetLeft = function() return 1500 end
party.GetRight = function() return 1620 end
grouped = true
TrackerUI:Place()
suite.check("group frames that are elsewhere leave it alone", Corner() == 8, Corner())
party.GetLeft = function() return 20 end
party.GetRight = function() return 140 end

-- Hidden group frames (another addon draws its own) are not dodged either.
party._visible = false
TrackerUI:Place()
suite.check("hidden group frames are ignored", Corner() == 8, Corner())
party._visible = true

-- A secret value from the client raises when compared; the panel just stays.
party.GetLeft = function() error("attempt to compare a secret value") end
local ok = pcall(TrackerUI.Place, TrackerUI)
suite.check("a secret value does not break it", ok and Corner() == 8, Corner())
party.GetLeft = function() return 20 end

-- Raid frames count too, and the widest wins.
local raid = env.Stub()
function raid:IsVisible() return true end
function raid:GetLeft() return 20 end
function raid:GetRight() return 400 end
function raid:GetTop() return 1000 end
function raid:GetBottom() return 300 end
_G.CompactRaidFrameContainer = raid
TrackerUI:Place()
suite.check("in a raid it clears the raid frames", Corner() == 408, Corner())
_G.CompactRaidFrameContainer = nil

-- Turned off, it stays put in a group.
ns.HandleSlash("tracker group off")
suite.check("/farm tracker group off turns it off", ns.db.trackerDodgeGroup == false)
suite.check("and the panel goes back to its own spot", Corner() == 8, Corner())
ns.HandleSlash("tracker group on")
suite.check("/farm tracker group on turns it back on", ns.db.trackerDodgeGroup == true)
suite.check("and it steps aside again", Corner() == 148, Corner())
suite.check("the group command does not hide the panel", ns.db.trackerHidden == false)

-- Dragged while grouped: that becomes the group spot, the solo spot stays.
frame._point = { "TOPLEFT", UIParent, "BOTTOMLEFT", 600, 700 }
frame:GetScript("OnDragStart")(frame)
frame:GetScript("OnDragStop")(frame)
suite.check("a drag in a group saves a group spot",
    ns.db.trackerGroupX == 600 and ns.db.trackerGroupY == 700,
    tostring(ns.db.trackerGroupX) .. "," .. tostring(ns.db.trackerGroupY))
suite.check("and leaves the solo spot alone", ns.db.trackerX == 8 and ns.db.trackerY == -190,
    tostring(ns.db.trackerX) .. "," .. tostring(ns.db.trackerY))

TrackerUI:Place()
suite.check("in a group it goes to the spot picked for groups", Corner() == 600, Corner())

grouped = false
TrackerUI:Place()
suite.check("alone it goes back to the solo spot", Corner() == 8, Corner())

-- Dragged alone: the solo spot, as before.
frame._point = { "TOPLEFT", UIParent, "BOTTOMLEFT", 50, 800 }
frame:GetScript("OnDragStart")(frame)
frame:GetScript("OnDragStop")(frame)
suite.check("a drag alone moves the solo spot", ns.db.trackerX == 50, tostring(ns.db.trackerX))
suite.check("and not the group spot", ns.db.trackerGroupX == 600, tostring(ns.db.trackerGroupX))

-- Settings > Window positions forgets both.
ns.SettingsUI:ResetPositions()
suite.check("putting windows back forgets the group spot",
    ns.db.trackerGroupX == nil and ns.db.trackerGroupY == nil)
suite.check("and the solo spot is the starting one", ns.db.trackerX == 8, tostring(ns.db.trackerX))

grouped = true
TrackerUI:Place()
suite.check("then in a group it is beside the party frames again", Corner() == 148, Corner())

-- What the settings checkbox calls.
ns.SettingsUI:Build()
suite.check("the settings page has the switch", ns.SettingsUI.controls.dodgeGroup ~= nil)
TrackerUI:SetDodgeGroup(false)
suite.check("the switch turns it off", ns.db.trackerDodgeGroup == false and Corner() == 8,
    Corner())
TrackerUI:SetDodgeGroup(true)

suite.check("the tally is untouched",
    ns.db.tracker.mobs["Defias Bandit"] and ns.db.tracker.mobs["Defias Bandit"].kills == 25)

_G.PartyFrame = nil
_G.IsInGroup = nil
_G.IsInRaid = nil
grouped = false

suite.done()
