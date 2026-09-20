--[[--------------------------------------------------------------------------
  Blackthorne's Farmer -- Search and formatting

  Turns a typed query into a ranked list of items, and turns an item into the
  lines both the window and the chat output print.
----------------------------------------------------------------------------]]

local BF = BlackthornesFarmer

-- How well "needle" matches "haystack". Higher is better; 0 is no match.
local function MatchScore(haystack, needle)
	if not haystack or haystack == "" then return 0 end
	if haystack == needle then return 100 end
	local start = string.find(haystack, needle, 1, true)
	if start == 1 then return 60 end
	if start then return 30 end
	return 0
end

--[[ Ranked search over the database.

  Matches, best first:
    1. the item name or one of its aliases
    2. the category ("mining", "cloth", ...)
    3. a zone or a source name, so "/farm Westfall" or "/farm Defias" answers
       "what can I get here / off these" as well as "where do I get this"

  Returns an array of { item = <item>, score = <number>, why = <string> }.
----------------------------------------------------------------------------]]
function BF:Search(query)
	local results = {}
	query = string.lower(BF.Trim(query or ""))
	if query == "" then return results end

	local i
	for i = 1, table.getn(self.itemOrder) do
		local item = self.items[self.itemOrder[i]]
		local score, why = MatchScore(string.lower(item.name), query), "name"

		local a
		for a = 1, table.getn(item.aliases) do
			local aliasScore = MatchScore(string.lower(item.aliases[a]), query)
			if aliasScore > score then score, why = aliasScore, "name" end
		end

		if score == 0 and MatchScore(string.lower(item.category), query) > 0 then
			score, why = 20, "category"
		end

		if score == 0 then
			local s
			for s = 1, table.getn(item.sources) do
				local src = item.sources[s]
				if MatchScore(string.lower(src.zone), query) > 0 then
					score, why = 15, "zone"
					break
				end
				if src.name and MatchScore(string.lower(src.name), query) > 0 then
					score, why = 10, "source"
					break
				end
			end
		end

		if score > 0 then
			table.insert(results, { item = item, score = score, why = why })
		end
	end

	table.sort(results, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		return a.item.name < b.item.name
	end)

	return results
end

-- Sources of one item, lowest level first, so the list reads as "closest to
-- your level is near the top".
function BF:SortedSources(item)
	local sorted, i = {}, nil
	for i = 1, table.getn(item.sources) do
		table.insert(sorted, item.sources[i])
	end
	table.sort(sorted, function(a, b)
		local al, bl = a.minLevel or 0, b.minLevel or 0
		if al ~= bl then return al < bl end
		local ah, bh = a.maxLevel or al, b.maxLevel or bl
		if ah ~= bh then return ah < bh end
		return (a.zone or "") < (b.zone or "")
	end)
	return sorted
end

function BF:LevelText(src)
	if not src.minLevel then return "??" end
	if src.maxLevel and src.maxLevel ~= src.minLevel then
		return src.minLevel .. "-" .. src.maxLevel
	end
	return "" .. src.minLevel
end

-- One source as a display string, e.g.
--   [10-20] Westfall - Copper Vein (mining node, needs Mining 1)
-- A source with no name of its own -- a herb node, say, which is just called
-- after the herb -- drops the name and shows only the zone and the kind.
function BF:SourceLine(src)
	local C = self.COLOR
	local detail = self.KIND_LABEL[src.kind] or src.kind
	if src.requires then detail = detail .. ", needs " .. src.requires end
	if src.chance then detail = detail .. ", ~" .. src.chance .. "%" end

	local line = C.dim .. "[" .. self:LevelText(src) .. "]" .. C.off .. " " .. src.zone
	if src.name then
		line = line .. C.dim .. " - " .. C.off .. src.name
	end
	line = line .. " " .. C.kind .. "(" .. detail .. ")" .. C.off

	if src.note then
		line = line .. " " .. C.note .. src.note .. C.off
	end
	return line
end

function BF:ItemHeader(item)
	local C = self.COLOR
	local count = table.getn(item.sources)
	local spots = count == 1 and "1 spot" or (count .. " spots")
	return C.item .. item.name .. C.off .. " " .. C.dim .. "(" .. item.category .. ", " .. spots .. ")" .. C.off
end

--[[ Flat list of display lines for a set of results, used by the window and,
  with the same text, by the chat output. maxItems keeps a broad query such as
  "/farm cloth" from flooding either one. ------------------------------------]]
function BF:BuildLines(query, maxItems)
	local results = self:Search(query)
	local lines = {}
	local total = table.getn(results)
	maxItems = maxItems or 12

	if total == 0 then
		table.insert(lines, self.COLOR.dim .. "Nothing found for \"" .. query
			.. "\". Try part of a name, a zone, or a category." .. self.COLOR.off)
		return lines, 0
	end

	local shown = total
	if shown > maxItems then shown = maxItems end

	local i
	for i = 1, shown do
		local item = results[i].item
		table.insert(lines, self:ItemHeader(item))
		if item.note then
			table.insert(lines, "  " .. self.COLOR.note .. item.note .. self.COLOR.off)
		end
		local sources = self:SortedSources(item)
		local s
		for s = 1, table.getn(sources) do
			table.insert(lines, "  " .. self:SourceLine(sources[s]))
		end
		if i < shown then
			table.insert(lines, " ")
		end
	end

	if total > shown then
		table.insert(lines, " ")
		table.insert(lines, self.COLOR.dim .. "... and " .. (total - shown)
			.. " more items. Narrow the search to see them." .. self.COLOR.off)
	end

	return lines, total
end

function BF:PrintResults(query)
	local lines, total = self:BuildLines(query, 5)
	self:Print("results for " .. self.COLOR.item .. query .. self.COLOR.off
		.. " (" .. total .. " items):")
	local i
	for i = 1, table.getn(lines) do
		if BF.Trim(lines[i]) ~= "" then
			DEFAULT_CHAT_FRAME:AddMessage(lines[i])
		end
	end
end
