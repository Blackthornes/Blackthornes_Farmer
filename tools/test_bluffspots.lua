-- Mulgore's Classic drop spots on Forever's own Mulgore map.
--
-- Forever's Mulgore map covers more ground than the one Classic's numbers
-- were measured on, so a Classic spot read on it landed north and west of
-- the mob (Tradeskills found it first, 2026-11-17, with Thunder Bluff's
-- trainers). Data/Data_ClassicDrops.lua is moved by tools/classic_maps.py.
-- What must hold:
--   1. Mobs that keep to one camp land where players looted them on
--      Forever (SEEN below).
--   2. Classic's Mulgore spots, taken together, land nearer Forever's.
--   3. Other zones are left as they were.

local failures = 0
local function check(label, got, want)
  if got == want then
    print("  ok   " .. label)
  else
    failures = failures + 1
    print(string.format("  FAIL %s: got %s, want %s", label, tostring(got), tostring(want)))
  end
end

-- Every source row of a data file, by zone and mob name.
local function Rows(path)
  local rows = {}
  local DB = {}
  function DB:RegisterItem(item)
    for _, s in ipairs(item.sources or {}) do
      if s.coords and s.name then
        rows[#rows + 1] = { name = s.name, zone = s.zone, x = s.coords[1], y = s.coords[2] }
      end
    end
  end
  assert(loadfile(lfs_cwd .. "/" .. path))("Blackthornes_Farmer", { DB = DB })
  return rows
end

local classic = Rows("Data/Data_ClassicDrops.lua")

-- Where players looted each mob in Mulgore on Forever, from
-- Data/Data_Harvested.lua on 2026-11-17. Kept here, not read from that file,
-- because tools/test_harvest_import.py runs these suites on other drop data.
local SEEN = {
  ["Adult Plainstrider"] = { 47.9, 69.6 }, ["Bael'dun Appraiser"] = { 34.4, 53.5 },
  ["Bael'dun Digger"] = { 33.8, 52.7 }, ["Battleboar"] = { 51.6, 79.0 },
  ["Bristleback Battleboar"] = { 60.3, 80.9 }, ["Bristleback Quilboar"] = { 56.9, 79.2 },
  ["Bristleback Shaman"] = { 59.8, 82.3 }, ["Elder Plainstrider"] = { 51.4, 27.6 },
  ["Flatland Cougar"] = { 52.5, 51.5 }, ["Flatland Prowler"] = { 49.5, 24.4 },
  ["Mountain Cougar"] = { 44.2, 87.7 }, ["Plainstrider"] = { 45.1, 78.2 },
  ["Prairie Stalker"] = { 52.6, 52.5 }, ["Prairie Wolf"] = { 40.9, 73.6 },
  ["Prairie Wolf Alpha"] = { 55.8, 36.1 }, ["Swoop"] = { 46.0, 51.4 },
  ["Taloned Swoop"] = { 55.6, 37.5 }, ["Venture Co. Taskmaster"] = { 43.8, 51.2 },
  ["Windfury Harpy"] = { 61.8, 69.6 }, ["Windfury Matriarch"] = { 33.9, 37.0 },
  ["Windfury Sorceress"] = { 33.0, 36.8 }, ["Windfury Wind Witch"] = { 62.2, 70.1 },
  ["Wiry Swoop"] = { 44.7, 72.3 },
}

-- How far a Classic row is from the nearest spot the mob was looted at.
local function Off(row)
  local s = SEEN[row.name]
  return s and math.max(math.abs(s[1] - row.x), math.abs(s[2] - row.y))
end

print("")
print("bluff spots")

-- 1. Camp mobs: the quilboar, the dwarves' dig and the goblins' mine.
local CAMPS = { ["Bael'dun Appraiser"] = true, ["Bael'dun Digger"] = true,
  ["Venture Co. Taskmaster"] = true, ["Bristleback Quilboar"] = true }
local camps, near = 0, 0
for _, row in ipairs(classic) do
  if row.zone == "Mulgore" and CAMPS[row.name] and Off(row) then
    camps = camps + 1
    if Off(row) <= 2 then
      near = near + 1
    else
      print(string.format("  %s: %.1f, %.1f is %.1f from where it was looted", row.name, row.x, row.y, Off(row)))
    end
  end
end
check("camp mobs are compared", camps >= 4, true)
check("every camp mob lands where it was looted", near, camps)

-- 2. All of Mulgore together.
local total, count = 0, 0
for _, row in ipairs(classic) do
  if row.zone == "Mulgore" and Off(row) then
    total, count = total + Off(row), count + 1
  end
end
check("Mulgore mobs are compared", count >= 20, true)
check("Mulgore's spots are on average within 5 of Forever's", count > 0 and total / count < 5, true)

-- 3. Another zone stays as Classic had it.
local tirisfal
for _, row in ipairs(classic) do
  if row.zone == "Tirisfal Glades" and row.name == "Rattlecage Soldier" then tirisfal = row end
end
check("Tirisfal's spots are left alone", tirisfal and tirisfal.x == 45.8 and tirisfal.y == 40.4, true)

print("")
if failures > 0 then error(string.format("%d bluff spot check(s) failed", failures)) end
print("  all bluff spot checks passed")
print("")
