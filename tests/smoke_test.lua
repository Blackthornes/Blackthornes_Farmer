--[[--------------------------------------------------------------------------
  Loads the addon against the stub client and checks that searching works.

  Run from the repo root with any Lua 5.1+:  lua tests/smoke_test.lua
----------------------------------------------------------------------------]]

local stub = dofile("tests/wow_stub.lua").Install()

local failures = 0
local function check(name, ok, detail)
	if ok then
		print("  ok   " .. name)
	else
		failures = failures + 1
		print("  FAIL " .. name .. (detail and ("  -> " .. tostring(detail)) or ""))
	end
end

-- Load in the same order as the .toc
dofile("BlackthornesFarmer/Core.lua")
dofile("BlackthornesFarmer/Search.lua")
dofile("BlackthornesFarmer/UI.lua")
dofile("BlackthornesFarmer/Data/Data_Mining.lua")
dofile("BlackthornesFarmer/Data/Data_Herbalism.lua")
dofile("BlackthornesFarmer/Data/Data_Cloth.lua")
dofile("BlackthornesFarmer/Data/Data_Leather.lua")
dofile("BlackthornesFarmer/Data/Data_Misc.lua")

local BF = BlackthornesFarmer
BF:InitDB()

print("database")
check("items loaded", BF:CountItems() > 0, BF:CountItems())
check("sources loaded", BF:CountSources() > 0, BF:CountSources())
check("every item has at least one source", (function()
	local i
	for i = 1, table.getn(BF.itemOrder) do
		local item = BF.items[BF.itemOrder[i]]
		if table.getn(item.sources) == 0 then return false end
	end
	return true
end)())
check("every source has a zone and a level", (function()
	local i
	for i = 1, table.getn(BF.itemOrder) do
		local item = BF.items[BF.itemOrder[i]]
		local s
		for s = 1, table.getn(item.sources) do
			local src = item.sources[s]
			if not src.zone or not src.minLevel then return false end
		end
	end
	return true
end)())

print("search")
local exact = BF:Search("copper ore")
check("exact name ranks first", exact[1] and exact[1].item.name == "Copper Ore",
	exact[1] and exact[1].item.name)

local partial = BF:Search("mithril")
check("partial name matches", partial[1] and partial[1].item.name == "Mithril Ore",
	partial[1] and partial[1].item.name)

local byZone = BF:Search("westfall")
check("zone search returns items", table.getn(byZone) > 0, table.getn(byZone))
check("zone search is ranked below name matches", (function()
	local i
	for i = 1, table.getn(byZone) do
		if byZone[i].why == "name" then return false end
	end
	return true
end)())

local byCategory = BF:Search("herbalism")
check("category search returns items", table.getn(byCategory) > 3, table.getn(byCategory))

local byMob = BF:Search("defias")
check("mob-name search returns Linen Cloth",
	byMob[1] and byMob[1].item.name == "Linen Cloth",
	byMob[1] and byMob[1].item.name)

check("nonsense finds nothing", table.getn(BF:Search("qqzzxx")) == 0)
check("empty query finds nothing", table.getn(BF:Search("")) == 0)

print("formatting")
local copper = BF:GetItem("Copper Ore")
local sorted = BF:SortedSources(copper)
check("sources sort by level", (function()
	local i
	for i = 2, table.getn(sorted) do
		if sorted[i].minLevel < sorted[i - 1].minLevel then return false end
	end
	return true
end)())
check("source line names the zone",
	string.find(BF:SourceLine(sorted[1]), sorted[1].zone, 1, true) ~= nil)
check("source line shows the level band",
	string.find(BF:SourceLine(sorted[1]), BF:LevelText(sorted[1]), 1, true) ~= nil)

local lines, total = BF:BuildLines("copper ore", 12)
check("build lines produces output", table.getn(lines) > 1, table.getn(lines))
check("build lines reports a total", total >= 1, total)
local miss = BF:BuildLines("qqzzxx", 12)
check("no-match message is shown", string.find(miss[1], "Nothing found", 1, true) ~= nil)

print("window")
BF:ShowUI("copper ore")
check("frame is shown", BF.UI.frame:IsShown())
check("search box holds the query", BF.UI.searchBox:GetText() == "copper ore",
	BF.UI.searchBox:GetText())
check("first row has text", BF.UI.rows[1]:GetText() ~= "")
check("header counts the matches", string.find(BF.UI.header:GetText(), "matching", 1, true) ~= nil)

BF.UI.lines = {}
local n
for n = 1, 100 do table.insert(BF.UI.lines, "line " .. n) end
BF.UI.offset = 0
BF.UI:Scroll(-1)
check("wheel down scrolls", BF.UI.offset == 3, BF.UI.offset)
BF.UI:Scroll(1)
check("wheel up scrolls back", BF.UI.offset == 0, BF.UI.offset)
BF.UI.offset = 0
BF.UI:Scroll(-500)
check("scrolling clamps at the end", BF.UI.offset == 100 - 20, BF.UI.offset)

print("slash commands")
local before = table.getn(stub.chat)
SlashCmdList["BLACKTHORNESFARMER"]("help")
check("/farm help prints", table.getn(stub.chat) > before)
before = table.getn(stub.chat)
SlashCmdList["BLACKTHORNESFARMER"]("chat copper ore")
check("/farm chat prints results", table.getn(stub.chat) > before)
before = table.getn(stub.chat)
SlashCmdList["BLACKTHORNESFARMER"]("stats")
check("/farm stats prints", table.getn(stub.chat) > before)
SlashCmdList["BLACKTHORNESFARMER"]("mithril")
check("/farm <query> drives the window",
	BF.UI.searchBox:GetText() == "mithril", BF.UI.searchBox:GetText())

print("")
if failures == 0 then
	print("all checks passed (" .. BF:CountItems() .. " items, " .. BF:CountSources() .. " spots)")
	os.exit(0)
end
print(failures .. " check(s) failed")
os.exit(1)
