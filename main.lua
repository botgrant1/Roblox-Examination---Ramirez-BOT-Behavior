local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")
local animator = humanoid:WaitForChild("Animator")

humanoid.AutoRotate = true

getgenv().LurkerAI_Enabled = false
getgenv().GilbertFootSpeed = 0.75 
getgenv().Ramirez_ShowFOV = true 
getgenv().Ramirez_ShowWaypoints = true 

local SelfDodgeConfig = {
	Enabled = true,
	DodgeChance = 0.70,     
	Cooldown = 3.0,         
	DodgeForce = 12,        
	DodgeDuration = 0.15    
}

local canDodgeSelf = true
local lastDodgeTime = 0

local DodgeAnimationIds = {
	"rbxassetid://132266728249440",
	"rbxassetid://107901103720798"
}

local function playRandomDodgeAnim()
	if #DodgeAnimationIds == 0 or not animator then return end
	
	local randomId = DodgeAnimationIds[math.random(1, #DodgeAnimationIds)]
	local animObj = Instance.new("Animation")
	animObj.AnimationId = randomId
	
	local track = animator:LoadAnimation(animObj)
	track.Priority = Enum.AnimationPriority.Action
	track:Play()
end

local getHuiFunction = gethui or function() return player:WaitForChild("PlayerGui") end
local targetGuiParent = getHuiFunction()

if targetGuiParent:FindFirstChild("LurkerControlGui") then
	targetGuiParent.LurkerControlGui:Destroy()
end

local MovementConfig = {
	PatrolSpeed   = 9.5,   
	CombatSpeed   = 11.5,  
	TurnSpeed     = 2.5,   
	AgentRadius   = 3.5,   
	AgentHeight   = 5.0,
	AgentCanJump  = false  
}

local originalWalkSpeed = humanoid.WalkSpeed

local WeaponRegistry = {
	["A9 Brigadier"]     = { FireRate = 0.25, KeepDistance = 18, AutoADS = true },
	["Lock-17"]          = { FireRate = 0.20, KeepDistance = 18, AutoADS = true },
	["F7 Lynx"]          = { FireRate = 0.16, KeepDistance = 18, AutoADS = true },
	["SMX-9"]            = { FireRate = 0.08, KeepDistance = 16, AutoADS = true },
	["SRS-58"]           = { FireRate = 0.85, KeepDistance = 10, AutoADS = false }, 
	["VGS-9"]            = { FireRate = 0.09, KeepDistance = 15, AutoADS = true },
	["IA AR-56"]         = { FireRate = 0.11, KeepDistance = 20, AutoADS = true }, 
	["MPV-SD"]           = { FireRate = 0.07, KeepDistance = 14, AutoADS = true }, 
	["PMS-12T 'Hammer'"] = { FireRate = 0.75, KeepDistance = 10, AutoADS = false }, 
	["VGS-45 'Striker'"] = { FireRate = 0.10, KeepDistance = 15, AutoADS = true }
}

local DefaultWeaponSettings = { FireRate = 0.15, KeepDistance = 16, AutoADS = true }
local currentWeaponName = "None"
local activeFireRate = DefaultWeaponSettings.FireRate
local activeKeepDistance = DefaultWeaponSettings.KeepDistance

local VisualConfig = {
	FieldOfView = 95,        
	ViewDistance = 75,       
}

local currentWaypoints = {}
local currentWaypointIndex = 1

local currentEnemyTarget = nil
local combatScanRange = 75 
local lastRangedShotTime = 0
local lastBashTime = 0
local bashCooldown = 1.2

local lastKnownHealth = humanoid.Health
local overrideActive = false
local leftLaserPart = nil
local rightLaserPart = nil

local lastPositionCheck = Vector3.zero
local stuckTimer = 0
local pathLifeTimer = 0 
local idleWatchdogTimer = 0

local pathCache = {}

local function executeSelfDodge()
	if not canDodgeSelf or not rootPart then return end
	canDodgeSelf = false
	
	local oldVel = rootPart:FindFirstChild("Ramirez_DodgeVel")
	if oldVel then oldVel:Destroy() end

	local isLeft = math.random() > 0.5
	local directionVector = isLeft and -rootPart.CFrame.RightVector or rootPart.CFrame.RightVector

	local dodgeVel = Instance.new("BodyVelocity")
	dodgeVel.Name = "Ramirez_DodgeVel"
	dodgeVel.MaxForce = Vector3.new(math.huge, 0, math.huge)
	dodgeVel.Velocity = (directionVector * SelfDodgeConfig.DodgeForce) + (rootPart.CFrame.LookVector * 4)
	dodgeVel.Parent = rootPart

	playRandomDodgeAnim()

	task.delay(SelfDodgeConfig.DodgeDuration, function()
		if dodgeVel and dodgeVel.Parent then
			dodgeVel:Destroy()
		end
	end)

	task.delay(SelfDodgeConfig.Cooldown, function()
		canDodgeSelf = true
	end)
end

local function triggerBash()
	if os.clock() - lastBashTime >= bashCooldown then
		lastBashTime = os.clock()
		task.spawn(function()
			VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.G, false, game)
			task.wait(0.05)
			VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.G, false, game)
		end)
	end
end

local function isMeleeEnemyNearby(radius)
	radius = radius or 12
	local boxParams = OverlapParams.new()
	boxParams.FilterType = Enum.RaycastFilterType.Exclude
	boxParams.FilterDescendantsInstances = {character, leftLaserPart, rightLaserPart}
	
	local nearbyParts = Workspace:GetPartBoundsInBox(rootPart.CFrame, Vector3.new(radius, 10, radius), boxParams)
	for _, part in ipairs(nearbyParts) do
		local model = part.Parent
		if model and model:IsA("Model") and model ~= character then
			local hum = model:FindFirstChildOfClass("Humanoid")
			local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
			if hum and hum.Health > 0 and root then
				local isRanged = model:FindFirstChildOfClass("Tool") ~= nil or model.Name:find("Gilbert") or model.Name:find("Gunner")
				if not isRanged then
					return true
				end
			end
		end
	end
	return false
end

local function getCacheKey(startPos, endPos)
	return string.format("%.1f_%.1f_%.1f_%.1f_%.1f_%.1f", startPos.X, startPos.Y, startPos.Z, endPos.X, endPos.Y, endPos.Z)
end

local function getCachedWaypoints(startPos, endPos)
	local key = getCacheKey(startPos, endPos)
	local cached = pathCache[key]
	if cached and (os.clock() - cached.time < 3) then
		return cached.waypoints
	end
	return nil
end

local function setCachedWaypoints(startPos, endPos, waypoints)
	local key = getCacheKey(startPos, endPos)
	pathCache[key] = {
		waypoints = waypoints,
		time = os.clock()
	}
end

local function renderDebugWaypoints(waypoints)
	if not getgenv().Ramirez_ShowWaypoints then return end
	for i, wp in ipairs(waypoints) do
		local sphere = Instance.new("Part")
		sphere.Name = "Ramirez_WaypointNode"
		sphere.Size = Vector3.new(0.4, 0.4, 0.4)
		sphere.Shape = Enum.PartType.Ball
		sphere.Material = Enum.Material.Neon
		sphere.Anchored = true
		sphere.CanCollide = false
		sphere.Position = wp.Position
		
		if i == #waypoints then
			sphere.Color = Color3.fromRGB(0, 255, 120) 
		else
			sphere.Color = Color3.fromRGB(255, 160, 30) 
		end
		
		sphere.Parent = Workspace
		Debris:AddItem(sphere, 2.5)
	end
end

local function generatePathTo(destination)
	pathLifeTimer = 0 
	idleWatchdogTimer = 0
	
	local cachedWps = getCachedWaypoints(rootPart.Position, destination)
	if cachedWps then
		currentWaypoints = cachedWps
		currentWaypointIndex = 2
		return
	end

	local path = PathfindingService:CreatePath({
		AgentRadius = MovementConfig.AgentRadius,
		AgentHeight = MovementConfig.AgentHeight,
		AgentCanJump = MovementConfig.AgentCanJump
	})

	local success, err = pcall(function()
		path:ComputeAsync(rootPart.Position, destination)
	end)

	if success and path.Status == Enum.PathStatus.Success then
		currentWaypoints = path:GetWaypoints()
		currentWaypointIndex = 2
		setCachedWaypoints(rootPart.Position, destination, currentWaypoints)
		renderDebugWaypoints(currentWaypoints)
	else
		-- FALLBACK: Si falla el pathfinding, fuerza movimiento directo a un punto libre
		local fallbackDirection = rootPart.CFrame.LookVector * 25
		humanoid:MoveTo(rootPart.Position + fallbackDirection)
		currentWaypoints = {}
		currentWaypointIndex = 1
	end
end

local function findPatrolDestination()
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {character, leftLaserPart, rightLaserPart}
	
	local origin = rootPart.Position
	local currentForward = rootPart.CFrame.LookVector

	local bestPoint = nil
	local maxDistance = 0

	for i = -6, 6 do
		local angle = math.rad(i * 20)
		local dir = (CFrame.new(Vector3.zero, currentForward) * CFrame.Angles(0, angle, 0)).LookVector
		
		local ray = Workspace:Raycast(origin, dir * 100, rayParams)
		local dist = ray and (ray.Position - origin).Magnitude or 100

		if dist > maxDistance and dist > 15 then
			maxDistance = dist
			bestPoint = origin + dir * (dist - 6)
		end
	end

	if not bestPoint then
		bestPoint = origin + (CFrame.Angles(0, math.rad(math.random(-180, 180)), 0) * currentForward) * 40
	end

	generatePathTo(bestPoint)
end

local function scanEquippedWeapon()
	if not character then return end
	local targetTool = character:FindFirstChildOfClass("Tool")
	
	if not targetTool and player:FindFirstChild("Backpack") then
		for _, tool in ipairs(player.Backpack:GetChildren()) do
			if WeaponRegistry[tool.Name] then
				targetTool = tool
				break
			end
		end
	end
	
	if targetTool then
		local name = targetTool.Name
		if name ~= currentWeaponName then
			currentWeaponName = name
			local registryData = WeaponRegistry[name]
			if registryData then
				activeFireRate = registryData.FireRate
				activeKeepDistance = registryData.KeepDistance
			else
				activeFireRate = DefaultWeaponSettings.FireRate
				activeKeepDistance = DefaultWeaponSettings.KeepDistance
			end
		end
	else
		if currentWeaponName ~= "None" then
			currentWeaponName = "None"
			activeFireRate = DefaultWeaponSettings.FireRate
			activeKeepDistance = DefaultWeaponSettings.KeepDistance
		end
	end
end

local function isPlayerPressingMovementKeys()
	return UserInputService:IsKeyDown(Enum.KeyCode.W) 
		or UserInputService:IsKeyDown(Enum.KeyCode.A) 
		or UserInputService:IsKeyDown(Enum.KeyCode.S) 
		or UserInputService:IsKeyDown(Enum.KeyCode.D)
end

local function updateVisionLasers()
	if not getgenv().Ramirez_ShowFOV or not getgenv().LurkerAI_Enabled or not character:FindFirstChild("Head") then
		if leftLaserPart then leftLaserPart:Destroy() leftLaserPart = nil end
		if rightLaserPart then rightLaserPart:Destroy() rightLaserPart = nil end
		return
	end

	local function createLaser(name)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(230, 45, 45)
		part.Transparency = 0.8 
		part.Parent = Workspace
		return part
	end

	leftLaserPart = leftLaserPart or createLaser("Ramirez_LeftFOVBound")
	rightLaserPart = rightLaserPart or createLaser("Ramirez_RightFOVBound")

	local head = character.Head
	local startPos = head.Position
	
	local halfFOV = VisualConfig.FieldOfView / 2
	local leftDirection = (rootPart.CFrame * CFrame.Angles(0, math.rad(halfFOV), 0)).LookVector
	local rightDirection = (rootPart.CFrame * CFrame.Angles(0, math.rad(-halfFOV), 0)).LookVector

	local laserParams = RaycastParams.new()
	laserParams.FilterType = Enum.RaycastFilterType.Exclude
	laserParams.FilterDescendantsInstances = {character, leftLaserPart, rightLaserPart}

	local rayLeft = Workspace:Raycast(startPos, leftDirection * VisualConfig.ViewDistance, laserParams)
	local endPosLeft = rayLeft and rayLeft.Position or (startPos + leftDirection * VisualConfig.ViewDistance)
	local distLeft = (startPos - endPosLeft).Magnitude
	leftLaserPart.Size = Vector3.new(0.06, 0.06, distLeft) 
	leftLaserPart.CFrame = CFrame.lookAt(startPos, endPosLeft) * CFrame.new(0, 0, -distLeft / 2)

	local rayRight = Workspace:Raycast(startPos, rightDirection * VisualConfig.ViewDistance, laserParams)
	local endPosRight = rayRight and rayRight.Position or (startPos + rightDirection * VisualConfig.ViewDistance)
	local distRight = (startPos - endPosRight).Magnitude
	rightLaserPart.Size = Vector3.new(0.06, 0.06, distRight)
	rightLaserPart.CFrame = CFrame.lookAt(startPos, endPosRight) * CFrame.new(0, 0, -distRight / 2)
end

local function isTargetInRamirezCone(enemyRoot)
	local botToTarget = (enemyRoot.Position - rootPart.Position)
	local distance = botToTarget.Magnitude
	if distance > VisualConfig.ViewDistance then return false end
	
	local botLookDirection = rootPart.CFrame.LookVector
	local directionToTarget = botToTarget.Unit
	local dotProduct = botLookDirection:Dot(directionToTarget)
	local angle = math.acos(math.clamp(dotProduct, -1, 1)) * (180 / math.pi)
	
	if angle <= (VisualConfig.FieldOfView / 2) then
		local losParams = RaycastParams.new()
		losParams.FilterType = Enum.RaycastFilterType.Exclude
		local ignoreList = {character, leftLaserPart, rightLaserPart}
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then table.insert(ignoreList, p.Character) end
		end
		losParams.FilterDescendantsInstances = ignoreList
		
		local originPoint = rootPart.Position + Vector3.new(0, 0.5, 0)
		local direction = (enemyRoot.Position - originPoint)
		local losRay = Workspace:Raycast(originPoint, direction, losParams)
		
		if not losRay or losRay.Instance:IsDescendantOf(enemyRoot.Parent) then
			return true
		end
	end
	return false
end

-- GUI Interface
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LurkerControlGui"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 999
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = targetGuiParent

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 260, 0, 480) 
mainFrame.Position = UDim2.new(0.04, 0, 0.25, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.ZIndex = 10
mainFrame.Parent = screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 8)
mainCorner.Parent = mainFrame

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = Color3.fromRGB(45, 48, 56)
mainStroke.Thickness = 1
mainStroke.Parent = mainFrame

local headerFrame = Instance.new("Frame")
headerFrame.Size = UDim2.new(1, 0, 0, 36)
headerFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
headerFrame.BorderSizePixel = 0
headerFrame.ZIndex = 11
headerFrame.Parent = mainFrame

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 8)
headerCorner.Parent = headerFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -40, 1, 0)
titleLabel.Position = UDim2.new(0, 12, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "RAMIREZ AI • V10.5"
titleLabel.TextColor3 = Color3.fromRGB(240, 80, 80)
titleLabel.TextSize = 13
titleLabel.Font = Enum.Font.Code
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.ZIndex = 12
titleLabel.Parent = headerFrame

local minimizeButton = Instance.new("TextButton")
minimizeButton.Size = UDim2.new(0, 28, 0, 28)
minimizeButton.Position = UDim2.new(1, -32, 0, 4)
minimizeButton.BackgroundTransparency = 1
minimizeButton.Text = "−"
minimizeButton.TextColor3 = Color3.fromRGB(180, 180, 180)
minimizeButton.TextSize = 18
minimizeButton.Font = Enum.Font.SourceSansBold
minimizeButton.ZIndex = 12
minimizeButton.Parent = headerFrame

local contentFrame = Instance.new("Frame")
contentFrame.Name = "ContentFrame"
contentFrame.Size = UDim2.new(1, -20, 1, -48)
contentFrame.Position = UDim2.new(0, 10, 0, 42)
contentFrame.BackgroundTransparency = 1
contentFrame.ZIndex = 11
contentFrame.Parent = mainFrame

local toggleButton = Instance.new("TextButton")
toggleButton.Size = UDim2.new(1, 0, 0, 36)
toggleButton.Position = UDim2.new(0, 0, 0, 0)
toggleButton.BackgroundColor3 = Color3.fromRGB(30, 22, 24)
toggleButton.Text = "SYSTEM: DISABLED"
toggleButton.TextColor3 = Color3.fromRGB(220, 90, 90)
toggleButton.TextSize = 13
toggleButton.Font = Enum.Font.SourceSansBold
toggleButton.ZIndex = 12
toggleButton.Parent = contentFrame

local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, 6)
buttonCorner.Parent = toggleButton

local buttonStroke = Instance.new("UIStroke")
buttonStroke.Color = Color3.fromRGB(90, 35, 35)
buttonStroke.Thickness = 1
buttonStroke.Parent = toggleButton

local statusFrame = Instance.new("Frame")
statusFrame.Size = UDim2.new(1, 0, 0, 26)
statusFrame.Position = UDim2.new(0, 0, 0, 42)
statusFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
statusFrame.ZIndex = 11
statusFrame.Parent = contentFrame

local statusCorner = Instance.new("UICorner")
statusCorner.CornerRadius = UDim.new(0, 5)
statusCorner.Parent = statusFrame

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -12, 1, 0)
statusLabel.Position = UDim2.new(0, 8, 0, 0)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Status: Standby"
statusLabel.TextColor3 = Color3.fromRGB(140, 145, 155)
statusLabel.TextSize = 11
statusLabel.Font = Enum.Font.Code
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.ZIndex = 12
statusLabel.Parent = statusFrame

local weaponFrame = Instance.new("Frame")
weaponFrame.Size = UDim2.new(1, 0, 0, 26)
weaponFrame.Position = UDim2.new(0, 0, 0, 74)
weaponFrame.BackgroundColor3 = Color3.fromRGB(22, 18, 28)
weaponFrame.ZIndex = 11
weaponFrame.Parent = contentFrame

local weaponCorner = Instance.new("UICorner")
weaponCorner.CornerRadius = UDim.new(0, 5)
weaponCorner.Parent = weaponFrame

local weaponLabel = Instance.new("TextLabel")
weaponLabel.Size = UDim2.new(1, -12, 1, 0)
weaponLabel.Position = UDim2.new(0, 8, 0, 0)
weaponLabel.BackgroundTransparency = 1
weaponLabel.Text = "Weapon: Scanning..."
weaponLabel.TextColor3 = Color3.fromRGB(185, 140, 245)
weaponLabel.TextSize = 11
weaponLabel.Font = Enum.Font.Code
weaponLabel.TextXAlignment = Enum.TextXAlignment.Left
weaponLabel.ZIndex = 12
weaponLabel.Parent = weaponFrame

local fovToggleButton = Instance.new("TextButton")
fovToggleButton.Size = UDim2.new(1, 0, 0, 26)
fovToggleButton.Position = UDim2.new(0, 0, 0, 106)
fovToggleButton.BackgroundColor3 = Color3.fromRGB(20, 26, 36)
fovToggleButton.Text = "FOV CONE: ACTIVE"
fovToggleButton.TextColor3 = Color3.fromRGB(100, 160, 245)
fovToggleButton.TextSize = 11
fovToggleButton.Font = Enum.Font.SourceSansBold
fovToggleButton.ZIndex = 12
fovToggleButton.Parent = contentFrame

local fovCorner = Instance.new("UICorner")
fovCorner.CornerRadius = UDim.new(0, 5)
fovCorner.Parent = fovToggleButton

local waypointsToggleButton = Instance.new("TextButton")
waypointsToggleButton.Size = UDim2.new(1, 0, 0, 26)
waypointsToggleButton.Position = UDim2.new(0, 0, 0, 138)
waypointsToggleButton.BackgroundColor3 = Color3.fromRGB(20, 32, 28)
waypointsToggleButton.Text = "PATH NODES: VISIBLE"
waypointsToggleButton.TextColor3 = Color3.fromRGB(80, 220, 150)
waypointsToggleButton.TextSize = 11
waypointsToggleButton.Font = Enum.Font.SourceSansBold
waypointsToggleButton.ZIndex = 12
waypointsToggleButton.Parent = contentFrame

local waypointsCorner = Instance.new("UICorner")
waypointsCorner.CornerRadius = UDim.new(0, 5)
waypointsCorner.Parent = waypointsToggleButton

local speedFrame = Instance.new("Frame")
speedFrame.Size = UDim2.new(1, 0, 0, 32)
speedFrame.Position = UDim2.new(0, 0, 0, 170)
speedFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
speedFrame.ZIndex = 11
speedFrame.Parent = contentFrame

local speedCorner = Instance.new("UICorner")
speedCorner.CornerRadius = UDim.new(0, 5)
speedCorner.Parent = speedFrame

local speedLabel = Instance.new("TextLabel")
speedLabel.Size = UDim2.new(0.6, 0, 1, 0)
speedLabel.Position = UDim2.new(0, 8, 0, 0)
speedLabel.BackgroundTransparency = 1
speedLabel.Text = "Anim Speed: " .. string.format("%.2f", getgenv().GilbertFootSpeed)
speedLabel.TextColor3 = Color3.fromRGB(180, 185, 195)
speedLabel.TextSize = 11
speedLabel.Font = Enum.Font.Code
speedLabel.TextXAlignment = Enum.TextXAlignment.Left
speedLabel.ZIndex = 12
speedLabel.Parent = speedFrame

local minusButton = Instance.new("TextButton")
minusButton.Size = UDim2.new(0, 30, 0, 22)
minusButton.Position = UDim2.new(1, -68, 0, 5)
minusButton.BackgroundColor3 = Color3.fromRGB(28, 30, 36)
minusButton.Text = "-"
minusButton.TextColor3 = Color3.fromRGB(220, 220, 220)
minusButton.TextSize = 14
minusButton.Font = Enum.Font.SourceSansBold
minusButton.ZIndex = 12
minusButton.Parent = speedFrame

local minusCorner = Instance.new("UICorner")
minusCorner.CornerRadius = UDim.new(0, 4)
minusCorner.Parent = minusButton

local plusButton = Instance.new("TextButton")
plusButton.Size = UDim2.new(0, 30, 0, 22)
plusButton.Position = UDim2.new(1, -34, 0, 5)
plusButton.BackgroundColor3 = Color3.fromRGB(28, 30, 36)
plusButton.Text = "+"
plusButton.TextColor3 = Color3.fromRGB(220, 220, 220)
plusButton.TextSize = 14
plusButton.Font = Enum.Font.SourceSansBold
plusButton.ZIndex = 12
plusButton.Parent = speedFrame

local plusCorner = Instance.new("UICorner")
plusCorner.CornerRadius = UDim.new(0, 4)
plusCorner.Parent = plusButton

local changelogContainer = Instance.new("Frame")
changelogContainer.Size = UDim2.new(1, 0, 0, 215)
changelogContainer.Position = UDim2.new(0, 0, 0, 210)
changelogContainer.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
changelogContainer.BorderSizePixel = 0
changelogContainer.ZIndex = 11
changelogContainer.Parent = contentFrame

local changelogCorner = Instance.new("UICorner")
changelogCorner.CornerRadius = UDim.new(0, 6)
changelogCorner.Parent = changelogContainer

local changelogStroke = Instance.new("UIStroke")
changelogStroke.Color = Color3.fromRGB(35, 38, 45)
changelogStroke.Thickness = 1
changelogStroke.Parent = changelogContainer

local changelogTitle = Instance.new("TextLabel")
changelogTitle.Size = UDim2.new(1, -12, 0, 24)
changelogTitle.Position = UDim2.new(0, 8, 0, 2)
changelogTitle.BackgroundTransparency = 1
changelogTitle.Text = "CHANGELOG • V10.5"
changelogTitle.TextColor3 = Color3.fromRGB(245, 170, 70)
changelogTitle.TextSize = 11
changelogTitle.Font = Enum.Font.Code
changelogTitle.TextXAlignment = Enum.TextXAlignment.Left
changelogTitle.ZIndex = 12
changelogTitle.Parent = changelogContainer

local changelogScroll = Instance.new("ScrollingFrame")
changelogScroll.Size = UDim2.new(1, -12, 1, -30)
changelogScroll.Position = UDim2.new(0, 6, 0, 26)
changelogScroll.BackgroundTransparency = 1
changelogScroll.BorderSizePixel = 0
changelogScroll.ScrollBarThickness = 3
changelogScroll.ScrollBarImageColor3 = Color3.fromRGB(70, 75, 90)
changelogScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
changelogScroll.ZIndex = 12
changelogScroll.Parent = changelogContainer

local changelogListLayout = Instance.new("UIListLayout")
changelogListLayout.SortOrder = Enum.SortOrder.LayoutOrder
changelogListLayout.Padding = UDim.new(0, 4)
changelogListLayout.Parent = changelogScroll

changelogListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	changelogScroll.CanvasSize = UDim2.new(0, 0, 0, changelogListLayout.AbsoluteContentSize.Y + 6)
end)

local function addChangelogEntry(text, color)
	local entryLabel = Instance.new("TextLabel")
	entryLabel.Size = UDim2.new(1, -6, 0, 0)
	entryLabel.AutomaticSize = Enum.AutomaticSize.Y
	entryLabel.BackgroundTransparency = 1
	entryLabel.Text = text
	entryLabel.TextColor3 = color or Color3.fromRGB(170, 175, 185)
	entryLabel.TextSize = 10
	entryLabel.Font = Enum.Font.Code
	entryLabel.TextXAlignment = Enum.TextXAlignment.Left
	entryLabel.TextWrapped = true
	entryLabel.ZIndex = 13
	entryLabel.Parent = changelogScroll
end

-- Changelog en inglés para la UI
addChangelogEntry("[+] Smart Melee Bash: Only triggers if infected/melee enemies are within ≤12 studs.", Color3.fromRGB(110, 220, 140))
addChangelogEntry("[+] Distance Damage Fix: Prioritizes dodging over empty swings when taking ranged hits.", Color3.fromRGB(110, 220, 140))
addChangelogEntry("[+] Realistic Animations: Replaced dodge animation IDs with smoother, realistic sequences.", Color3.fromRGB(110, 220, 140))
addChangelogEntry("[+] Path Freeze Fix: Added fallback movement & idle watchdog to prevent getting stuck at path ends.", Color3.fromRGB(110, 220, 140))
addChangelogEntry("[*] Combat Prediction: Optimized lead targeting for fast-moving or dodging targets.", Color3.fromRGB(245, 190, 90))
addChangelogEntry("[*] UI Enhancements: Integrated scrollable Changelog panel into the gethui interface.", Color3.fromRGB(245, 190, 90))

local isMinimized = false
minimizeButton.Activated:Connect(function()
	isMinimized = not isMinimized
	if isMinimized then
		mainFrame.Size = UDim2.new(0, 260, 0, 36)
		minimizeButton.Text = "+"
		contentFrame.Visible = false
	else
		mainFrame.Size = UDim2.new(0, 260, 0, 480)
		minimizeButton.Text = "−"
		contentFrame.Visible = true
	end
end)

fovToggleButton.Activated:Connect(function()
	getgenv().Ramirez_ShowFOV = not getgenv().Ramirez_ShowFOV
	if getgenv().Ramirez_ShowFOV then
		fovToggleButton.Text = "FOV CONE: ACTIVE"
		fovToggleButton.BackgroundColor3 = Color3.fromRGB(20, 26, 36)
		fovToggleButton.TextColor3 = Color3.fromRGB(100, 160, 245)
	else
		fovToggleButton.Text = "FOV CONE: DISABLED"
		fovToggleButton.BackgroundColor3 = Color3.fromRGB(22, 22, 24)
		fovToggleButton.TextColor3 = Color3.fromRGB(120, 120, 120)
		if leftLaserPart then leftLaserPart:Destroy() leftLaserPart = nil end
		if rightLaserPart then rightLaserPart:Destroy() rightLaserPart = nil end
	end
end)

waypointsToggleButton.Activated:Connect(function()
	getgenv().Ramirez_ShowWaypoints = not getgenv().Ramirez_ShowWaypoints
	if getgenv().Ramirez_ShowWaypoints then
		waypointsToggleButton.Text = "PATH NODES: VISIBLE"
		waypointsToggleButton.BackgroundColor3 = Color3.fromRGB(20, 32, 28)
		waypointsToggleButton.TextColor3 = Color3.fromRGB(80, 220, 150)
	else
		waypointsToggleButton.Text = "PATH NODES: HIDDEN"
		waypointsToggleButton.BackgroundColor3 = Color3.fromRGB(22, 22, 24)
		waypointsToggleButton.TextColor3 = Color3.fromRGB(120, 120, 120)
	end
end)

minusButton.Activated:Connect(function()
	if getgenv().GilbertFootSpeed > 0.3 then
		getgenv().GilbertFootSpeed = math.max(0.3, getgenv().GilbertFootSpeed - 0.05)
		speedLabel.Text = "Anim Speed: " .. string.format("%.2f", getgenv().GilbertFootSpeed)
	end
end)

plusButton.Activated:Connect(function()
	if getgenv().GilbertFootSpeed < 3.0 then
		getgenv().GilbertFootSpeed = math.min(3.0, getgenv().GilbertFootSpeed + 0.05)
		speedLabel.Text = "Anim Speed: " .. string.format("%.2f", getgenv().GilbertFootSpeed)
	end
end)

local function disableSystemFully()
	getgenv().LurkerAI_Enabled = false
	humanoid.WalkSpeed = originalWalkSpeed
	humanoid:MoveTo(rootPart.Position)
	toggleButton.Text = "SYSTEM: DISABLED"
	toggleButton.BackgroundColor3 = Color3.fromRGB(30, 22, 24)
	toggleButton.TextColor3 = Color3.fromRGB(220, 90, 90)
	buttonStroke.Color = Color3.fromRGB(90, 35, 35)
	currentEnemyTarget = nil
	overrideActive = false
	
	if leftLaserPart then leftLaserPart:Destroy() leftLaserPart = nil end
	if rightLaserPart then rightLaserPart:Destroy() rightLaserPart = nil end
end

humanoid.HealthChanged:Connect(function(currentHealth)
	if not getgenv().LurkerAI_Enabled then 
		lastKnownHealth = currentHealth
		return 
	end
	if currentHealth < lastKnownHealth and currentHealth > 0 then
		lastKnownHealth = currentHealth
		
		if isMeleeEnemyNearby(12) then
			triggerBash()
		end
		
		if SelfDodgeConfig.Enabled and math.random() < SelfDodgeConfig.DodgeChance then
			executeSelfDodge()
		end

		statusLabel.Text = "Status: TAKING DAMAGE / EVADING"
		statusLabel.TextColor3 = Color3.fromRGB(255, 60, 80)
	else
		lastKnownHealth = currentHealth
	end
end)

toggleButton.Activated:Connect(function()
	if getgenv().LurkerAI_Enabled then
		disableSystemFully()
		statusLabel.Text = "Status: Manual Control"
		statusLabel.TextColor3 = Color3.fromRGB(140, 145, 155)
	else
		getgenv().LurkerAI_Enabled = true
		overrideActive = false
		lastKnownHealth = humanoid.Health
		toggleButton.Text = "SYSTEM: ACTIVE"
		toggleButton.BackgroundColor3 = Color3.fromRGB(20, 34, 24)
		toggleButton.TextColor3 = Color3.fromRGB(90, 220, 110)
		buttonStroke.Color = Color3.fromRGB(35, 90, 45)
		statusLabel.Text = "Status: Sweeping..."
		statusLabel.TextColor3 = Color3.fromRGB(90, 220, 110)
		
		currentEnemyTarget = nil
		findPatrolDestination()
	end
end)

task.spawn(function()
	while true do
		task.wait(0.1) 
		scanEquippedWeapon() 
		weaponLabel.Text = "Weapon: " .. currentWeaponName
		
		if getgenv().LurkerAI_Enabled and character and character:FindFirstChild("HumanoidRootPart") then
			if currentEnemyTarget and currentEnemyTarget.Parent and currentEnemyTarget.Parent:FindFirstChildOfClass("Humanoid") then
				local hum = currentEnemyTarget.Parent:FindFirstChildOfClass("Humanoid")
				local dist = (rootPart.Position - currentEnemyTarget.Position).Magnitude
				if hum.Health <= 0 or dist > combatScanRange then
					currentEnemyTarget = nil
				end
			else
				currentEnemyTarget = nil
			end

			if not currentEnemyTarget then
				local closestEnemy = nil
				local shortestDistance = combatScanRange
				
				local boxParams = OverlapParams.new()
				boxParams.FilterType = Enum.RaycastFilterType.Exclude
				boxParams.FilterDescendantsInstances = {character, leftLaserPart, rightLaserPart}
				
				local nearbyParts = Workspace:GetPartBoundsInBox(rootPart.CFrame, Vector3.new(combatScanRange, 16, combatScanRange), boxParams)
				local analyzedModels = {}

				for _, part in ipairs(nearbyParts) do
					local model = part.Parent
					if model and model:IsA("Model") and not analyzedModels[model] and model ~= character then
						analyzedModels[model] = true
						local enemyHumanoid = model:FindFirstChildOfClass("Humanoid")
						local enemyRoot = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
						
						if enemyHumanoid and enemyRoot and enemyHumanoid.Health > 0 then
							if not Players:GetPlayerFromCharacter(model) then
								local dist = (rootPart.Position - enemyRoot.Position).Magnitude
								if dist < shortestDistance and isTargetInRamirezCone(enemyRoot) then
									shortestDistance = dist
									closestEnemy = enemyRoot
								end
							end
						end
					end
				end
				currentEnemyTarget = closestEnemy
			end
		end
	end
end)

RunService.Heartbeat:Connect(function(deltaTime)
	if not getgenv().LurkerAI_Enabled or not humanoid or humanoid.Health <= 0 then 
		if leftLaserPart then leftLaserPart:Destroy() leftLaserPart = nil end
		if rightLaserPart then rightLaserPart:Destroy() rightLaserPart = nil end
		return 
	end
	
	updateVisionLasers()
	
	if isPlayerPressingMovementKeys() then
		overrideActive = true 
		currentEnemyTarget = nil 
		statusLabel.Text = "Status: Manual Override"
		statusLabel.TextColor3 = Color3.fromRGB(120, 170, 245)
		return 
	end

	if overrideActive and not isPlayerPressingMovementKeys() then
		overrideActive = false
		findPatrolDestination()
		statusLabel.Text = "Status: Resuming Patrol"
		statusLabel.TextColor3 = Color3.fromRGB(245, 180, 80)
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			if track.Name == "WalkAnim" or track.Name == "RunAnim" or string.find(string.lower(track.Name), "walk") or string.find(string.lower(track.Name), "run") then
				track:AdjustSpeed(getgenv().GilbertFootSpeed)
			end
		end
	end

	pathLifeTimer = pathLifeTimer + deltaTime

	-- DETECCIÓN DE ATASCAMIENTO POR FÍSICAS O COLISIONES
	if (rootPart.Position - lastPositionCheck).Magnitude < 0.15 then
		stuckTimer = stuckTimer + deltaTime
		if stuckTimer > 0.6 then
			findPatrolDestination() 
			stuckTimer = 0
		end
	else
		stuckTimer = 0
		lastPositionCheck = rootPart.Position
	end

	if pathLifeTimer > 4.5 then
		findPatrolDestination()
	end

	if currentEnemyTarget and currentEnemyTarget.Parent then
		humanoid.WalkSpeed = MovementConfig.CombatSpeed
		
		local enemyModel = currentEnemyTarget.Parent
		local isRangedEnemy = enemyModel:FindFirstChildOfClass("Tool") ~= nil or enemyModel.Name:find("Gilbert") or enemyModel.Name:find("Gunner")
		
		local enemyVelocity = currentEnemyTarget.AssemblyLinearVelocity or Vector3.zero
		local isDodging = currentEnemyTarget:FindFirstChild("DodgeVelocity") or currentEnemyTarget:FindFirstChild("ReturnVelocity")
		
		local targetAimPosition = currentEnemyTarget.Position
		
		if (isRangedEnemy and enemyVelocity.Magnitude > 2) or isDodging then
			targetAimPosition = targetAimPosition + (enemyVelocity * 0.14)
		end

		local distanceToEnemy = (rootPart.Position - targetAimPosition).Magnitude
		
		if distanceToEnemy > combatScanRange then
			currentEnemyTarget = nil
			return
		end
		
		statusLabel.Text = "Status: Engaged (" .. (isRangedEnemy and "PRIORITY: RANGED" or "MELEE INFECTED") .. ")"
		statusLabel.TextColor3 = isRangedEnemy and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(255, 150, 50)
		
		if not isRangedEnemy and distanceToEnemy <= 8.5 then
			triggerBash()
		end

		local desiredDistance = isRangedEnemy and activeKeepDistance or 8.0
		if distanceToEnemy < desiredDistance - 2 then
			humanoid:MoveTo(rootPart.Position - (targetAimPosition - rootPart.Position).Unit * 4)
		else
			humanoid:MoveTo(targetAimPosition)
		end

		local lookTarget = Vector3.new(targetAimPosition.X, rootPart.Position.Y, targetAimPosition.Z)
		local smoothTurn = isDodging and (MovementConfig.TurnSpeed * 1.8) or MovementConfig.TurnSpeed
		rootPart.CFrame = rootPart.CFrame:Lerp(CFrame.lookAt(rootPart.Position, lookTarget), math.clamp(smoothTurn * deltaTime, 0, 1))

		if os.clock() - lastRangedShotTime >= activeFireRate then
			lastRangedShotTime = os.clock()
			task.spawn(function()
				VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
				task.wait(0.015)
				VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
			end)
		end
		return
	end

	humanoid.WalkSpeed = MovementConfig.PatrolSpeed

	-- WATCHDOG: Evita que se quede inmóvil si la lista de waypoints se vacía sin reasignar
	if #currentWaypoints == 0 or currentWaypointIndex > #currentWaypoints then
		idleWatchdogTimer = idleWatchdogTimer + deltaTime
		if idleWatchdogTimer >= 0.2 then
			findPatrolDestination()
		end
	else
		idleWatchdogTimer = 0
		local targetWaypoint = currentWaypoints[currentWaypointIndex]
		local wayPointPos = targetWaypoint.Position
		local distance = (rootPart.Position - Vector3.new(wayPointPos.X, rootPart.Position.Y, wayPointPos.Z)).Magnitude

		humanoid:MoveTo(wayPointPos)

		local isLastWaypoint = (currentWaypointIndex == #currentWaypoints)
		local threshold = isLastWaypoint and 5.0 or 3.5

		if distance < threshold then 
			currentWaypointIndex = currentWaypointIndex + 1
			if currentWaypointIndex > #currentWaypoints then
				findPatrolDestination()
			end
		end
	end

	statusLabel.Text = "Status: Pathfinding Patrol"
	statusLabel.TextColor3 = Color3.fromRGB(90, 220, 110)
end)

humanoid.Died:Connect(function() 
	if leftLaserPart then leftLaserPart:Destroy() end
	if rightLaserPart then rightLaserPart:Destroy() rightLaserPart = nil end
	screenGui:Destroy() 
end)
