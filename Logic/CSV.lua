-- Blackthornes Farmer -- Logic/CSV.lua
-- Your counts as a spreadsheet (a player asked, the owner agreed 2026-10-12).
--
-- An addon cannot write files, so this is text for the Export window: copy
-- it, paste it into Notepad and save it as a .csv, or paste it straight into
-- a spreadsheet. One sheet a kind of count, each with its own heading row:
--
--   loot       a row per mob and item: corpses looted, times it dropped,
--              how many came, the drop rate and what one is worth
--   kills      a row per mob: kills, coin looted, coin and worth per kill
--   gathering  a row per node and item: times gathered, what it gave
--   fishing    a row per spot and item: casts, what it gave
--
-- It reads the same tables as the rest of the addon and changes nothing.
-- Counts only: no character, goal, setting or position beyond a record's own
-- zone and spot. What the player hides (skinning, the hide list) is left out,
-- as everywhere else. Built a few records a frame, never in a fight, and a
-- big sheet comes in parts, each with its heading row, so each part pastes on
-- its own.

local _, ns = ...
local L = ns.L

local CSV = ns.NewModule("CSV")

-- Records worked through a frame.
CSV.STEP = 60
-- Characters in one part, cut at a line, so the copy box never chokes.
CSV.PART_CHARS = 150000

CSV.SHEETS = { "loot", "kills", "gathering", "fishing" }
CSV.LABELS = {
    loot = L["Loot"],
    kills = L["Kills"],
    gathering = L["Gathering"],
    fishing = L["Fishing"],
}

--------------------------------------------------------------------------------
-- Fields
--------------------------------------------------------------------------------

--- One field as CSV writes it. Text with a comma, quote or line break is
--- quoted; text a spreadsheet would read as a formula (= + - @) is led by an
--- apostrophe, since names can come from another player's string.
function CSV.Field(value)
    if value == nil then return "" end
    if type(value) == "number" then
        if value ~= value then return "" end
        if value == math.floor(value) and math.abs(value) < 2 ^ 53 then
            return ("%d"):format(value)
        end
        return (("%.4f"):format(value):gsub("0+$", ""):gsub("%.$", ""))
    end

    local text = tostring(value):gsub("|", "")
    if text:match("^[=+%-@\t\r]") then text = "'" .. text end
    if text:find('[,"\r\n]') then
        text = '"' .. text:gsub('"', '""') .. '"'
    end
    return text
end

local function Line(fields, count)
    local out = {}
    for index = 1, count do out[index] = CSV.Field(fields[index]) end
    return table.concat(out, ",")
end

local function Gold(copper)
    if type(copper) ~= "number" then return nil end
    return math.floor(copper + 0.5) / 10000
end

local function Percent(part, whole)
    part, whole = tonumber(part), tonumber(whole)
    if not part or not whole or whole <= 0 then return nil end
    return math.floor(part / whole * 10000 + 0.5) / 100
end

local function Zone(zone)
    if ns.Spots and ns.Spots.Show then return ns.Spots.Show(zone) end
    return zone
end

local function Coord(coords, index)
    if type(coords) ~= "table" or type(coords[index]) ~= "number" then return nil end
    return math.floor(coords[index] * 10 + 0.5) / 10
end

local function HidesItem(name)
    return ns.DB ~= nil and ns.DB:HidesItem(name)
end

local function HidesSource(name)
    return ns.DB ~= nil and type(name) == "string" and ns.DB:IsHiddenSource(name)
end

-- What one is worth, in gold, kept for the build so an item is priced once.
local function Pricer()
    local kept = {}
    return function(name, id)
        local key = id or name
        if kept[key] == nil then
            local Value = ns.Value
            local price = false
            if Value then
                local ok, unit = pcall(function()
                    return Value:UnitPrice(id or Value:ItemID(name))
                end)
                if ok and unit then price = Gold(unit) end
            end
            kept[key] = price
        end
        return kept[key] or nil
    end
end

local function SortedNames(map)
    local names = {}
    if type(map) == "table" then
        for name, entry in pairs(map) do
            if type(name) == "string" and entry ~= nil and not HidesItem(name) then
                names[#names + 1] = name
            end
        end
    end
    table.sort(names)
    return names
end

--------------------------------------------------------------------------------
-- Sheets
--------------------------------------------------------------------------------

-- Each sheet: its heading row, the records to work through (sorted, so the
-- same counts always give the same text) and the rows one record makes.

local SHEETS = {}

SHEETS.loot = {
    head = function()
        return { L["Mob"], L["Zone"], L["Subzone"], L["Min level"], L["Max level"], "X", "Y",
            L["Corpses looted"], L["Item"], L["Item ID"], L["Times dropped"], L["Items looted"],
            L["Drop %"], L["Value each (gold)"] }
    end,
    records = function()
        local list = {}
        for _, record in pairs(ns.Harvest and ns.Harvest.records or {}) do
            if type(record) == "table" and type(record.mob) == "string" and not HidesSource(record.mob) then
                list[#list + 1] = record
            end
        end
        table.sort(list, function(a, b)
            if a.mob ~= b.mob then return a.mob < b.mob end
            if (a.zone or "") ~= (b.zone or "") then return (a.zone or "") < (b.zone or "") end
            return (a.location or "") < (b.location or "")
        end)
        return list
    end,
    rows = function(record, price, add)
        local base = { record.mob, Zone(record.zone), record.location, record.minLevel,
            record.maxLevel or record.minLevel, Coord(record.coords, 1), Coord(record.coords, 2),
            tonumber(record.corpses) or 0 }
        local any = false
        for _, name in ipairs(SortedNames(record.items)) do
            local entry = record.items[name]
            if type(entry) == "table" then
                any = true
                local row = { unpack(base, 1, 8) }
                row[9] = name
                row[10] = entry.id
                row[11] = tonumber(entry.corpses) or 0
                row[12] = tonumber(entry.count) or 0
                row[13] = Percent(entry.corpses, record.corpses)
                row[14] = price(name, entry.id)
                add(row)
            end
        end
        -- Coin alone, or nothing: the corpses still count.
        if not any then add(base) end
    end,
}

SHEETS.kills = {
    head = function()
        return { L["Mob"], L["Kills"], L["Coin looted (gold)"], L["Coin per kill (gold)"],
            L["Worth per kill (gold)"] }
    end,
    records = function()
        local Tracker = ns.Tracker
        local mobs = Tracker and Tracker:Store() or {}
        local list = {}
        for name, mob in pairs(mobs) do
            if type(name) == "string" and type(mob) == "table" and not HidesSource(name) then
                list[#list + 1] = { name = name, mob = mob }
            end
        end
        table.sort(list, function(a, b)
            local ka, kb = tonumber(a.mob.kills) or 0, tonumber(b.mob.kills) or 0
            if ka ~= kb then return ka > kb end
            return a.name < b.name
        end)
        return list
    end,
    rows = function(record, _, add)
        local Tracker, Value = ns.Tracker, ns.Value
        local mob = record.mob
        local coin = (tonumber(mob.copper) or 0) + (tonumber(mob.oldCopper) or 0)
        local perKill = Tracker and Tracker:CoinPerKill(record.name)
        local worth
        if Value then
            local ok, value = pcall(Value.FromTally, Value, record.name)
            if ok then worth = value end
        end
        add({ record.name, tonumber(mob.kills) or 0, Gold(coin), Gold(perKill), Gold(worth) })
    end,
}

SHEETS.gathering = {
    head = function()
        return { L["Node"], L["Kind"], L["Zone"], L["Subzone"], "X", "Y", L["Times gathered"],
            L["Item"], L["Item ID"], L["Times it gave"], L["Items gathered"], L["Gave %"],
            L["Value each (gold)"] }
    end,
    records = function()
        local db = ns.db
        local nodes = type(db) == "table" and type(db.gathering) == "table" and db.gathering.nodes or {}
        local list = {}
        for _, node in pairs(nodes) do
            if type(node) == "table" and not HidesSource(node.node) then list[#list + 1] = node end
        end
        table.sort(list, function(a, b)
            if (a.node or "") ~= (b.node or "") then return (a.node or "") < (b.node or "") end
            if (a.zone or "") ~= (b.zone or "") then return (a.zone or "") < (b.zone or "") end
            return (a.location or "") < (b.location or "")
        end)
        return list
    end,
    rows = function(node, price, add)
        local base = { node.node, node.kind, Zone(node.zone), node.location,
            Coord(node.coords, 1), Coord(node.coords, 2), tonumber(node.gathers) or 0 }
        local any = false
        for _, name in ipairs(SortedNames(node.items)) do
            local entry = node.items[name]
            if type(entry) == "table" then
                any = true
                local row = { unpack(base, 1, 7) }
                row[8] = name
                row[9] = entry.id
                row[10] = tonumber(entry.gathers) or 0
                row[11] = tonumber(entry.count) or 0
                row[12] = Percent(entry.gathers, node.gathers)
                row[13] = price(name, entry.id)
                add(row)
            end
        end
        if not any then add(base) end
    end,
}

SHEETS.fishing = {
    head = function()
        return { L["Spot"], L["Zone"], L["Subzone"], "X", "Y", L["Casts"], L["Item"], L["Item ID"],
            L["Times caught"], L["Items caught"], L["Catch %"], L["Value each (gold)"] }
    end,
    records = function()
        local db = ns.db
        local spots = type(db) == "table" and type(db.fishing) == "table" and db.fishing.spots or {}
        local list = {}
        for _, spot in pairs(spots) do
            if type(spot) == "table" and not HidesSource(spot.school) then list[#list + 1] = spot end
        end
        table.sort(list, function(a, b)
            if (a.zone or "") ~= (b.zone or "") then return (a.zone or "") < (b.zone or "") end
            if (a.location or "") ~= (b.location or "") then return (a.location or "") < (b.location or "") end
            return (a.school or "") < (b.school or "")
        end)
        return list
    end,
    rows = function(spot, price, add)
        local school = spot.school
        if school == nil or school == "" or school == "open water" then school = L["open water"] end
        local base = { school, Zone(spot.zone), spot.location, Coord(spot.coords, 1),
            Coord(spot.coords, 2), tonumber(spot.casts) or 0 }
        local any = false
        for _, name in ipairs(SortedNames(spot.items)) do
            local entry = spot.items[name]
            if type(entry) == "table" then
                any = true
                local row = { unpack(base, 1, 6) }
                row[7] = name
                row[8] = entry.id
                row[9] = tonumber(entry.casts) or 0
                row[10] = tonumber(entry.count) or 0
                row[11] = Percent(entry.casts, spot.casts)
                row[12] = price(name, entry.id)
                add(row)
            end
        end
        if not any then add(base) end
    end,
}

CSV.Sheets = SHEETS

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

local function InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

--- Cut `lines` (heading first) into parts of about PART_CHARS, each led by
--- the heading row.
function CSV.Parts(lines)
    local head = lines[1] or ""
    local parts, current, size = {}, { head }, #head
    for index = 2, #lines do
        local line = lines[index]
        if size + #line + 1 > CSV.PART_CHARS and #current > 1 then
            parts[#parts + 1] = table.concat(current, "\n")
            current, size = { head }, #head
        end
        current[#current + 1] = line
        size = size + #line + 1
    end
    parts[#parts + 1] = table.concat(current, "\n")
    return parts
end

--- Build sheet `key`, a few records a frame, then `done(parts, rows)`:
--- parts is a list of CSV texts, rows how many rows below the heading.
function CSV:Build(key, done)
    local sheet = SHEETS[key]
    if not sheet then done(nil, 0) return end

    local head = sheet.head()
    local width = #head
    local lines = { Line(head, width) }
    local records = sheet.records()
    local price = Pricer()
    local function add(fields) lines[#lines + 1] = Line(fields, width) end

    local index = 1
    local function Step()
        if InCombat() then C_Timer.After(2, Step) return end
        local stop = math.min(#records, index + CSV.STEP - 1)
        while index <= stop do
            sheet.rows(records[index], price, add)
            index = index + 1
        end
        if index <= #records then
            C_Timer.After(0, Step)
        else
            done(CSV.Parts(lines), #lines - 1)
        end
    end
    Step()
end

--- The sheet a typed word means ("loot", "kills", "gathering", "fishing",
--- or the start of one), or nil.
function CSV.SheetFor(text)
    text = tostring(text or ""):lower()
    if text == "" then return "loot" end
    for _, key in ipairs(CSV.SHEETS) do
        if key:sub(1, #text) == text then return key end
    end
    if text == "drops" or text == "harvest" then return "loot" end
    if text == "fish" then return "fishing" end
    return nil
end

--- Show sheet `key` in the Export window, part `part` (1 by default), with
--- buttons for the other sheets.
function CSV:Show(key, part)
    key = key or "loot"
    self.showing = key
    CSV:Build(key, function(parts, rows)
        -- Another sheet was picked while this one was being built.
        if CSV.showing ~= key or not parts then return end
        part = math.max(1, math.min(part or 1, #parts))
        local title = L.Format("Spreadsheet: %s", CSV.LABELS[key] or key)
        local nav
        if #parts > 1 then
            title = L.Format("%s (part %d of %d)", title, part, #parts)
            nav = { index = part, count = #parts, step = function(delta) CSV:Show(key, part + delta) end }
        end
        local text = parts[part]
        if rows == 0 then
            text = text .. "\n"
        end
        ns.UI:ShowExport(text, title, nav, {
            sheets = CSV.SHEETS, labels = CSV.LABELS, current = key,
            pick = function(sheet) CSV:Show(sheet) end,
            hint = rows == 0 and L["Nothing recorded here yet."]
                or L["Press Ctrl+C. Paste into Notepad and save as farmer.csv, or into a spreadsheet."],
        })
    end)
end
