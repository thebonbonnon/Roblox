-- Server-side visual effects (neon parts that replicate to everyone).
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Effects = {}

local function fxFolder()
	local folder = workspace:FindFirstChild("FX")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "FX"
		folder.Parent = workspace
	end
	return folder
end

function Effects.basePart(size, color, cframe, shape)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	p.CFrame = cframe
	if shape then
		p.Shape = shape
	end
	p.Parent = fxFolder()
	return p
end

-- Expanding, fading sphere.
function Effects.flash(pos, radius, color, duration)
	duration = duration or 0.35
	local p = Effects.basePart(Vector3.one * 0.5, color, CFrame.new(pos), Enum.PartType.Ball)
	p.Transparency = 0.35
	TweenService:Create(p, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * radius * 2,
		Transparency = 1,
	}):Play()
	Debris:AddItem(p, duration + 0.1)
end

-- Flat telegraph disc on the ground.
function Effects.ring(pos, radius, color, duration)
	local cf = CFrame.new(pos.X, Config.GroundY + 0.25, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	local p = Effects.basePart(Vector3.new(0.2, radius * 2, radius * 2), color, cf, Enum.PartType.Cylinder)
	p.Transparency = 0.65
	Debris:AddItem(p, duration)
	return p
end

-- Thin streak between two points (dash trails).
function Effects.trail(a, b, color)
	local len = (b - a).Magnitude
	if len < 0.5 then
		return
	end
	local p = Effects.basePart(Vector3.new(0.6, 0.6, len), color, CFrame.lookAt((a + b) / 2, b))
	p.Transparency = 0.3
	TweenService:Create(p, TweenInfo.new(0.4), { Transparency = 1, Size = Vector3.new(0.1, 0.1, len) }):Play()
	Debris:AddItem(p, 0.5)
end

-- Projectile that homes onto a moving target. getTargetPos returns nil when the target is gone.
function Effects.homing(fromPos, getTargetPos, speed, color, size, onHit)
	local p = Effects.basePart(Vector3.one * size, color, CFrame.new(fromPos), Enum.PartType.Ball)
	local started = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		local targetPos = getTargetPos()
		if not targetPos or os.clock() - started > 3 or not p.Parent then
			conn:Disconnect()
			p:Destroy()
			return
		end
		local delta = targetPos - p.Position
		local step = speed * dt
		if delta.Magnitude <= step + 0.5 then
			conn:Disconnect()
			p:Destroy()
			onHit()
			return
		end
		p.CFrame = CFrame.new(p.Position + delta.Unit * step)
	end)
end

function Effects.clear()
	local folder = workspace:FindFirstChild("FX")
	if folder then
		folder:ClearAllChildren()
	end
end

return Effects
