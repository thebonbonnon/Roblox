-- AI-controlled heroes that fill empty team slots.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MapData = require(ReplicatedStorage.Shared.MapData)
local Units = require(script.Parent.Units)
local HeroService = require(script.Parent.HeroService)
local Abilities = require(script.Parent.Abilities)
local Structures = require(script.Parent.Structures)
local ModelFactory = require(script.Parent.ModelFactory)

local flat = Units.flat
local Bots = {}
Bots.list = {}

local THINK_INTERVAL = 0.15
local accum = 0

---------------------------------------------------------------------------
-- Body (see tools/gen_models.py for the part layout)
---------------------------------------------------------------------------
local function buildModel(u, pos)
	local model, root, info = ModelFactory.build("Hero_" .. u.heroId, {
		team = u.team,
		name = u.name,
		cframe = CFrame.new(pos.X, Config.GroundY, pos.Z) * CFrame.Angles(0, u.team == "Red" and math.rad(180) or 0, 0),
	})
	u.rootY = Config.GroundY + info.rootY
	u.barHeight = info.barHeight
	model.Parent = workspace:WaitForChild("Units")
	return model, root
end

---------------------------------------------------------------------------
-- Brain
---------------------------------------------------------------------------
local function moveToward(u, point)
	local d = flat(point) - flat(u.root.Position)
	u.moveDir = d.Magnitude > 1 and d.Unit or Vector3.zero
end

local function dangerousTower(u, pos)
	for _, t in ipairs(Structures.towers) do
		if t.alive and t.team ~= u.team then
			local d = (flat(t.root.Position) - flat(pos)).Magnitude - t.radius
			if d <= t.range + 3 then
				-- Safe only if allied minions are tanking it and it isn't targeting us.
				if t.target == u then
					return t
				end
				local tanked = false
				for o in pairs(Units.all) do
					if o.kind == "minion" and o.team == u.team and o.alive and Units.edgeDist(o, t) <= t.range then
						tanked = true
						break
					end
				end
				if not tanked then
					return t
				end
			end
		end
	end
	return nil
end

local function tryAbilities(u, enemy)
	local d = Units.edgeDist(u, enemy)
	local hpPct = u.hp / u.maxHp
	for _, slot in ipairs({ "R", "Q", "E", "W" }) do
		local ab = u.def.abilities[slot]
		if Abilities.isReady(u, slot) and math.random() < 0.5 then
			local inRange
			if ab.type == "selfaoe" then
				inRange = d <= ab.radius - 1
			elseif ab.type == "buff" then
				inRange = d <= 15
			elseif ab.type == "dash" then
				inRange = d <= ab.range and (ab.damage ~= nil and hpPct > 0.5 or d < 8)
			else
				inRange = d <= ab.range
			end
			if slot == "R" and ab.type == "execute" then
				inRange = inRange and enemy.hp / enemy.maxHp < 0.45
			end
			if inRange then
				-- Tumble/Blink-style dashes without damage are used to kite away from melee threats.
				local aim = enemy.root.Position
				if ab.type == "dash" and not ab.damage then
					aim = u.root.Position + (u.root.Position - enemy.root.Position)
				end
				if Abilities.tryCast(u, slot, aim) then
					return
				end
			end
		end
	end
end

local function shop(u)
	for _, id in ipairs(u.def.build) do
		local owned = 0
		for _, have in ipairs(u.items) do
			if have == id then
				owned += 1
			end
		end
		local wanted = 0
		for _, want in ipairs(u.def.build) do
			if want == id then
				wanted += 1
			end
		end
		if owned < wanted then
			HeroService.buy(u, id) -- fails silently if too expensive; we save up
			return
		end
	end
end

local function think(u)
	if Units.isStunned(u) then
		u.moveDir = Vector3.zero
		return
	end
	local pos = u.root.Position
	local hpPct = u.hp / u.maxHp
	local fountain = MapData.Fountain[u.team]

	-- Retreat to heal at low health.
	if u.retreating then
		if hpPct > 0.92 and u.mana > u.maxMana * 0.6 then
			u.retreating = false
			u.wp = 2
		end
	elseif hpPct < 0.28 then
		u.retreating = true
	end
	if u.retreating then
		u.target = nil
		if (flat(pos) - flat(fountain)).Magnitude < Config.FountainRadius - 6 then
			u.moveDir = Vector3.zero
			shop(u)
		else
			moveToward(u, fountain)
			-- Still throw spells at chasers.
			local chaser = Units.nearestEnemy(u, 20, function(o)
				return o.kind == "hero"
			end)
			if chaser then
				tryAbilities(u, chaser)
			end
		end
		return
	end

	-- Opportunistic shopping when passing the fountain.
	if (flat(pos) - flat(fountain)).Magnitude < Config.ShopRadius then
		shop(u)
	end

	-- Don't stand under an enemy tower without minion cover.
	local tower = dangerousTower(u, pos)
	if tower then
		u.target = nil
		local away = flat(pos) - flat(tower.root.Position)
		if away.Magnitude < 0.1 then
			away = flat(MapData.Fountain[u.team]) - flat(pos)
		end
		moveToward(u, pos + away.Unit * 10)
		return
	end

	-- Fight enemy heroes when healthy.
	local enemyHero = Units.nearestEnemy(u, 28, function(o)
		return o.kind == "hero"
	end)
	if enemyHero and hpPct > 0.35 then
		tryAbilities(u, enemyHero)
		if not dangerousTower(u, enemyHero.root.Position) then
			u.target = enemyHero
		end
	end

	local t = u.target
	if not Units.valid(t) or Units.isInvulnerable(t) or Units.edgeDist(u, t) > 30 then
		t = Units.nearestEnemy(u, 20, nil, function(o)
			-- Last-hit priority: low health minions first.
			if o.kind == "minion" then
				return (o.hp / o.maxHp) * 6
			end
			return o.kind == "hero" and 4 or 2
		end)
		u.target = t
	end

	if t then
		local d = Units.edgeDist(u, t)
		if d > u.range then
			local nextPos = t.root.Position
			if dangerousTower(u, nextPos) and t.kind ~= "tower" then
				u.target = nil
				u.moveDir = Vector3.zero
			else
				moveToward(u, nextPos)
			end
		else
			u.moveDir = Vector3.zero
			Units.face(u, t.root.Position)
		end
		return
	end

	-- Walk the lane toward the enemy base, stopping short of uncovered towers.
	local wp = u.path[u.wp]
	if wp then
		if (flat(wp) - flat(pos)).Magnitude < 6 and u.wp < #u.path then
			u.wp += 1
			wp = u.path[u.wp]
		end
		local toWp = flat(wp) - flat(pos)
		if toWp.Magnitude < 1 then
			u.moveDir = Vector3.zero
		elseif dangerousTower(u, pos + toWp.Unit * 6) then
			u.moveDir = Vector3.zero
		else
			moveToward(u, wp)
		end
	end
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
function Bots.create(team, heroId, lane)
	local u = HeroService.newHero(heroId, team, nil)
	u.lane = lane
	u.path = MapData.GetLanePath(lane, team)
	u.wp = 2
	u.kinematic = true
	u.moveDir = Vector3.zero
	u.customSpawn = function(self, pos)
		local model, root = buildModel(self, pos)
		Units.attach(self, model, root)
		self.wp = 2
		self.retreating = false
		self.moveDir = Vector3.zero
	end
	u.customDespawn = function(self)
		if self.model then
			self.model:Destroy()
		end
	end
	Bots.list[u] = true
	HeroService.spawn(u)
	return u
end

function Bots.remove(u)
	Bots.list[u] = nil
	HeroService.removeHero(u)
end

function Bots.step(dt)
	accum += dt
	local doThink = accum >= THINK_INTERVAL
	if doThink then
		accum = 0
	end
	for u in pairs(Bots.list) do
		if Units.valid(u) then
			if doThink then
				think(u)
			end
			Units.stepMove(u, dt)
		end
	end
end

function Bots.clear()
	for u in pairs(Bots.list) do
		if u.model then
			u.model:Destroy()
		end
	end
	Bots.list = {}
end

return Bots
