--[[
	All on-screen UI: hero select, ability bar, stats, score, kill feed, shop, scoreboard,
	minimap, damage numbers and click markers. Built in code so the project has no assets.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local HeroDefs = require(Shared:WaitForChild("Heroes"))
local Items = require(Shared:WaitForChild("Items"))
local MapData = require(Shared:WaitForChild("MapData"))

local HUD = {}

-- Key shown (and pressed) for each ability slot. W walks forward in first person, so the second
-- ability is on E and the third on F.
HUD.KEY_LABELS = { Q = "Q", W = "E", E = "F", R = "R" }

local remotes
local gui
local el = {} -- named UI elements
local cooldownEnd, cooldownLen = {}, {}
local movement -- client Movement module (dash charges)
local barTarget = { hp = 1, mana = 1 }
local barShown = { hp = 1, mana = 1 }
local lastHp = nil
local killedBy = nil
local streak, streakUntil = 0, 0
local bannerUntil = 0

local DARK = Color3.fromRGB(20, 22, 28)
local PANEL = Color3.fromRGB(30, 33, 42)
local GOLD = Color3.fromRGB(255, 205, 70)
local WHITE = Color3.new(1, 1, 1)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function make(className, props, children)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function corner(r)
	return make("UICorner", { CornerRadius = UDim.new(0, r or 6) })
end

local function label(props, children)
	local defaults = {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextColor3 = WHITE,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for k, v in pairs(props) do
		defaults[k] = v
	end
	return make("TextLabel", defaults, children)
end

local function bar(parent, pos, size, color)
	local bg = make("Frame", {
		Parent = parent, Position = pos, Size = size,
		BackgroundColor3 = DARK, BorderSizePixel = 0,
	}, { corner(3) })
	local fill = make("Frame", {
		Parent = bg, Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BorderSizePixel = 0,
	}, { corner(3) })
	local text = label({
		Parent = bg, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 11, ZIndex = 2, TextStrokeTransparency = 0.5,
	})
	return fill, text
end

local function myTeam()
	return player.Team and player.Team.Name or "Blue"
end

local function heroDef()
	local id = player:GetAttribute("HeroId")
	return id and HeroDefs.Defs[id]
end

local TYPE_NAMES = {
	skillshot = "Skillshot", aoe = "Area", selfaoe = "Area around you", dash = "Dash", buff = "Self buff", execute = "Execute",
}

local function describeAbility(slot, ab)
	local lines = { string.format("[%s] %s  (%s)", HUD.KEY_LABELS[slot], ab.name, TYPE_NAMES[ab.type] or ab.type) }
	if ab.damage then
		table.insert(lines, string.format("Damage: %d (+%d per level, +%d%% Power)", ab.damage, ab.perLevel or 0, (ab.ratio or 0) * 100))
	end
	if ab.missingHp then
		table.insert(lines, string.format("+%d%% of target's missing health", ab.missingHp * 100))
	end
	local extras = {}
	if ab.stun then
		table.insert(extras, string.format("Stun %.1fs", ab.stun))
	end
	if ab.slow then
		table.insert(extras, string.format("Slow %d%% for %.1fs", ab.slow * 100, ab.slowDuration or 2))
	end
	if ab.speedMult then
		table.insert(extras, string.format("+%d%% move speed", (ab.speedMult - 1) * 100))
	end
	if ab.armor then
		table.insert(extras, string.format("+%d armor", ab.armor))
	end
	if ab.attackSpeed or (ab.buff and ab.buff.attackSpeed) then
		table.insert(extras, string.format("+%d%% attack speed", (ab.attackSpeed or ab.buff.attackSpeed) * 100))
	end
	if ab.heal then
		table.insert(extras, string.format("Heal %d", ab.heal))
	end
	if ab.pierce then
		table.insert(extras, "Pierces")
	end
	if ab.count then
		table.insert(extras, string.format("%d projectiles", ab.count))
	end
	if #extras > 0 then
		table.insert(lines, table.concat(extras, " · "))
	end
	table.insert(lines, string.format("Mana %d · Cooldown %ds%s", ab.mana, ab.cooldown, slot == "R" and string.format(" · Unlocks at level %d", Config.UltLevel) or ""))
	return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
local function buildBottomPanel()
	local panel = make("Frame", {
		Parent = gui, Name = "BottomPanel",
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(560, 146), BackgroundColor3 = PANEL, BackgroundTransparency = 0.1,
	}, { corner(10) })
	el.panel = panel
	el.heroTitle = label({ Parent = panel, Position = UDim2.fromOffset(12, 6), Size = UDim2.fromOffset(320, 20), TextSize = 16 })
	el.xpFill = bar(panel, UDim2.fromOffset(12, 28), UDim2.fromOffset(310, 4), Color3.fromRGB(170, 120, 255))

	el.slots = {}
	for i, slot in ipairs(HeroDefs.Slots) do
		local box = make("Frame", {
			Parent = panel, Position = UDim2.fromOffset(12 + (i - 1) * 80, 38), Size = UDim2.fromOffset(70, 70),
			BackgroundColor3 = Color3.fromRGB(55, 60, 78),
		}, { corner(8), make("UIStroke", { Color = Color3.fromRGB(110, 115, 140), Thickness = 1.5 }) })
		local name = label({ Parent = box, Size = UDim2.new(1, -6, 0, 30), Position = UDim2.fromOffset(3, 18), TextSize = 11, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center })
		local key = label({ Parent = box, Position = UDim2.fromOffset(5, 2), Size = UDim2.fromOffset(20, 16), Text = HUD.KEY_LABELS[slot], TextColor3 = GOLD, TextSize = 14 })
		local cost = label({ Parent = box, Position = UDim2.new(0, 0, 1, -16), Size = UDim2.new(1, -5, 0, 14), TextSize = 10, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Color3.fromRGB(120, 180, 255) })
		local overlay = make("Frame", {
			Parent = box, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, ZIndex = 3,
		}, { corner(8) })
		local cdText = label({ Parent = box, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 22, ZIndex = 4, Text = "" })
		local lock = label({
			Parent = box, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 12, ZIndex = 5,
			BackgroundTransparency = 0.25, BackgroundColor3 = Color3.new(0, 0, 0), Text = "Lv " .. Config.UltLevel, Visible = false,
		})
		corner(8).Parent = lock
		box.MouseEnter:Connect(function()
			local def = heroDef()
			if def then
				el.tooltip.Text = describeAbility(slot, def.abilities[slot])
				el.tooltip.Visible = true
			end
		end)
		box.MouseLeave:Connect(function()
			el.tooltip.Visible = false
		end)
		local ready = make("Frame", {
			Parent = box, Size = UDim2.fromScale(1, 1), BackgroundColor3 = GOLD, BackgroundTransparency = 1, ZIndex = 6,
		}, { corner(8) })
		el.slots[slot] = { box = box, name = name, key = key, cost = cost, overlay = overlay, cdText = cdText, lock = lock, ready = ready }
	end

	-- Items and stats on the right
	el.itemBoxes = {}
	for i = 1, Config.MaxItems do
		local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
		local box = make("TextLabel", {
			Parent = panel, Position = UDim2.fromOffset(344 + col * 38, 8 + row * 36), Size = UDim2.fromOffset(34, 32),
			BackgroundColor3 = Color3.fromRGB(50, 54, 68), Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = GOLD, Text = "",
		}, { corner(5) })
		el.itemBoxes[i] = box
	end
	el.stats = label({
		Parent = panel, Position = UDim2.fromOffset(462, 6), Size = UDim2.fromOffset(92, 100), TextSize = 12,
		TextYAlignment = Enum.TextYAlignment.Top, Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(210, 210, 220),
	})
	el.shopHint = label({
		Parent = panel, Position = UDim2.fromOffset(344, 82), Size = UDim2.fromOffset(110, 24), TextSize = 11,
		Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(180, 180, 190), Text = "[B] Shop",
	})

	el.hpFill, el.hpText = bar(panel, UDim2.fromOffset(12, 114), UDim2.new(1, -24, 0, 15), Color3.fromRGB(70, 200, 90))
	el.manaFill, el.manaText = bar(panel, UDim2.fromOffset(12, 131), UDim2.new(1, -24, 0, 10), Color3.fromRGB(70, 130, 240))

	el.tooltip = label({
		Parent = gui, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -164), Size = UDim2.fromOffset(380, 92),
		BackgroundColor3 = DARK, BackgroundTransparency = 0.05, TextSize = 13, Font = Enum.Font.Gotham, TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top, Visible = false, ZIndex = 10,
	}, { corner(8), make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingTop = UDim.new(0, 8), PaddingRight = UDim.new(0, 10) }) })
end

local function buildTopBar()
	local top = make("Frame", {
		Parent = gui, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(320, 40), BackgroundColor3 = PANEL, BackgroundTransparency = 0.1,
	}, { corner(8) })
	el.blueScore = label({ Parent = top, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.35, 0, 1, 0), TextSize = 20, TextColor3 = Config.TeamColors.Blue })
	el.redScore = label({ Parent = top, Position = UDim2.new(0.65, -12, 0, 0), Size = UDim2.new(0.35, 0, 1, 0), TextSize = 20, TextColor3 = Config.TeamColors.Red, TextXAlignment = Enum.TextXAlignment.Right })
	el.clock = label({ Parent = top, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 16 })

	local goldBox = make("Frame", {
		Parent = gui, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(190, 54), BackgroundColor3 = PANEL, BackgroundTransparency = 0.1,
	}, { corner(8) })
	el.gold = label({ Parent = goldBox, Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -24, 0, 24), TextSize = 18, TextColor3 = GOLD })
	el.kda = label({ Parent = goldBox, Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -24, 0, 20), TextSize = 13, Font = Enum.Font.Gotham })

	el.feed = make("Frame", {
		Parent = gui, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 70),
		Size = UDim2.fromOffset(320, 220), BackgroundTransparency = 1,
	}, { make("UIListLayout", { Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder }) })

	el.banner = label({
		Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.fromOffset(700, 80),
		TextXAlignment = Enum.TextXAlignment.Center, TextSize = 48, Font = Enum.Font.GothamBlack, TextStrokeTransparency = 0.3, Text = "",
	})
	el.subBanner = label({
		Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.3, 50), Size = UDim2.fromOffset(700, 30),
		TextXAlignment = Enum.TextXAlignment.Center, TextSize = 20, TextStrokeTransparency = 0.4, Text = "",
	})
	el.toast = label({
		Parent = gui, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -200), Size = UDim2.fromOffset(500, 24),
		TextXAlignment = Enum.TextXAlignment.Center, TextSize = 16, TextColor3 = Color3.fromRGB(255, 120, 120), TextStrokeTransparency = 0.4, Text = "",
	})

	label({
		Parent = gui, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -10), Size = UDim2.fromOffset(300, 90),
		TextSize = 12, Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(230, 230, 230), TextStrokeTransparency = 0.5,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		Text = "WASD: move · Space: jump\nLeft click: shoot / swing · Right click: zoom\nQ E F R: abilities at the crosshair\nB: shop · Tab: scores",
	})
end

local function buildShop()
	local shop = make("Frame", {
		Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(560, 400), BackgroundColor3 = PANEL, Visible = false, ZIndex = 20,
	}, { corner(10) })
	el.shop = shop
	-- A modal button frees the mouse from first-person lock while the shop is open.
	make("TextButton", { Parent = shop, Modal = true, BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 20 })
	label({ Parent = shop, Position = UDim2.fromOffset(16, 10), Size = UDim2.fromOffset(300, 28), Text = "Shop", TextSize = 22, ZIndex = 21 })
	el.shopNote = label({ Parent = shop, Position = UDim2.fromOffset(16, 38), Size = UDim2.fromOffset(500, 18), TextSize = 12, Font = Enum.Font.Gotham, ZIndex = 21 })
	local close = make("TextButton", {
		Parent = shop, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(30, 30),
		Text = "X", Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = WHITE, BackgroundColor3 = Color3.fromRGB(160, 50, 50), ZIndex = 21,
	}, { corner(6) })
	close.MouseButton1Click:Connect(function()
		shop.Visible = false
	end)
	local grid = make("Frame", { Parent = shop, Position = UDim2.fromOffset(16, 64), Size = UDim2.new(1, -32, 1, -80), BackgroundTransparency = 1, ZIndex = 21 }, {
		make("UIGridLayout", { CellSize = UDim2.fromOffset(170, 100), CellPadding = UDim2.fromOffset(9, 9), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, id in ipairs(Items.Order) do
		local item = Items.Defs[id]
		local card = make("TextButton", {
			Parent = grid, LayoutOrder = i, Text = "", AutoButtonColor = true, BackgroundColor3 = Color3.fromRGB(50, 54, 68), ZIndex = 22,
		}, { corner(8) })
		label({ Parent = card, Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -20, 0, 18), Text = item.name, TextSize = 14, ZIndex = 23 })
		label({
			Parent = card, Position = UDim2.fromOffset(10, 30), Size = UDim2.new(1, -20, 0, 40), Text = Items.Describe(id), TextSize = 12,
			Font = Enum.Font.Gotham, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Color3.fromRGB(200, 200, 210), ZIndex = 23,
		})
		label({ Parent = card, Position = UDim2.new(0, 10, 1, -26), Size = UDim2.new(1, -20, 0, 18), Text = item.cost .. " gold", TextColor3 = GOLD, TextSize = 13, ZIndex = 23 })
		card.MouseButton1Click:Connect(function()
			remotes.BuyItem:FireServer(id)
		end)
	end
end

local function buildHeroSelect()
	local frame = make("Frame", {
		Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(950, 400), BackgroundColor3 = PANEL, Visible = false, ZIndex = 30,
	}, { corner(12) })
	el.heroSelect = frame
	make("TextButton", { Parent = frame, Modal = true, BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 30 })
	label({ Parent = frame, Position = UDim2.fromOffset(20, 12), Size = UDim2.fromOffset(400, 32), Text = "Choose your hero", TextSize = 26, ZIndex = 31 })
	el.pickTimer = label({ Parent = frame, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 16), Size = UDim2.fromOffset(300, 24), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 16, ZIndex = 31 })
	for i, id in ipairs(HeroDefs.Order) do
		local def = HeroDefs.Defs[id]
		local card = make("TextButton", {
			Parent = frame, Position = UDim2.fromOffset(20 + (i - 1) * 152, 60), Size = UDim2.fromOffset(144, 320),
			Text = "", BackgroundColor3 = Color3.fromRGB(48, 52, 66), ZIndex = 31,
		}, { corner(10), make("UIStroke", { Color = def.color, Thickness = 2 }) })
		make("Frame", { Parent = card, Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 0, 70), BackgroundColor3 = def.color, ZIndex = 32 }, { corner(8) })
		label({ Parent = card, Position = UDim2.fromOffset(10, 86), Size = UDim2.new(1, -20, 0, 22), Text = def.displayName, TextSize = 18, ZIndex = 32 })
		label({ Parent = card, Position = UDim2.fromOffset(10, 108), Size = UDim2.new(1, -20, 0, 16), Text = def.role .. (def.ranged and " · Ranged" or " · Melee"), TextSize = 12, TextColor3 = GOLD, ZIndex = 32 })
		label({
			Parent = card, Position = UDim2.fromOffset(10, 128), Size = UDim2.new(1, -20, 0, 60), Text = def.description, TextSize = 12, Font = Enum.Font.Gotham,
			TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Color3.fromRGB(210, 210, 220), ZIndex = 32,
		})
		local abilityNames = {}
		for _, slot in ipairs(HeroDefs.Slots) do
			table.insert(abilityNames, slot .. ": " .. def.abilities[slot].name)
		end
		label({
			Parent = card, Position = UDim2.fromOffset(10, 196), Size = UDim2.new(1, -20, 0, 80), Text = table.concat(abilityNames, "\n"), TextSize = 12,
			Font = Enum.Font.Gotham, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 32,
		})
		label({
			Parent = card, Position = UDim2.new(0, 10, 1, -30), Size = UDim2.new(1, -20, 0, 20), TextSize = 11, Font = Enum.Font.Gotham,
			Text = string.format("HP %d · Range %d", def.hp, def.range), TextColor3 = Color3.fromRGB(170, 170, 180), ZIndex = 32,
		})
		card.MouseButton1Click:Connect(function()
			remotes.PickHero:FireServer(id)
			frame.Visible = false
		end)
	end
end

local function buildScoreboard()
	local frame = make("Frame", {
		Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(720, 330), BackgroundColor3 = PANEL, BackgroundTransparency = 0.05, Visible = false, ZIndex = 40,
	}, { corner(10) })
	el.scoreboard = frame
	el.scoreCols = {}
	for i, team in ipairs(Config.TeamNames) do
		local col = make("Frame", {
			Parent = frame, Position = UDim2.new((i - 1) * 0.5, 10, 0, 10), Size = UDim2.new(0.5, -20, 1, -20), BackgroundTransparency = 1, ZIndex = 41,
		}, { make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }) })
		label({ Parent = col, LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 26), Text = team:upper(), TextSize = 18, TextColor3 = Config.TeamColors[team], ZIndex = 41 })
		el.scoreCols[team] = col
	end
end

local function buildMinimap()
	local frame = make("Frame", {
		Parent = gui, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -10, 1, -10),
		Size = UDim2.fromOffset(200, 200), BackgroundColor3 = Color3.fromRGB(50, 80, 45), ClipsDescendants = true,
	}, { corner(8), make("UIStroke", { Color = Color3.fromRGB(20, 20, 20), Thickness = 2 }) })
	el.minimap = frame
	el.dots = {}
end

local pulse = 0
local hitUntil = 0
local function buildCrosshair()
	local holder = make("Frame", {
		Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(60, 60), BackgroundTransparency = 1,
	})
	el.crosshair = holder
	el.crossBars = {}
	for i, d in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
		local horizontal = d[2] == 0
		local bar = make("Frame", {
			Parent = holder, AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, BackgroundColor3 = WHITE,
			Size = horizontal and UDim2.fromOffset(9, 2) or UDim2.fromOffset(2, 9),
		}, { make("UIStroke", { Color = Color3.new(0, 0, 0), Transparency = 0.4, Thickness = 1 }) })
		el.crossBars[i] = { frame = bar, dir = d }
	end
	make("Frame", {
		Parent = holder, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(3, 3), BorderSizePixel = 0, BackgroundColor3 = WHITE,
	}, { corner(2) })
	local hit = make("Frame", {
		Parent = holder, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 1, Visible = false,
	})
	el.hitBars = {}
	for i, rot in ipairs({ 45, -45 }) do
		el.hitBars[i] = make("Frame", {
			Parent = hit, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(22, 2), Rotation = rot, BorderSizePixel = 0, BackgroundColor3 = WHITE,
		})
	end
	el.hitmarker = hit

	-- Dash charges under the crosshair.
	el.dashPips = {}
	for i = 1, 2 do
		local pip = make("Frame", {
			Parent = holder, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, (i - 1.5) * 16, 0.5, 22),
			Size = UDim2.fromOffset(12, 3), BorderSizePixel = 0, BackgroundColor3 = Color3.fromRGB(60, 60, 70), BackgroundTransparency = 0.3,
		}, { corner(2) })
		local fill = make("Frame", { Parent = pip, Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, BackgroundColor3 = Color3.fromRGB(140, 220, 255) }, { corner(2) })
		el.dashPips[i] = fill
	end

	-- Red screen flash when you take damage.
	el.vignette = make("Frame", {
		Parent = gui, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(200, 20, 20), BackgroundTransparency = 1, ZIndex = 0,
	}, {
		make("UIGradient", {
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.85), NumberSequenceKeypoint.new(0.7, 0.85), NumberSequenceKeypoint.new(1, 0) }),
		}),
	})

	-- Kill banner ("ELIMINATED", streaks).
	el.killBanner = label({
		Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.38), Size = UDim2.fromOffset(600, 40),
		TextXAlignment = Enum.TextXAlignment.Center, TextSize = 30, Font = Enum.Font.GothamBlack, TextStrokeTransparency = 0.3,
		TextTransparency = 1, TextStrokeColor3 = Color3.new(0, 0, 0), Text = "",
	}, { make("UIScale", { Scale = 1 }) })
end

local function updateCrosshair(dt)
	pulse *= math.exp(-dt * 12)
	local gap = 7 + pulse * 7
	for _, b in ipairs(el.crossBars) do
		b.frame.Position = UDim2.new(0.5, b.dir[1] * gap, 0.5, b.dir[2] * gap)
	end
	el.hitmarker.Visible = os.clock() < hitUntil
	if movement then
		local charges, _, progress = movement.charges()
		for i, fill in ipairs(el.dashPips) do
			local amount = i <= charges and 1 or (i == charges + 1 and progress or 0)
			fill.Size = UDim2.fromScale(amount, 1)
			fill.BackgroundTransparency = i <= charges and 0 or 0.5
		end
	end
	for key, fill in pairs({ hp = el.hpFill, mana = el.manaFill }) do
		barShown[key] += (barTarget[key] - barShown[key]) * math.min(1, dt * 10)
		fill.Size = UDim2.fromScale(barShown[key], 1)
	end
	local char = player.Character
	local alive = char and (char:GetAttribute("Health") or 0) > 0
	el.crosshair.Visible = alive and player:GetAttribute("HeroId") ~= nil and not HUD.menuOpen()
end

---------------------------------------------------------------------------
-- Updates
---------------------------------------------------------------------------
local function fmtTime(s)
	s = math.max(0, math.floor(s))
	return string.format("%02d:%02d", s // 60, s % 60)
end

local function mapToMinimap(pos)
	local h = MapData.HalfSize
	local u, v = (pos.X + h) / (2 * h), (pos.Z + h) / (2 * h)
	if myTeam() == "Red" then
		u, v = 1 - u, 1 - v
	end
	return UDim2.fromScale(math.clamp(u, 0, 1), math.clamp(v, 0, 1))
end

local function updateMinimap()
	local used = 0
	local function dot(pos, size, color, z)
		used += 1
		local d = el.dots[used]
		if not d then
			d = make("Frame", { Parent = el.minimap, AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0 }, { corner(10) })
			el.dots[used] = d
		end
		d.Visible = true
		d.Position = mapToMinimap(pos)
		d.Size = UDim2.fromOffset(size, size)
		d.BackgroundColor3 = color
		d.ZIndex = z
	end
	-- Lanes (static, drawn as dots along the paths once per update is cheap enough)
	for _, path in pairs(MapData.Lanes) do
		for i = 1, #path - 1 do
			for t = 0, 1, 0.1 do
				dot(path[i]:Lerp(path[i + 1], t), 6, Color3.fromRGB(150, 130, 90), 1)
			end
		end
	end
	local folder = workspace:FindFirstChild("Units")
	if folder then
		for _, m in ipairs(folder:GetChildren()) do
			local team, kind = m:GetAttribute("Team"), m:GetAttribute("Kind")
			if team and (m:GetAttribute("Health") or 0) > 0 and m.PrimaryPart then
				local color = Config.TeamColors[team]
				if kind == "minion" then
					dot(m:GetPivot().Position, 3, color, 2)
				elseif kind == "tower" then
					dot(m:GetPivot().Position, 8, color:Lerp(WHITE, 0.3), 3)
				elseif kind == "nexus" then
					dot(m:GetPivot().Position, 12, color:Lerp(WHITE, 0.3), 3)
				elseif kind == "hero" then
					dot(m:GetPivot().Position, 8, color, 4)
				end
			end
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		if char and char.PrimaryPart and (char:GetAttribute("Health") or 0) > 0 then
			local team = char:GetAttribute("Team")
			local color = p == player and Color3.fromRGB(255, 240, 80) or (Config.TeamColors[team] or WHITE)
			dot(char:GetPivot().Position, p == player and 11 or 9, color, 5)
		end
	end
	for i = used + 1, #el.dots do
		el.dots[i].Visible = false
	end
end

local function updateScoreboard()
	if not el.scoreboard.Visible then
		return
	end
	for _, col in pairs(el.scoreCols) do
		for _, child in ipairs(col:GetChildren()) do
			if child:IsA("TextLabel") and child.LayoutOrder > 0 then
				child:Destroy()
			end
		end
	end
	local board = ReplicatedStorage:FindFirstChild("Scoreboard")
	if not board then
		return
	end
	for i, entry in ipairs(board:GetChildren()) do
		local col = el.scoreCols[entry:GetAttribute("Team")]
		if col then
			local items = {}
			for id in string.gmatch(entry:GetAttribute("Items") or "", "[^,]+") do
				table.insert(items, Items.Defs[id] and Items.Defs[id].short or id)
			end
			label({
				Parent = col, LayoutOrder = i, Size = UDim2.new(1, 0, 0, 44), TextSize = 13, ZIndex = 41,
				BackgroundTransparency = 0.6, BackgroundColor3 = DARK, TextWrapped = true,
				TextColor3 = entry:GetAttribute("Alive") and WHITE or Color3.fromRGB(130, 130, 130),
				Text = string.format("  %s (%s) Lv%d   %d / %d / %d\n  %s",
					entry:GetAttribute("Name") or "?", entry:GetAttribute("Hero") or "?", entry:GetAttribute("Level") or 1,
					entry:GetAttribute("Kills") or 0, entry:GetAttribute("Deaths") or 0, entry:GetAttribute("Assists") or 0,
					table.concat(items, " ")),
			})
		end
	end
end

local function update()
	local now = workspace:GetServerTimeNow()
	local def = heroDef()
	local char = player.Character

	-- Hero select
	if not player:GetAttribute("HeroId") then
		el.heroSelect.Visible = true
		local deadline = player:GetAttribute("PickDeadline") or now
		el.pickTimer.Text = "Random pick in " .. math.max(0, math.ceil(deadline - now)) .. "s"
	else
		el.heroSelect.Visible = false
	end

	-- Score / clock
	local state = ReplicatedStorage:FindFirstChild("MatchState")
	if state then
		el.blueScore.Text = "BLUE " .. (state:GetAttribute("BlueKills") or 0)
		el.redScore.Text = (state:GetAttribute("RedKills") or 0) .. " RED"
		el.clock.Text = fmtTime(now - (state:GetAttribute("StartTime") or now))
	end

	-- Player stats
	el.gold.Text = "Gold: " .. (player:GetAttribute("Gold") or 0)
	el.kda.Text = string.format("K / D / A:  %d / %d / %d", player:GetAttribute("Kills") or 0, player:GetAttribute("Deaths") or 0, player:GetAttribute("Assists") or 0)

	local level = player:GetAttribute("Level") or 1
	el.panel.Visible = def ~= nil
	if def then
		el.heroTitle.Text = string.format("%s  ·  Level %d", def.displayName, level)
		local xp, xpNext = player:GetAttribute("XP") or 0, player:GetAttribute("XPNext") or 1
		el.xpFill.Size = UDim2.fromScale(math.clamp(xp / xpNext, 0, 1), 1)
		el.stats.Text = string.format("Damage %d\nPower %d\nArmor %d\nSpeed %d",
			player:GetAttribute("StatDamage") or 0, player:GetAttribute("StatPower") or 0,
			player:GetAttribute("StatArmor") or 0, player:GetAttribute("StatSpeed") or 0)

		local hp = char and char:GetAttribute("Health") or 0
		local maxHp = char and char:GetAttribute("MaxHealth") or 1
		local mana = char and char:GetAttribute("Mana") or 0
		local maxMana = char and char:GetAttribute("MaxMana") or 1
		barTarget.hp = math.clamp(hp / maxHp, 0, 1)
		if lastHp and hp < lastHp - 1 and hp > 0 then
			HUD.hurt(math.clamp((lastHp - hp) / maxHp * 4, 0.25, 1))
		end
		lastHp = hp
		el.hpText.Text = string.format("%d / %d", hp, maxHp)
		barTarget.mana = math.clamp(mana / maxMana, 0, 1)
		el.manaText.Text = string.format("%d / %d", mana, maxMana)

		local clock = os.clock()
		for _, slot in ipairs(HeroDefs.Slots) do
			local ab = def.abilities[slot]
			local s = el.slots[slot]
			s.name.Text = ab.name
			s.cost.Text = tostring(ab.mana)
			local remaining = (cooldownEnd[slot] or 0) - clock
			if remaining > 0 then
				s.overlay.Size = UDim2.fromScale(1, remaining / (cooldownLen[slot] or 1))
				s.cdText.Text = remaining >= 1 and tostring(math.ceil(remaining)) or string.format("%.1f", remaining)
				s.wasCooling = true
			else
				s.overlay.Size = UDim2.fromScale(1, 0)
				s.cdText.Text = ""
				if s.wasCooling then
					-- Ability is ready again: quick gold glow.
					s.wasCooling = false
					s.ready.BackgroundTransparency = 0.35
					TweenService:Create(s.ready, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
				end
			end
			s.lock.Visible = slot == "R" and level < Config.UltLevel
			s.box.BackgroundColor3 = mana < ab.mana and Color3.fromRGB(40, 45, 80) or Color3.fromRGB(55, 60, 78)
		end

		local items = {}
		for id in string.gmatch(player:GetAttribute("Items") or "", "[^,]+") do
			table.insert(items, id)
		end
		for i, box in ipairs(el.itemBoxes) do
			local id = items[i]
			box.Text = id and Items.Defs[id] and Items.Defs[id].short or ""
		end

		-- Death banner
		local respawnAt = player:GetAttribute("RespawnAt") or 0
		if bannerUntil < clock then
			if respawnAt > now and hp <= 0 then
				el.banner.Text = "YOU DIED"
				el.banner.TextColor3 = Color3.fromRGB(230, 80, 80)
				el.subBanner.Text = (killedBy and ("Eliminated by " .. killedBy .. "  ·  ") or "") .. "Respawning in " .. math.ceil(respawnAt - now) .. "s"
			else
				el.banner.Text = ""
				el.subBanner.Text = ""
			end
		end

		-- Shop note
		local fountain = MapData.Fountain[myTeam()]
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local inShop = hp <= 0 or (hrp and fountain and (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - fountain).Magnitude <= Config.ShopRadius)
		el.shopNote.Text = inShop and "Click an item to buy it." or "You can only buy items at your fountain (or while dead)."
		el.shopNote.TextColor3 = inShop and Color3.fromRGB(140, 230, 140) or Color3.fromRGB(240, 150, 120)
	end

	updateMinimap()
	updateScoreboard()
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
function HUD.init(ctx)
	remotes = ctx.remotes
	movement = ctx.movement
	player.CharacterAdded:Connect(function()
		killedBy, lastHp = nil, nil
	end)
	gui = make("ScreenGui", {
		Name = "MobaHUD", ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	buildBottomPanel()
	buildTopBar()
	buildShop()
	buildHeroSelect()
	buildScoreboard()
	buildMinimap()
	buildCrosshair()
	RunService.RenderStepped:Connect(updateCrosshair)

	local accum = 0
	RunService.RenderStepped:Connect(function(dt)
		accum += dt
		if accum >= 0.1 then
			accum = 0
			update()
		end
	end)
end

function HUD.setCooldown(slot, duration)
	cooldownEnd[slot] = os.clock() + duration
	cooldownLen[slot] = duration
end

function HUD.menuOpen()
	return el.shop ~= nil and (el.shop.Visible or el.heroSelect.Visible)
end

-- Crosshair kick when one of your attacks goes off.
function HUD.attackPulse()
	pulse = 1
end

-- Brief X on the crosshair when your damage lands (red on enemy heroes).
function HUD.hitmarker(heroVsHero)
	hitUntil = os.clock() + 0.15
	for _, bar in ipairs(el.hitBars) do
		bar.BackgroundColor3 = heroVsHero and Color3.fromRGB(255, 70, 60) or WHITE
	end
end

function HUD.hurt(amount)
	el.vignette.BackgroundTransparency = 1 - 0.55 * amount
	TweenService:Create(el.vignette, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
end

function HUD.killBanner(text, color)
	local b = el.killBanner
	b.Text = text
	b.TextColor3 = color
	b.TextTransparency = 0
	b.TextStrokeTransparency = 0.3
	local scale = b:FindFirstChildOfClass("UIScale")
	scale.Scale = 1.6
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(1.6, function()
		if b.Text == text then
			TweenService:Create(b, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

function HUD.toggleShop()
	el.shop.Visible = not el.shop.Visible
end

function HUD.showScoreboard(visible)
	el.scoreboard.Visible = visible
	if visible then
		updateScoreboard()
	end
end

local function feedLine(text, color)
	local line = label({
		Parent = el.feed, Size = UDim2.fromOffset(320, 22), Text = text, TextColor3 = color or WHITE, TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right, BackgroundColor3 = DARK, BackgroundTransparency = 0.4,
		LayoutOrder = -math.floor(os.clock() * 100),
	}, { corner(4), make("UIPadding", { PaddingRight = UDim.new(0, 8) }) })
	Debris:AddItem(line, 8)
	local lines = {}
	for _, c in ipairs(el.feed:GetChildren()) do
		if c:IsA("TextLabel") then
			table.insert(lines, c)
		end
	end
	if #lines > 8 then
		table.sort(lines, function(a, b)
			return a.LayoutOrder > b.LayoutOrder
		end)
		lines[1]:Destroy()
	end
end

function HUD.notify(kind, ...)
	if kind == "kill" then
		local killer, killerTeam, victim, victimTeam = ...
		feedLine(string.format("%s  killed  %s", killer, victim), Config.TeamColors[killerTeam])
		local me = player.DisplayName
		if killer == me and killerTeam == myTeam() then
			local now = os.clock()
			streak = now < streakUntil and streak + 1 or 1
			streakUntil = now + 10
			local names = { [2] = "DOUBLE KILL", [3] = "TRIPLE KILL", [4] = "QUADRA KILL" }
			HUD.killBanner(streak >= 5 and "RAMPAGE" or names[streak] or ("ELIMINATED  " .. string.upper(victim)), streak >= 2 and GOLD or WHITE)
		elseif victim == me and victimTeam == myTeam() then
			killedBy = killer
			streak = 0
		end
	elseif kind == "tower" then
		local team, lane = ...
		feedLine(string.format("%s %s tower destroyed!", team, lane or ""), Config.TeamColors[team == "Blue" and "Red" or "Blue"])
	elseif kind == "victory" then
		local winner = ...
		local won = winner == myTeam()
		el.banner.Text = won and "VICTORY" or "DEFEAT"
		el.banner.TextColor3 = won and GOLD or Color3.fromRGB(230, 80, 80)
		el.subBanner.Text = string.format("%s team destroyed the nexus. New match in %ds.", winner, Config.RestartDelay)
		bannerUntil = os.clock() + Config.RestartDelay
	elseif kind == "msg" then
		local text = ...
		el.toast.Text = text
		local stamp = os.clock()
		task.delay(2.5, function()
			if el.toast.Text == text and os.clock() - stamp >= 2.4 then
				el.toast.Text = ""
			end
		end)
	end
end

function HUD.damageNumber(pos, amount, heroVsHero)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame = CFrame.new(pos + Vector3.new(math.random() * 2 - 1, 3, math.random() * 2 - 1))
	anchor.Parent = workspace.CurrentCamera
	local bb = make("BillboardGui", { Parent = anchor, Size = UDim2.fromOffset(80, 30), AlwaysOnTop = true, Adornee = anchor })
	local text = label({
		Parent = bb, Size = UDim2.fromScale(1, 1), Text = tostring(amount), TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = heroVsHero and 20 or 14, TextColor3 = heroVsHero and Color3.fromRGB(255, 90, 70) or Color3.fromRGB(255, 240, 200),
		TextStrokeTransparency = 0.3,
	})
	TweenService:Create(anchor, TweenInfo.new(0.8), { CFrame = anchor.CFrame + Vector3.new(0, 4, 0) }):Play()
	TweenService:Create(text, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 0.9)
end

function HUD.clickMarker(pos, color)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(0.2, 3, 3)
	p.CFrame = CFrame.new(pos.X, Config.GroundY + 0.3, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	p.Parent = workspace.CurrentCamera
	TweenService:Create(p, TweenInfo.new(0.4), { Size = Vector3.new(0.2, 0.5, 0.5), Transparency = 1 }):Play()
	Debris:AddItem(p, 0.45)
end

return HUD
