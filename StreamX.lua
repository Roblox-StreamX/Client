--[[
	        ______                     _  __
	       / __/ /________ ___ ___ _  | |/_/
	      _\ \/ __/ __/ -_) _ `/  ' \_>  <  
	     /___/\__/_/  \__/\_,_/_/_/_/_/|_|  
		
		         StreamX Luau v1
		    
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
]]

-- [[ CONFIGURATION ]]
local Configuration = {
	StreamingURLs = {
		["Primary"] = {
			"https://streamx-lb1.quantumpython.xyz",	-- iiPythonx (MS)
			"https://streamx-lb2.quantumpython.xyz",	-- Crcoli737 (WV)
		},
		["Backup"] = {
			"https://streamx.iipython.cf",				-- iiPythonx (MS)
			"https://del3.quantumpython.xyz"			-- DarkPixlz (FL)
		}
	},
	Throttle 		 = 10,			-- % Streaming Throttle (x10 stud diff.)
	UpdateDelay		 = 4,			-- Second delay between updates (keep above 5)
	EnableReuseComp	 = false,		-- Enables duplicate computation (can normalize lag, at the cost of frequent spikes)
	ChunkAmount		 = 1000,		-- Amount of parts sent in each upload request
	APIKey           = "",			-- Your API key, obviously
	PrintMessages 	 = true, 		-- Enables printing normal messages. Warnings and errors are logged seperately.
}

--[[
	StreamX Internal Code
	Please don't edit this unless you KNOW what you're doing.
	
	If you experience issues and have modified this section, we can't help.
]]

-- Services
local HTTP = game:GetService("HttpService")
local Serial = require(11708986356)

-- Logging setup
local function log(message) 
	if Configuration.PrintMessages then
		print("[StreamX]:", message)
	end
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
for _, p in pairs(Configuration.StreamingURLs.Primary) do
	if IsInstanceActive(p) then table.insert(ActiveURLs, p) end
end
if not #ActiveURLs then

	-- Select a backup server
	warn_("No primary servers available, searching for active backups ...")
	for _, p in pairs(Configuration.StreamingURLs.Backup) do
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
			{ ["X-StreamX-Key"] = Configuration.APIKey }
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
if NeedsUpload or true then
	log("Server requested upload, performing action!")
	local sp, t0 = {}, time()
	for _, p in pairs(Folder:GetDescendants()) do
		if p:IsA("MeshPart") or p:IsA("Part") or p:IsA("BasePart") then
			table.insert(sp, Serial.serialize(p))
			if #sp == 1000 then
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
	c:Destroy()
end
local PlayerParts = {}

while task.wait() do
	for _, plr in pairs(game.Players:GetPlayers()) do
		if PlayerParts[plr.UserId] == nil then PlayerParts[plr.UserId] = {} end
		local head = plr.Character:WaitForChild("Head", .1)  -- DO NOT wait for one players head, just keep going
		local data = DownloadParts({
			["HeadPosition"] = string.split(Serial.serializeV3ForTransport(head.Position), ":"),
			["StudDifference"] = Configuration.Throttle * 10
		})
		if data == "!" then continue end

		-- TODO: implement Configuration.EnableReuseComp since it's currently force enabled
		-- TODO: figure out why the following statements don't work half the time

		local n = {}
		for _, p in pairs(string.split(data, ",")) do
			pt = Serial.deserialize(p, Folder, PlayerParts[plr.UserId])
			if pt ~= nil then table.insert(n, pt) end
		end
		for _, p in pairs(PlayerParts[plr.UserId]) do p:Destroy() end
		PlayerParts[plr.UserId] = n
	end
	task.wait(Configuration.UpdateDelay)
end
