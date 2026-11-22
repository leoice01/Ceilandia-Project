--!strict

local DEFAULT_ZONE = "Rua"

local Zones = {}

local function isPointInsidePart(part: BasePart, worldPos: Vector3): boolean
	local localPos = part.CFrame:PointToObjectSpace(worldPos)
	local half = part.Size * 0.5
	return math.abs(localPos.X) <= half.X
		and math.abs(localPos.Y) <= half.Y
		and math.abs(localPos.Z) <= half.Z
end

function Zones.findZone(position: Vector3, zonesFolder: Instance?): string
	local folder = zonesFolder or workspace:FindFirstChild("Zones")
	if not folder then
		return DEFAULT_ZONE
	end

	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then
			local zoneName = child:GetAttribute("ZoneName")
			if typeof(zoneName) == "string" and zoneName ~= "" and isPointInsidePart(child, position) then
				return zoneName
			end
		end
	end

	return DEFAULT_ZONE
end

return Zones