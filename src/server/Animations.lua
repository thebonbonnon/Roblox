--[[
	R6 animations for hero rigs. These are Roblox's own default R6 animations (the ones the
	classic R6 "Animate" script uses), which any game can load.
]]
local Animations = {}

local IDS = {
	idle = "rbxassetid://180435571",
	walk = "rbxassetid://180426354",
	slash = "rbxassetid://129967390",
	lunge = "rbxassetid://129967478",
}

local cache = {}
local function animation(name)
	if not cache[name] then
		local a = Instance.new("Animation")
		a.Name = name
		a.AnimationId = IDS[name]
		cache[name] = a
	end
	return cache[name]
end

-- Returns a small controller, or nil if there is no Humanoid.
-- options.actionsOnly: only use attack animations (for player characters, whose own Animate
-- script plays idle and walk).
function Animations.attach(humanoid, options)
	if not humanoid then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local ok, tracks = pcall(function()
		local t = {}
		for name in pairs(IDS) do
			t[name] = animator:LoadAnimation(animation(name))
		end
		t.idle.Looped = true
		t.walk.Looped = true
		t.idle.Priority = Enum.AnimationPriority.Idle
		t.walk.Priority = Enum.AnimationPriority.Movement
		t.slash.Priority = Enum.AnimationPriority.Action
		t.lunge.Priority = Enum.AnimationPriority.Action
		return t
	end)
	if not ok then
		warn("[Animations] could not load R6 animations:", tracks)
		return nil
	end

	local ctrl = { tracks = tracks, moving = nil }

	-- speed: studs per second (0 = standing still)
	function ctrl.setMoving(speed)
		local moving = speed > 0.1
		if moving ~= ctrl.moving then
			ctrl.moving = moving
			if moving then
				tracks.idle:Stop(0.2)
				tracks.walk:Play(0.15)
			else
				tracks.walk:Stop(0.2)
				tracks.idle:Play(0.2)
			end
		end
		if moving then
			-- The R6 walk cycle is authored for the default 16 studs/s walk speed.
			tracks.walk:AdjustSpeed(speed / 16)
		end
	end

	-- kind: "slash" (melee swing) or "lunge" (thrust / cast)
	function ctrl.attack(kind)
		local track = tracks[kind or "slash"]
		if track then
			track:Play(0.05)
		end
	end

	if options and options.actionsOnly then
		ctrl.setMoving = function() end
	else
		ctrl.setMoving(0)
	end
	return ctrl
end

return Animations
