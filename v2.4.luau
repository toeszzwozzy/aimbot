--// Preventing Multiple Processes
pcall(function()
	getgenv().Aimbot.Functions:Exit()
end)

--// Environment
getgenv().Aimbot = {}
local Environment = getgenv().Aimbot

--// Services
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")
local Camera = game:GetService("Workspace").CurrentCamera
local Stats = game:GetService("Stats")

--// Variables
local LocalPlayer = Players.LocalPlayer
local Title = "Exunys Developer"
local FileNames = {"Aimbot", "Configuration.json", "Drawing.json", "Prediction.json"}
local Typing, Running, Animation, RequiredDistance, ServiceConnections = false, false, nil, 2000, {}

--// Support Functions
local mousemoverel = mousemoverel or (Input and Input.MouseMove)
local queueonteleport = queue_on_teleport or syn.queue_on_teleport

--// Script Settings
Environment.Settings = {
	SendNotifications = false,
	SaveSettings = true, -- Re-execute upon changing
	ReloadOnTeleport = false,
	Enabled = false,
	TeamCheck = false,
	AliveCheck = true,
	WallCheck = false, -- Laggy
	Sensitivity = 0, -- Animation length (in seconds) before fully locking onto target
	ThirdPerson = false, -- Uses mousemoverel instead of CFrame to support locking in third person (could be choppy)
	ThirdPersonSensitivity = 3, -- Boundary: 0.1 - 5
	TriggerKey = "MouseButton2",
	Toggle = false,
	LockPart = "Head", -- Body part to lock on
	MaximumDistance = 1000 -- Maximum distance to target (prevents locking onto far away players)
}

Environment.FOVSettings = {
	Enabled = true,
	Visible = false,
	Amount = 90,
	Color = "255, 255, 255",
	LockedColor = "255, 70, 70",
	Transparency = 0.5,
	Sides = 60,
	Thickness = 1,
	Filled = false
}

-- New prediction settings
Environment.PredictionSettings = {
	Enabled = false,
	PredictionMode = "Default", -- "Default", "Ping", "Custom"
	DefaultPrediction = 0.165,
	PingBasedMultiplier = 0.001, -- Multiplier for ping-based prediction
	CustomPrediction = 0.2
}

Environment.FOVCircle = Drawing.new("Circle")
Environment.Locked = nil
Environment.LockedOn = false -- New flag to track if we're actively locked on a target

--// Core Functions
local function Encode(Table)
	if Table and type(Table) == "table" then
		local EncodedTable = HttpService:JSONEncode(Table)
		return EncodedTable
	end
end

local function Decode(String)
	if String and type(String) == "string" then
		local DecodedTable = HttpService:JSONDecode(String)
		return DecodedTable
	end
end

local function GetColor(Color)
	local R = tonumber(string.match(Color, "([%d]+)[%s]*,[%s]*[%d]+[%s]*,[%s]*[%d]+"))
	local G = tonumber(string.match(Color, "[%d]+[%s]*,[%s]*([%d]+)[%s]*,[%s]*[%d]+"))
	local B = tonumber(string.match(Color, "[%d]+[%s]*,[%s]*[%d]+[%s]*,[%s]*([%d]+)"))
	return Color3.fromRGB(R, G, B)
end

local function SendNotification(TitleArg, DescriptionArg, DurationArg)
	if Environment.Settings.SendNotifications then
		StarterGui:SetCore("SendNotification", {
			Title = TitleArg,
			Text = DescriptionArg,
			Duration = DurationArg
		})
	end
end

--// Functions
local function SaveSettings()
	if Environment.Settings.SaveSettings then
		if isfile(Title.."/"..FileNames[1].."/"..FileNames[2]) then
			writefile(Title.."/"..FileNames[1].."/"..FileNames[2], Encode(Environment.Settings))
		end
		if isfile(Title.."/"..FileNames[1].."/"..FileNames[3]) then
			writefile(Title.."/"..FileNames[1].."/"..FileNames[3], Encode(Environment.FOVSettings))
		end
		if isfile(Title.."/"..FileNames[1].."/"..FileNames[4]) then
			writefile(Title.."/"..FileNames[1].."/"..FileNames[4], Encode(Environment.PredictionSettings))
		end
	end
end

-- Function to get current prediction value based on settings
local function GetPredictionValue()
	if not Environment.PredictionSettings.Enabled then
		return 0
	end
	
	if Environment.PredictionSettings.PredictionMode == "Default" then
		return Environment.PredictionSettings.DefaultPrediction
	elseif Environment.PredictionSettings.PredictionMode == "Ping" then
		local ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
		return ping * Environment.PredictionSettings.PingBasedMultiplier
	elseif Environment.PredictionSettings.PredictionMode == "Custom" then
		return Environment.PredictionSettings.CustomPrediction
	end
	
	return Environment.PredictionSettings.DefaultPrediction
end

-- Function to check if a player is valid for targeting
local function IsValidTarget(player)
    if player == LocalPlayer then return false end
    if not player.Character or not player.Character:FindFirstChild(Environment.Settings.LockPart) then return false end
    if not player.Character:FindFirstChildOfClass("Humanoid") then return false end
    
    if Environment.Settings.TeamCheck and player.Team == LocalPlayer.Team then return false end
    if Environment.Settings.AliveCheck and player.Character:FindFirstChildOfClass("Humanoid").Health <= 0 then return false end
    if Environment.Settings.WallCheck and #(Camera:GetPartsObscuringTarget({player.Character[Environment.Settings.LockPart].Position}, player.Character:GetDescendants())) > 0 then return false end
    
    -- Check if target is within maximum distance
    local distance = (player.Character[Environment.Settings.LockPart].Position - Camera.CFrame.Position).Magnitude
    if distance > Environment.Settings.MaximumDistance then return false end
    
    return true
end

-- Modified to only find a target when we don't have one
local function GetClosestPlayer()
    -- If we're already locked on, don't find a new target
    if Environment.LockedOn and Environment.Locked and Environment.Locked.Character and Environment.Locked.Character:FindFirstChild(Environment.Settings.LockPart) then
        -- Check if current target is still valid
        if IsValidTarget(Environment.Locked) then
            local Vector, OnScreen = Camera:WorldToViewportPoint(Environment.Locked.Character[Environment.Settings.LockPart].Position)
            local MousePos = Vector2.new(UserInputService:GetMouseLocation().X, UserInputService:GetMouseLocation().Y)
            local TargetPos = Vector2.new(Vector.X, Vector.Y)
            local Distance = (MousePos - TargetPos).Magnitude
            
            -- Only unlock if target is off screen
            if not OnScreen then
                Environment.Locked = nil
                Environment.LockedOn = false
                if Animation then Animation:Cancel() end
                Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
            end
            
            return
        else
            -- Target is no longer valid
            Environment.Locked = nil
            Environment.LockedOn = false
            if Animation then Animation:Cancel() end
            Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
        end
    end
    
    -- Find a new target if we're not locked on
    if not Environment.LockedOn then
        local ClosestDistance = Environment.FOVSettings.Enabled and Environment.FOVSettings.Amount or 2000
        local ClosestPlayer = nil
        
        for _, player in next, Players:GetPlayers() do
            if IsValidTarget(player) then
                local Vector, OnScreen = Camera:WorldToViewportPoint(player.Character[Environment.Settings.LockPart].Position)
                if OnScreen then
                    local MousePos = Vector2.new(UserInputService:GetMouseLocation().X, UserInputService:GetMouseLocation().Y)
                    local TargetPos = Vector2.new(Vector.X, Vector.Y)
                    local Distance = (MousePos - TargetPos).Magnitude
                    
                    if Distance < ClosestDistance then
                        ClosestDistance = Distance
                        ClosestPlayer = player
                    end
                end
            end
        end
        
        if ClosestPlayer then
            Environment.Locked = ClosestPlayer
            Environment.LockedOn = true
            Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.LockedColor)
        end
    end
end

-- Function to unlock target
local function UnlockTarget()
    Environment.Locked = nil
    Environment.LockedOn = false
    if Animation then Animation:Cancel() end
    Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
end

--// Typing Check
ServiceConnections.TypingStartedConnection = UserInputService.TextBoxFocused:Connect(function()
	Typing = true
end)

ServiceConnections.TypingEndedConnection = UserInputService.TextBoxFocusReleased:Connect(function()
	Typing = false
end)

--// Create, Save & Load Settings
if Environment.Settings.SaveSettings then
	if not isfolder(Title) then
		makefolder(Title)
	end
	if not isfolder(Title.."/"..FileNames[1]) then
		makefolder(Title.."/"..FileNames[1])
	end
	if not isfile(Title.."/"..FileNames[1].."/"..FileNames[2]) then
		writefile(Title.."/"..FileNames[1].."/"..FileNames[2], Encode(Environment.Settings))
	else
		Environment.Settings = Decode(readfile(Title.."/"..FileNames[1].."/"..FileNames[2]))
	end
	if not isfile(Title.."/"..FileNames[1].."/"..FileNames[3]) then
		writefile(Title.."/"..FileNames[1].."/"..FileNames[3], Encode(Environment.FOVSettings))
	else
		Environment.FOVSettings = Decode(readfile(Title.."/"..FileNames[1].."/"..FileNames[3]))
	end
	if not isfile(Title.."/"..FileNames[1].."/"..FileNames[4]) then
		writefile(Title.."/"..FileNames[1].."/"..FileNames[4], Encode(Environment.PredictionSettings))
	else
		Environment.PredictionSettings = Decode(readfile(Title.."/"..FileNames[1].."/"..FileNames[4]))
	end
	coroutine.wrap(function()
		while wait(10) and Environment.Settings.SaveSettings do
			SaveSettings()
		end
	end)()
else
	if isfolder(Title) then
		delfolder(Title)
	end
end

local function Load()
	ServiceConnections.RenderSteppedConnection = RunService.RenderStepped:Connect(function()
		-- FOV Circle handling
		if Environment.FOVSettings.Enabled and Environment.Settings.Enabled then
			Environment.FOVCircle.Radius = Environment.FOVSettings.Amount
			Environment.FOVCircle.Thickness = Environment.FOVSettings.Thickness
			Environment.FOVCircle.Filled = Environment.FOVSettings.Filled
			Environment.FOVCircle.NumSides = Environment.FOVSettings.Sides
			Environment.FOVCircle.Color = Environment.LockedOn and GetColor(Environment.FOVSettings.LockedColor) or GetColor(Environment.FOVSettings.Color)
			Environment.FOVCircle.Transparency = Environment.FOVSettings.Transparency
			Environment.FOVCircle.Visible = Environment.FOVSettings.Visible
			Environment.FOVCircle.Position = Vector2.new(UserInputService:GetMouseLocation().X, UserInputService:GetMouseLocation().Y)
		else
			Environment.FOVCircle.Visible = false
		end
		
		-- Aimbot logic
		if Running and Environment.Settings.Enabled then
			GetClosestPlayer()
			
			if Environment.LockedOn and Environment.Locked and Environment.Locked.Character and Environment.Locked.Character:FindFirstChild(Environment.Settings.LockPart) then
				local targetPart = Environment.Locked.Character[Environment.Settings.LockPart]
				local predictionValue = GetPredictionValue()
				local predictedPosition = targetPart.Position + (targetPart.Velocity * predictionValue)
				
				if Environment.Settings.ThirdPerson then
					Environment.Settings.ThirdPersonSensitivity = math.clamp(Environment.Settings.ThirdPersonSensitivity, 0.1, 5)
					local Vector = Camera:WorldToViewportPoint(predictedPosition)
					mousemoverel(
						(Vector.X - UserInputService:GetMouseLocation().X) * Environment.Settings.ThirdPersonSensitivity, 
						(Vector.Y - UserInputService:GetMouseLocation().Y) * Environment.Settings.ThirdPersonSensitivity
					)
				else
					if Environment.Settings.Sensitivity > 0 then
						if Animation then Animation:Cancel() end
						Animation = TweenService:Create(Camera, TweenInfo.new(Environment.Settings.Sensitivity, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {CFrame = CFrame.new(Camera.CFrame.Position, predictedPosition)})
						Animation:Play()
					else
						Camera.CFrame = CFrame.new(Camera.CFrame.Position, predictedPosition)
					end
				end
			end
		end
	end)

		ServiceConnections.InputEndedConnection = UserInputService.InputEnded:Connect(function(Input)
		if not Typing then
			pcall(function()
				if Input.KeyCode == Enum.KeyCode[Environment.Settings.TriggerKey] then
					if not Environment.Settings.Toggle then
						Running = false
						UnlockTarget()
					end
				end
			end)
			pcall(function()
				if Input.UserInputType == Enum.UserInputType[Environment.Settings.TriggerKey] then
					if not Environment.Settings.Toggle then
						Running = false
						UnlockTarget()
					end
				end
			end)
		end
	end)
end

--// Functions
Environment.Functions = {}

function Environment.Functions:Exit()
	SaveSettings()
	for _, v in next, ServiceConnections do
		v:Disconnect()
	end
	if Environment.FOVCircle.Remove then Environment.FOVCircle:Remove() end
	getgenv().Aimbot.Functions = nil
	getgenv().Aimbot = nil
end

function Environment.Functions:Restart()
	SaveSettings()
	for _, v in next, ServiceConnections do
		v:Disconnect()
	end
	Load()
end

function Environment.Functions:ResetSettings()
	Environment.Settings = {
		SendNotifications = true,
		SaveSettings = true, -- Re-execute upon changing
		ReloadOnTeleport = true,
		Enabled = true,
		TeamCheck = false,
		AliveCheck = true,
		WallCheck = false,
		Sensitivity = 0, -- Animation length (in seconds) before fully locking onto target
		ThirdPerson = false,
		ThirdPersonSensitivity = 3,
		TriggerKey = "MouseButton2",
		Toggle = false,
		LockPart = "Head", -- Body part to lock on
		MaximumDistance = 1000 -- Maximum distance to target
	}
	
	Environment.FOVSettings = {
		Enabled = true,
		Visible = true,
		Amount = 90,
		Color = "255, 255, 255",
		LockedColor = "255, 70, 70",
		Transparency = 0.5,
		Sides = 60,
		Thickness = 1,
		Filled = false
	}
	
	Environment.PredictionSettings = {
		Enabled = false,
		PredictionMode = "Default", -- "Default", "Ping", "Custom"
		DefaultPrediction = 0.165,
		PingBasedMultiplier = 0.001, -- Multiplier for ping-based prediction
		CustomPrediction = 0.2
	}
end

--// Support Check
if not Drawing or not getgenv then
	print("Error: Your exploit does not support Drawing or getgenv functions")
	return
end

--// Reload On Teleport
if Environment.Settings.ReloadOnTeleport then
	if queueonteleport then
		queueonteleport(game:HttpGet("https://raw.githubusercontent.com/Exunys/Aimbot-V2/main/Resources/Scripts/Main.lua"))
	else
		print("Your exploit does not support queue_on_teleport, auto-reloading disabled")
	end
end

--// Load
Load()


