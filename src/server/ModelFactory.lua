--[[
	Builds every unit model in the game.

	Where models come from, in order:
	  1. ServerStorage.Models (or ReplicatedStorage.Models): a model named "<name>_<team>"
	     (e.g. "Tower_Red") or "<name>" (e.g. "Tower", "Hero_Knight").
	     - Saved with the MOBA Model Kit plugin (has a MobaModel attribute): used exactly as built,
	       with TeamColor parts recolored. Heroes stay animated R6 rigs.
	     - Anything else (a Creator Store or Meshy import): scaled to the built-in model's height,
	       stood on the ground, and moved as one rigid piece.
	  2. Otherwise the built-in model from ModelSpecs (tools/gen_models.py).
	Scripts inside custom models are always removed.

	Usage:
	  local model, root, info = ModelFactory.build("Tower", {
	      team = "Blue", cframe = CFrame.new(x, groundY, z), static = true, parent = folder })
	  info.rootY      root part height above the ground point
	  info.barHeight  health bar offset above the root
	  info.fire       part that projectiles are fired from (if any)
	  info.humanoid   the rig's Humanoid (R6 heroes)
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local PhysicsService = game:GetService("PhysicsService")

local ModelBuilder = require(ReplicatedStorage.Shared.ModelBuilder)
local Specs = ModelBuilder.Specs

local ModelFactory = {}

-- Moving units don't collide with players, the map or each other (no snagging on towers/trees).
ModelFactory.UNIT_GROUP = "MobaUnits"
pcall(function()
	PhysicsService:RegisterCollisionGroup(ModelFactory.UNIT_GROUP)
	PhysicsService:CollisionGroupSetCollidable(ModelFactory.UNIT_GROUP, "Default", false)
	PhysicsService:CollisionGroupSetCollidable(ModelFactory.UNIT_GROUP, ModelFactory.UNIT_GROUP, false)
end)

local function findCustom(name, team)
	local candidates = team and { name .. "_" .. team, name } or { name }
	for _, candidate in ipairs(candidates) do
		for _, container in ipairs({ ServerStorage, ReplicatedStorage }) do
			local folder = container:FindFirstChild("Models")
			local m = folder and folder:FindFirstChild(candidate)
			if m and m:IsA("Model") then
				return m
			end
		end
	end
	return nil
end
ModelFactory.findCustom = findCustom

local function cleanClone(template)
	local model = template:Clone()
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then
			d:Destroy() -- never run scripts that came with a free model
		elseif d:IsA("Humanoid") then
			d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			d.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		end
	end
	return model
end

local function baseParts(model)
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			parts[#parts + 1] = d
		end
	end
	return parts
end

local function findPart(parts, name)
	for _, p in ipairs(parts) do
		if p.Name == name then
			return p
		end
	end
	return nil
end

-- A model saved with the MOBA Model Kit: its pivot is already the ground point.
local function buildFromKit(template, spec, opts, scale)
	local model = cleanClone(template)
	if scale ~= 1 then
		model:ScaleTo(model:GetScale() * scale)
	end
	model:PivotTo(opts.cframe)
	ModelBuilder.recolor(model, opts.team)
	local parts = baseParts(model)
	local root = findPart(parts, spec.root) or model.PrimaryPart
	local fire = spec.fire and findPart(parts, spec.fire) or nil
	for _, p in ipairs(parts) do
		if p:GetAttribute("FirePoint") then
			fire = p
		end
	end
	return model, root, fire, parts
end

-- Any other model (Creator Store, Meshy...): fit it to the built-in model's size.
local function buildFromImport(template, spec, opts, scale)
	local model = cleanClone(template)
	local _, size = model:GetBoundingBox()
	if size.Y > 0.01 then
		model:ScaleTo(model:GetScale() * (spec.height * scale) / size.Y)
	end
	local bbox, newSize = model:GetBoundingBox()
	local bottom = CFrame.new(bbox.Position - Vector3.new(0, newSize.Y / 2, 0))
	model:PivotTo(opts.cframe * bottom:ToObjectSpace(model:GetPivot()))

	local parts = baseParts(model)
	for _, d in ipairs(parts) do
		if string.sub(d.Name, 1, 4) == "Team" and d:GetAttribute("TeamColor") == nil then
			d:SetAttribute("TeamColor", "team")
		end
	end
	ModelBuilder.recolor(model, opts.team)

	-- Invisible root (and fire point) matching the built-in model keeps gameplay identical.
	local function invisible(name, p, collide)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = ModelBuilder.partSize(p, scale)
		part.CFrame = opts.cframe * ModelBuilder.localCFrame(p, scale)
		part.Transparency = 1
		part.CanCollide = collide
		part.CanTouch = false
		part.CastShadow = false
		part.Parent = model
		parts[#parts + 1] = part
		return part
	end
	local root, fire
	for _, p in ipairs(spec.parts) do
		if p.name == spec.root then
			root = invisible("Root", p, p.collide == true)
		elseif p.name == spec.fire then
			fire = invisible("FirePoint", p, false)
		end
	end
	return model, root, fire, parts
end

function ModelFactory.has(name)
	return Specs[name] ~= nil
end

function ModelFactory.build(name, opts)
	local spec = Specs[name]
	assert(spec, "No model spec named " .. tostring(name))
	opts = opts or {}
	opts.cframe = opts.cframe or CFrame.new()
	local scale = opts.scale or 1

	local custom = findCustom(name, opts.team)
	local isKit = custom ~= nil and custom:GetAttribute("MobaModel") ~= nil
	local model, root, fire, parts
	if custom then
		if isKit then
			model, root, fire, parts = buildFromKit(custom, spec, opts, scale)
		else
			model, root, fire, parts = buildFromImport(custom, spec, opts, scale)
		end
		if not root then
			warn(string.format("[ModelFactory] %s has no root part; using the built-in model", custom.Name))
			model:Destroy()
			custom, isKit = nil, false
		end
	end
	if not custom then
		local parts2
		model, parts2, root, fire = ModelBuilder.buildParts(name, opts.team, opts.cframe, scale)
		parts = parts2
	end

	-- Heroes become animated R6 rigs; everything else is one rigid piece welded to its root.
	local humanoid
	if spec.rig == "R6" and (not custom or isKit) then
		local err
		humanoid, err = ModelBuilder.assembleR6(model, parts)
		if not humanoid then
			warn(string.format("[ModelFactory] %s can't be animated (%s); it will move as one piece", model.Name, err))
		end
	end
	if not humanoid then
		for _, part in ipairs(parts) do
			for _, child in ipairs(part:GetChildren()) do
				if child:IsA("JointInstance") or child:IsA("WeldConstraint") then
					child:Destroy()
				end
			end
			if opts.static or part == root then
				part.Anchored = true
			else
				part.Anchored = false
				part.Massless = true
				ModelBuilder.weld(root, part)
			end
		end
	end
	if not opts.static then
		for _, part in ipairs(parts) do
			part.CanCollide = false
			part.CanTouch = false
			part.CollisionGroup = ModelFactory.UNIT_GROUP
		end
	end

	model.Name = opts.name or name
	model.PrimaryPart = root
	model:SetAttribute("MobaModel", nil)

	-- Health bar sits just above the model (custom models may be taller than the built-in one).
	local groundY = opts.cframe.Position.Y
	local rootY = root.Position.Y - groundY
	local bbox, size = model:GetBoundingBox()
	local top = bbox.Position.Y + size.Y / 2 - groundY
	local barTop = math.max(spec.barTop * scale, top + 0.8)
	if opts.parent then
		model.Parent = opts.parent
	end
	return model, root, {
		rootY = rootY,
		barHeight = barTop - rootY,
		fire = fire,
		height = top,
		humanoid = humanoid,
	}
end

---------------------------------------------------------------------------
-- Player hero gear
---------------------------------------------------------------------------
-- Puts a hero's gear (armor, helmet, weapon, shield...) onto a player's R6 character, taken
-- from the kit-saved hero model if there is one, otherwise from the built-in model.
-- Returns false if the character isn't R6.
function ModelFactory.attachGear(name, character, team)
	local spec = Specs[name]
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not spec or spec.rig ~= "R6" or not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R6 then
		return false
	end
	local custom = findCustom(name, team)
	local source
	if custom and custom:GetAttribute("MobaModel") then
		source = cleanClone(custom)
		source:PivotTo(CFrame.new())
		ModelBuilder.recolor(source, team)
	else
		source = ModelBuilder.buildParts(name, team, CFrame.new(), 1)
	end
	local parts = baseParts(source)
	local body = ModelBuilder.findBody(parts)
	if not body.Torso then
		source:Destroy()
		return false
	end

	local folder = Instance.new("Folder")
	folder.Name = "HeroGear"
	local coversHead = false
	for _, part in ipairs(parts) do
		local isBody = body[part.Name] == part
		-- Players keep their own face, so skip painted-on bot eyes (glowing visor eyes stay).
		local paintedEye = string.sub(part.Name, 1, 3) == "Eye" and part.Material ~= Enum.Material.Neon
		if not isBody and not paintedEye then
			local limbName = ModelBuilder.limbFor(part, body)
			local srcLimb, dstLimb = body[limbName], character:FindFirstChild(limbName)
			if srcLimb and dstLimb and dstLimb:IsA("BasePart") then
				local offset = srcLimb.CFrame:Inverse() * part.CFrame
				for _, child in ipairs(part:GetChildren()) do
					if child:IsA("JointInstance") or child:IsA("WeldConstraint") then
						child:Destroy()
					end
				end
				part.CFrame = dstLimb.CFrame * offset
				part.Anchored = false
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.Massless = true
				ModelBuilder.weld(dstLimb, part)
				part.Parent = folder
				if limbName == "Head" and math.max(part.Size.X, part.Size.Y, part.Size.Z) >= 1.4 then
					coversHead = true -- helmet, hood or hat
				end
			end
		end
	end
	source:Destroy()

	-- Hats and hair would poke through helmets and hoods.
	if coversHead then
		for _, acc in ipairs(character:GetChildren()) do
			if acc:IsA("Accessory") and (acc.AccessoryType == Enum.AccessoryType.Hat or acc.AccessoryType == Enum.AccessoryType.Hair) then
				acc:Destroy()
			end
		end
	end
	folder.Parent = character
	return true
end


return ModelFactory
