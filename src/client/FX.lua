--[[
	Client-side effects: draws what the server's Effects module describes. Everything here is
	local-only (parented under the camera), animated every frame, so it stays smooth regardless of
	network speed and never costs server bandwidth.
]]
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local FX = {}

local folder
local function fxFolder()
	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "ClientFX"
		folder.Parent = workspace.CurrentCamera
	end
	return folder
end

local function part(size, color, cframe, shape)
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

local function glow(p, color, range)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = 2
	light.Shadows = false
	light.Parent = p
end

-- Active projectiles, advanced in one RenderStepped loop.
local homing = {} -- { part, model, lastPos, speed, born }
local shots = {} -- [id] = { part, dir, speed, range, travelled }

local handlers = {}

function handlers.flash(pos, radius, color, duration)
	local p = part(Vector3.one * 0.5, color, CFrame.new(pos), Enum.PartType.Ball)
	p.Transparency = 0.3
	TweenService:Create(p, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * radius * 2,
		Transparency = 1,
	}):Play()
	Debris:AddItem(p, duration + 0.1)
end

function handlers.ring(pos, radius, color, duration)
	local cf = CFrame.new(pos.X, Config.GroundY + 0.25, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	-- Outer warning disc plus an inner disc that grows to show when the spell lands.
	local outer = part(Vector3.new(0.15, radius * 2, radius * 2), color, cf, Enum.PartType.Cylinder)
	outer.Transparency = 0.7
	local inner = part(Vector3.new(0.2, 0.2, 0.2), color, cf, Enum.PartType.Cylinder)
	inner.Transparency = 0.45
	TweenService:Create(inner, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		Size = Vector3.new(0.2, radius * 2, radius * 2),
	}):Play()
	Debris:AddItem(outer, duration)
	Debris:AddItem(inner, duration)
end

function handlers.trail(a, b, color)
	local len = (b - a).Magnitude
	if len < 0.5 then
		return
	end
	local p = part(Vector3.new(0.6, 0.6, len), color, CFrame.lookAt((a + b) / 2, b))
	p.Transparency = 0.3
	TweenService:Create(p, TweenInfo.new(0.4), { Transparency = 1, Size = Vector3.new(0.1, 0.1, len) }):Play()
	Debris:AddItem(p, 0.5)
end

function handlers.homing(fromPos, targetModel, speed, color, size)
	local p = part(Vector3.one * size, color, CFrame.new(fromPos), Enum.PartType.Ball)
	glow(p, color, size * 5)
	table.insert(homing, { part = p, model = targetModel, lastPos = nil, speed = speed, born = os.clock() })
end

function handlers.shot(id, origin, dir, speed, range, width, color)
	local p = part(Vector3.one * width, color, CFrame.new(origin), Enum.PartType.Ball)
	glow(p, color, width * 4)
	shots[id] = { part = p, dir = dir, speed = speed, range = range, travelled = 0 }
end

function handlers.shotEnd(id)
	local s = shots[id]
	if s then
		s.part:Destroy()
		shots[id] = nil
	end
end

function handlers.clear()
	for _, h in ipairs(homing) do
		h.part:Destroy()
	end
	homing = {}
	for id, s in pairs(shots) do
		s.part:Destroy()
		shots[id] = nil
	end
	fxFolder():ClearAllChildren()
end

function FX.handle(kind, ...)
	local fn = handlers[kind]
	if fn then
		fn(...)
	end
end

RunService.RenderStepped:Connect(function(dt)
	for i = #homing, 1, -1 do
		local h = homing[i]
		local target = h.lastPos
		if h.model and h.model.Parent then
			target = h.model:GetPivot().Position
			h.lastPos = target
		end
		local done = not target or os.clock() - h.born > 3
		if not done then
			local delta = target - h.part.Position
			local step = h.speed * dt
			if delta.Magnitude <= step + 0.5 then
				done = true
			else
				h.part.CFrame = CFrame.new(h.part.Position + delta.Unit * step)
			end
		end
		if done then
			h.part:Destroy()
			table.remove(homing, i)
		end
	end
	for id, s in pairs(shots) do
		local step = s.speed * dt
		s.travelled += step
		if s.travelled >= s.range then
			s.part:Destroy()
			shots[id] = nil
		else
			s.part.CFrame = CFrame.new(s.part.Position + s.dir * step)
		end
	end
end)

return FX
