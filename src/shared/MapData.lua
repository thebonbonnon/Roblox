-- Map layout shared by server (building / AI) and client (minimap).
-- Blue base is the bottom-left corner (-X, +Z), Red base the top-right (+X, -Z).
local MapData = {}

local B = Vector3.new(-230, 0, 230)
local R = Vector3.new(230, 0, -230)

MapData.HalfSize = 300
MapData.LaneWidth = 24
MapData.Nexus = { Blue = B, Red = R }
MapData.Fountain = { Blue = Vector3.new(-264, 0, 264), Red = Vector3.new(264, 0, -264) }

-- Lane paths, written from Blue's nexus to Red's nexus.
MapData.Lanes = {
	Top = { B, Vector3.new(-230, 0, -230), R },
	Mid = { B, R },
	Bot = { B, Vector3.new(230, 0, 230), R },
}
MapData.LaneOrder = { "Top", "Mid", "Bot" }

-- Tower positions as fractions of the lane length, measured from the owning nexus.
-- Tier 1 = inner (base) tower, tier 2 = outer tower.
MapData.TowerFractions = { 0.16, 0.34 }

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

function MapData.GetLanePath(lane, team)
	local path = MapData.Lanes[lane]
	if team == "Blue" then
		return table.clone(path)
	end
	local reversed = {}
	for i = #path, 1, -1 do
		table.insert(reversed, path[i])
	end
	return reversed
end

function MapData.PathLength(path)
	local total = 0
	for i = 1, #path - 1 do
		total += (path[i + 1] - path[i]).Magnitude
	end
	return total
end

function MapData.PointAlong(path, fraction)
	local remaining = MapData.PathLength(path) * fraction
	for i = 1, #path - 1 do
		local seg = path[i + 1] - path[i]
		local len = seg.Magnitude
		if remaining <= len then
			return path[i] + seg.Unit * remaining
		end
		remaining -= len
	end
	return path[#path]
end

function MapData.DistToSegment(p, a, b)
	p, a, b = flat(p), flat(a), flat(b)
	local ab = b - a
	local lenSq = ab:Dot(ab)
	if lenSq < 1e-6 then
		return (p - a).Magnitude
	end
	local t = math.clamp((p - a):Dot(ab) / lenSq, 0, 1)
	return (p - (a + ab * t)).Magnitude
end

function MapData.DistToLanes(p)
	local best = math.huge
	for _, path in pairs(MapData.Lanes) do
		for i = 1, #path - 1 do
			best = math.min(best, MapData.DistToSegment(p, path[i], path[i + 1]))
		end
	end
	return best
end

return MapData
