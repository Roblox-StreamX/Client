--[[
		   ______                     _  __
		  / __/ /________ ___ ___ _  | |/_/
		 _\ \/ __/ __/ -_) _ `/  ' \_>  <  
		/___/\__/_/  \__/\_,_/_/_/_/_/|_|  
]]

-- StreamX Serializers
-- Lots of code inspired by:
--	 https://raw.githubusercontent.com/howmanysmall/FastBitBuffer/master/src/init.lua

-- Initialization
local BitBuffer = require(script.Parent:FindFirstChild("BitBuffer") or 11809378734)
local SerialMap = {
	["Anchored"] = "Bool",
	["CanCollide"] = "Bool",
	["CanQuery"] = "Bool",
	["CanTouch"] = "Bool",
	["CastShadow"] = "Bool",
	["CFrame"] = "CFrame",
	["Color"] = "Color3",
	["Name"] = "String",
	["Material"] = "Material",
	["MaterialVariant"] = "String",
	["PivotOffset"] = "CFrame",
	["Reflectance"] = "Float32",
	["Size"] = "Vector3",
	["Transparency"] = "Float32"
}

function genSerialMap(m)
	local so = {}
	for o, _ in pairs(m) do table.insert(so, o) end
	table.sort(so)
	return so
end
local SerialOrder = genSerialMap(SerialMap)

-- CFrames (gh/Dekkonot/bitbuffer)
local CFVectorNormIDs = {
	[0] = Vector3.new(1, 0, 0),		-- Enum.NormalId.Right
	[1] = Vector3.new(0, 1, 0),		-- Enum.NormalId.Top
	[2] = Vector3.new(0, 0, 1),		-- Enum.NormalId.Back
	[3] = Vector3.new(-1, 0, 0),		-- Enum.NormalId.Left
	[4] = Vector3.new(0, -1, 0),		-- Enum.NormalId.Bottom
	[5] = Vector3.new(0, 0, -1)		-- Enum.NormalId.Front
}
local CFVectorOne = Vector3.new(1, 1, 1)

-- Enum storage
local EnumMat = Enum.Material:GetEnumItems()

-- Serializers
local Serial = {
	serializeBool = function(bb, v) bb:WriteBool(v) end,
	deserializeBool = function(bb) return bb:ReadBool() end,
	serializeNumber = function(bb, v) bb:WriteInt(16, v) end,
	deserializeNumber = function(bb) return bb:ReadInt(16) end,
	serializeFloat32 = function(bb, v) bb:WriteFloat32(v) end,
	deserializeFloat32 = function(bb) return bb:ReadFloat32() end,
	serializeString = function(bb, v) bb:WriteString(v) end,
	deserializeString = function(bb) return bb:ReadString() end,
	serializeCFrame = function(bb, v)
		-- https://github.com/Dekkonot/bitbuffer/blob/main/src/roblox.lua
		local uv = v.UpVector
		local rv = v.RightVector
		local ra = math.abs(rv:Dot(CFVectorOne))
		local upAligned = math.abs(uv:Dot(CFVectorOne))
		local axisAligned = (math.abs(1 - ra) < 0.00001 or ra == 0)
			and (math.abs(1 - upAligned) < 0.00001 or upAligned == 0)
		if axisAligned then
			local position = v.Position
			local rn, un
			for i = 0, 5 do
				local a = CFVectorNormIDs[i]
				if 1 - a:Dot(rv) < 0.00001 then rn = i end
				if 1 - a:Dot(uv) < 0.00001 then un = i end
			end
			bb:WriteInt(8, rn * 6 + un)
			bb:WriteFloat32(position.X)
			bb:WriteFloat32(position.Y)
			bb:WriteFloat32(position.Z)
		else
			bb:WriteInt(8, 0)
			local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = v:GetComponents()
			bb:WriteFloat32(x)
			bb:WriteFloat32(y)
			bb:WriteFloat32(z)
			bb:WriteFloat32(r00)
			bb:WriteFloat32(r01)
			bb:WriteFloat32(r02)
			bb:WriteFloat32(r10)
			bb:WriteFloat32(r11)
			bb:WriteFloat32(r12)
			bb:WriteFloat32(r20)
			bb:WriteFloat32(r21)
			bb:WriteFloat32(r22)
		end
	end,
	deserializeCFrame = function(bb)
		-- https://github.com/Dekkonot/bitbuffer/blob/main/src/roblox.lua
		local id = bb:ReadInt(8)
		if id == 0 then
			return CFrame.new(
				bb:ReadFloat64(), bb:ReadFloat64(), bb:ReadFloat64(),
				bb:ReadFloat64(), bb:ReadFloat64(), bb:ReadFloat64(),
				bb:ReadFloat64(), bb:ReadFloat64(), bb:ReadFloat64(),
				bb:ReadFloat64(), bb:ReadFloat64(), bb:ReadFloat64()
			)
		else
			local rv = CFVectorNormIDs[math.floor(id / 6)]
			local uv = CFVectorNormIDs[id % 6]
			local lv = rv:Cross(uv)
			return CFrame.new(
				bb:ReadFloat32(), bb:ReadFloat32(), bb:ReadFloat32(),
				rv.X, uv.X, lv.X,
				rv.Y, uv.Y, lv.Y,
				rv.Z, uv.Z, lv.Z
			)
		end
	end,
	serializeVector3 = function(bb, v)
		bb:WriteFloat64(v.X)
		bb:WriteFloat64(v.Y)
		bb:WriteFloat64(v.Z)
	end,
	deserializeVector3 = function(bb)
		return Vector3.new(
			bb:ReadFloat64(),
			bb:ReadFloat64(),
			bb:ReadFloat64()
		)
	end,
	serializeColor3 = function(bb, v)
		bb:WriteUInt(8, 255 * v.R)
		bb:WriteUInt(8, 255 * v.G)
		bb:WriteUInt(8, 255 * v.B)
	end,
	deserializeColor3 = function(bb)
		return Color3.fromRGB(bb:ReadUInt(8), bb:ReadUInt(8), bb:ReadUInt(8))
	end,
	serializeMaterial = function(bb, v) bb:WriteUInt(16, v.Value) end,
	deserializeMaterial = function(bb) return bb:ReadUInt(16) end,
	serializeV3ForTransport = function(p)
		return tostring(math.round(p.X)) .. ":" .. tostring(math.round(p.Y)) .. ":" .. tostring(math.round(p.Z))
	end
}

-- Handlers
local function serialize(p)
	local bb = BitBuffer.new()
	bb:WriteString(p.ClassName)
	for _, v in ipairs(SerialOrder) do
		Serial["serialize" .. SerialMap[v]](bb, p[v])
	end
	local b64 = bb:ToBase64()
	bb:ResetBuffer()
	setmetatable(bb, nil)
	return Serial.serializeV3ForTransport(p.Position) .. ":" .. b64
end
local function deserialize(p, f, rc, pts)
	local bb = BitBuffer.FromBase64(p)
	local pt = Instance.new(bb:ReadString())
	for _, v in ipairs(SerialOrder) do
		pt[v] = Serial["deserialize" .. SerialMap[v]](bb)
	end
	bb:ResetBuffer()
	setmetatable(bb, nil)
	if rc then
		for p, c in pairs(pts) do
			if c.CFrame == pt.CFrame then
				table.remove(pts, p)
				return c
			end
		end
	end
	pt.Parent = f
	return pt
end

Serial.serialize = serialize
Serial.deserialize = deserialize
return Serial
