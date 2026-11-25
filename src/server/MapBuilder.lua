-- Procedurally builds the 3-lane battlefield out of parts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage.Shared.Config)
local MapData = require(ReplicatedStorage.Shared.MapData)
local ModelFactory = require(script.Parent.ModelFactory)

local MapBuilder = {}


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
	local model = ModelFactory.build("Tree", {
		cframe = CFrame.new(pos.X, Config.GroundY, pos.Z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
		scale = rng:NextNumber(0.8, 1.25),
		static = true,
	})
	model.Parent = parent
end

local function lamp(parent, pos)
	local gy = Config.GroundY
	make("Part", {
		Name = "LampPost", Shape = Enum.PartType.Cylinder, Size = Vector3.new(7, 0.45, 0.45),
		CFrame = CFrame.new(pos.X, gy + 3.5, pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(45, 45, 52), Material = Enum.Material.Metal,
	}, parent)
	make("Part", {
		Name = "LampBase", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 1.4, 1.4),
		CFrame = CFrame.new(pos.X, gy + 0.3, pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(45, 45, 52), Material = Enum.Material.Metal,
	}, parent)
	local glowPart = make("Part", {
		Name = "Lantern", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.1,
		CFrame = CFrame.new(pos.X, gy + 7.3, pos.Z), Color = Color3.fromRGB(255, 200, 120),
		Material = Enum.Material.Neon, CanCollide = false,
	}, parent)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 120)
	light.Range = 20
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = glowPart
end

local function rocks(parent, pos, rng)
	for _ = 1, rng:NextInteger(1, 3) do
		local d = rng:NextNumber(1.8, 4.5)
		make("Part", {
			Name = "Rock", Shape = Enum.PartType.Ball, Size = Vector3.one * d,
			CFrame = CFrame.new(pos.X + rng:NextNumber(-2, 2), Config.GroundY + d * 0.2, pos.Z + rng:NextNumber(-2, 2)),
			Color = Color3.fromRGB(rng:NextInteger(105, 130), rng:NextInteger(105, 125), rng:NextInteger(110, 130)),
			Material = Enum.Material.Slate,
		}, parent)
	end
end

local function bush(parent, pos, rng)
	for i = 1, 3 do
		local d = rng:NextNumber(2, 3.4)
		make("Part", {
			Name = "Bush", Shape = Enum.PartType.Ball, Size = Vector3.one * d,
			CFrame = CFrame.new(pos.X + (i - 2) * 1.2, Config.GroundY + d * 0.35, pos.Z + rng:NextNumber(-0.8, 0.8)),
			Color = Color3.fromRGB(rng:NextInteger(40, 60), rng:NextInteger(105, 135), rng:NextInteger(45, 60)),
			Material = Enum.Material.Grass, CanCollide = false,
		}, parent)
	end
end

-- Golden-hour lighting with haze, bloom (so neon glows), color grading and sun rays.
local function setupLighting()
	Lighting.ClockTime = 16.3
	Lighting.GeographicLatitude = 35
	Lighting.Brightness = 2.6
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.Ambient = Color3.fromRGB(40, 40, 52)
	Lighting.OutdoorAmbient = Color3.fromRGB(125, 122, 135)
	Lighting.ShadowSoftness = 0.2
	Lighting.GlobalShadows = true
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:GetAttribute("MobaLighting") then
			child:Destroy()
		end
	end
	local function effect(className, props)
		local e = Instance.new(className)
		for k, v in pairs(props) do
			e[k] = v
		end
		e:SetAttribute("MobaLighting", true)
		e.Parent = Lighting
	end
	effect("Atmosphere", { Density = 0.3, Offset = 0.25, Color = Color3.fromRGB(205, 192, 172), Decay = Color3.fromRGB(110, 118, 150), Glare = 0.35, Haze = 1.4 })
	effect("BloomEffect", { Intensity = 0.6, Size = 28, Threshold = 1.4 })
	effect("ColorCorrectionEffect", { Brightness = 0.02, Contrast = 0.12, Saturation = 0.15, TintColor = Color3.fromRGB(255, 247, 238) })
	effect("SunRaysEffect", { Intensity = 0.07, Spread = 0.8 })
	if not Lighting:FindFirstChildOfClass("Sky") then
		effect("Sky", { SunAngularSize = 14 })
	end
end

function MapBuilder.build()
	MapBuilder.clear()
	local half = MapData.HalfSize
	local gy = Config.GroundY

	local map = Instance.new("Folder")
	map.Name = "Map"

	-- Terrain: grass field, sand lanes, a shallow river you can wade across, stone bases.
	local terrain = workspace.Terrain
	terrain:FillBlock(CFrame.new(0, gy - 6, 0), Vector3.new(half * 2, 12, half * 2), Enum.Material.Grass)
	local w = MapData.LaneWidth
	for _, path in pairs(MapData.Lanes) do
		for i = 1, #path - 1 do
			local a, b = path[i], path[i + 1]
			local mid = (a + b) / 2
			local cf = CFrame.lookAt(Vector3.new(mid.X, gy - 2, mid.Z), Vector3.new(b.X, gy - 2, b.Z))
			terrain:FillBlock(cf, Vector3.new(w, 4, (b - a).Magnitude + w), Enum.Material.Sand)
		end
	end
	local riverCF = CFrame.new(0, gy, 0) * CFrame.Angles(0, -math.pi / 4, 0)
	terrain:FillBlock(riverCF * CFrame.new(0, -2, 0), Vector3.new(half * 2 * 1.4, 4, 26), Enum.Material.Air)
	terrain:FillBlock(riverCF * CFrame.new(0, -3, 0), Vector3.new(half * 2 * 1.4, 2, 30), Enum.Material.Mud)
	terrain:FillBlock(riverCF * CFrame.new(0, -1.25, 0), Vector3.new(half * 2 * 1.4, 1.5, 26), Enum.Material.Water)
	for _, team in ipairs(Config.TeamNames) do
		local center = MapData.Nexus[team]:Lerp(MapData.Fountain[team], 0.4)
		terrain:FillCylinder(CFrame.new(center.X, gy - 2, center.Z), 4, 60, Enum.Material.Slate)
	end
	terrain.WaterColor = Color3.fromRGB(56, 128, 160)
	terrain.WaterTransparency = 0.55
	terrain.WaterReflectance = 0.6
	terrain.WaterWaveSize = 0.08
	terrain.WaterWaveSpeed = 6

	-- Bases and fountains
	for _, team in ipairs(Config.TeamNames) do
		local color = Config.TeamColors[team]
		local fountain = MapData.Fountain[team]
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

	-- Lane lamps (alternating sides), rocks and bushes.
	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = map
	for _, path in pairs(MapData.Lanes) do
		local length = MapData.PathLength(path)
		local side = 1
		for d = 35, length - 35, 70 do
			local p = MapData.PointAlong(path, d / length)
			local ahead = MapData.PointAlong(path, math.min(1, (d + 1) / length))
			local dir = (ahead - p).Magnitude > 0 and (ahead - p).Unit or Vector3.new(1, 0, 0)
			local pos = p + Vector3.new(-dir.Z, 0, dir.X) * (w / 2 + 3) * side
			side = -side
			if math.abs(pos.X - pos.Z) / math.sqrt(2) > 18 and (pos - MapData.Nexus.Blue).Magnitude > 40 and (pos - MapData.Nexus.Red).Magnitude > 40 then
				lamp(props, pos)
			end
		end
	end
	for _ = 1, 260 do
		local p = Vector3.new(rng:NextNumber(-half + 10, half - 10), 0, rng:NextNumber(-half + 10, half - 10))
		local riverDist = math.abs(p.X - p.Z) / math.sqrt(2)
		if MapData.DistToLanes(p) > w / 2 + 4 and riverDist > 16 then
			if rng:NextNumber() < 0.4 then
				rocks(props, p, rng)
			else
				bush(props, p, rng)
			end
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

	setupLighting()
end

function MapBuilder.clear()
	local old = workspace:FindFirstChild("Map")
	if old then
		old:Destroy()
	end
	workspace.Terrain:Clear()
end

return MapBuilder
