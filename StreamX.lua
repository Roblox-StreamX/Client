--[[
	        ______                     _  __
	       / __/ /________ ___ ___ _  | |/_/
	      _\ \/ __/ __/ -_) _ `/  ' \_>  <  
	     /___/\__/_/  \__/\_,_/_/_/_/_/|_|  
		
		         StreamX Luau v3.0.6
		    
			 DarkPixlz 	| Payment Guru
		     Crcoli737	|      Backend
   			 iiPythonx	|      Backend

	[ INSTRUCTIONS ]
		1) Find an open StreamX server or setup one yourself
		2) Enable HTTP requests via Game Settings
		3) Place all parts you wish to stream a folder named StreamX in the workspace
		4) Change the options in the 'Configuration' table below.
		5) That's it, you're done!

	[ PROBLEMS? ]
		o) The StreamX team generally does not offer support anymore.
		o) If you see an issue and have the knowledge to fix it, feel free to open a pull request on the GitHub.
			
	[ CONTRIBUTE ]
		o) The StreamX client and server code is open sourced,
		o) at https://github.com/Roblox-StreamX/Client
		o) Contributions are welcome.
]]

-- [[ CONFIGURATION ]]
local Configuration = {
	StreamingURLs = {
		["Primary"] = {
			-- Insert the URL of your streaming server(s)
		},
		["Backup"] = {
			-- Insert the URL of a backup streaming server which will be called on if any of the primaries fail.
		}
	},
	Throttle		= 15,		-- % Streaming Throttle (x10 stud diff.)
	UpdateDelay		= 10,		-- Second delay between updates (keep above 5). The larger the Throttle is, the higher this should be.
	EnableReuseComp	= true,		-- Enables duplicate computation (can normalize lag, at the cost of heavier spikes)
	ChunkAmount		= 1000,		-- Amount of parts sent in each upload request
	APIKey			= "",		-- StreamX API key, if required by your server.
	PrintMessages	= true, 	-- Enables printing of potentially useful information for debugging. Warnings and errors are logged seperately.
	DebugMode		= true,		-- If you are getting support from us, enable this. Will print out EVERYTHING that StreamX is doing, and will increase memory substantially, so you shouldn't use it normally.
	Backlog			= {
		Size		= 500,		-- How many parts to render before waiting to continue
		LoadDelay	= .1,		-- The amount of time to wait between backlog renders
		Enabled		= true		-- Enable the backlog
	}
}

--[[
	StreamX Internal Code
	Please don't edit this unless you know what you're doing.
	
	If you experience issues and have modified this section, we can't help.
]]

local C = Configuration

-- Services
local HTTP = game:GetService("HttpService")
local Serial = require(script:FindFirstChild("Serializer") or 11708986356)

-- Logging setup
local function Log(message) if C.PrintMessages then print("[StreamX]:", message) end end
local function SWarn(message) warn("[StreamX]:", message) end
local function SError(message) error("\n[StreamX]: " .. message) end
local function Debug(message)  if C.DebugMode then print("[StreamX Debug]:", message) end end

-- Pick server URL
local function IsInstanceActive(url)
	Debug(`Checking if URL {url} is active ...`)
	local S, M = pcall(function() return HTTP:PostAsync(url, true) end)
	if S and M == "OK" then 
		Debug(`Connected to {url}!`)
		return true 
	end
	Debug(`Faailed connecting to {url} for {M}`)
	return false
end

-- Check HTTPService status
if not pcall(function()
		HTTP:GetAsync("http://1.1.1.1")
	end) then
	SError("HTTPService is disabled! Please enable it before using StreamX.")
end
Debug("Successfully connected to HTTPService!")

-- Select URL
local URL = nil
local ActiveURLs = {}
for _, p in pairs(C.StreamingURLs.Primary) do
	if IsInstanceActive(p) then table.insert(ActiveURLs, p) end
end
if #ActiveURLs == 0 then
	-- Select a backup server
	SWarn("No primary servers available, searching for active backups ...")
	for _, p in pairs(C.StreamingURLs.Backup) do
		if IsInstanceActive(p) then URL = p; break end
	end

else URL = ActiveURLs[math.random(1, #ActiveURLs)] end
if not URL then
	return SError("No URLs are available for streaming at this time. Make sure you added valid StreamX servers to the Configuration.")
end

Log("Selected URL: " .. URL)

-- Initialization
local function MakeRequest(endpoint, data)
	local s, d = pcall(function()
		return HTTP:PostAsync(
			URL .. "/" .. endpoint,
			HTTP:JSONEncode(data),
			Enum.HttpContentType.ApplicationJson,
			false,
			{
				["X-StreamX-Key"] = C.APIKey,
				["X-StreamX-PlaceID"] = tostring(game.PlaceId),
				["X-StreamX-PlaceVer"] = tostring(game.PlaceVersion)
			}
		)
	end)
	if not s then
		if d ~= "HTTP 401 (Unauthorized)" then
			SError(d)
		else
			SWarn("Your API key didn't work. This is likely something on the server's end. Check you entered the API key correctly, then contact the server owner.")
		end
	end
	return { Success = s, Data = HTTP:JSONDecode(d) }
end

Log("Initializing connection to StreamX ...")
local InitReq = MakeRequest("init")

Debug("Made request! Awating response ...")
local AuthKey, NeedsUpload = InitReq.Data.key, InitReq.Data.upload

Log("Authentication key is " .. AuthKey)

local function UploadParts(parts)
	HTTP:PostAsync(
		URL .. "/upload", table.concat(parts, ","), nil, false,
		{ ["X-StreamX-Auth"] = AuthKey }
	)
end

-- Handle deinitialization
local function DeInitialize()
	SWarn("Deinitializing StreamX")
end
game:BindToClose(DeInitialize)

-- Initialize downloading
local function DownloadParts(data)
	return HTTP:PostAsync(
		URL .. "/download",
		HTTP:JSONEncode(data),
		Enum.HttpContentType.ApplicationJson,
		false,
		{ ["X-StreamX-Auth"] = AuthKey }
	)
end

local Folder = game.Workspace:FindFirstChild("StreamX")
if Folder == nil then
	return SError(
		"No streaming folder found to stream from!\nPlease add a folder named \"StreamX\" into the Workspace and add anything you would like streamed.")
end
Debug("Located folder 'StreamX' inside workspace.")

-- Begin uploading data
function round(n, p)
	local pl = (p) and (10 ^ p) or 1
	return (((n * pl) + 0.5 - ((n * pl) + 0.5) % 1) / pl)
end

if NeedsUpload then
	Debug("Now uploading all parts ...")
	local sp, t0 = {}, time()
	for _, p in pairs(Folder:GetDescendants()) do
		if p:IsA("MeshPart") or p:IsA("Part") or p:IsA("BasePart") then
			table.insert(sp, Serial.serialize(p))
			if #sp == C.ChunkAmount then
				UploadParts(sp)
				sp = {}
			end
		end
	end	
	if #sp > 0 then UploadParts(sp) end  -- Catch any leftovers
	Log("Uploaded all parts to server in " .. tostring(round(time() - t0, 3)) .. " seconds")
end

Debug("All parts uploaded successfully!")

-- Start deleting
Debug("Now erasing all items inside 'StreamX' ...")
Folder:ClearAllChildren()
Debug("Folder erasing complete!")

-- Backlog streamers
local PlayerParts = {}
local rc, bls, blw = C.EnableReuseComp, C.Backlog.Size, C.Backlog.LoadDelay
local function dsNoBL(plr, data)
	local n = {}
	local rcp = if rc then PlayerParts[plr.UserId] else {}
	for _, p in pairs(string.split(data, ",")) do
		table.insert(n, Serial.deserialize(p, Folder, rc, rcp))
	end
	return n
end
local function dsBL(plr, data)
	local n, i = {}, 0
	local rcp = if rc then PlayerParts[plr.UserId] else {}
	for _, p in pairs(string.split(data, ",")) do
		table.insert(n, Serial.deserialize(p, Folder, rc, rcp))
		i += 1
		if i == bls then
			task.wait(blw)
			i = 0
		end
	end
	return n
end
local ds = if C.Backlog.Enabled then dsBL else dsNoBL

Debug(`Set to deserialize {C.Backlog.Enabled and "using" or "without"} the backlog!`)

-- Remove parts upon leaving + handle deinit
game.Players.PlayerRemoving:Connect(function(p)
	for _, p in pairs(PlayerParts[p.UserId]) do p:Destroy() end
	if #game.Players:GetPlayers() == 0 then
		DeInitialize()
		Debug("No players remain, deinitializing StreamX ...")
	end
end)

-- Start streaming
local prv = {}
local roundV3 = function(v) return Vector3.new(math.round(v.X), math.round(v.Y), math.round(v.Z)) end
while task.wait() do
	Debug("Iterating through players ...")
	for _, plr in pairs(game.Players:GetPlayers()) do

		-- Pre-checks
		Debug("Analyzing", plr.Name)
		if PlayerParts[plr.UserId] == nil then
			PlayerParts[plr.UserId] = {}
			Debug(plr.Name .. " is new, parts table has been created.") 
		end
		if plr.Character == nil then  -- Prevent breaking from not having a character
			Debug(plr.Name .. " does not have a character, skipping for now."); continue
		end

		local head = plr.Character:FindFirstChild("Head")
		if head == nil then  -- DO NOT wait for one players head, just keep going
			Debug(plr.Name .. " does not have a head, skipping for now."); continue
		end

		-- Download data if player has moved
		local pos = roundV3(head.Position)
		if (not prv[plr.Name]) or ((prv[plr.Name] - head.Position).magnitude > 2) then
			prv[plr.Name] = pos
			local data = DownloadParts({
				["HeadPosition"] = string.split(Serial.serializeV3ForTransport(head.Position), ":"),
				["StudDifference"] = C.Throttle * 10
			})
			Debug("Parts downloaded for " .. plr.Name)
			if data == "!" then
				for _, p in pairs(PlayerParts[plr.UserId]) do p:Destroy() end
				continue
			end
			local n = ds(plr, data)
			for _, p in pairs(PlayerParts[plr.UserId]) do p:Destroy() end
			PlayerParts[plr.UserId] = n
			Debug("Streaming complete for " .. plr.Name)
		end
	end

	-- Debug + wait until next iter
	Debug("All players have been updated.")
	Debug("Sleeping until UpdateDelay is over ...")
	task.wait(C.UpdateDelay)
end
