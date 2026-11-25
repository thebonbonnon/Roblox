--[[
	First-person viewmodel: your hero's own arms and whatever they hold (sword, staff, bow,
	shield, carbine...), shown in the corners of the screen. Built from the same model specs as
	the 3D heroes, so a hero edited with the Model Kit plugin shows its new weapon here too.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ModelBuilder = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ModelBuilder"))

local Viewmodel = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local SCALE = 0.6
local ARM_ANGLE = math.rad(85) -- arms point forward, slightly down
local SHOULDER = { ["Right Arm"] = Vector3.new(0.75, -0.55, 0.15), ["Left Arm"] = Vector3.new(-0.75, -0.55, 0.15) }

local model -- the current viewmodel
local entries = {} -- { part, limb, offset }
local builtFor = ""
local kick = 0
local hidden = false

local function clear()
	if model then
		model:Destroy()
	end
	model, entries = nil, {}
end

-- A hero edited with the Model Kit and saved to ReplicatedStorage.Models is visible to clients;
-- otherwise the built-in model is used.
local function sourceModel(name, team)
	local folder = ReplicatedStorage:FindFirstChild("Models")
	local custom = folder and (folder:FindFirstChild(name .. "_" .. team) or folder:FindFirstChild(name))
	if custom and custom:IsA("Model") and custom:GetAttribute("MobaModel") then
		local copy = custom:Clone()
		copy:PivotTo(CFrame.new())
		copy:ScaleTo(copy:GetScale() * SCALE)
		ModelBuilder.recolor(copy, team)
		local parts = {}
		for _, d in ipairs(copy:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(parts, d)
			elseif d:IsA("LuaSourceContainer") then
				d:Destroy()
			end
		end
		return copy, parts
	end
	local m, parts = ModelBuilder.buildParts(name, team, CFrame.new(), SCALE)
	return m, parts
end

local function build(heroId, team)
	clear()
	local name = "Hero_" .. heroId
	if not ModelBuilder.Specs[name] then
		return
	end
	local src, parts = sourceModel(name, team)
	local body = ModelBuilder.findBody(parts)
	if not body["Right Arm"] then
		src:Destroy()
		return
	end
	model = Instance.new("Model")
	model.Name = "Viewmodel"
	for _, part in ipairs(parts) do
		if body[part.Name] ~= part then
			local limb = ModelBuilder.limbFor(part, body)
			if limb == "Right Arm" or limb == "Left Arm" then
				table.insert(entries, { part = part, limb = limb, offset = body[limb].CFrame:Inverse() * part.CFrame })
				for _, child in ipairs(part:GetChildren()) do
					if child:IsA("JointInstance") or child:IsA("WeldConstraint") then
						child:Destroy()
					end
				end
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.CastShadow = false
				part.Parent = model
			end
		end
	end
	src:Destroy()
	model.Parent = camera
end

-- Recoil / swing kick, 0..1.
function Viewmodel.kick(amount)
	kick = math.max(kick, amount or 1)
end

function Viewmodel.setHidden(value)
	hidden = value
end

function Viewmodel.init()
	RunService:BindToRenderStep("MobaViewmodel", Enum.RenderPriority.Camera.Value + 2, function(dt)
		local heroId = player:GetAttribute("HeroId")
		local team = player.Team and player.Team.Name or "Blue"
		local key = tostring(heroId) .. team
		if heroId and key ~= builtFor then
			builtFor = key
			build(heroId, team)
		end
		if not model then
			return
		end

		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local alive = hum and hum.Health > 0 and (char:GetAttribute("Health") or 1) > 0
		local firstPerson = (camera.CFrame.Position - camera.Focus.Position).Magnitude < 1.5
		local show = alive and firstPerson and not hidden
		local parent = show and camera or nil
		if model.Parent ~= parent then
			model.Parent = parent
		end
		if not show then
			return
		end

		kick *= math.exp(-dt * 10)
		local t = os.clock()
		local moving = hum.MoveDirection.Magnitude > 0.1 and hum.FloorMaterial ~= Enum.Material.Air
		local bob = moving and Vector3.new(math.cos(t * 9) * 0.04, math.abs(math.sin(t * 9)) * 0.05, 0) or Vector3.zero
		local cam = camera.CFrame
		local limbCF = {}
		for limb, shoulder in pairs(SHOULDER) do
			local swing = limb == "Right Arm" and kick or kick * 0.3
			limbCF[limb] = cam
				* CFrame.new(shoulder + bob + Vector3.new(0, 0, swing * 0.15))
				* CFrame.Angles(ARM_ANGLE - swing * math.rad(25), 0, 0)
				* CFrame.new(0, -1 * SCALE, 0)
		end
		for _, e in ipairs(entries) do
			e.part.CFrame = limbCF[e.limb] * e.offset
		end
	end)
	player.CharacterAdded:Connect(function()
		builtFor = "" -- rebuild for the new life (team or hero may have changed)
	end)
end

return Viewmodel
