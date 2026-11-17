-- Mulgore's Classic drop spots on Forever's own Mulgore map.
--
-- Forever's Mulgore map covers more ground than the one Classic's numbers
-- were measured on, so a Classic spot read on it landed north and west of
-- the mob (Tradeskills found it first, 2026-11-17, with Thunder Bluff's
-- trainers). Data/Data_ClassicDrops.lua is moved by tools/classic_maps.py.
-- What must hold:
--   1. Mobs that keep to one camp land where players looted them on
--      Forever (Data/Data_Harvested.lua).
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
local seen = {}
for _, r in ipairs(Rows("Data/Data_Harvested.lua")) do
  if r.zone == "Mulgore" then
    seen[r.name] = seen[r.name] or {}
    table.insert(seen[r.name], r)
  end
end

-- How far a Classic row is from the nearest spot the mob was looted at.
local function Off(row)
  local best
  for _, s in ipairs(seen[row.name] or {}) do
    local d = math.max(math.abs(s.x - row.x), math.abs(s.y - row.y))
    if not best or d < best then best = d end
  end
  return best
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
