-- Blackthornes Farmer -- Logic/Search.lua
-- Ranked search over the database, and the display lines the window and the
-- chat output both print.
--
-- The ranking is the whole feature. One box has to answer two questions --
-- "where do I get this" and "what is worth farming here" -- without the second
-- ever burying the first, so an item whose *name* matches always outranks one
-- that merely happens to drop in a zone you named.

local _, ns = ...

local Search = ns.NewModule("Search")

local Util = ns.Util

local SCORE = {
    exact    = 100,
    prefix   = 60,
    infix    = 30,
    category = 20,
    zone     = 15,
    source   = 10,
}

--- How well `needle` matches `haystack`. Higher is better; 0 is no match.
local function MatchScore(haystack, needle)
    if not haystack or haystack == "" then return 0 end
    if haystack == needle then return SCORE.exact end

    local start = haystack:find(needle, 1, true)
    if start == 1 then return SCORE.prefix end
    if start then return SCORE.infix end

    return 0
end

--- Ranked search. Returns an array of { item, score, why }.
function Search:Run(query)
    local results = {}

    query = Util.Trim(query):lower()
    if query == "" then return results end

    for item in ns.DB:Iterate() do
        local score, why = MatchScore(item.name:lower(), query), "name"

        for _, alias in ipairs(item.aliases) do
            local aliasScore = MatchScore(alias:lower(), query)
            if aliasScore > score then
                score, why = aliasScore, "name"
            end
        end

        if score == 0 and MatchScore(item.category:lower(), query) > 0 then
            score, why = SCORE.category, "category"
        end

        if score == 0 then
            for _, source in ipairs(item.sources) do
                if MatchScore(source.zone:lower(), query) > 0 then
                    score, why = SCORE.zone, "zone"
                    break
                end

                -- A landmark is how people actually name a farming spot to
                -- each other: "Durnholde", "Raven Hill". Worth matching.
                if source.location and MatchScore(source.location:lower(), query) > 0 then
                    score, why = SCORE.zone, "location"
                    break
                end

                if source.name and MatchScore(source.name:lower(), query) > 0 then
                    score, why = SCORE.source, "source"
                    break
                end
            end
        end

        if score > 0 then
            results[#results + 1] = { item = item, score = score, why = why }
        end
    end

    table.sort(results, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.item.name < b.item.name
    end)

    return results
end

--- An item's sources, lowest level first, so the closest to your level is at
--- the top rather than wherever the data file happened to list it.
function Search:SortedSources(item)
    local sorted = {}
    for index, source in ipairs(item.sources) do
        sorted[index] = source
    end

    table.sort(sorted, function(a, b)
        local aLow, bLow = a.minLevel or 0, b.minLevel or 0
        if aLow ~= bLow then return aLow < bLow end

        local aHigh, bHigh = a.maxLevel or aLow, b.maxLevel or bLow
        if aHigh ~= bHigh then return aHigh < bHigh end

        return (a.zone or "") < (b.zone or "")
    end)

    return sorted
end

function Search:LevelText(source)
    if not source.minLevel then return "??" end

    if source.maxLevel and source.maxLevel ~= source.minLevel then
        return ("%d-%d"):format(source.minLevel, source.maxLevel)
    end

    return tostring(source.minLevel)
end

--- One source as a line, e.g.
---   [10-20] Westfall - Copper Vein (mining node, needs Mining 1)
--- A source with no name of its own -- a herb node, which is just called after
--- the herb -- drops the name rather than printing the kind twice.
function Search:SourceLine(source)
    local detail = ns.DB:KindLabel(source.kind)

    if source.requires then
        detail = detail .. ", needs " .. source.requires
    end

    if source.chance then
        detail = ("%s, ~%d%%"):format(detail, source.chance)
    end

    local line = ("%s %s"):format(
        Util.Colored("muted", "[" .. self:LevelText(source) .. "]"), source.zone)

    if source.name then
        line = line .. Util.Colored("muted", " - ") .. source.name
    end

    local where = ns.DB:WhereText(source)
    if where then
        line = line .. Util.Colored("muted", " @ ") .. where
    end

    line = line .. " " .. Util.Colored("accent", "(" .. detail .. ")")

    -- Only confirmed rows are marked. Tagging every Classic row instead would
    -- put a label on almost every line and say nothing.
    if source.provenance == "forever" then
        line = line .. " " .. Util.Colored("good", "[Forever]")
    end

    if source.note then
        line = line .. " " .. Util.Colored("muted", source.note)
    end

    return line
end

function Search:ItemHeader(item)
    return ("%s %s"):format(
        Util.Colored("text", item.name),
        Util.Colored("muted", ("(%s, %s)"):format(
            item.category, Util.Plural(#item.sources, "spot"))))
end

--- Flat display lines for a query, shared by the window and `/farm chat`.
-- @return lines, total number of matching items
function Search:BuildLines(query, maxItems)
    local results = self:Run(query)
    local total = #results
    local lines = {}

    maxItems = maxItems or 12

    if total == 0 then
        lines[1] = Util.Colored("muted",
            ('Nothing found for "%s". Try part of a name, a zone, or a category.')
            :format(query))
        return lines, 0
    end

    local shown = math.min(total, maxItems)

    for index = 1, shown do
        local item = results[index].item

        lines[#lines + 1] = self:ItemHeader(item)

        if item.note then
            lines[#lines + 1] = "  " .. Util.Colored("muted", item.note)
        end

        for _, source in ipairs(self:SortedSources(item)) do
            lines[#lines + 1] = "  " .. self:SourceLine(source)
        end

        if index < shown then
            lines[#lines + 1] = " "
        end
    end

    if total > shown then
        lines[#lines + 1] = " "
        lines[#lines + 1] = Util.Colored("muted",
            ("... and %d more. Narrow the search to see them."):format(total - shown))
    end

    return lines, total
end

--------------------------------------------------------------------------------
-- Rows for the window
--
-- The window draws columns rather than sentences, so it needs the parts, not a
-- formatted string. Chat still gets BuildLines above, because a chat frame has
-- no columns to draw into.
--------------------------------------------------------------------------------

--- @param opts { max = item cap, kind = only this source kind }
-- @return rows, matching item count, total sources drawn
function Search:BuildRows(query, opts)
    opts = opts or {}

    local maxItems = opts.max or 40
    local rows = {}

    local results = self:Run(query)
    local total = #results
    local drawn = 0

    if total == 0 then
        return rows, 0, 0
    end

    local shown = math.min(total, maxItems)

    for index = 1, shown do
        local item = results[index].item
        local sources = self:SortedSources(item)

        -- A kind filter that empties an item hides the item too, rather than
        -- leaving a heading with nothing under it.
        if opts.kind then
            local kept = {}
            for _, source in ipairs(sources) do
                if source.kind == opts.kind then
                    kept[#kept + 1] = source
                end
            end
            sources = kept
        end

        if #sources > 0 then
            rows[#rows + 1] = { type = "item", item = item, count = #sources }

            if item.note then
                rows[#rows + 1] = { type = "note", text = item.note }
            end

            for _, source in ipairs(sources) do
                rows[#rows + 1] = { type = "source", item = item, source = source }
                drawn = drawn + 1
            end
        end
    end

    if total > shown then
        rows[#rows + 1] = {
            type = "more",
            text = ("and %d more items. Narrow the search to see them."):format(total - shown),
        }
    end

    return rows, total, drawn
end

--- Which source kinds a query actually turns up, so the filter chips can show
--- only the ones worth clicking.
function Search:KindsInResults(query)
    local seen, order = {}, {}

    for _, result in ipairs(self:Run(query)) do
        for _, source in ipairs(result.item.sources) do
            if not seen[source.kind] then
                seen[source.kind] = true
                order[#order + 1] = source.kind
            end
        end
    end

    table.sort(order)
    return order
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

--- `/farm <text>`: search, and show the results in the window.
function ns.RunSearch(query)
    query = Util.Trim(query)
    if query == "" then return end

    if ns.UI and ns.UI.Search then
        ns.UI:Search(query)
    else
        ns.Search:PrintResults(query)
    end
end

function Search:PrintResults(query)
    local lines, total = self:BuildLines(query, 5)

    ns.Print(("results for %s (%s):"):format(
        Util.Colored("accent", query), Util.Plural(total, "item")))

    for _, line in ipairs(lines) do
        if Util.Trim(Util.StripColor(line)) ~= "" then
            ns.PrintRaw(line)
        end
    end
end

ns.RegisterCommand("chat", "print results to chat instead of the window", function(rest)
    if Util.Trim(rest) == "" then
        ns.Print("usage: /farm chat <text>")
        return
    end
    ns.Search:PrintResults(rest)
end)

ns.RegisterCommand("stats", "how much data is loaded", function()
    ns.Print(("%s, %s loaded"):format(
        Util.Plural(ns.DB:CountItems(), "item"),
        Util.Plural(ns.DB:CountSources(), "farming spot")))
end)

ns.RegisterCommand("data", "where the data came from", function()
    local counts = ns.DB:CountByProvenance()

    ns.Print("data sources:")

    for key, label in pairs(ns.DB.PROVENANCE) do
        ns.PrintRaw(("  %s  %s"):format(
            Util.Colored(key == "forever" and "good" or "muted",
                Util.Plural(counts[key] or 0, "spot")),
            Util.Colored("muted", label)))
    end

    ns.PrintRaw(Util.Colored("muted",
        "  Classic rows are leads, not gospel: Forever can differ."))
end)

ns.RegisterCommand("list", "list every item in the database", function()
    ns.Print(("database holds %s:"):format(Util.Plural(ns.DB:CountItems(), "item")))

    local row = {}
    for item in ns.DB:Iterate() do
        row[#row + 1] = item.name

        if #row == 4 then
            ns.PrintRaw("  " .. table.concat(row, ", "))
            row = {}
        end
    end

    if #row > 0 then
        ns.PrintRaw("  " .. table.concat(row, ", "))
    end
end)
