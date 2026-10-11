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

--- Ranked search. Returns an array of { item, score, why, sources }.
--
-- `sources` is set when the item was found through some of its sources (a
-- zone, a landmark or a mob) and holds just those. A search for "defias"
-- wants the Defias, not every mob in the game that drops linen.
function Search:Run(query)
    local results = {}

    query = Util.Trim(query):lower()
    if query == "" then return results end

    -- A keystroke asks twice, once for the chips and once for the rows, so
    -- the last answer is kept while the data it came from stands. Callers
    -- never change what comes back.
    -- On a client in another language the names it gives the items are
    -- searched too ("leinen" finds Linen Cloth), read as they come in.
    ns.DB:LearnClientNames()

    local last = self.lastRun
    if last and last.query == query and last.changes == ns.DB.changes
        and last.names == ns.DB.namesVersion and last.skinning == ns.DB.skinningVersion then
        self.skinningHid = last.skinningHid
        return last.results
    end

    -- With skinning left out, an item that comes from skinning is no
    -- result at all ("Hide skinning", DB:HidesItem).
    self.skinningHid = false

    for item in ns.DB:Iterate() do
        local score, why = MatchScore(item.name:lower(), query), "name"
        local matched

        for _, alias in ipairs(item.aliases) do
            local aliasScore = MatchScore(alias:lower(), query)
            if aliasScore > score then
                score, why = aliasScore, "name"
            end
        end

        local clientName = ns.DB:ClientName(item)
        if clientName then
            local clientScore = MatchScore(clientName:lower(), query)
            if clientScore > score then score, why = clientScore, "name" end
        end

        if score == 0 and MatchScore(item.category:lower(), query) > 0 then
            score, why = SCORE.category, "category"
        end

        if score == 0 then
            for _, source in ipairs(item.sources) do
                local how

                if MatchScore(source.zone:lower(), query) > 0 then
                    how = "zone"

                -- A landmark is how people actually name a farming spot to
                -- each other: "Durnholde", "Raven Hill". Worth matching.
                elseif source.location and MatchScore(source.location:lower(), query) > 0 then
                    how = "location"

                elseif source.name and MatchScore(source.name:lower(), query) > 0 then
                    how = "source"
                end

                if how then
                    matched = matched or {}
                    matched[#matched + 1] = source

                    -- The first source that matches ranks the item; the
                    -- rest are only listed under it.
                    if score == 0 then
                        score, why = how == "source" and SCORE.source or SCORE.zone, how
                    end
                end
            end
        end

        if score > 0 and ns.DB:HidesItem(item) then
            self.skinningHid = true
        elseif score > 0 then
            results[#results + 1] = { item = item, score = score, why = why, sources = matched }
        end
    end

    table.sort(results, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.item.name < b.item.name
    end)

    self.lastRun = { query = query, changes = ns.DB.changes, names = ns.DB.namesVersion,
        skinning = ns.DB.skinningVersion, skinningHid = self.skinningHid, results = results }
    return results
end

--- An item's sources (or only `sources`, some of them), lowest level first,
--- so the closest to your level is at the top rather than wherever the data
--- file happened to list it.
function Search:SortedSources(item, sources)
    local sorted = {}
    for index, source in ipairs(sources or item.sources) do
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

--------------------------------------------------------------------------------
-- Sorting and grouping a search's spots
--
-- A player asked (2026-10-05) to sort by drop rate and by what a kill is
-- worth, to section by zone, and for the spots closest to them. The window's
-- column headings sort each item's spots (UI/Main.lua); with no heading
-- chosen they stay lowest level first, as SortedSources has them.
--
-- "Closest" knows no map distances, so it means: your own zone first, then
-- zones by how near their levels are to yours. A spot with nothing to sort
-- by (no drop rate, no worth) is never guessed at: it goes last, whichever
-- way round the sort runs.
--------------------------------------------------------------------------------

--- The player's level and zone, each nil when the client will not say.
function Search:Here()
    local level
    if UnitLevel then
        local ok, value = pcall(UnitLevel, "player")
        level = ok and ns.Harvest.ReadableNumber(value) or nil
        if level and level <= 0 then level = nil end
    end

    local zone = ns.Harvest and (ns.Harvest:Where()) or nil
    return level, zone
end

--- How far a spot is from you, for "closest": 0 up in your own zone, 1000 up
--- anywhere else, and within either, how many levels its band is from yours
--- (0 inside it). Nil when nothing is known: no zone or level of yours, and
--- no level on the spot.
function Search.Distance(source, level, zone)
    -- Your zone as the client names it, the data's in English (Spots.English
    -- knows the client's name once the map has told it).
    local Spots = ns.Spots
    local here = zone and (source.zone == zone
        or (Spots and Spots.English(source.zone) == Spots.English(zone)))
    local away = here and 0 or 1000

    local low = tonumber(source.minLevel)
    local high = tonumber(source.maxLevel) or low
    local gap = 50
    if level and low then
        if level < low then gap = low - level
        elseif level > high then gap = level - high
        else gap = 0 end
    elseif not zone then
        return nil
    end

    return away + gap
end

--- What a kill of the spot's mob is worth, and how sure: 2 your own tally,
--- 1 an estimate from the database's rates, nil no worth (not a mob, or
--- nothing priced). `cache` keeps each mob's answer for one draw.
function Search:Worth(source, cache)
    if not (source.name and (source.kind or "mob") == "mob" and ns.Value) then return nil end

    cache = cache or {}
    local known = cache[source.name]
    if known == nil then
        local worth, details = ns.Value:ForMob(source.name)
        known = worth and { worth = worth, sure = details and details.basis == "tally" and 2 or 1 } or false
        cache[source.name] = known
    end

    if not known then return nil end
    return known.worth, known.sure
end

-- The headings a search can be sorted by, and which way each starts:
-- names A to Z, levels and distance lowest first, rates and worth highest.
Search.SORT_KEYS = { name = true, where = true, level = true, drop = true, value = true }
Search.SORT_STARTS_LOW = { name = true, where = true, level = true }

--- `sources` (already lowest level first) in the order `sort` asks for:
--- { key = one of SORT_KEYS, ascending = true or false }, or nil to leave
--- them as they are. Ties, and spots with nothing to sort by, keep the order
--- they came in, the second lot after the rest.
function Search:SortSources(sources, sort, cache)
    local key = sort and sort.key
    if not (key and Search.SORT_KEYS[key]) then return sources end

    local level, zone = self:Here()
    local ascending = sort.ascending and true or false

    local keyed = {}
    for index, source in ipairs(sources) do
        local value, rank
        if key == "name" then
            value = (source.name or source.requires or ns.DB:KindLabel(source.kind) or ""):lower()
        elseif key == "where" then
            value = Search.Distance(source, level, zone)
        elseif key == "level" then
            value = tonumber(source.minLevel)
        elseif key == "drop" then
            value = tonumber(source.chance)
        elseif key == "value" then
            value, rank = self:Worth(source, cache)
        end
        keyed[index] = { source = source, value = value, rank = rank or 0, position = index }
    end

    table.sort(keyed, function(a, b)
        if (a.value == nil) ~= (b.value == nil) then return b.value == nil end
        if a.value == nil then return a.position < b.position end

        -- Your own tally's worth is never ranked in with an estimate's:
        -- estimates leave out coin and run low (Rankings keeps them apart
        -- the same way). Measured ones come first either way round.
        if a.rank ~= b.rank then return a.rank > b.rank end

        if a.value ~= b.value then
            if ascending then return a.value < b.value end
            return a.value > b.value
        end
        return a.position < b.position
    end)

    local sorted = {}
    for index, entry in ipairs(keyed) do sorted[index] = entry.source end
    return sorted
end

--- `sources` sectioned by zone: { { zone, sources = {...} }, ... }, the zones
--- in the order their first spot comes in, so whatever the spots are sorted
--- by, the zone with the best of them leads.
function Search.ByZone(sources)
    local groups, index = {}, {}
    for _, source in ipairs(sources) do
        local zone = source.zone or "?"
        local group = index[zone]
        if not group then
            group = { zone = zone, sources = {} }
            index[zone] = group
            groups[#groups + 1] = group
        end
        group.sources[#group.sources + 1] = source
    end
    return groups
end

function Search:LevelText(source)
    if not source.minLevel then return "??" end

    if source.maxLevel and source.maxLevel ~= source.minLevel then
        return ("%d-%d"):format(source.minLevel, source.maxLevel)
    end

    return tostring(source.minLevel)
end

--- A database drop rate as a line gives it: "~4%", or "<1%" for a rare
--- drop, which "%d" printed as "0%".
function Search:ChanceText(chance)
    local text = ns.Tracker.FormatChance(chance)
    if chance < 1 then return text end
    return "~" .. text
end

--- "12 spots", or "3 of 12 spots" when only some of them are shown.
function Search:SpotsText(shown, total)
    if shown < total then
        return ("%d of %s"):format(shown, Util.Plural(total, "spot"))
    end
    return Util.Plural(total, "spot")
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
        detail = ("%s, %s"):format(detail, self:ChanceText(source.chance))
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

--- `shown` is how many of its spots are listed under it, when not all.
function Search:ItemHeader(item, shown)
    return ("%s %s"):format(
        Util.Colored("text", item.name),
        Util.Colored("muted", ("(%s, %s)"):format(
            item.category, self:SpotsText(shown or #item.sources, #item.sources))))
end

--- What an empty search says. When skinning is left out and that is what
--- emptied it, it says so, rather than that nothing is known.
function Search:NothingFoundText(query)
    if self.skinningHid then
        return ('Only skinning has "%s", and skinning is left out. Untick Hide skinning '
            .. "in Settings (Loot), or type /farm skinning."):format(query)
    end
    return ('Nothing found for "%s". Try part of a name, a zone, or a category.'):format(query)
end

--- Flat display lines for a query, shared by the window and `/farm chat`.
-- @return lines, total number of matching items
function Search:BuildLines(query, maxItems)
    local results = self:Run(query)
    local total = #results
    local lines = {}

    maxItems = maxItems or 12

    if total == 0 then
        lines[1] = Util.Colored("muted", self:NothingFoundText(query))
        return lines, 0
    end

    local shown = math.min(total, maxItems)

    for index = 1, shown do
        local result = results[index]
        local item = result.item
        local sources = self:SortedSources(item, result.sources)

        lines[#lines + 1] = self:ItemHeader(item, #sources)

        if item.note then
            lines[#lines + 1] = "  " .. Util.Colored("muted", item.note)
        end

        for _, source in ipairs(sources) do
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

--- @param opts { max = item cap, kind = only this source kind, sort = { key,
---   ascending } (SortSources), byZone = a "zone" row over each zone's spots }
-- @return rows, matching item count, total sources drawn
function Search:BuildRows(query, opts)
    opts = opts or {}

    local maxItems = opts.max or 40
    local rows = {}
    local total, drawn = 0, 0
    -- The caller's per-draw worth cache, when it has one, so a mob priced
    -- for the sort is not priced again for the row.
    local worth = opts.worth or {}

    -- The kind filter comes before the cap. Capped first, a chip could show
    -- nothing but "and 55 more items" while its kind sat further down.
    for _, result in ipairs(self:Run(query)) do
        local item = result.item
        local sources = self:SortedSources(item, result.sources)

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
            total = total + 1
        end

        -- Past the cap an item is only counted, for the "more" line.
        if #sources > 0 and total <= maxItems then
            rows[#rows + 1] = { type = "item", item = item, count = #sources }

            if item.note then
                rows[#rows + 1] = { type = "note", text = item.note }
            end

            sources = self:SortSources(sources, opts.sort, worth)

            if opts.byZone then
                for _, group in ipairs(Search.ByZone(sources)) do
                    rows[#rows + 1] = { type = "zone", item = item, zone = group.zone,
                        count = #group.sources }
                    for _, source in ipairs(group.sources) do
                        rows[#rows + 1] = { type = "source", item = item, source = source }
                        drawn = drawn + 1
                    end
                end
            else
                for _, source in ipairs(sources) do
                    rows[#rows + 1] = { type = "source", item = item, source = source }
                    drawn = drawn + 1
                end
            end
        end
    end

    if total > maxItems then
        rows[#rows + 1] = {
            type = "more",
            text = ("and %d more items. Narrow the search to see them."):format(total - maxItems),
        }
    end

    return rows, total, drawn
end

--- Which source kinds a query actually turns up, so the filter chips can show
--- only the ones worth clicking.
function Search:KindsInResults(query)
    local seen, order = {}, {}

    for _, result in ipairs(self:Run(query)) do
        for _, source in ipairs(result.sources or result.item.sources) do
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

-- The kinds of material the search window suggests for your level, in the
-- order it shows them.
Search.SUGGEST_CATEGORIES = { "Cloth", "Leatherworking", "Mining", "Herbalism" }

--- One item per suggested category that suits a character of `level`: the
--- one with the most places whose level band takes it in. Nothing for a
--- category where no band does. For the empty search window. With your
--- gathering skills (`skills`, Spots.Skills; read here when not given), a
--- node or herb a profession you have cannot take yet is not counted, so a 20-Mining
--- miner is never offered Mithril.
function Search:ForLevel(level, skills)
    level = tonumber(level) or 0
    if level <= 0 then return {} end
    if skills == nil and ns.Spots and ns.Spots.Skills then
        local ok, read = pcall(ns.Spots.Skills)
        skills = ok and read or nil
    end
    local player = skills and { skills = skills } or nil

    local best = {}

    for item in ns.DB:Iterate() do
        local fits = 0
        if ns.DB:HidesItem(item) then fits = -1 end
        for _, source in ipairs(item.sources) do
            local low = tonumber(source.minLevel)
            local high = tonumber(source.maxLevel) or (low and low + 10)
            local profession, needed, have
            if player then profession, needed, have = ns.Spots.SkillNeed(source, player) end
            local canGather = not profession or have == nil or have >= needed
            if fits >= 0 and canGather and low and low <= level and level <= high then fits = fits + 1 end
        end

        local pick = best[item.category]
        if fits > 0 and (not pick or fits > pick.fits) then
            best[item.category] = { item = item, fits = fits }
        end
    end

    local picks = {}
    for _, category in ipairs(self.SUGGEST_CATEGORIES) do
        if best[category] then picks[#picks + 1] = best[category].item end
    end
    return picks
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

-- Skinning shown or left out (DB:SetShowSkinning, the Settings row "Show
-- skinning").
ns.RegisterCommand("skinning", "show skinning, or leave it out and show only drops: on or off", function(rest)
    local word = Util.Trim(rest or ""):lower()
    local on
    if word == "on" or word == "show" then
        on = true
    elseif word == "off" or word == "hide" then
        on = false
    else
        on = not ns.DB:ShowsSkinning()
    end
    ns.DB:SetShowSkinning(on)
    ns.Print(on and "skinning is shown again."
        or "skinning is left out: only drops are shown. /farm skinning puts it back.")
    if ns.SettingsUI then ns.SettingsUI:Refresh() end
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
