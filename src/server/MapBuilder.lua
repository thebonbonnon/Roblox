-- Procedurally builds the 3-lane battlefield out of parts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage.Shared.Config)
local MapData = require(ReplicatedStorage.Shared.MapData)

local MapBuilder = {}

local GRASS = Color3.fromRGB(78, 130, 62)
local LANE = Color3.fromRGB(196, 170, 120)
local RIVER = Color3.fromRGB(70, 140, 190)

local function make(className, props, parent)
	local inst = Instance.new(className)
	if inst:IsA("BasePart") then
		inst.Anchored = true
		inst.TopSurface = Enum.SurfaceType.Smooth
		inst.BottomSurface = Enum.SurfaceType.Smooth
	end
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function disc(parent, name, center, radius, y, thickness, color, material, transparency)
	return make("Part", {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thickness, radius * 2, radius * 2),
		CFrame = CFrame.new(center.X, y, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Transparency = transparency or 0,
		CanCollide = false,
	}, parent)
end

local function tree(parent, pos, rng)
	local h = rng:NextNumber(5, 8)
	make("Part", {
		Name = "Trunk",
		Size = Vector3.new(1.6, h, 1.6),
		CFrame = CFrame.new(pos.X, Config.GroundY + h / 2, pos.Z),
		Color = Color3.fromRGB(105, 70, 40),
		Material = Enum.Material.Wood,
	}, parent)
	local s = rng:NextNumber(7, 11)
	make("Part", {
		Name = "Leaves",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * s,
		CFrame = CFrame.new(pos.X, Config.GroundY + h + s * 0.3, pos.Z),
		Color = Color3.fromRGB(40, rng:NextInteger(90, 120), 45),
		Material = Enum.Material.Grass,
		CanCollide = false,
	}, parent)
end

function MapBuilder.build()
	MapBuilder.clear()
	local half = MapData.HalfSize
	local gy = Config.GroundY

	local map = Instance.new("Folder")
	map.Name = "Map"

	make("Part", {
		Name = "Ground",
		Size = Vector3.new(half * 2, 4, half * 2),
		CFrame = CFrame.new(0, gy - 2, 0),
		Color = GRASS,
		Material = Enum.Material.Grass,
	}, map)

	-- River along the anti-diagonal (cuts all three lanes)
	make("Part", {
		Name = "River",
		Size = Vector3.new(half * 2 * 1.40, 0.1, 26),
		CFrame = CFrame.new(0, gy + 0.03, 0) * CFrame.Angles(0, -math.pi / 4, 0),
		Color = RIVER,
		Material = Enum.Material.Glass,
		Transparency = 0.15,
		CanCollide = false,
	}, map)

	-- Lanes
	local w = MapData.LaneWidth
	for laneName, path in pairs(MapData.Lanes) do
		for i = 1, #path - 1 do
			local a, b = path[i], path[i + 1]
			local mid = (a + b) / 2
			make("Part", {
				Name = laneName .. "Lane",
				Size = Vector3.new(w, 0.14, (b - a).Magnitude + w),
				CFrame = CFrame.lookAt(Vector3.new(mid.X, gy + 0.07, mid.Z), Vector3.new(b.X, gy + 0.07, b.Z)),
				Color = LANE,
				Material = Enum.Material.Sand,
				CanCollide = false,
			}, map)
		end
	end

	-- Bases and fountains
	for _, team in ipairs(Config.TeamNames) do
		local color = Config.TeamColors[team]
		local nexus = MapData.Nexus[team]
		local fountain = MapData.Fountain[team]
		local baseCenter = nexus:Lerp(fountain, 0.4)
		disc(map, team .. "Base", baseCenter, 60, gy + 0.1, 0.2, color:Lerp(LANE, 0.75), Enum.Material.Slate)
		disc(map, team .. "Fountain", fountain, Config.FountainRadius, gy + 0.2, 0.3, color, Enum.Material.Neon, 0.55)
		make("Part", {
			Name = team .. "FountainPillar",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(10, 4, 4),
			CFrame = CFrame.new(fountain.X, gy + 5, fountain.Z) * CFrame.Angles(0, 0, math.rad(90)),
			Color = color,
			Material = Enum.Material.Neon,
		}, map)
	end

	-- Jungle trees (deterministic layout, avoiding lanes, river and bases)
	local trees = Instance.new("Folder")
	trees.Name = "Trees"
	trees.Parent = map
	local rng = Random.new(1337)
	for _ = 1, 500 do
		local p = Vector3.new(rng:NextNumber(-half + 12, half - 12), 0, rng:NextNumber(-half + 12, half - 12))
		local riverDist = math.abs(p.X - p.Z) / math.sqrt(2)
		local farFromBases = (p - MapData.Nexus.Blue).Magnitude > 75 and (p - MapData.Nexus.Red).Magnitude > 75
		if MapData.DistToLanes(p) > w / 2 + 8 and riverDist > 18 and farFromBases then
			tree(trees, p, rng)
		end
	end

	-- Invisible boundary walls
	for _, side in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
		local x, z = side[1], side[2]
		make("Part", {
			Name = "Boundary",
			Size = Vector3.new(x ~= 0 and 4 or half * 2, 60, z ~= 0 and 4 or half * 2),
			CFrame = CFrame.new(x * (half + 2), gy + 30, z * (half + 2)),
			Transparency = 1,
		}, map)
	end

	map.Parent = workspace

	Lighting.ClockTime = 14
	Lighting.Brightness = 2
	Lighting.GlobalShadows = true
end

function MapBuilder.clear()
	local old = workspace:FindFirstChild("Map")
	if old then
		old:Destroy()
	end
end

return MapBuilder
