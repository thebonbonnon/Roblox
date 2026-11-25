--[[
	Visual effects. The server only decides *what* happens and sends one small message per effect;
	each client draws and animates it locally (src/client/FX.lua), so effects are smooth at any
	frame rate and cost almost no network traffic. Gameplay timing (when damage lands) is still
	simulated here on the server.
]]
local RunService = game:GetService("RunService")

local Effects = {}

local net
local nextShotId = 0

function Effects.init(netModule)
	net = netModule
end

local function send(...)
	if net then
		net.FX:FireAllClients(...)
	end
end

-- Expanding, fading sphere.
function Effects.flash(pos, radius, color, duration)
	send("flash", pos, radius, color, duration or 0.35)
end

-- Ground telegraph for delayed spells.
function Effects.ring(pos, radius, color, duration)
	send("ring", pos, radius, color, duration)
end

-- Streak between two points (dashes).
function Effects.trail(a, b, color)
	send("trail", a, b, color)
end

-- Homing projectile (basic attacks). The server tracks its flight to time the hit; clients draw
-- a ball that follows `targetModel`.
function Effects.homing(fromPos, targetModel, getTargetPos, speed, color, size, onHit)
	send("homing", fromPos, targetModel, speed, color, size)
	local pos = fromPos
	local started = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		local targetPos = getTargetPos()
		if not targetPos or os.clock() - started > 3 then
			conn:Disconnect()
			return
		end
		local delta = targetPos - pos
		local step = speed * dt
		if delta.Magnitude <= step + 0.5 then
			conn:Disconnect()
			onHit()
			return
		end
		pos += delta.Unit * step
	end)
end

-- Straight skillshot visual. Returns an id so the shot can be removed early when it hits.
function Effects.skillshot(origin, dir, speed, range, width, color)
	nextShotId += 1
	send("shot", nextShotId, origin, dir, speed, range, width, color)
	return nextShotId
end

function Effects.endShot(id)
	send("shotEnd", id)
end

function Effects.clear()
	send("clear")
end

return Effects
