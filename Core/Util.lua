-- Blackthornes Farmer -- Core/Util.lua
-- Small text helpers shared by the search and the window.

local _, ns = ...

local Util = {}
ns.Util = Util

function Util.Trim(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Is the client in English? The data names items, zones and skills in
--- English, so only another language needs the client's own names looked
--- up. A client that will not say counts as English, as before.
function Util.EnglishClient()
    if type(GetLocale) ~= "function" then return true end
    local ok, locale = pcall(GetLocale)
    if not ok or type(locale) ~= "string" then return true end
    return locale == "enUS" or locale == "enGB"
end

--- Strip the |cffffffff ... |r escapes, so text can be measured or compared.
function Util.StripColor(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

function Util.Colored(colorKey, text)
    return ("|c%s%s|r"):format(ns.COLORS[colorKey] or ns.COLORS.text, text)
end

--- "1 spot" / "4 spots", because "1 spots" reads as a bug.
function Util.Plural(count, singular, plural)
    if count == 1 then return "1 " .. singular end
    return ("%d %s"):format(count, plural or (singular .. "s"))
end

--- A copy of `items` in the order a sortable heading asks for: by
--- `valueOf(item)` (a number or a string), lowest first when `ascending`,
--- else highest first. Items with nothing to sort by (nil) go last either
--- way, and ties keep the order they came in, so a heading never shuffles
--- rows it cannot tell apart.
function Util.SortBy(items, ascending, valueOf)
    local keyed = {}
    for index, item in ipairs(items or {}) do
        local value = valueOf(item)
        if type(value) == "string" then value = value:lower() end
        if value ~= nil and type(value) ~= "number" and type(value) ~= "string" then value = nil end
        keyed[index] = { item = item, value = value, position = index }
    end

    table.sort(keyed, function(a, b)
        if (a.value == nil) ~= (b.value == nil) then return b.value == nil end
        if a.value ~= nil and type(a.value) == type(b.value) and a.value ~= b.value then
            if ascending then return a.value < b.value end
            return a.value > b.value
        end
        return a.position < b.position
    end)

    local sorted = {}
    for index, entry in ipairs(keyed) do sorted[index] = entry.item end
    return sorted
end
