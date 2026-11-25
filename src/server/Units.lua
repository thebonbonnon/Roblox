--[[
	Unit registry and combat core. Every combatant (hero, minion, tower, nexus) is a "unit" table:
	  model, root, team, kind, name, hp, maxHp, armor, damage, range, attackCd, speed, radius,
	  ranged, alive, lastAttack, buffs, stunUntil, bonus (item stats), recentHeroDamagers
	Health is tracked here (not on Humanoids) and mirrored to model attributes for the client.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Effects = require(script.Parent.Effects)

local Units = {}
Units.all = {} -- set: [unit] = true
Units.byModel = {} -- [model] = unit
Units.net = nil

local deathListeners = {}
local nextId = 0

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end
Units.flat = flat

local function now()
	return os.clock()
end
Units.now = now

function Units.onDeath(fn)
	table.insert(deathListeners, fn)
end

---------------------------------------------------------------------------
-- Overhead health bars
---------------------------------------------------------------------------
local BAR_STYLE = {
	hero = { w = 100, h = 9, name = true },
	minion = { w = 40, h = 5 },
	tower = { w = 110, h = 9 },
	nexus = { w = 160, h = 12 },
}

local function buildBar(u)
	if u.bar then
		u.bar:Destroy()
	end
	local style = BAR_STYLE[u.kind] or BAR_STYLE.minion
	local nameHeight = style.name and 16 or 0

	local gui = Instance.new("BillboardGui")
	gui.Name = "UnitBar"
	gui.Size = UDim2.fromOffset(style.w, style.h + nameHeight)
	gui.StudsOffsetWorldSpace = Vector3.new(0, u.barHeight or 4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 300
	gui.LightInfluence = 0

	local bg = Instance.new("Frame")
	bg.Name = "Bg"
	bg.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
	bg.BorderSizePixel = 0
	bg.Size = UDim2.new(1, 0, 0, style.h)
	bg.Position = UDim2.new(0, 0, 1, -style.h)
	bg.Parent = gui

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = Config.TeamColors[u.team] or Color3.new(1, 1, 1)
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = bg

	if style.name then
		local label = Instance.new("TextLabel")
		label.Name = "NameLabel"
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 40, 0, 14)
		label.Position = UDim2.fromOffset(-20, 0)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 12
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.4
		label.Parent = gui
		u.barLabel = label
	end

	gui.Adornee = u.root
	gui.Parent = u.root
	u.bar = gui
	u.barFill = fill
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------
function Units.new(p)
	nextId += 1
	local u = {
		id = nextId,
		team = p.team,
		kind = p.kind,
		name = p.name or p.kind,
		maxHp = p.maxHp or 100,
		hp = p.maxHp or 100,
		armor = p.armor or 0,
		damage = p.damage or 0,
		range = p.range or 5,
		attackCd = p.attackCd or 1,
		speed = p.speed or 0,
		radius = p.radius or 1.5,
		ranged = p.ranged or false,
		barHeight = p.barHeight or 4,
		alive = p.model ~= nil,
		lastAttack = 0,
		buffs = {},
		stunUntil = 0,
		bonus = {},
		recentHeroDamagers = {},
		lastHeroAggression = 0,
	}
	Units.all[u] = true
	if p.model then
		Units.attach(u, p.model, p.root)
	end
	return u
end

-- (Re)binds a unit to a model, e.g. when a hero respawns with a new character.
function Units.attach(u, model, root)
	if u.model then
		Units.byModel[u.model] = nil
	end
	u.model = model
	u.root = root
	Units.byModel[model] = u
	model:SetAttribute("Team", u.team)
	model:SetAttribute("Kind", u.kind)
	model:SetAttribute("UnitId", u.id)
	model:SetAttribute("Radius", u.radius)
	model:SetAttribute("UnitName", u.name)
	-- Vertical extent relative to the root, used for first-person aiming.
	local ok, cf, size = pcall(function()
		return model:GetBoundingBox()
	end)
	if ok then
		u.aimBottom = cf.Position.Y - size.Y / 2 - root.Position.Y
		u.aimTop = cf.Position.Y + size.Y / 2 - root.Position.Y
	end
	buildBar(u)
	Units.refresh(u)
end

function Units.remove(u)
	Units.all[u] = nil
	if u.model then
		Units.byModel[u.model] = nil
	end
	u.alive = false
end

function Units.clear()
	table.clear(Units.all)
	table.clear(Units.byModel)
end

---------------------------------------------------------------------------
-- Stats
---------------------------------------------------------------------------
local function pruneBuffs(u)
	local t = now()
	for i = #u.buffs, 1, -1 do
		if u.buffs[i].expires <= t then
			table.remove(u.buffs, i)
		end
	end
end

function Units.addBuff(u, stat, value, duration)
	if u.kind == "tower" or u.kind == "nexus" then
		return
	end
	table.insert(u.buffs, { stat = stat, value = value, expires = now() + duration })
end

function Units.stun(u, duration)
	if u.kind == "tower" or u.kind == "nexus" then
		return
	end
	u.stunUntil = math.max(u.stunUntil, now() + duration)
end

function Units.isStunned(u)
	return now() < u.stunUntil
end

function Units.isInvulnerable(u)
	if u.invulnerable then
		return true
	end
	return u.invulnFn ~= nil and u.invulnFn() == true
end

local function buffSum(u, stat)
	local t, total = now(), 0
	for _, b in ipairs(u.buffs) do
		if b.stat == stat and b.expires > t then
			total += b.value
		end
	end
	return total
end

local function buffProduct(u, stat)
	local t, total = now(), 1
	for _, b in ipairs(u.buffs) do
		if b.stat == stat and b.expires > t then
			total *= b.value
		end
	end
	return total
end

function Units.getArmor(u)
	return u.armor + (u.bonus.armor or 0) + buffSum(u, "armor")
end

function Units.getDamage(u)
	return u.damage + (u.bonus.damage or 0)
end

function Units.getAttackCd(u)
	return u.attackCd / (1 + (u.bonus.attackSpeed or 0) + buffSum(u, "attackSpeed"))
end

function Units.getSpeed(u)
	if Units.isStunned(u) then
		return 0
	end
	return (u.speed + (u.bonus.speed or 0)) * buffProduct(u, "speed")
end

---------------------------------------------------------------------------
-- Queries
---------------------------------------------------------------------------
function Units.valid(u)
	return u ~= nil and u.alive and u.root ~= nil and u.root.Parent ~= nil
end

function Units.edgeDist(a, b)
	return (flat(a.root.Position) - flat(b.root.Position)).Magnitude - b.radius
end

local function isStructure(u)
	return u.kind == "tower" or u.kind == "nexus"
end
Units.isStructure = isStructure

-- Attackable enemies of `team` whose edge is within radius of pos.
function Units.enemiesNear(team, pos, radius, includeStructures)
	local result = {}
	local p = flat(pos)
	for o in pairs(Units.all) do
		if o.team ~= team and Units.valid(o) and (includeStructures or not isStructure(o)) and not Units.isInvulnerable(o) then
			if (flat(o.root.Position) - p).Magnitude - o.radius <= radius then
				table.insert(result, o)
			end
		end
	end
	return result
end

-- Nearest attackable enemy to unit u. `bias(o)` adds to the distance score to set priorities.
function Units.nearestEnemy(u, radius, filter, bias)
	local best, bestScore = nil, math.huge
	local p = flat(u.root.Position)
	for o in pairs(Units.all) do
		if o.team ~= u.team and Units.valid(o) and not Units.isInvulnerable(o) and (not filter or filter(o)) then
			local d = (flat(o.root.Position) - p).Magnitude - o.radius
			if d <= radius then
				local score = d + (bias and bias(o) or 0)
				if score < bestScore then
					best, bestScore = o, score
				end
			end
		end
	end
	return best
end

---------------------------------------------------------------------------
-- Health
---------------------------------------------------------------------------
function Units.refresh(u)
	pruneBuffs(u)
	if u.barFill then
		u.barFill.Size = UDim2.fromScale(math.clamp(u.hp / u.maxHp, 0, 1), 1)
	end
	if u.barLabel then
		u.barLabel.Text = string.format("%s  Lv%d", u.name, u.level or 1)
	end
	local m = u.model
	if m and m.Parent then
		m:SetAttribute("Health", math.ceil(u.hp))
		m:SetAttribute("MaxHealth", math.floor(u.maxHp))
		if u.maxMana then
			m:SetAttribute("Mana", math.floor(u.mana))
			m:SetAttribute("MaxMana", math.floor(u.maxMana))
		end
		m:SetAttribute("Stunned", Units.isStunned(u))
		m:SetAttribute("Invulnerable", Units.isInvulnerable(u))
	end
end

function Units.kill(u, killer)
	if not u.alive then
		return
	end
	u.alive = false
	u.hp = 0
	Units.refresh(u)
	for _, fn in ipairs(deathListeners) do
		task.spawn(fn, u, killer)
	end
end

function Units.damage(target, amount, source)
	if not Units.valid(target) or Units.isInvulnerable(target) or amount <= 0 then
		return 0
	end
	local dealt = amount * 100 / (100 + math.max(0, Units.getArmor(target)))
	target.hp -= dealt

	local t = now()
	if source and source.kind == "hero" then
		target.recentHeroDamagers[source] = t
		if target.kind == "hero" then
			source.lastHeroAggression = t
		end
	end
	target.lastDamagedBy = source

	if Units.net and ((source and source.kind == "hero") or target.kind == "hero") then
		local heroVsHero = source ~= nil and source.kind == "hero" and target.kind == "hero"
		local sourceUserId = source and source.player and source.player.UserId or 0
		Units.net.FX:FireAllClients("dmg", target.root.Position, math.floor(dealt + 0.5), heroVsHero, sourceUserId)
	end

	if target.hp <= 0 then
		Units.kill(target, source)
	else
		Units.refresh(target)
	end
	return dealt
end

function Units.heal(u, amount)
	if not u.alive then
		return
	end
	u.hp = math.min(u.maxHp, u.hp + amount)
	Units.refresh(u)
end

---------------------------------------------------------------------------
-- Attacks & movement helpers
---------------------------------------------------------------------------
-- Turns a moving unit's anchored root into a server-simulated physics body. Clients interpolate
-- physics replication, so minions and bots glide smoothly instead of being teleported every
-- frame, and the server only sends a new velocity when it actually changes.
function Units.makeKinematic(u)
	local root = u.root
	local att = Instance.new("Attachment")
	att.Name = "MoveAttachment"
	att.Parent = root

	local lv = Instance.new("LinearVelocity")
	lv.Name = "Move"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	-- Unlimited force: the unit moves exactly at its speed and holds its height (no gravity sag).
	lv.MaxForce = math.huge
	pcall(function()
		lv.ForceLimitsEnabled = false
	end)
	lv.VectorVelocity = Vector3.zero
	lv.Parent = root

	local ao = Instance.new("AlignOrientation")
	ao.Name = "Facing"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.RigidityEnabled = true
	ao.CFrame = root.CFrame.Rotation
	ao.Parent = root

	u.lv, u.ao = lv, ao
	u.lastVel = Vector3.zero
	u.kinematic = true
	root.Anchored = false
	pcall(function()
		root:SetNetworkOwner(nil) -- the server simulates it, never a nearby player
	end)
end

function Units.face(u, pos)
	if not u.ao then
		return
	end
	local d = flat(pos - u.root.Position)
	if d.Magnitude > 0.1 then
		u.ao.CFrame = CFrame.lookAt(Vector3.zero, d.Unit)
		u.lastDir = d.Unit
	end
end

-- First-person aiming: the enemy whose body the aim ray passes closest to (within `assist`
-- studs of its edge), nearest along the ray. Returns the unit or nil.
function Units.aimPick(u, origin, dir, range, assist)
	local best, bestT = nil, math.huge
	for o in pairs(Units.all) do
		if o.team ~= u.team and Units.valid(o) and not Units.isInvulnerable(o) then
			local rp = o.root.Position
			local lo, hi = o.aimBottom or -1.5, o.aimTop or 2.5
			for i = 0, 3 do
				local p = rp + Vector3.new(0, lo + (hi - lo) * (i + 0.5) / 4, 0)
				local v = p - origin
				local t = v:Dot(dir)
				if t > 0 and t <= range + o.radius and t < bestT and (v - dir * t).Magnitude <= o.radius + assist then
					best, bestT = o, t
				end
			end
		end
	end
	return best
end

function Units.canAttack(u)
	return not Units.isStunned(u) and now() - u.lastAttack >= Units.getAttackCd(u)
end

function Units.basicAttack(a, t)
	a.lastAttack = now()
	Units.face(a, t.root.Position)
	if a.anim then
		a.anim.attack(a.ranged and "lunge" or "slash")
	end
	local dmg = Units.getDamage(a)
	if a.ranged then
		local origin = (a.firePart or a.root).Position
		local isTower = a.kind == "tower"
		local color = isTower and Color3.fromRGB(255, 235, 140) or Config.TeamColors[a.team]
		Effects.homing(origin, t.model, function()
			if Units.valid(t) then
				return t.root.Position
			end
			return nil
		end, isTower and 90 or 75, color, isTower and 1.6 or 0.7, function()
			if Units.valid(t) then
				Units.damage(t, dmg, a)
			end
		end)
	else
		Effects.flash(t.root.Position, 1.4, Color3.new(1, 1, 1), 0.15)
		Units.damage(t, dmg, a)
	end
end

-- Applies u.moveDir to a kinematic unit (minions and bot heroes). Call it whenever the AI
-- updates; the velocity persists between calls, so it doesn't need to run every frame.
function Units.stepMove(u)
	if not u.lv or not u.root.Parent then
		return
	end
	local dir = u.moveDir or Vector3.zero
	local speed = Units.getSpeed(u)
	local vel = (dir.Magnitude > 0.01 and speed > 0) and dir * speed or Vector3.zero

	-- Stay inside the map.
	local p = u.root.Position
	local limit = Config.MapHalfSize - 6
	if math.abs(p.X) > limit and p.X * vel.X > 0 then
		vel = Vector3.new(0, 0, vel.Z)
	end
	if math.abs(p.Z) > limit and p.Z * vel.Z > 0 then
		vel = Vector3.new(vel.X, 0, 0)
	end
	-- Gently correct any height drift.
	local dy = u.rootY - p.Y
	if math.abs(dy) > 0.05 then
		vel += Vector3.new(0, math.clamp(dy * 5, -10, 10), 0)
	end

	if (vel - u.lastVel).Magnitude > 0.05 then
		u.lv.VectorVelocity = vel
		u.lastVel = vel
	end
	if dir.Magnitude > 0.01 and (not u.lastDir or (dir - u.lastDir).Magnitude > 0.05) then
		u.ao.CFrame = CFrame.lookAt(Vector3.zero, dir)
		u.lastDir = dir
	end
end

return Units
