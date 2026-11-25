--[[
	Hero-shooter movement on top of Roblox walking:
	  Shift        dash in the direction you're moving (2 charges, each recharges)
	  Space (air)  double jump
	  Ctrl / C     slide while moving on the ground: a fast, low burst that slows down
	Runs on the client (players own their character's physics), so it responds instantly.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Movement = {}

local DASH_SPEED = 75
local DASH_TIME = 0.16
local DASH_CHARGES = 2
local DASH_RECHARGE = 2.4
local DOUBLE_JUMP_POWER = 48
local SLIDE_SPEED = 46
local SLIDE_TIME = 0.65
local SLIDE_COOLDOWN = 1.0

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local charges = DASH_CHARGES
local nextCharge = 0 -- os.clock() when the next charge comes back
local dashUntil, dashVel = 0, Vector3.zero
local slideStart, slideUntil, slideDir, nextSlide = 0, 0, Vector3.zero, 0
local airJumped = false
local hooks = {}

local function rig()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 or (char:GetAttribute("Health") or 1) <= 0 then
		return nil
	end
	if char:GetAttribute("Stunned") then
		return nil
	end
	return char, hum, hrp
end

local function flatLook()
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
end

local function moveDir(hum)
	local d = hum.MoveDirection
	return d.Magnitude > 0.1 and Vector3.new(d.X, 0, d.Z).Unit or flatLook()
end

local function dash()
	local _, hum, hrp = rig()
	if not hum or charges <= 0 then
		return
	end
	charges -= 1
	if charges == DASH_CHARGES - 1 then
		nextCharge = os.clock() + DASH_RECHARGE
	end
	dashVel = moveDir(hum) * DASH_SPEED
	dashUntil = os.clock() + DASH_TIME
	hrp.AssemblyLinearVelocity = dashVel + Vector3.new(0, 4, 0)
	if hooks.onDash then
		hooks.onDash(hrp.Position, dashVel.Unit)
	end
end

local function doubleJump()
	local _, hum, hrp = rig()
	if not hum or airJumped then
		return
	end
	local state = hum:GetState()
	if state ~= Enum.HumanoidStateType.Freefall and state ~= Enum.HumanoidStateType.Jumping then
		return
	end
	airJumped = true
	local v = hrp.AssemblyLinearVelocity
	hrp.AssemblyLinearVelocity = Vector3.new(v.X, DOUBLE_JUMP_POWER, v.Z)
	if hooks.onDoubleJump then
		hooks.onDoubleJump(hrp.Position)
	end
end

local function slide()
	local _, hum, hrp = rig()
	local now = os.clock()
	if not hum or now < nextSlide or hum.MoveDirection.Magnitude < 0.1 or hum.FloorMaterial == Enum.Material.Air then
		return
	end
	slideStart, slideUntil, nextSlide = now, now + SLIDE_TIME, now + SLIDE_TIME + SLIDE_COOLDOWN
	slideDir = moveDir(hum)
	if hooks.onSlide then
		hooks.onSlide(hrp.Position)
	end
end

function Movement.charges()
	return charges, DASH_CHARGES, math.clamp(1 - (nextCharge - os.clock()) / DASH_RECHARGE, 0, 1)
end

function Movement.isSliding()
	return os.clock() < slideUntil
end

-- hooks: onDash(pos, dir), onDoubleJump(pos), onSlide(pos), blocked() -> bool (menus open)
function Movement.init(h)
	hooks = h or {}
	UserInputService.InputBegan:Connect(function(input, processed)
		-- Roblox's own controls may mark Space as handled, so only skip while typing in chat.
		local _ = processed
		if UserInputService:GetFocusedTextBox() or (hooks.blocked and hooks.blocked()) then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.LeftShift or key == Enum.KeyCode.RightShift then
			dash()
		elseif key == Enum.KeyCode.Space then
			doubleJump()
		elseif key == Enum.KeyCode.LeftControl or key == Enum.KeyCode.C then
			slide()
		end
	end)

	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if charges < DASH_CHARGES and now >= nextCharge then
			charges += 1
			if charges < DASH_CHARGES then
				nextCharge = now + DASH_RECHARGE
			end
		end
		local _, hum, hrp = rig()
		if not hum then
			return
		end
		if hum.FloorMaterial ~= Enum.Material.Air then
			airJumped = false
		end
		-- Hold the dash velocity for its short duration (walking would otherwise brake it).
		if now < dashUntil then
			local v = hrp.AssemblyLinearVelocity
			hrp.AssemblyLinearVelocity = Vector3.new(dashVel.X, math.max(v.Y, 0), dashVel.Z)
		end
		-- Slide: low camera, fast start easing back to walking speed; steer a little.
		if now < slideUntil then
			local t = (now - slideStart) / SLIDE_TIME
			local speed = SLIDE_SPEED + (hum.WalkSpeed - SLIDE_SPEED) * t * t
			local steer = hum.MoveDirection.Magnitude > 0.1 and Vector3.new(hum.MoveDirection.X, 0, hum.MoveDirection.Z).Unit or slideDir
			slideDir = (slideDir * 0.9 + steer * 0.1).Unit
			local v = hrp.AssemblyLinearVelocity
			hrp.AssemblyLinearVelocity = Vector3.new(slideDir.X * speed, v.Y, slideDir.Z * speed)
			hum.CameraOffset = hum.CameraOffset:Lerp(Vector3.new(0, -1.6, 0), 0.3)
		elseif hum.CameraOffset.Magnitude > 0.01 then
			hum.CameraOffset = hum.CameraOffset:Lerp(Vector3.zero, 0.25)
		end
	end)

	player.CharacterAdded:Connect(function()
		charges, airJumped, dashUntil, slideUntil = DASH_CHARGES, false, 0, 0
	end)
end

return Movement
