-- Lane minions: wave spawning and simple lane AI.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MapData = require(ReplicatedStorage.Shared.MapData)
local Units = require(script.Parent.Units)
local ModelFactory = require(script.Parent.ModelFactory)

local flat = Units.flat
local Minions = {}
Minions.list = {}
Minions.active = false

local AI_INTERVAL = 0.12
local accum = 0

function Minions.spawn(team, lane, minionType)
	if not Minions.active then
		return
	end
	local s = Config.Minions[minionType]
	local path = MapData.GetLanePath(lane, team)
	local start = path[1] + (path[2] - path[1]).Unit * 14
	local side = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 4
	local ground = Vector3.new(start.X + side.X, Config.GroundY, start.Z + side.Z)
	local model, body, info = ModelFactory.build("Minion_" .. minionType, {
		team = team,
		name = team .. " " .. minionType .. " minion",
		cframe = CFrame.lookAt(ground, Vector3.new(path[2].X, Config.GroundY, path[2].Z)),
	})
	model.Parent = workspace:WaitForChild("Units")

	local u = Units.new({
		model = model, root = body, team = team, kind = "minion", name = minionType,
		maxHp = s.hp, damage = s.damage, armor = s.armor, range = s.range, attackCd = s.attackCd,
		speed = s.speed, radius = s.radius, ranged = s.ranged, barHeight = info.barHeight,
	})
	u.minionType = minionType
	u.path = path
	u.wp = 2
	u.rootY = Config.GroundY + info.rootY
	u.moveDir = Vector3.zero
	Units.makeKinematic(u)
	Minions.list[u] = true
	return u
end

function Minions.spawnWave(waveNumber)
	local queue = { "melee", "melee", "melee", "caster", "caster" }
	if waveNumber % Config.SiegeEvery == 0 then
		table.insert(queue, 4, "siege")
	end
	for _, team in ipairs(Config.TeamNames) do
		for _, lane in ipairs(MapData.LaneOrder) do
			for i, minionType in ipairs(queue) do
				task.delay((i - 1) * 0.9, Minions.spawn, team, lane, minionType)
			end
		end
	end
end

local function think(u)
	if Units.isStunned(u) then
		u.moveDir = Vector3.zero
		return
	end
	local pos = flat(u.root.Position)

	local tgt = u.target
	if not Units.valid(tgt) or Units.isInvulnerable(tgt) or Units.edgeDist(u, tgt) > Config.MinionLeash then
		-- Prefer minions, then structures, then heroes.
		tgt = Units.nearestEnemy(u, Config.MinionAggro, nil, function(o)
			if o.kind == "hero" then
				return 8
			elseif o.kind == "minion" then
				return 0
			end
			return 4
		end)
	end
	u.target = tgt

	local dir = Vector3.zero
	if tgt then
		local d = Units.edgeDist(u, tgt)
		if d <= u.range then
			if Units.canAttack(u) then
				Units.basicAttack(u, tgt)
			end
		else
			dir = flat(tgt.root.Position) - pos
		end
	else
		local wp = u.path[u.wp]
		if wp then
			local toWp = flat(wp) - pos
			if toWp.Magnitude < 4 and u.wp < #u.path then
				u.wp += 1
			end
			dir = toWp
		end
	end

	if dir.Magnitude > 0.1 then
		dir = dir.Unit
		-- Light separation from nearby allied minions so waves don't stack into one blob.
		local push = Vector3.zero
		for o in pairs(Minions.list) do
			if o ~= u and o.team == u.team and o.alive then
				local away = pos - flat(o.root.Position)
				local m = away.Magnitude
				if m > 0.01 and m < 3 then
					push += away.Unit * (3 - m) / 3
				end
			end
		end
		dir = (dir + push * 0.8)
		dir = dir.Magnitude > 0.01 and dir.Unit or Vector3.zero
	end
	u.moveDir = dir
end

function Minions.step(dt)
	accum += dt
	local doThink = accum >= AI_INTERVAL
	if doThink then
		accum = 0
	end
	for u in pairs(Minions.list) do
		if Units.valid(u) then
			if doThink then
				think(u)
				Units.stepMove(u)
			end
		end
	end
end

Units.onDeath(function(u)
	if u.kind ~= "minion" then
		return
	end
	Minions.list[u] = nil
	Units.remove(u)
	task.delay(0.15, function()
		if u.model then
			u.model:Destroy()
		end
	end)
end)

function Minions.clear()
	for u in pairs(Minions.list) do
		if u.model then
			u.model:Destroy()
		end
	end
	Minions.list = {}
end

return Minions
