-- The note on screen when a clam or sack from the bags is opened.
--
-- What matters: it says how many are opened out of 20 until then, and what
-- one is worth after; it shows when Containers counts an opening; it goes
-- after a few seconds; unticked, it never shows.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("opennote")

local ns = env.Load({ ui = true })
local OpenNote, Containers, Value = ns.OpenNote, ns.Containers, ns.Value

local CLAM = { name = "Small Barnacled Clam", id = 5523 }
local MEAT = { name = "Clam Meat", id = 5503 }
local clock = 100
_G.GetTime = function() return clock end

_G.C_Item = { GetItemInfo = function(id)
    return "item", nil, 1, 1, 1, "", "", 1, "", "", id == MEAT.id and 25 or 1
end }

suite.check("on unless unticked", OpenNote:Enabled())
suite.check("under 20 it counts up",
    OpenNote.Text(CLAM.name, 3) == "Small Barnacled Clam: 3 of 20 opened", OpenNote.Text(CLAM.name, 3))

-- Opened from the bags, as the loot window sees it.
local function OpenOne()
    Containers.opening = { id = CLAM.id, name = CLAM.name, at = GetTime(), unsure = false }
    env.world.loot = { MEAT }
    Containers:OnLoot()
    Containers:OnLootClosed()
end

OpenOne()
local frame = OpenNote.frame
suite.check("an opening shows the note", frame ~= nil and frame:IsShown())
suite.check("with the count", frame.label:GetText() == "Small Barnacled Clam: 1 of 20 opened",
    frame and frame.label:GetText())

OpenNote:Tick(OpenNote.HOLD + OpenNote.FADE * 2 + 0.1)
suite.check("it goes after a few seconds", not frame:IsShown())

for _ = 2, 20 do OpenOne() end
local text = frame.label:GetText()
suite.check("at 20 it says what one is worth", text:find("20 opened, about", 1, true) ~= nil, text)
suite.check("in coins", text:find("25c", 1, true) ~= nil, text)

OpenNote:Hide()
OpenNote:SetEnabled(false)
OpenOne()
suite.check("unticked, nothing shows", not frame:IsShown())
suite.check("but the opening still counts", Containers:Store()[CLAM.name].opens == 21)
OpenNote:SetEnabled(true)

ns.HandleSlash("opennote")
suite.check("/farm opennote turns it off", not OpenNote:Enabled())
ns.HandleSlash("opennote")
suite.check("and on again", OpenNote:Enabled())

suite.done()
