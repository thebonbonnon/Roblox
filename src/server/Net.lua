-- Creates the RemoteEvents used between client and server.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

local EVENTS = {
	-- client -> server
	"SetTarget", -- (model?) right-clicked enemy to auto-attack, or nil to clear
	"CastAbility", -- (slot, Vector3 mouse ground position)
	"BuyItem", -- (itemId)
	"PickHero", -- (heroId)
	-- server -> client
	"Cooldown", -- (slot, duration)
	"Notify", -- (kind, ...) kill feed, victory, messages
	"FX", -- (kind, ...) cosmetic effects such as damage numbers
}

function Net.init()
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
	end
	for _, name in ipairs(EVENTS) do
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		Net[name] = remote
	end
	folder.Parent = ReplicatedStorage
	return Net
end

return Net
