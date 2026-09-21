-- Blackthornes Farmer -- Core/Util.lua
-- Small text helpers shared by the search and the window.

local _, ns = ...

local Util = {}
ns.Util = Util

function Util.Trim(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
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
