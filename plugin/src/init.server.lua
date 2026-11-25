--[[
	MOBA Model Kit: a Roblox Studio plugin for editing the game's models visually.

	1. Pick a model: an editable copy appears in Workspace (folder "MobaModelKit").
	2. Edit it like any Studio model: move, resize, recolor, add parts or MeshParts
	   (Meshy imports, Creator Store pieces...). Mark parts as "team color" so they turn
	   blue or red in game.
	3. Save: the model goes into ServerStorage.Models, and the game uses it from then on.
	   Heroes stay animated R6 rigs: keep the body part names (Torso, Head, Left Arm, ...)
	   and every other part follows the limb it's closest to.
]]
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")
local ServerStorage = game:GetService("ServerStorage")

local ModelBuilder = require(script.ModelBuilder)
local Specs = ModelBuilder.Specs

local MODELS = {
	{ "Hero_Knight", "Knight" },
	{ "Hero_Mage", "Mage" },
	{ "Hero_Ranger", "Ranger" },
	{ "Hero_Guardian", "Guardian" },
	{ "Hero_Assassin", "Assassin" },
	{ "Minion_melee", "Melee minion" },
	{ "Minion_caster", "Caster minion" },
	{ "Minion_siege", "Siege minion" },
	{ "Tower", "Tower" },
	{ "Nexus", "Nexus" },
	{ "Tree", "Tree" },
}

local previewTeam = "Blue"

---------------------------------------------------------------------------
-- Model helpers
---------------------------------------------------------------------------
local function kitFolder()
	local f = workspace:FindFirstChild("MobaModelKit")
	if not f then
		f = Instance.new("Folder")
		f.Name = "MobaModelKit"
		f.Parent = workspace
	end
	return f
end

local function modelsFolder()
	local f = ServerStorage:FindFirstChild("Models")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Models"
		f.Parent = ServerStorage
	end
	return f
end

local function savedVersions(name)
	local f = ServerStorage:FindFirstChild("Models")
	local found = {}
	if f then
		for _, suffix in ipairs({ "", "_Blue", "_Red" }) do
			local m = f:FindFirstChild(name .. suffix)
			if m then
				table.insert(found, m)
			end
		end
	end
	return found
end

-- The kit model the user is working on: the selection's MobaModel ancestor, or the only one.
local function currentKitModel()
	for _, inst in ipairs(Selection:Get()) do
		local node = inst
		while node and node ~= game do
			if node:IsA("Model") and node:GetAttribute("MobaModel") then
				return node
			end
			node = node.Parent
		end
	end
	local folder = workspace:FindFirstChild("MobaModelKit")
	if folder then
		local kits = {}
		for _, m in ipairs(folder:GetChildren()) do
			if m:IsA("Model") and m:GetAttribute("MobaModel") then
				table.insert(kits, m)
			end
		end
		if #kits == 1 then
			return kits[1]
		end
	end
	return nil
end

local function anchorAll(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
end

local function placementPoint()
	local cam = workspace.CurrentCamera
	local focus = cam and cam.Focus.Position or Vector3.zero
	local count = #kitFolder():GetChildren()
	return CFrame.new(focus.X + count * 25, 0, focus.Z)
end

local function frameCamera(model)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local pivot = model:GetPivot().Position
	local _, size = model:GetBoundingBox()
	local r = math.max(size.X, size.Y, size.Z)
	local center = pivot + Vector3.new(0, size.Y / 2, 0)
	-- Models face -Z, so look at the front.
	cam.CFrame = CFrame.lookAt(center + Vector3.new(r * 0.9, r * 0.6, -r * 1.4), center)
	cam.Focus = CFrame.new(center)
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
local setStatus -- defined with the UI

local function editModel(name)
	local base = placementPoint()
	local model
	local saved = savedVersions(name)
	if #saved > 0 then
		model = saved[1]:Clone()
		model:SetAttribute("MobaModel", name)
		model:PivotTo(base)
		ModelBuilder.recolor(model, previewTeam)
		setStatus(("Editing your saved %s (%s)."):format(name, saved[1].Name))
	else
		model = ModelBuilder.buildParts(name, previewTeam, base, 1)
		setStatus(("Editing the built-in %s. Change anything, then press Save."):format(name))
	end
	anchorAll(model)
	model.Name = name
	model.Parent = kitFolder()
	Selection:Set({ model })
	frameCamera(model)
	ChangeHistoryService:SetWaypoint("MOBA Model Kit: edit " .. name)
end

local function markTeam(value)
	local count = 0
	for _, inst in ipairs(Selection:Get()) do
		local list = inst:IsA("BasePart") and { inst } or inst:GetDescendants()
		for _, part in ipairs(list) do
			if part:IsA("BasePart") then
				part:SetAttribute("TeamColor", value)
				if value then
					part.Color = ModelBuilder.resolveColor(value, previewTeam)
				end
				count += 1
			end
		end
	end
	if count == 0 then
		setStatus("Select one or more parts first.", true)
		return
	end
	ChangeHistoryService:SetWaypoint("MOBA Model Kit: team color")
	setStatus(value and ("%d part(s) will now use the team color."):format(count)
		or ("%d part(s) keep their own color now."):format(count))
end

local function preview(team)
	previewTeam = team
	local folder = workspace:FindFirstChild("MobaModelKit")
	if folder then
		for _, m in ipairs(folder:GetChildren()) do
			ModelBuilder.recolor(m, team)
		end
	end
	setStatus("Previewing " .. team .. " team colors.")
end

local function checkModel(model, spec)
	local parts, names = {}, {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			names[d.Name] = true
		end
	end
	if not names[spec.root] then
		return false, ("The model needs a part named \"%s\" (its root). Undo or rename a part to fix it."):format(spec.root)
	end
	local notes = {}
	if spec.rig == "R6" then
		local missing = {}
		for _, n in ipairs(ModelBuilder.R6_BODY) do
			if not names[n] then
				table.insert(missing, n)
			end
		end
		if #missing > 0 then
			table.insert(notes, "Missing body parts (" .. table.concat(missing, ", ") .. "), so it won't animate.")
		end
	end
	local scripts = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then
			scripts += 1
		end
	end
	if scripts > 0 then
		table.insert(notes, ("Removed %d script(s) from the saved copy."):format(scripts))
	end
	return true, table.concat(notes, " ")
end

local function save(team)
	local model = currentKitModel()
	if not model then
		setStatus("Select the model you're editing first (anything inside it works).", true)
		return
	end
	local name = model:GetAttribute("MobaModel")
	local spec = Specs[name]
	local ok, note = checkModel(model, spec)
	if not ok then
		setStatus(note, true)
		return
	end
	local savedName = team and (name .. "_" .. team) or name
	local copy = model:Clone()
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	anchorAll(copy)
	copy.Name = savedName
	copy:SetAttribute("MobaModel", name)
	local old = modelsFolder():FindFirstChild(savedName)
	if old then
		old:Destroy()
	end
	copy.Parent = modelsFolder()
	ChangeHistoryService:SetWaypoint("MOBA Model Kit: save " .. savedName)

	local msg = ("Saved as ServerStorage > Models > %s. Press Play to see it in game."):format(savedName)
	if not team then
		local overrides = {}
		for _, t in ipairs({ "Blue", "Red" }) do
			if modelsFolder():FindFirstChild(name .. "_" .. t) then
				table.insert(overrides, name .. "_" .. t)
			end
		end
		if #overrides > 0 then
			msg ..= (" Note: %s still overrides it for that team."):format(table.concat(overrides, " and "))
		end
	end
	setStatus(msg .. (note ~= "" and (" " .. note) or ""))
end

local function removeSaved()
	local model = currentKitModel()
	if not model then
		setStatus("Select the model whose saved versions you want to remove.", true)
		return
	end
	local name = model:GetAttribute("MobaModel")
	local saved = savedVersions(name)
	if #saved == 0 then
		setStatus(name .. " has no saved versions; the game uses the built-in one.")
		return
	end
	for _, m in ipairs(saved) do
		m:Destroy()
	end
	ChangeHistoryService:SetWaypoint("MOBA Model Kit: remove " .. name)
	setStatus(("Removed %d saved version(s) of %s. The game uses the built-in model again (Undo brings them back)."):format(#saved, name))
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
local toolbar = plugin:CreateToolbar("MOBA Model Kit")
local toggleButton = toolbar:CreateButton("MobaModelKit", "Edit the MOBA's models", "rbxasset://textures/StudioToolbox/AssetPreview/Model.png", "Model Kit")
toggleButton.ClickableWhenViewportHidden = true

local widget = plugin:CreateDockWidgetPluginGui(
	"MobaModelKit",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 320, 600, 260, 320)
)
widget.Title = "MOBA Model Kit"
widget.Name = "MobaModelKit"
toggleButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

local themed = {}
local function theme(inst, bg, fg)
	table.insert(themed, { inst = inst, bg = bg, fg = fg })
	return inst
end
local function applyTheme()
	local t = settings().Studio.Theme
	for _, e in ipairs(themed) do
		if e.bg then
			e.inst.BackgroundColor3 = t:GetColor(Enum.StudioStyleGuideColor[e.bg])
		end
		if e.fg then
			e.inst.TextColor3 = t:GetColor(Enum.StudioStyleGuideColor[e.fg])
		end
	end
end

local scroll = theme(Instance.new("ScrollingFrame"), "MainBackground")
scroll.Size = UDim2.fromScale(1, 1)
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new()
scroll.Parent = widget
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 8)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = scroll
local pad = Instance.new("UIPadding")
for _, side in ipairs({ "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" }) do
	pad[side] = UDim.new(0, 10)
end
pad.Parent = scroll

local order = 0
local function add(inst)
	order += 1
	inst.LayoutOrder = order
	inst.Parent = scroll
	return inst
end

local function label(text, dim, size, bold)
	local l = theme(Instance.new("TextLabel"), nil, dim and "DimmedText" or "MainText")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Font = bold and Enum.Font.SourceSansBold or Enum.Font.SourceSans
	l.TextSize = size or 15
	l.Text = text
	return l
end

local function button(text, primary, height)
	local b = theme(Instance.new("TextButton"), primary and "DialogMainButton" or "Button", primary and "DialogMainButtonText" or "ButtonText")
	b.Size = UDim2.new(1, 0, 0, height or 28)
	b.Text = text
	b.Font = Enum.Font.SourceSans
	b.TextSize = 15
	b.AutoButtonColor = true
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 4)
	c.Parent = b
	return b
end

local function row(buttons)
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.Size = UDim2.new(1, 0, 0, 28)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.Parent = f
	for i, b in ipairs(buttons) do
		b.LayoutOrder = i
		b.Size = UDim2.new(1 / #buttons, -6 * (#buttons - 1) / #buttons, 1, 0)
		b.Parent = f
	end
	return f
end

-- 1. Pick
add(label("1. Pick a model to edit", false, 17, true))
add(label("An editable copy appears in Workspace > MobaModelKit. Models marked (saved) have a version the game is using.", true, 14))
local grid = Instance.new("Frame")
grid.BackgroundTransparency = 1
grid.Size = UDim2.new(1, 0, 0, 0)
grid.AutomaticSize = Enum.AutomaticSize.Y
local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.new(0.5, -3, 0, 28)
gridLayout.CellPadding = UDim2.fromOffset(6, 6)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = grid
add(grid)
local modelButtons = {}
for i, entry in ipairs(MODELS) do
	local b = button(entry[2])
	b.LayoutOrder = i
	b.Parent = grid
	b.MouseButton1Click:Connect(function()
		editModel(entry[1])
	end)
	modelButtons[entry[1]] = { button = b, label = entry[2] }
end

-- 2. Edit
add(label("2. Edit it", false, 17, true))
add(label("Move, resize and recolor parts, or drop in MeshParts (Meshy, Creator Store). Keep the model's root part. For heroes, keep the body part names (Torso, Head, Left Arm...): every other part follows the nearest limb, so armor and weapons animate.", true, 14))
local markBtn, unmarkBtn = button("Use team color"), button("Keep own color")
add(row({ markBtn, unmarkBtn }))
markBtn.MouseButton1Click:Connect(function()
	markTeam("team")
end)
unmarkBtn.MouseButton1Click:Connect(function()
	markTeam(nil)
end)
add(label("Applies to the selected parts. Team-colored parts turn blue or red in game (plain parts and untextured meshes).", true, 13))
local blueBtn, redBtn = button("Preview Blue"), button("Preview Red")
add(row({ blueBtn, redBtn }))
blueBtn.MouseButton1Click:Connect(function()
	preview("Blue")
end)
redBtn.MouseButton1Click:Connect(function()
	preview("Red")
end)

-- 3. Save
add(label("3. Save it to the game", false, 17, true))
local saveBtn = add(button("Save for both teams", true, 32))
saveBtn.MouseButton1Click:Connect(function()
	save(nil)
end)
local saveBlue, saveRed = button("Save Blue only"), button("Save Red only")
add(row({ saveBlue, saveRed }))
saveBlue.MouseButton1Click:Connect(function()
	save("Blue")
end)
saveRed.MouseButton1Click:Connect(function()
	save("Red")
end)
add(label("Use the team-only saves for meshes with blue or red painted into their texture.", true, 13))
local removeBtn = add(button("Go back to the built-in model"))
local confirmUntil = 0
removeBtn.MouseButton1Click:Connect(function()
	if os.clock() < confirmUntil then
		confirmUntil = 0
		removeBtn.Text = "Go back to the built-in model"
		removeSaved()
	else
		confirmUntil = os.clock() + 3
		removeBtn.Text = "Click again to delete the saved versions"
		task.delay(3, function()
			if os.clock() >= confirmUntil then
				removeBtn.Text = "Go back to the built-in model"
			end
		end)
	end
end)

-- Status
local status = add(label("Pick a model to start.", true, 14))
local function refreshList()
	for name, e in pairs(modelButtons) do
		e.button.Text = e.label .. (#savedVersions(name) > 0 and "  (saved)" or "")
	end
end
function setStatus(text, isError)
	status.Text = text
	status.TextColor3 = isError and Color3.fromRGB(230, 90, 80)
		or settings().Studio.Theme:GetColor(Enum.StudioStyleGuideColor.DimmedText)
	refreshList()
end

applyTheme()
refreshList()
settings().Studio.ThemeChanged:Connect(applyTheme)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	toggleButton:SetActive(widget.Enabled)
	if widget.Enabled then
		refreshList()
	end
end)
