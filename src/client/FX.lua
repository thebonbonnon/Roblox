--[[
	Client-side effects: draws what the server's Effects module describes, plus local movement
	effects. Everything is local-only (parented under the camera) and animated every frame, so
	it stays smooth regardless of network speed.

	Uses only Roblox's built-in particle textures and sounds (rbxasset://), so no uploads needed.
]]
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local FX = {}

local camera = workspace.CurrentCamera

local TEX = {
	spark = "rbxasset://textures/particles/sparkles_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
}
local SOUNDS = {
	shot = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.25, pitch = 1.6 },
	swing = { id = "rbxasset://sounds/swordslash.wav", volume = 0.4, pitch = 1.1 },
	cast = { id = "rbxasset://sounds/swordlunge.wav", volume = 0.35, pitch = 0.9 },
	boom = { id = "rbxasset://sounds/Rocket shot.wav", volume = 0.6, pitch = 0.6 },
	hit = { id = "rbxasset://sounds/collide.wav", volume = 0.3, pitch = 1.4 },
	dash = { id = "rbxasset://sounds/swordlunge.wav", volume = 0.3, pitch = 1.6 },
}

local folder
local function fxFolder()
	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "ClientFX"
		folder.Parent = camera
	end
	return folder
end

local function part(size, color, cframe, shape, material)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = material or Enum.Material.Neon
	p.Color = color
	p.Size = size
	p.CFrame = cframe
	if shape then
		p.Shape = shape
	end
	p.Parent = fxFolder()
	return p
end

local function glow(p, color, range, brightness)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness or 2
	light.Shadows = false
	light.Parent = p
	return light
end

-- One-shot sound at a position (quietly does nothing if a built-in sound is missing).
function FX.sound(name, pos)
	local s = SOUNDS[name]
	if not s or (camera.CFrame.Position - pos).Magnitude > 90 then
		return
	end
	local holder = part(Vector3.one * 0.1, Color3.new(), CFrame.new(pos))
	holder.Transparency = 1
	local snd = Instance.new("Sound")
	snd.SoundId = s.id
	snd.Volume = s.volume
	snd.PlaybackSpeed = s.pitch * (0.92 + math.random() * 0.16)
	snd.RollOffMaxDistance = 160
	snd.Parent = holder
	snd:Play()
	Debris:AddItem(holder, 3)
end

-- Particle burst at a position.
local function burst(pos, color, opts)
	local holder = part(Vector3.one * 0.1, color, CFrame.new(pos))
	holder.Transparency = 1
	local att = Instance.new("Attachment")
	att.Parent = holder
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEX[opts.texture or "spark"]
	e.Color = ColorSequence.new(color, opts.color2 or color)
	e.LightEmission = opts.emission or 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, opts.size or 1), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, opts.alpha or 0.1), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(opts.life or 0.35, (opts.life or 0.35) * 1.6)
	e.Speed = NumberRange.new((opts.speed or 20) * 0.5, opts.speed or 20)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = opts.drag or 4
	e.Acceleration = opts.accel or Vector3.zero
	e.RotSpeed = NumberRange.new(-180, 180)
	e.Rotation = NumberRange.new(0, 360)
	e.Enabled = false
	e.Parent = att
	e:Emit(opts.count or 16)
	Debris:AddItem(holder, (opts.life or 0.35) * 2 + 0.2)
end

-- Expanding flat shockwave ring on the ground.
local function shockwave(pos, radius, color, duration)
	local cf = CFrame.new(pos.X, Config.GroundY + 0.3, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	local p = part(Vector3.new(0.2, 1, 1), color, cf, Enum.PartType.Cylinder)
	p.Transparency = 0.2
	TweenService:Create(p, TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.1, radius * 2.2, radius * 2.2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(p, duration + 0.1)
end

-- A bright light that fades out (impacts and explosions light up the scene).
local function lightFlash(pos, color, range, duration)
	local p = part(Vector3.one * 0.1, color, CFrame.new(pos))
	p.Transparency = 1
	local light = glow(p, color, range, 6)
	TweenService:Create(light, TweenInfo.new(duration), { Brightness = 0 }):Play()
	Debris:AddItem(p, duration + 0.1)
end

---------------------------------------------------------------------------
-- Screen shake
---------------------------------------------------------------------------
local shake = 0
function FX.shake(amount)
	shake = math.min(1.5, shake + amount)
end
-- Shake scaled by how close the effect is to you.
local function shakeNear(pos, amount, range)
	local d = (camera.CFrame.Position - pos).Magnitude
	if d < range then
		FX.shake(amount * (1 - d / range))
	end
end
RunService:BindToRenderStep("MobaShake", Enum.RenderPriority.Camera.Value + 3, function(dt)
	if shake > 0.001 then
		local t = os.clock() * 40
		camera.CFrame *= CFrame.Angles(math.noise(t, 0) * shake * 0.03, math.noise(0, t) * shake * 0.03, 0)
		shake *= math.exp(-dt * 7)
	end
end)

---------------------------------------------------------------------------
-- Projectiles
---------------------------------------------------------------------------
local homing = {} -- { part, model, lastPos, speed, born, color }
local shots = {} -- [id] = { part, dir, speed, range, travelled, color }

local function withTrail(p, color, width)
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Position, a1.Position = Vector3.new(0, width / 2, 0), Vector3.new(0, -width / 2, 0)
	a0.Parent, a1.Parent = p, p
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Color = ColorSequence.new(color)
	trail.LightEmission = 1
	trail.Lifetime = 0.18
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.FaceCamera = true
	trail.Parent = p
end

local function impact(pos, color, big)
	burst(pos, color, { count = big and 24 or 12, speed = big and 28 or 18, size = big and 1.2 or 0.7, life = 0.3 })
	lightFlash(pos, color, big and 14 or 8, 0.25)
end

---------------------------------------------------------------------------
-- Handlers for server messages
---------------------------------------------------------------------------
local handlers = {}

function handlers.flash(pos, radius, color, duration)
	local p = part(Vector3.one * 0.5, color, CFrame.new(pos), Enum.PartType.Ball)
	p.Transparency = 0.25
	TweenService:Create(p, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * radius * 2,
		Transparency = 1,
	}):Play()
	Debris:AddItem(p, duration + 0.1)

	if radius >= 6 then
		-- Spell explosion: fire, smoke, sparks, shockwave, light, shake and a boom.
		shockwave(pos, radius, color, 0.5)
		burst(pos, color, { count = 40, speed = radius * 4, size = 2, life = 0.45 })
		burst(pos, Color3.fromRGB(255, 170, 80), { texture = "fire", count = 18, speed = radius * 2, size = 3, life = 0.5, color2 = color })
		burst(pos + Vector3.new(0, 1, 0), Color3.fromRGB(90, 90, 100), { texture = "smoke", count = 14, speed = radius * 1.2, size = 4, life = 1.1, emission = 0, alpha = 0.4, accel = Vector3.new(0, 6, 0) })
		lightFlash(pos + Vector3.new(0, 3, 0), color, radius * 3, 0.5)
		shakeNear(pos, radius / 12, 70)
		FX.sound("boom", pos)
	elseif radius >= 2.5 then
		impact(pos, color, radius >= 4)
		FX.sound("hit", pos)
	else
		burst(pos, color, { count = 8, speed = 14, size = 0.6, life = 0.2 })
		FX.sound("swing", pos)
	end
end

function handlers.ring(pos, radius, color, duration)
	local cf = CFrame.new(pos.X, Config.GroundY + 0.25, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	-- Outer warning disc plus an inner disc that grows to show when the spell lands.
	local outer = part(Vector3.new(0.15, radius * 2, radius * 2), color, cf, Enum.PartType.Cylinder)
	outer.Transparency = 0.72
	local edge = part(Vector3.new(0.18, radius * 2.04, radius * 2.04), color, cf * CFrame.new(-0.02, 0, 0), Enum.PartType.Cylinder)
	edge.Transparency = 0.45
	local inner = part(Vector3.new(0.2, 0.2, 0.2), color, cf, Enum.PartType.Cylinder)
	inner.Transparency = 0.4
	TweenService:Create(inner, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		Size = Vector3.new(0.2, radius * 2, radius * 2),
	}):Play()
	TweenService:Create(edge, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.8 }):Play()
	for _, p in ipairs({ outer, edge, inner }) do
		Debris:AddItem(p, duration)
	end
end

function handlers.trail(a, b, color)
	local len = (b - a).Magnitude
	if len < 0.5 then
		return
	end
	local p = part(Vector3.new(0.35, 0.35, len), color, CFrame.lookAt((a + b) / 2, b))
	p.Transparency = 0.15
	TweenService:Create(p, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Transparency = 1, Size = Vector3.new(0.05, 0.05, len) }):Play()
	Debris:AddItem(p, 0.35)
	if len > 12 then
		-- A long thin streak is a missed shot; dashes get a burst of wind particles.
		FX.sound("shot", a)
	else
		burst(a, color, { count = 10, speed = 10, size = 0.8, life = 0.3 })
		burst(b, color, { count = 14, speed = 14, size = 0.9, life = 0.35 })
		FX.sound("dash", b)
	end
end

function handlers.homing(fromPos, targetModel, speed, color, size)
	local p = part(Vector3.one * size, color, CFrame.new(fromPos), Enum.PartType.Ball)
	glow(p, color, size * 6)
	withTrail(p, color, size * 0.9)
	burst(fromPos, color, { count = 6, speed = 10, size = size * 0.6, life = 0.15 })
	FX.sound("shot", fromPos)
	table.insert(homing, { part = p, model = targetModel, lastPos = nil, speed = speed, born = os.clock(), color = color, size = size })
end

function handlers.shot(id, origin, dir, speed, range, width, color)
	local p = part(Vector3.one * width, color, CFrame.new(origin), Enum.PartType.Ball)
	glow(p, color, width * 5)
	withTrail(p, color, width)
	burst(origin, color, { count = 10, speed = 16, size = width * 0.5, life = 0.2 })
	FX.sound("cast", origin)
	shots[id] = { part = p, dir = dir, speed = speed, range = range, travelled = 0, color = color }
end

function handlers.shotEnd(id)
	local s = shots[id]
	if s then
		impact(s.part.Position, s.color, true)
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

---------------------------------------------------------------------------
-- Local movement effects
---------------------------------------------------------------------------
function FX.dash(pos, dir)
	burst(pos - Vector3.new(0, 1.5, 0), Color3.fromRGB(220, 235, 255), { count = 18, speed = 16, size = 1.2, life = 0.35, alpha = 0.5, emission = 0.4 })
	FX.sound("dash", pos)
	FX.shake(0.15)
end

function FX.jump(pos)
	shockwave(pos - Vector3.new(0, 3, 0), 3, Color3.fromRGB(220, 235, 255), 0.35)
	burst(pos - Vector3.new(0, 2.5, 0), Color3.fromRGB(220, 235, 255), { count = 10, speed = 10, size = 0.9, life = 0.3, alpha = 0.5, emission = 0.4 })
end

function FX.slide(pos)
	burst(pos - Vector3.new(0, 2.5, 0), Color3.fromRGB(200, 180, 140), { texture = "smoke", count = 12, speed = 8, size = 2, life = 0.6, emission = 0, alpha = 0.5 })
	FX.sound("dash", pos)
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
				impact(target, h.color, h.size > 1)
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
