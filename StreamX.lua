--[[
	        ______                     _  __
	       / __/ /________ ___ ___ _  | |/_/
	      _\ \/ __/ __/ -_) _ `/  ' \_>  <  
	     /___/\__/_/  \__/\_,_/_/_/_/_/|_|  
		
		         StreamX Luau v3
		    
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
			"https://streamx-lb1.quantumpython.xyz",		-- iiPythonx (MS)
			"https://streamx-lb2.quantumpython.xyz",		-- Crcoli737 (WV)
		},
		["Backup"] = {
			"https://streamx.iipython.cf",				-- iiPythonx (MS)
			"https://del3.quantumpython.xyz"				-- DarkPixlz (FL)
		}
	},
	Throttle			= 10,		-- % Streaming Throttle (x10 stud diff.)
	UpdateDelay		= 6,			-- Second delay between updates (keep above 5)
	EnableReuseComp	= true,		-- Enables duplicate computation (can normalize lag, at the cost of frequent spikes)
	ChunkAmount		= 1000,		-- Amount of parts sent in each upload request
	APIKey			= "",		-- StreamX API key
	PrintMessages	= true, 		-- Enables printing normal messages. Warnings and errors are logged seperately.
	Backlog			= {
		Size			= 100,		-- How many parts to render before calling task.wait(BacklogWait)
		LoadDelay	= .1,		-- The amount of time to wait between backlog renders
		Enabled		= false		-- Enable the backlog
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

-- Logging setup
local function log(message) 
	if C.PrintMessages then print("[StreamX]:", message) end
end
local function warn_(message) warn("[StreamX]:", message) end
local function error_(message) error("[StreamX]: " .. message) end

-- Pick server URL
local function IsInstanceActive(url)
	local S, M = pcall(function() return HTTP:GetAsync(url, true) end)
	if S and M == "OK" then return true end
	return false
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
	return error_("No URLs available to use for streaming, or HTTPService is disabled!")
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
	-- This doesn't do anything yet
end

game:BindToClose(DeInitialize)
game.Players.PlayerRemoving:Connect(function(p)
	if #game.Players:GetPlayers() == 0 then DeInitialize() end
end)

log("Initializing connection to StreamX ...")
local InitReq = MakeRequest("init", { gameid = game.GameId, placever = game.PlaceVersion })
local AuthKey, NeedsUpload = InitReq.Data.key, InitReq.Data.upload

log("Authentication key is " .. AuthKey)

local function UploadParts(parts)
	HTTP:PostAsync(
		URL .. "/upload", table.concat(parts, ","), nil, false,
		{ ["X-StreamX-Auth"] = AuthKey }
	)
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
	warn_("WARNING: Please rename your ASSETS folder to \"StreamX\" to prevent future compatibility issues.")
end
if Folder == nil then 
	error_("No streaming directory found to stream from!\nPlease add a folder named \"StreamX\" into the Workspace and add items into this folder to stream.")
end

-- Begin uploading data
if NeedsUpload then
	log("Server requested upload, performing action!")
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
	log("Uploaded all parts to server in " .. tostring(Serial.round(time() - t0, 3)) .. " seconds")
end

-- Start deleting
for _, c in pairs(Folder:GetDescendants()) do
	-- TODO: check each part and check if it's in a player's streaming radius
	-- TODO: if it is, don't destroy it (makes the whole system look faster)
	c:Destroy()
end

-- Backlog streamers
local PlayerParts = {}
local rc, bls, blw = C.EnableReuseComp, C.Backlog.Size, C.Backlog.LoadDelay
local function dsNoBL(plr, data)
	local n = {}
	local rcp = if rc then PlayerParts[plr.UserId] else {}
	for _, p in pairs(string.split(data, ",")) do table.insert(n, Serial.deserialize(p, Folder, rc, rcp)) end
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

-- Start streaming
while task.wait() do  -- task.wait() because it looks cleaner then true lol
	for _, plr in pairs(game.Players:GetPlayers()) do
		if PlayerParts[plr.UserId] == nil then PlayerParts[plr.UserId] = {} end
		local head = plr.Character:WaitForChild("Head", .1)  -- DO NOT wait for one players head, just keep going
		local data = DownloadParts({
			["HeadPosition"] = string.split(Serial.serializeV3ForTransport(head.Position), ":"),
			["StudDifference"] = C.Throttle * 10
		})
		if data == "!" then
			for _, p in pairs(PlayerParts[plr.UserId]) do p:Destroy() end
			continue
		end
		local n = ds(plr, data)
		for _, p in pairs(PlayerParts[plr.UserId]) do p:Destroy() end
		PlayerParts[plr.UserId] = n
	end
	task.wait(C.UpdateDelay)
end
