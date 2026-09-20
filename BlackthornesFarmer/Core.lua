--[[--------------------------------------------------------------------------
  Blackthorne's Farmer -- Core

  Addon table, the item database and its registration API, and the slash
  commands. Written against the 1.12 (vanilla / Turtle WoW) Lua API:
  Lua 5.0, so no "#" length operator, no string.gmatch, no select().

  Event and script handlers are written so they work whether the client calls
  them with arguments (modern) or through the globals "this" / "event" /
  "arg1" (1.12).
----------------------------------------------------------------------------]]

BlackthornesFarmer = BlackthornesFarmer or {}
local BF = BlackthornesFarmer

BF.version = "0.1.0"
BF.addonName = "Blackthorne's Farmer"

-- items[lowercase name] = item definition; itemOrder keeps iteration stable.
BF.items = {}
BF.itemOrder = {}

-- What a source actually is. Every source entry names one of these so the UI
-- can label it; unknown kinds fall back to the raw string.
BF.KIND_LABEL = {
	mob        = "mob",
	node       = "mining node",
	herb       = "herb node",
	skinning   = "skinning",
	fishing    = "fishing",
	container  = "container",
	vendor     = "vendor",
	quest      = "quest",
}

BF.COLOR = {
	item   = "|cffffd100",
	dim    = "|cff909090",
	kind   = "|cff7fbfff",
	note   = "|cffb0a070",
	bad    = "|cffff5555",
	accent = "|cff33ff99",
	off    = "|r",
}

--[[ helpers ----------------------------------------------------------------]]

function BF.Trim(s)
	if not s then return "" end
	s = string.gsub(s, "^%s+", "")
	s = string.gsub(s, "%s+$", "")
	return s
end

function BF:Print(msg)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(self.COLOR.accent .. "Farmer" .. self.COLOR.off .. ": " .. tostring(msg))
	end
end

--[[ data registration ------------------------------------------------------

  Data files call:

    BlackthornesFarmer:RegisterItem({
      name     = "Copper Ore",
      id       = 2770,                  -- optional, for future item links
      category = "Mining",
      aliases  = { "copper" },          -- optional extra search terms
      note     = "...",                 -- optional one-liner
      sources  = {
        { kind = "node", name = "Copper Vein", zone = "Durotar",
          minLevel = 1, maxLevel = 10, requires = "Mining 1", note = "..." },
      },
    })

  Registering a name that already exists merges the new sources into the
  existing item, so the database can be split across as many files as we like
  and later files can extend earlier ones.
----------------------------------------------------------------------------]]

function BF:RegisterItem(def)
	if type(def) ~= "table" or type(def.name) ~= "string" or def.name == "" then
		self:Print(self.COLOR.bad .. "skipped a data entry with no name" .. self.COLOR.off)
		return nil
	end

	local key = string.lower(def.name)
	local item = self.items[key]

	if not item then
		item = {
			name     = def.name,
			id       = def.id,
			category = def.category or "Misc",
			aliases  = {},
			note     = def.note,
			sources  = {},
		}
		self.items[key] = item
		table.insert(self.itemOrder, key)
	else
		item.id       = item.id or def.id
		item.category = def.category or item.category
		item.note     = item.note or def.note
	end

	if def.aliases then
		local i
		for i = 1, table.getn(def.aliases) do
			table.insert(item.aliases, def.aliases[i])
		end
	end

	if def.sources then
		local i
		for i = 1, table.getn(def.sources) do
			self:AddSource(item, def.sources[i])
		end
	end

	return item
end

-- Accepts either an item table (from RegisterItem) or an item name, so other
-- addons / data packs can bolt a single source onto something already known.
function BF:AddSource(item, src)
	if type(item) == "string" then
		item = self.items[string.lower(item)]
	end
	if not item or type(src) ~= "table" then return nil end

	-- A source needs at least somewhere to go.
	if type(src.zone) ~= "string" or src.zone == "" then
		self:Print(self.COLOR.bad .. "skipped a source with no zone on " .. item.name .. self.COLOR.off)
		return nil
	end

	src.kind = src.kind or "mob"
	src.minLevel = src.minLevel or src.level
	src.maxLevel = src.maxLevel or src.minLevel
	table.insert(item.sources, src)
	return src
end

function BF:GetItem(name)
	if type(name) ~= "string" then return nil end
	return self.items[string.lower(BF.Trim(name))]
end

function BF:CountItems()
	return table.getn(self.itemOrder)
end

function BF:CountSources()
	local total, i = 0, nil
	for i = 1, table.getn(self.itemOrder) do
		total = total + table.getn(self.items[self.itemOrder[i]].sources)
	end
	return total
end

--[[ saved variables --------------------------------------------------------]]

local defaults = {
	point = "CENTER",
	relPoint = "CENTER",
	x = 0,
	y = 40,
	lastSearch = "",
}

function BF:InitDB()
	if type(BlackthornesFarmerDB) ~= "table" then
		BlackthornesFarmerDB = {}
	end
	local k, v
	for k, v in pairs(defaults) do
		if BlackthornesFarmerDB[k] == nil then
			BlackthornesFarmerDB[k] = v
		end
	end
	self.db = BlackthornesFarmerDB
end

--[[ slash commands ---------------------------------------------------------]]

local HELP = {
	"usage:",
	"  /farm <text>        search items, zones and mobs, and show the window",
	"  /farm chat <text>   print the same results to chat instead",
	"  /farm list          list every item in the database",
	"  /farm stats         how much data is loaded",
	"  /farm help          this text",
	"  /farm               open or close the window",
}

function BF:ShowHelp()
	local i
	self:Print(self.addonName .. " v" .. self.version)
	for i = 1, table.getn(HELP) do
		self:Print(HELP[i])
	end
end

function BF:ListItems()
	local i, line, count = nil, "", 0
	self:Print("database holds " .. self:CountItems() .. " items:")
	for i = 1, table.getn(self.itemOrder) do
		local item = self.items[self.itemOrder[i]]
		line = line .. item.name
		count = count + 1
		if count == 4 or i == table.getn(self.itemOrder) then
			self:Print("  " .. line)
			line, count = "", 0
		else
			line = line .. ", "
		end
	end
end

function BF:HandleSlash(msg)
	msg = BF.Trim(msg or "")
	local lower = string.lower(msg)

	if lower == "" then
		self:ToggleUI()
		return
	end

	if lower == "help" or lower == "?" then
		self:ShowHelp()
		return
	end

	if lower == "list" or lower == "items" then
		self:ListItems()
		return
	end

	if lower == "stats" then
		self:Print(self:CountItems() .. " items, " .. self:CountSources() .. " farming spots loaded")
		return
	end

	local _, _, chatQuery = string.find(lower, "^chat%s+(.+)$")
	if chatQuery then
		self:PrintResults(chatQuery)
		return
	end

	self:ShowUI(msg)
end

SLASH_BLACKTHORNESFARMER1 = "/farm"
SLASH_BLACKTHORNESFARMER2 = "/farmer"
SLASH_BLACKTHORNESFARMER3 = "/bfarm"
SlashCmdList["BLACKTHORNESFARMER"] = function(msg)
	BF:HandleSlash(msg)
end

--[[ load -------------------------------------------------------------------]]

local loader = CreateFrame("Frame", "BlackthornesFarmerLoader")
loader:RegisterEvent("VARIABLES_LOADED")
loader:SetScript("OnEvent", function()
	BF:InitDB()
	BF:Print("loaded. " .. BF:CountItems() .. " items, " .. BF:CountSources()
		.. " spots. Type " .. BF.COLOR.item .. "/farm" .. BF.COLOR.off .. " to search.")
end)
