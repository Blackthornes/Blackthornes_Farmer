-- Big damage numbers off mobs.
--
-- What matters: off until ticked, and nothing shows while off; ticked, the
-- game's own numbers go off with the player's value kept, and come back
-- when unticked (never in a fight: it waits); a hit on a mob's nameplate
-- shows its number there, a crit bigger with a ring and sparks; the
-- target with no nameplate shows just above the character, and one with a
-- nameplate never twice; misses, heals, friends and other people's mobs
-- show nothing; hits in a row count a combo; a hit that kills becomes the
-- killing blow with the kill count, rings and coins; a secret amount shows
-- without raising; the pools never grow past their caps and the driver
-- stops once nothing moves; How Big and Combo are saved; /farm
-- numbers and the Settings rows turn it all on and off.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("damagenumbers")

local ns = env.Load({ ui = true })
local DN = ns.DamageNumbers
DN:OnEnable()
local handler = _G.BlackthornesFarmerEventFrame:GetScript("OnEvent")
local function Fire(event, ...) handler(_G.BlackthornesFarmerEventFrame, event, ...) end

local now = 1000
_G.GetTime = function() return now end

local cvars = { floatingCombatTextCombatDamage = "1" }
_G.C_CVar = {
    GetCVar = function(name) return cvars[name] end,
    SetCVar = function(name, value) cvars[name] = value return true end,
}
local fighting = false
_G.InCombatLockdown = function() return fighting end

local units, plates = {}, {}
_G.UnitGUID = function(unit) return units[unit] and units[unit].guid end
_G.UnitName = function(unit) return units[unit] and units[unit].name end
_G.UnitCanAttack = function(_, unit) return units[unit] ~= nil and not units[unit].friendly end
_G.UnitIsTapDenied = function(unit) return units[unit] and units[unit].tapped or false end
_G.UnitIsDead = function(unit) return units[unit] and units[unit].dead or false end
_G.UnitIsPlayer = function() return false end
_G.UnitPlayerControlled = function() return false end
_G.C_NamePlate = { GetNamePlateForUnit = function(unit) return plates[unit] end }

local function Mob(token, name, guid, withPlate)
    units[token] = { name = name, guid = guid }
    if withPlate then
        plates[token] = CreateFrame("Frame")
        plates[token]._cx, plates[token]._cy = 400, 300
    else
        plates[token] = nil
    end
end

local function Plain(text)
    return (text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

local function Run(seconds)
    local steps = math.floor(seconds / 0.05 + 0.5)
    for _ = 1, steps do
        now = now + 0.05
        DN:Step(0.05)
    end
end

local function Live(pool)
    local count = 0
    for _, each in ipairs(pool) do if each.active then count = count + 1 end end
    return count
end

-- Off until ticked.
suite.check("off until ticked", not DN:IsEnabled())
Mob("nameplate1", "Plainstrider", "Creature-0-1-2-3-2955-00000001", true)
suite.check("nothing shows while off", DN:OnHit("nameplate1", "WOUND", nil, 25) == nil)
suite.check("the game's numbers are left alone", cvars.floatingCombatTextCombatDamage == "1")

-- Ticked.
DN:SetEnabled(true)
suite.check("ticked, the game's own numbers go away", cvars.floatingCombatTextCombatDamage == "0")
suite.check("and the player's value is kept",
    ns.db.damageNumbersCVars.floatingCombatTextCombatDamage == "1")

local n = DN:OnHit("nameplate1", "WOUND", nil, 25)
suite.check("a hit shows its number", n and n.text:GetText() == "25", n and n.text:GetText())
suite.check("on the mob's nameplate", n and n.anchor.plate == plates.nameplate1)
suite.check("as a plain hit", n and n.kind == "hit")

local crit = DN:OnHit("nameplate1", "WOUND", "CRITICAL", 61)
local critSize = crit and crit.text.fontSize
local pools = DN:Pools()
suite.check("a crit is bigger", crit and crit.kind == "crit"
    and crit.text.fontSize > n.text.fontSize, crit and crit.text.fontSize)
suite.check("with no word over it", crit and crit.tag == nil)
suite.check("a ring and sparks", Live(pools.rings) == 1 and Live(pools.sparks) > 0)
suite.check("the combo counts two hits", pools.combo and pools.combo.active
    and pools.combo.count:GetText() == "x2", pools.combo and pools.combo.count:GetText())

suite.check("a miss shows nothing", DN:OnHit("nameplate1", "MISS", nil, 0) == nil)
suite.check("a heal shows nothing", DN:OnHit("nameplate1", "HEAL", nil, 30) == nil)
suite.check("an absorbed hit shows nothing", DN:OnHit("nameplate1", "WOUND", nil, 0) == nil)

Mob("nameplate2", "Kodo", "Creature-0-1-2-3-2955-00000002", true)
units.nameplate2.tapped = true
suite.check("someone else's mob shows nothing", DN:OnHit("nameplate2", "WOUND", nil, 30) == nil)
units.nameplate2.tapped, units.nameplate2.friendly = false, true
suite.check("a friend shows nothing", DN:OnHit("nameplate2", "WOUND", nil, 30) == nil)
suite.check("the player shows nothing", DN:OnHit("player", "WOUND", nil, 30) == nil)

-- The target: at the spot when it has no nameplate, never twice when it does.
units.target = units.nameplate1
plates.target = plates.nameplate1
suite.check("a target with a nameplate is not shown twice", DN:OnHit("target", "WOUND", nil, 12) == nil)
Mob("target", "Bristleback", "Creature-0-1-2-3-3258-00000003", false)
UIParent._width, UIParent._height = 1024, 768
local spot = DN:OnHit("target", "WOUND", nil, 12)
local sx, sy = DN.Where(spot.anchor)
suite.check("one with none shows at the spot", spot and not spot.anchor.plate
    and sx == 512 + DN.SPOT_X and sy == 384 + DN.SPOT_Y, ("%s,%s"):format(sx, sy))

-- Combos heat up and a fifth hit rings.
for amount = 1, 3 do DN:OnHit("nameplate1", "WOUND", nil, amount) end
suite.check("five hits in a row are x5", pools.combo.count:GetText() == "x5", pools.combo.count:GetText())
local r, g = pools.combo.count._color[1], pools.combo.count._color[2]
suite.check("and the combo turns orange", r == 1 and g < 0.6, g)
Run(DN.COMBO_WINDOW + 0.2)
DN:OnHit("nameplate1", "WOUND", nil, 4)
suite.check("a pause starts the combo over", not pools.combo.active)

-- The kill.
ns.db.tracker = ns.db.tracker or {}
ns.db.tracker.mobs = ns.db.tracker.mobs or {}
ns.db.tracker.mobs.Plainstrider = { kills = 7, items = {} }
ns.KillTooltip.ForgetKept()
local last = DN:OnHit("nameplate1", "WOUND", nil, 40)
units.nameplate1.dead = true
Run(0.1)
suite.check("the hit that kills becomes the killing blow", last.kind == "kill")
suite.check("bigger than a crit", last.text.fontSize > critSize, last.text.fontSize)
suite.check("and the kill count coming under it", Plain(last.sub:GetText()) == "8/20", last.sub:GetText())
suite.check("with coins", Live(pools.coins) > 0)
units.nameplate1.dead = false

-- A nameplate that goes as the mob dies still makes the killing blow.
local gone = DN:OnHit("nameplate1", "WOUND", nil, 33)
units.nameplate1.dead = true
DN:PlateGone("nameplate1")
suite.check("a kill heard as the plate goes", gone.kind == "kill")
units.nameplate1.dead = false

-- Smaller and the combo off.
ns.HandleSlash("numbers some")
suite.check("/farm numbers some saves it", ns.db.damageNumbersSize == "some")
local small = DN:OnHit("nameplate1", "WOUND", nil, 9)
suite.check("and the numbers come out smaller", small.text.fontSize < n.text.fontSize)
DN:SetComboOn(false)
DN:OnHit("nameplate1", "WOUND", nil, 9)
suite.check("with the combo off, no counter", not pools.combo.active)
DN:SetComboOn(true)
ns.HandleSlash("numbers most")

-- A secret amount shows as it is.
local secret = env.Secret("number")
_G.issecretvalue = function(value) return value == secret end
local ok, hidden = pcall(DN.OnHit, DN, "nameplate1", "WOUND", nil, secret)
suite.check("a secret amount doesn't raise", ok, hidden)
suite.check("and still shows", ok and hidden ~= nil)
_G.issecretvalue = nil

-- Caps, and the driver stops.
for i = 1, 60 do DN:OnHit("nameplate1", "WOUND", "CRITICAL", i) end
suite.check("the numbers never pass their cap", #pools.numbers <= DN.MOST_NUMBERS, #pools.numbers)
suite.check("nor the sparks", #pools.sparks <= DN.MOST_SPARKS, #pools.sparks)
suite.check("nor the rings", #pools.rings <= DN.MOST_RINGS, #pools.rings)
Run(4)
suite.check("once all have faded nothing moves", DN:Active() == 0, DN:Active())

-- Off, in a fight: waits, then puts the player's value back.
fighting = true
ns.HandleSlash("numbers off")
suite.check("/farm numbers off turns it off", ns.db.damageNumbers == false)
suite.check("but in a fight the game's setting waits", cvars.floatingCombatTextCombatDamage == "0")
fighting = false
Fire("PLAYER_REGEN_ENABLED")
suite.check("and goes back after it", cvars.floatingCombatTextCombatDamage == "1")
suite.check("nothing kept once it's back", next(ns.db.damageNumbersCVars) == nil)

-- A player who had them off keeps them off.
cvars.floatingCombatTextCombatDamage = "0"
ns.HandleSlash("numbers on")
ns.HandleSlash("numbers off")
suite.check("a player who had them off keeps them off", cvars.floatingCombatTextCombatDamage == "0")

-- Settings.
ns.SettingsUI:Show()
local controls = ns.SettingsUI.controls
suite.check("the Settings box shows it off", not controls.damageNumbers:GetChecked())
controls.damageNumbers:GetScript("OnClick")(controls.damageNumbers)
suite.check("ticking it turns it on", ns.db.damageNumbers == true)
controls.damageNumbersCombo:GetScript("OnClick")(controls.damageNumbersCombo)
suite.check("the combo box turns the counter off", ns.db.damageNumbersCombo == false)
DN:SetEnabled(false)
DN:SetComboOn(true)

_G.C_NamePlate, _G.C_CVar, _G.InCombatLockdown = nil, nil, nil
suite.done()
