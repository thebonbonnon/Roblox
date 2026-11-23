-- Executes hero abilities (Q/W/E/R) for players and bots alike.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MapData = require(ReplicatedStorage.Shared.MapData)
local Units = require(script.Parent.Units)
local Effects = require(script.Parent.Effects)

local flat = Units.flat
local Abilities = {}

local function abilityDamage(u, ab)
	return (ab.damage or 0) + (ab.perLevel or 0) * (u.level - 1) + (u.bonus.power or 0) * (ab.ratio or 0)
end

local function applyHitEffects(target, ab)
	if ab.stun then
		Units.stun(target, ab.stun)
	end
	if ab.slow then
		Units.addBuff(target, "speed", 1 - ab.slow, ab.slowDuration or 2)
	end
end

local function hitArea(u, center, radius, ab, color)
	local dmg = abilityDamage(u, ab)
	for _, o in ipairs(Units.enemiesNear(u.team, center, radius, false)) do
		Units.damage(o, dmg, u)
		applyHitEffects(o, ab)
	end
	Effects.flash(Vector3.new(center.X, Config.GroundY + 1, center.Z), radius, color, 0.4)
end

-- Returns the flat point toward targetPos limited to range, and the flat direction.
local function clampToRange(u, targetPos, range)
	local origin = flat(u.root.Position)
	local d = flat(targetPos) - origin
	if d.Magnitude < 0.1 then
		d = flat(u.root.CFrame.LookVector)
		if d.Magnitude < 0.1 then
			d = Vector3.new(0, 0, -1)
		end
		d = d.Unit * 0.1
	end
	if d.Magnitude > range then
		d = d.Unit * range
	end
	return origin + d, d.Unit
end

local function applyBuff(u, b)
	local duration = b.duration or 3
	if b.speedMult then
		Units.addBuff(u, "speed", b.speedMult, duration)
	end
	if b.armor then
		Units.addBuff(u, "armor", b.armor, duration)
	end
	if b.attackSpeed then
		Units.addBuff(u, "attackSpeed", b.attackSpeed, duration)
	end
	if b.heal then
		Units.heal(u, b.heal + (b.healPerLevel or 0) * (u.level - 1))
	end
end

local function launch(u, ab, origin, dir, color)
	local width = ab.width or 2.5
	local p = Effects.basePart(Vector3.one * width, color, CFrame.new(origin), Enum.PartType.Ball)
	local dmg = abilityDamage(u, ab)
	local speed = ab.speed or 90
	local travelled = 0
	local hit = {}
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not p.Parent then
			conn:Disconnect()
			return
		end
		local step = speed * dt
		travelled += step
		local pos = p.Position + dir * step
		p.CFrame = CFrame.new(pos)
		for _, o in ipairs(Units.enemiesNear(u.team, pos, width, false)) do
			if not hit[o] then
				hit[o] = true
				Units.damage(o, dmg, u)
				applyHitEffects(o, ab)
				Effects.flash(o.root.Position, 2.5, color, 0.25)
				if not ab.pierce then
					conn:Disconnect()
					p:Destroy()
					return
				end
			end
		end
		if travelled >= ab.range then
			conn:Disconnect()
			p:Destroy()
		end
	end)
end

local executors = {}

executors.skillshot = function(u, ab, targetPos, color)
	local origin = u.root.Position
	local _, dir = clampToRange(u, targetPos, ab.range)
	local count = ab.count or 1
	local spread = math.rad(ab.spread or 0)
	for i = 1, count do
		local angle = count > 1 and (-spread / 2 + spread * (i - 1) / (count - 1)) or 0
		launch(u, ab, origin, CFrame.Angles(0, angle, 0):VectorToWorldSpace(dir), color)
	end
end

executors.aoe = function(u, ab, targetPos, color)
	local center = clampToRange(u, targetPos, ab.range)
	local delay = ab.delay or 0
	if delay > 0 then
		Effects.ring(center, ab.radius, color, delay)
		task.delay(delay, hitArea, u, center, ab.radius, ab, color)
	else
		hitArea(u, center, ab.radius, ab, color)
	end
end

executors.selfaoe = function(u, ab, _, color)
	local center = flat(u.root.Position)
	local delay = ab.delay or 0
	if delay > 0 then
		Effects.ring(center, ab.radius, color, delay)
		task.delay(delay, function()
			-- follows the caster during the wind-up
			if Units.valid(u) then
				center = flat(u.root.Position)
			end
			hitArea(u, center, ab.radius, ab, color)
		end)
	else
		hitArea(u, center, ab.radius, ab, color)
	end
end

executors.dash = function(u, ab, targetPos, color)
	local origin = u.root.Position
	local dest, dir = clampToRange(u, targetPos, ab.range)
	local destFull = Vector3.new(dest.X, origin.Y, dest.Z)
	u.model:PivotTo(CFrame.lookAt(destFull, destFull + dir))
	Effects.trail(origin, destFull, color)
	if ab.damage then
		local dmg = abilityDamage(u, ab)
		for _, o in ipairs(Units.enemiesNear(u.team, (origin + destFull) / 2, ab.range, false)) do
			if MapData.DistToSegment(o.root.Position, origin, destFull) <= 4 + o.radius then
				Units.damage(o, dmg, u)
				applyHitEffects(o, ab)
			end
		end
	end
	if ab.buff then
		applyBuff(u, ab.buff)
	end
end

executors.buff = function(u, ab, _, color)
	applyBuff(u, ab)
	Effects.flash(u.root.Position, 4, color, 0.5)
end

executors.execute = function(u, ab, targetPos, color)
	local best, bestDist = nil, math.huge
	for o in pairs(Units.all) do
		if o.kind == "hero" and o.team ~= u.team and Units.valid(o) and not Units.isInvulnerable(o) then
			local d = (flat(o.root.Position) - flat(targetPos)).Magnitude
			if d <= ab.radius and Units.edgeDist(u, o) <= ab.range and d < bestDist then
				best, bestDist = o, d
			end
		end
	end
	if not best then
		return false -- nothing to execute: don't consume mana/cooldown
	end
	local origin = u.root.Position
	local tp = best.root.Position
	local dir = flat(tp - origin)
	dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.new(0, 0, -1)
	local dest = Vector3.new(tp.X, origin.Y, tp.Z) - dir * 2.5
	u.model:PivotTo(CFrame.lookAt(dest, dest + dir))
	Effects.trail(origin, dest, color)
	local dmg = abilityDamage(u, ab) + (best.maxHp - best.hp) * (ab.missingHp or 0)
	Units.damage(best, dmg, u)
	Effects.flash(tp, 5, Color3.fromRGB(200, 0, 0), 0.4)
	return true
end

-- Returns ok, cooldown
function Abilities.tryCast(u, slot, targetPos)
	if not Units.valid(u) or Units.isStunned(u) then
		return false
	end
	local ab = u.def.abilities[slot]
	if not ab then
		return false
	end
	if slot == "R" and u.level < Config.UltLevel then
		return false
	end
	local t = os.clock()
	if (u.cooldowns[slot] or 0) > t or u.mana < ab.mana then
		return false
	end
	local exec = executors[ab.type]
	if not exec then
		return false
	end
	if exec(u, ab, targetPos, u.def.color) == false then
		return false
	end
	u.mana -= ab.mana
	u.cooldowns[slot] = t + ab.cooldown
	Units.refresh(u)
	return true, ab.cooldown
end

function Abilities.isReady(u, slot)
	local ab = u.def.abilities[slot]
	if slot == "R" and u.level < Config.UltLevel then
		return false
	end
	return (u.cooldowns[slot] or 0) <= os.clock() and u.mana >= ab.mana
end

return Abilities
