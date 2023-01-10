--[[
	        ______                     _  __
	       / __/ /________ ___ ___ _  | |/_/
	      _\ \/ __/ __/ -_) _ `/  ' \_>  <  
	     /___/\__/_/  \__/\_,_/_/_/_/_/|_|  
		
		         StreamX Luau v3.1
		    
			 DarkPixlz 	| Payment Guru
		     Crcoli737	|      Backend
   			 iiPythonx	|      Backend
	[ INSTRUCTIONS ]
		1) Enable HTTP requests via Game Settings
		2) Place all parts you wish to stream a folder named StreamX in the workspace
			- You can also name this folder "ASSETS", but it is only for backwards compatibility and might be removed without notice.
		3) Change the options in the 'Configuration' table below.
		4) That's it, you're done!
	[ PROBLEMS? ]
		o) Contact us via the StreamX topic on the devforum
		o) Discord is also an option:
			- Contact DarkPixlz @ Pixlz#1337		(fastest)
			- Contact iiPythonx @ iiPython#0768
			
	[ CONTRIBUTE ]
		o) Please note that this StreamX client is open-source and available
		o) at https://github.com/Roblox-StreamX/Client
		o) Contributions are welcome.
]]

-- [[ CONFIGURATION ]]
local Configuration = {
	StreamingURLs = {
		["Primary"] = {
			"https://streamx.quantumpython.xyz"		      -- High Availability Datacenter
		},
		["Backup"] = {
			"https://streamx-fallback.quantumpython.xyz"  -- Fallback Datacenter
		}
	},
	Throttle		= 10,		-- % Streaming Throttle (x10 stud diff.) Higher = Longer to stream.
	UpdateDelay		= 5,		-- Second delay between updates (keep above 5)
	EnableReuseComp	= true,		-- Enables duplicate computation (can normalize lag, at the cost of frequent spikes)
	ChunkAmount		= 1000,		-- Amount of parts sent in each upload request
	APIKey			= "API_KEY",		-- StreamX API key. Get this from the payment center.
	PrintMessages	= true, 		-- Enables printing normal messages. Warnings and errors are logged seperately.
	DebugMode = false,              -- If you are getting support from us, enable this. Will print out EVERYTHING that StreamX is doing, and will increase memory substantially.
	Backlog			= {
		Size		= 100,		-- How many parts to render before calling task.wait(BacklogWait)
		LoadDelay	= .1,		-- The amount of time to wait between backlog renders
		Enabled		= true		-- Enable the backlog
	}
}

--[[
	StreamX Internal Code
	Please don't edit this unless you KNOW what you're doing.
	
	If you experience issues and have modified this section, we can't help.
]]

local C = Configuration

-- Services
local HTTP = game:GetService("HttpService")
local Serial = require(script:FindFirstChild("Serializer") or 11708986356)
local Auth

-- Logging setup
local function log(message) 
	if C.PrintMessages then print("[StreamX]:", message) end
end
local function warn_(message) warn("[StreamX]:", message) end
local function error_(message)
	warn("Exiting StreamX due to error...")

	error("[StreamX]: " .. message) 
end
local function Debug(message) 
	if C.DebugMode then
		print("[StreamX Debug]: "..message)
	end
end

if C.DebugMode then
	warn_("Debug mode is enabled! This is only recommended in Studio, as it prints most stuff out to the server output.")
end
-- Pick server URL
local function IsInstanceActive(url)
	Debug("Checking if URL "..url.." is active!")
	local S, M = pcall(function() 
		Debug("Pinging URL")
		return HTTP:GetAsync(url, true) 
	end)
	if S and M == "OK" then 
		Debug("Connection to "..url.." succedded!")
		return true 
	end
	Debug("Failed to connect to "..url.."!\nMessage: "..M)
	return false
end

-- Check HTTPService status
--if not game:GetService("HttpService").HttpEnabled then
--	error("[StreamX]: HTTPService is disabled! Please enable it before using StreamX.")
--end 
-- DOES NOT WORK
local succ, err= pcall(function()
	local requ = game:GetService("HttpService"):GetAsync("https://google.com")
end)
if not succ then
	error("[StreamX]: HTTPService is disabled! Please enable it before using StreamX.")
else
	Debug("Successfully connected to HTTPService!")
end

local URL = nil
local ActiveURLs = {}
for _, p in pairs(C.StreamingURLs.Primary) do
	if IsInstanceActive(p) then table.insert(ActiveURLs, p) end
end
if #ActiveURLs == 0 then

	-- Select a backup server
	warn_("No primary servers available, searching for active backups ...")
	for _, p in pairs(C.StreamingURLs.Backup) do
		if IsInstanceActive(p) then URL = p; break end
	end
else URL = ActiveURLs[math.random(1, #ActiveURLs)] end

if not URL then
	Debug("ERROR: Could not find URL")
	
	return error_("No URLs are available at this time. This is probably something on our end - give us some time to fix it.")
end
log("Selected URL: " .. URL)


-- Initialization
local function MakeRequest(endpoint, data)
	local s, d = pcall(function()
		return HTTP:PostAsync(
			URL .. "/" .. endpoint,
			HTTP:JSONEncode(data),
			Enum.HttpContentType.ApplicationJson,
			false,
			{ ["X-StreamX-Key"] = C.APIKey }
		)
	end)
	if not s then
		if d ~= "HTTP 401 (Unauthorized)" then
			error_(d)
		else
			warn_("Your API key didn't work. This could be for many reasons, including:\n- You haven't renewed your subscription\n- The key you supplied is invalid\n- You haven't whitelisted this game ID in the payment center \n- The key was suspended for abuse.\nPlease resolve this before using StreamX, and if this is due to abuse please contact us.")
		end
	end
	return { Success = s, Data = HTTP:JSONDecode(d) }
end

local function DeInitialize()
	warn_("Deinitializing StreamX")
	Debug("Deinitializing server")
	MakeRequest("deinitialize",{authkey = Auth})
end



game:BindToClose(DeInitialize)
game.Players.PlayerRemoving:Connect(function(p)
	if #game.Players:GetPlayers() == 0 then
		DeInitialize()
		Debug("Deiniting because no players remain")
	end
end)

log("Initializing connection to StreamX ...")
local InitReq = MakeRequest("init", { placeid = game.PlaceId, placever = game.PlaceVersion, serverkeyguid = HTTP:GenerateGUID(false) })
Debug("Made request! Awating response")
local AuthKey, NeedsUpload = InitReq.Data.key, InitReq.Data.upload

Auth = AuthKey

log("Authentication key is " .. AuthKey)

local function UploadParts(parts)
	Debug("Uploading...")
	HTTP:PostAsync(
		URL .. "/upload", table.concat(parts, ","), nil, false,
		{ ["X-StreamX-Auth"] = AuthKey }
	)
end

-- Check update delay

-- Do NOT delete this. The server will reject your request if it's less than 1 second.

if math.round(C.UpdateDelay) <= 5 then
	warn_(
		"Your update delay is less than 5. If you have more active servers, or this game server is large, then it will lag. Please make it higher to prevent connection issues.")
end
if math.round(C.UpdateDelay) <= 1 then
	C.UpdateDelay = 7
	warn_("Sorry, but your update delay is too low. It has been turned to 7 to prevent connection issues. Changing this will result in requests being dropped by the server.") table.freeze(C)
end

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
	Folder = game.Workspace:FindFirstChild("ASSETS")
	Debug("Could not find StreamX Folder")
	if Folder then
		warn_("WARNING: Please rename your ASSETS folder to \"StreamX\" to prevent future compatibility issues.")
	end
end
if Folder == nil then 
	Debug("ERROR: No streaming directory found")
	error_("No streaming directory found to stream from!\nPlease add a folder named \"StreamX\" into the Workspace and add items into this folder to stream.")
	return
end
Debug("Folder found")
-- Begin uploading data
if NeedsUpload then
	log("Server requested upload, performing action!")
	Debug("Uploading...")
	local sp, t0 = {}, time()
	for _, p in pairs(Folder:GetDescendants()) do
		if p:IsA("MeshPart") or p:IsA("Part") or p:IsA("BasePart")  then
			Debug("Uploading part... ("..p.Name..")")
			table.insert(sp, Serial.serialize(p))
			if #sp == C.ChunkAmount then
				UploadParts(sp)
				Debug("Uploaded")
				sp = {}
			end
		end
	end	
	if #sp > 0 then UploadParts(sp) end  -- Catch any leftovers
	log("Uploaded all parts to server in " .. tostring(Serial.round(time() - t0, 3)) .. " seconds")
end
Debug("Uploading complete!")
-- Start deleting
Debug("Wiping folder...")
Folder:ClearAllChildren()
Debug("Complete!")
-- Backlog streamers
local PlayerParts = {}
local rc, bls, blw = C.EnableReuseComp, C.Backlog.Size, C.Backlog.LoadDelay
local function dsNoBL(plr, data)
	Debug("Deserializing without a backlog...")
	local n = {}
	local rcp = if rc then PlayerParts[plr.UserId] else {}
	for _, p in pairs(string.split(data, ",")) do 
		Debug("Deserializing part...")
		table.insert(n, 
			Serial.deserialize(p, Folder, rc, rcp)
		)
	end
	return n
end
local function dsBL(plr, data)
	Debug("Deserializing with backlog enabled...")
	local n, i = {}, 0
	local rcp = if rc then PlayerParts[plr.UserId] else {}
	for _, p in pairs(string.split(data, ",")) do
		Debug("Deserializing parts...")
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

-- Start streaming
local prv = {}
while task.wait() do
	Debug("Streaming...")
	for _, plr in pairs(game.Players:GetPlayers()) do
		Debug("Checking "..plr.Name)
		
		if PlayerParts[plr.UserId] == nil then
			PlayerParts[plr.UserId] = {}
			Debug("Player not found, made table") 
		end
		
		if plr.Character == nil then
			Debug("Could not find character head, exiting") 
			continue
		end	-- Prevent breaking from not having a character
		
		local head = plr.Character:FindFirstChild("Head")
		
		if head == nil then
			Debug("Head was not found, exiting")
			continue 
		end  -- DO NOT wait for one players head, just keep going
		
		if (not prv[plr.Name]) or (prv[plr.Name] ~= head.Position) then
			prv[plr.Name] = head.Position
			local data = DownloadParts({
				["HeadPosition"] = string.split(Serial.serializeV3ForTransport(head.Position), ":"),
				["StudDifference"] = C.Throttle * 10
			})
			Debug("Downloaded parts!")
			if data == "!" then
				for _, p in pairs(PlayerParts[plr.UserId]) do p:Destroy() end
				continue
			end
			local n = ds(plr, data)
			for _, p in pairs(PlayerParts[plr.UserId]) do p:Destroy() end
			PlayerParts[plr.UserId] = n
			Debug("Complete for "..plr.Name)
		end
	end
	Debug("Checked all players, task complete!")
	Debug("Waiting for update delay...")
	task.wait(C.UpdateDelay)
end
