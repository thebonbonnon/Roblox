-- Towers and nexuses: construction, targeting AI and destruction.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MapData = require(ReplicatedStorage.Shared.MapData)
local Units = require(script.Parent.Units)
local Effects = require(script.Parent.Effects)

local Structures = {}
Structures.towers = {}
Structures.nexus = {}
Structures.onNexusDestroyed = nil -- function(team)

local AI_INTERVAL = 0.1
local accum = 0

local function unitsFolder()
	return workspace:WaitForChild("Units")
end

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

local function buildTower(team, lane, tier, pos)
	local color = Config.TeamColors[team]
	local gy = Config.GroundY
	local model = Instance.new("Model")
	model.Name = string.format("%s %s Tower %d", team, lane, tier)

	local base = part({
		Name = "Base",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(14, 8, 8),
		CFrame = CFrame.new(pos.X, gy + 7, pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(120, 120, 130),
		Material = Enum.Material.Slate,
	}, model)
	part({
		Name = "Band",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.2, 8.6, 8.6),
		CFrame = CFrame.new(pos.X, gy + 12, pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
	}, model)
	local crystal = part({
		Name = "Crystal",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 3.5,
		CFrame = CFrame.new(pos.X, gy + 16.5, pos.Z),
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
	}, model)
	model.PrimaryPart = base
	model.Parent = unitsFolder()

	local s = Config.Tower
	local u = Units.new({
		model = model, root = base, team = team, kind = "tower",
		name = model.Name, maxHp = s.hp, armor = s.armor, damage = s.damage,
		range = s.range, attackCd = s.attackCd, radius = s.radius, ranged = true, barHeight = 13,
	})
	u.firePart = crystal
	u.lane = lane
	u.tier = tier
	return u
end

local function buildNexus(team)
	local pos = MapData.Nexus[team]
	local color = Config.TeamColors[team]
	local gy = Config.GroundY
	local model = Instance.new("Model")
	model.Name = team .. " Nexus"
	local base = part({
		Name = "Base",
		Size = Vector3.new(14, 4, 14),
		CFrame = CFrame.new(pos.X, gy + 2, pos.Z),
		Color = Color3.fromRGB(90, 90, 100),
		Material = Enum.Material.Slate,
	}, model)
	part({
		Name = "Core",
		Size = Vector3.new(7, 7, 7),
		CFrame = CFrame.new(pos.X, gy + 9, pos.Z) * CFrame.Angles(math.rad(45), math.rad(45), 0),
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
	}, model)
	model.PrimaryPart = base
	model.Parent = unitsFolder()
	local s = Config.Nexus
	return Units.new({
		model = model, root = base, team = team, kind = "nexus",
		name = model.Name, maxHp = s.hp, armor = s.armor, radius = s.radius, barHeight = 12,
	})
end

function Structures.build()
	Structures.towers = {}
	Structures.nexus = {}
	for _, team in ipairs(Config.TeamNames) do
		local inner = {}
		for _, lane in ipairs(MapData.LaneOrder) do
			local path = MapData.GetLanePath(lane, team)
			local tiers = {}
			for tier, frac in ipairs(MapData.TowerFractions) do
				local t = buildTower(team, lane, tier, MapData.PointAlong(path, frac))
				tiers[tier] = t
				table.insert(Structures.towers, t)
			end
			-- Inner towers can't be damaged until the outer tower of their lane falls.
			local outer = tiers[2]
			tiers[1].invulnFn = function()
				return outer.alive
			end
			table.insert(inner, tiers[1])
		end
		-- The nexus is vulnerable once any inner tower of that team has fallen.
		local nexus = buildNexus(team)
		nexus.invulnFn = function()
			for _, t in ipairs(inner) do
				if not t.alive then
					return false
				end
			end
			return true
		end
		Structures.nexus[team] = nexus
	end
end

local function chooseTarget(tower)
	local t = Units.now()
	-- 1. Enemy heroes that attacked one of our heroes recently get top priority.
	local aggressor = Units.nearestEnemy(tower, tower.range, function(o)
		return o.kind == "hero" and t - o.lastHeroAggression < 1.5
	end)
	if aggressor then
		return aggressor
	end
	-- 2. Keep the current target if still valid.
	local cur = tower.target
	if Units.valid(cur) and Units.edgeDist(tower, cur) <= tower.range then
		return cur
	end
	-- 3. Minions first, then heroes.
	return Units.nearestEnemy(tower, tower.range, function(o)
		return not Units.isStructure(o)
	end, function(o)
		return o.kind == "hero" and 1000 or 0
	end)
end

function Structures.step(dt)
	accum += dt
	if accum < AI_INTERVAL then
		return
	end
	accum = 0
	for _, tower in ipairs(Structures.towers) do
		if tower.alive then
			tower.target = chooseTarget(tower)
			if tower.target and Units.canAttack(tower) then
				Units.basicAttack(tower, tower.target)
			end
		end
	end
	for _, nexus in pairs(Structures.nexus) do
		Units.refresh(nexus) -- keeps the Invulnerable attribute up to date
	end
	for _, tower in ipairs(Structures.towers) do
		if tower.alive then
			Units.refresh(tower)
		end
	end
end

local function ruin(u)
	local model = u.model
	if not model then
		return
	end
	local pos = u.root.Position
	Effects.flash(pos + Vector3.new(0, 6, 0), 14, Config.TeamColors[u.team], 0.8)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p ~= u.root then
			p:Destroy()
		end
	end
	u.root.Color = Color3.fromRGB(50, 50, 55)
	u.root.Size = Vector3.new(3, u.root.Size.Y, u.root.Size.Z)
	u.root.CFrame = CFrame.new(pos.X, Config.GroundY + 1.5, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	if u.bar then
		u.bar:Destroy()
	end
end

Units.onDeath(function(u)
	if u.kind == "tower" then
		ruin(u)
		Units.remove(u)
	elseif u.kind == "nexus" then
		ruin(u)
		Units.remove(u)
		if Structures.onNexusDestroyed then
			Structures.onNexusDestroyed(u.team)
		end
	end
end)

function Structures.clear()
	Structures.towers = {}
	Structures.nexus = {}
end

return Structures
