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
	["Reflectance"] = "Number",
	["Size"] = "Vector3",
	["Transparency"] = "Number"
}
local SerialMapSpecs = {
	["MeshPart"] = {
		["MeshId"] = "String",
		["TextureID"] = "String"
	},
	["UnionOperation"] = {
		["AssetId"] = "String"
	}
}

function genSerialMap(m)
	local so = {}
	for o, _ in pairs(m) do table.insert(so, o) end
	table.sort(so)
	return so
end
function round(n, p)
	local pl = (p) and (10 ^ p) or 1
	return (((n * pl) + 0.5 - ((n * pl) + 0.5) % 1) / pl)
end

local Pi = 3.1415926535898
local SerialOrder = genSerialMap(SerialMap)

-- Serializers
function serializeCFRot(bb, v)
	local LookVector = v.LookVector
	local Azumith = math.atan2(-LookVector.X, -LookVector.Z)
	local Elevation = math.atan2(LookVector.Y, math.sqrt(LookVector.X * LookVector.X + LookVector.Z * LookVector.Z))
	local WithoutRoll = CFrame.new(v.Position) * CFrame.Angles(0, Azumith, 0) * CFrame.Angles(Elevation, 0, 0)
	local _, _, Roll = (WithoutRoll:Inverse() * v):ToEulerAnglesXYZ()

	Azumith = math.floor(((Azumith / Pi) * 2097151) + 0.5)
	Roll = math.floor(((Roll / Pi) * 1048575) + 0.5)
	Elevation = math.floor(((Elevation / 1.5707963267949) * 1048575) + 0.5)

	bb:WriteInt(22, Azumith)
	bb:WriteInt(21, Roll)
	bb:WriteInt(21, Elevation)
end
function deserializeCFRot(bb)
	local Azumith = bb:ReadInt(22)
	local Roll = bb:ReadInt(21)
	local Elevation = bb:ReadInt(21)

	Azumith = Pi * (Azumith / 2097151)
	Roll = Pi * (Roll / 1048575)
	Elevation = Pi * (Elevation / 1048575)

	local Rotation = CFrame.Angles(0, Azumith, 0)
	Rotation = Rotation * CFrame.Angles(Elevation, 0, 0)
	Rotation = Rotation * CFrame.Angles(0, 0, Roll)

	return Rotation
end

local Serial = {
	serializeBool = function(bb, v) bb:WriteBool(v) end,
	deserializeBool = function(bb) return bb:ReadBool() end,
	serializeNumber = function(bb, v) bb:WriteInt(16, v) end,
	deserializeNumber = function(bb) return bb:ReadInt(16) end,
	serializeString = function(bb, v) bb:WriteString(v) end,
	deserializeString = function(bb) return bb:ReadString() end,
	serializeCFrame = function(bb, v)
		-- https://github.com/Dekkonot/bitbuffer/blob/main/src/roblox.lua
		-- Sure as hell not optimized, but my "optimized" implementation screwed up rotation
		local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = v:GetComponents()
		bb:WriteFloat64(x)
		bb:WriteFloat64(y)
		bb:WriteFloat64(z)
		bb:WriteFloat64(r00)
		bb:WriteFloat64(r01)
		bb:WriteFloat64(r02)
		bb:WriteFloat64(r10)
		bb:WriteFloat64(r11)
		bb:WriteFloat64(r12)
		bb:WriteFloat64(r20)
		bb:WriteFloat64(r21)
		bb:WriteFloat64(r22)
	end,
	deserializeCFrame = function(bb)
		return CFrame.new(
			bb:ReadFloat64(), bb:ReadFloat64(), bb:ReadFloat64(),
			bb:ReadFloat64(), bb:ReadFloat64(), bb:ReadFloat64(),
			bb:ReadFloat64(), bb:ReadFloat64(), bb:ReadFloat64(),
			bb:ReadFloat64(), bb:ReadFloat64(), bb:ReadFloat64()
		)
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
		bb:WriteFloat64(v.R)
		bb:WriteFloat64(v.G)
		bb:WriteFloat64(v.B)
	end,
	deserializeColor3 = function(bb)
		return Color3.fromRGB(
			255 * bb:ReadFloat64(),
			255 * bb:ReadFloat64(),
			255 * bb:ReadFloat64()
		)
	end,
	serializeMaterial = function(bb, v)
		bb:WriteString(v.Name)
	end,
	deserializeMaterial = function(bb)
		return Enum.Material[bb:ReadString()]
	end,
	serializeV3ForTransport = function(p)
		return tostring(round(p.X, 3)) .. ":" .. tostring(round(p.Y, 3)) .. ":" .. tostring(round(p.Z, 3))
	end
}

-- Handlers
local function serialize(p)
	local bb = BitBuffer.new()
	bb:WriteString(p.ClassName)
	for _, v in ipairs(SerialOrder) do
		Serial["serialize" .. SerialMap[v]](bb, p[v])
	end
	for n, a in pairs(SerialMapSpecs) do
		if p.ClassName ~= n then continue end
		for _, v in ipairs(genSerialMap(a)) do Serial["serialize" .. a[v]](bb, p[v]) end
	end
	return Serial.serializeV3ForTransport(p.Position) .. ":" .. bb:ToBase64()
end
local function deserialize(p, f, rc, pts)
	local bb = BitBuffer.FromBase64(p)
	local pt = Instance.new(bb:ReadString())
	for _, v in ipairs(SerialOrder) do
		pt[v] = Serial["deserialize" .. SerialMap[v]](bb)
	end
	if rc then
		for p, c in pairs(pts) do
			if c.CFrame == pt.CFrame then
				table.remove(pts, p)
				return c
			end
		end
	end
	for n, a in pairs(SerialMapSpecs) do
		if pt.ClassName ~= n then continue end
		for _, v in ipairs(genSerialMap(a)) do
			pt[v] = Serial["deserialize" .. a[v]](bb)
		end
	end
	pt.Parent = f
	return pt
end

Serial.serialize = serialize
Serial.deserialize = deserialize
Serial.round = round
return Serial
