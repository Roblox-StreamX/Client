--[[

StreamX Luau v0.2.3 (Public Beta)

How to use:

Put all parts you want to stream in a folder named "ASSETS" in the Workspace, this will tell the code what you want to stream.
Do not put baseplates or base parts in the ASSETS folder, your game will be broken!

Once you're done with that, change the settings below to your liking.

Contact Crcoli737 on the DevForum if you have any questions!


By the way, there's no harm in the printing, with the server identifier etc.

This is printed in the server output, nobody but devs can see it.

]]

local HttpService = game:GetService("HttpService")
local url = "https://streaming.quantumpython.xyz/"
local key = "YOUR_KEY" -- Enter your api key here!
local throttle = 30 -- Streaming Throttle (in Percent) 10 = 100 Studs Difference 100 = 1000 Studs Difference
local updatedelay = 10 -- Delay (in seconds) between part updates (WARNING: Do not turn below 5 as it will result in excessive lagging, turn this number up as you increase throttle.)

local total = 0

warn("Initilizing Server Streaming Connection...")

local identifier = HttpService:JSONDecode(HttpService:GetAsync(url.."/initilize-server/"..key))["identifier"]

print("Identifier is "..identifier)

function parseVector3(sourceString)
	local tonum = tonumber
	local separated = string.split(sourceString, ",")
	local result = Vector3.new(tonum(separated[1]), tonum(separated[2]), tonum(separated[3]))
	return result
end

function tobool(stringBool)
	local bool = false
	if stringBool == "true" then
		bool = true
	end
	return bool
end

game:BindToClose(function()
	HttpService:GetAsync(url.."/delete/part-info/"..key.."/"..identifier)
end)

game.Players.PlayerRemoving:Connect(function()
	local players = game.Players:GetChildren()
	if #players == 1 then
		HttpService:GetAsync(url.."/delete/part-info/"..key.."/"..identifier)
	end
end)

local i = 0
local partdata = {}
local Total = 0

for __, v in ipairs(workspace.ASSETS:GetDescendants()) do
		Total += 1
	end
	for _, part in pairs(game.Workspace.ASSETS:GetDescendants()) do 
		if i > 1000 then
			print("Sending Part Data Request... ("..total.."/"..Total.." parts complete)")
			HttpService:PostAsync(url.."/upload/part-info/"..key.."/"..identifier, HttpService:JSONEncode(partdata))
			partdata = {}
			i = 0
		else
			if part:IsA("Part") then
				total += 1 
				local splitMaterial = string.split(tostring(part.Material), ".")
				local splitShape = string.split(tostring(part.Shape), ".")
				local propertylist = {
					["Anchored"] = tostring(part.Anchored),
					["BrickColor"] = tostring(part.BrickColor),
					["CFrame"] = tostring(part.CFrame),
					["CanCollide"] = tostring(part.CanCollide),
					["CanQuery"] = tostring(part.CanQuery),
					["CanTouch"] = tostring(part.CanTouch),
					["CastShadow"] = tostring(part.CastShadow),
					["Name"] = tostring(part.Name),
					["Material"] = splitMaterial[3],
					["Orientation"] = tostring(part.Orientation),
					["PivotOffset"] = tostring(part.PivotOffset),
					["Position"] = tostring(part.Position),
					["Reflectance"] = tostring(part.Reflectance),
					["Rotation"] = tostring(part.Rotation),
					["Shape"] = tostring(splitShape[3]),
					["Size"] = tostring(part.Size),
					["Transparency"] = tostring(part.Transparency)
				}
				partdata[#partdata+1] = propertylist
				i += 1
			end
		end
	end

	HttpService:PostAsync(url.."/upload/part-info/"..key.."/"..identifier, HttpService:JSONEncode(partdata))
	partdata = {}
	i = 0

	task.wait(3)

	for _, part in pairs(game.Workspace.ASSETS:GetDescendants()) do
		if part:IsA("Part") then
			part:Destroy()
		end
	end

	local partIterator = 0
	while true do
		for _, part in pairs(game.Workspace:GetChildren()) do
			if part:IsA("Part") and part.Name == "Part"..partIterator-1 then
				part:Destroy()
			end
		end
		partIterator += 1
		for _, plr in pairs(game.Players:GetChildren()) do
			playerHeadPosition = tostring(plr.Character:WaitForChild("Head").Position)
			dataToSend = {
				["HeadPosition"] = tostring(playerHeadPosition),
				["StudDifference"] = throttle * 10
			}
			response = HttpService:PostAsync(url.."/download/part-info/"..key.."/"..identifier, HttpService:JSONEncode(dataToSend))
			partsData = HttpService:JSONDecode(response)
			for _, partTable in pairs(partsData) do
				part = Instance.new("Part")
				part.Parent = game.Workspace
				part.Anchored = partTable[1]
				part.BrickColor = BrickColor.new(partTable[2])
				part.CFrame = CFrame.new(parseVector3(partTable[3]))
				part.CanCollide = tobool(partTable[4])
				part.CanQuery = tobool(partTable[5])
				part.CanTouch = tobool(partTable[6])
				part.CastShadow = partTable[7]
				part.Name = "Part"..partIterator
				part.Material = partTable[8]
				part.Orientation = parseVector3(partTable[10])
				part.PivotOffset = CFrame.new(parseVector3(partTable[11]))
				part.Position = parseVector3(partTable[12])
				part.Reflectance = partTable[13]
				part.Rotation = parseVector3(partTable[14])
				part.Shape = partTable[15]
				part.Size = parseVector3(partTable[16])
				part.Transparency = partTable[17]
			end
		end
		task.wait(updatedelay)
	end
