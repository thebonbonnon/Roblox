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
		Units.net.FX:FireAllClients("dmg", target.root.Position, math.floor(dealt + 0.5), heroVsHero)
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
function Units.face(u, pos)
	if not u.kinematic then
		return
	end
	local rp = u.root.Position
	local look = Vector3.new(pos.X, rp.Y, pos.Z)
	if (look - rp).Magnitude > 0.1 then
		u.root.CFrame = CFrame.lookAt(rp, look)
	end
end

function Units.canAttack(u)
	return not Units.isStunned(u) and now() - u.lastAttack >= Units.getAttackCd(u)
end

function Units.basicAttack(a, t)
	a.lastAttack = now()
	Units.face(a, t.root.Position)
	local dmg = Units.getDamage(a)
	if a.ranged then
		local origin = (a.firePart or a.root).Position
		local isTower = a.kind == "tower"
		local color = isTower and Color3.fromRGB(255, 235, 140) or Config.TeamColors[a.team]
		Effects.homing(origin, function()
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

-- Moves an anchored (kinematic) unit along u.moveDir. Used by minions and bot heroes.
function Units.stepMove(u, dt)
	local dir = u.moveDir
	if not dir or dir.Magnitude < 0.01 then
		return
	end
	local speed = Units.getSpeed(u)
	if speed <= 0 then
		return
	end
	local limit = Config.MapHalfSize - 6
	local np = u.root.Position + dir * speed * dt
	np = Vector3.new(math.clamp(np.X, -limit, limit), u.rootY, math.clamp(np.Z, -limit, limit))
	u.root.CFrame = CFrame.lookAt(np, np + dir)
end

return Units
