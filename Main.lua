-- Ramiréz BOT Behavior V6.0 - FULL SYSTEM RESTORATION (LASERS & PATHING FIXED)
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

getgenv().LurkerAI_Enabled = false
getgenv().GilbertFootSpeed = 1.7 
getgenv().Ramirez_ShowFOV = true 

if player:WaitForChild("PlayerGui"):FindFirstChild("LurkerControlGui") then
	player.PlayerGui.LurkerControlGui:Destroy()
end

-- =============================================================================
-- BASE DE DATOS DE ARMAS OFICIALES (EXAMINATION WIKI)
-- =============================================================================
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
local optimalKeepDistance = DefaultWeaponSettings.KeepDistance
local weaponAllowsADS = DefaultWeaponSettings.AutoADS

local VisualConfig = {
	FieldOfView = 90,        
	ViewDistance = 45,       
}

local targetPosition = rootPart.Position
local isResting = false
local restTimer = 0
local currentVisualHeading = rootPart.CFrame.LookVector
local dangerousZones = {} 

local currentEnemyTarget = nil
local combatScanRange = 45 
local lastRangedShotTime = 0
local internalManualHandover = false 
local isAimingADS = false

local lastKnownHealth = humanoid.Health
local overrideActive = false
local leftLaserPart = nil
local rightLaserPart = nil

-- RECONOCIMIENTO DE INVENTARIO MEJORADO
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
				optimalKeepDistance = registryData.KeepDistance
				weaponAllowsADS = registryData.AutoADS
			else
				activeFireRate = DefaultWeaponSettings.FireRate
				optimalKeepDistance = DefaultWeaponSettings.KeepDistance
				weaponAllowsADS = DefaultWeaponSettings.AutoADS
			end
		end
	else
		if currentWeaponName ~= "None" then
			currentWeaponName = "None"
			activeFireRate = DefaultWeaponSettings.FireRate
			optimalKeepDistance = DefaultWeaponSettings.KeepDistance
			weaponAllowsADS = DefaultWeaponSettings.AutoADS
		end
	end
end

local function isPlayerMovingInput()
	local moveDirection = humanoid.MoveDirection
	return moveDirection.Magnitude > 0.1
end

-- =============================================================================
-- RESTAURADO: FILTRO MATEMÁTICO DE CONO VISUAL Y ASIGNACIÓN DE LÁSERES FOV
-- =============================================================================
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
		part.Color = Color3.fromRGB(255, 65, 65)
		part.Transparency = 0.75 
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
	leftLaserPart.Size = Vector3.new(0.08, 0.08, distLeft) 
	leftLaserPart.CFrame = CFrame.lookAt(startPos, endPosLeft) * CFrame.new(0, 0, -distLeft / 2)

	local rayRight = Workspace:Raycast(startPos, rightDirection * VisualConfig.ViewDistance, laserParams)
	local endPosRight = rayRight and rayRight.Position or (startPos + rightDirection * VisualConfig.ViewDistance)
	local distRight = (startPos - endPosRight).Magnitude
	rightLaserPart.Size = Vector3.new(0.08, 0.08, distRight)
	rightLaserPart.CFrame = CFrame.lookAt(startPos, endPosRight) * CFrame.new(0, 0, -distRight / 2)
end

local function isTargetInRamirezCone(enemyRoot)
	local botToTarget = (enemyRoot.Position - rootPart.Position)
	local distance = botToTarget.Magnitude
	if distance > VisualConfig.ViewDistance then return false end
	
	local botLookDirection = rootPart.CFrame.LookVector
	local directionToTarget = botToTarget.Unit
	local dotProduct = botLookDirection:Dot(directionToTarget)
	local angle = math.acos(dotProduct) * (180 / math.pi)
	
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

-- RESTAURADO: GENERADOR DE RUTA AUTÓNOMA PARA PASILLOS
local function calculateSmartLurkerPath()
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {character, leftLaserPart, rightLaserPart}
	local origin = rootPart.Position + Vector3.new(0, 0.5, 0)
	local validOptions = {}
	
	for i = 1, 12 do
		local angle = math.rad(i * 30)
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle)).Unit
		local ray = Workspace:Raycast(origin, direction * 45, rayParams)
		local dist = ray and (ray.Position - rootPart.Position).Magnitude or 45
		
		if dist > 12 then
			local potentialPoint = rootPart.Position + direction * (dist - 4)
			local isSafe = true
			for dangerPos, _ in pairs(dangerousZones) do
				if (potentialPoint - dangerPos).Magnitude < 25 then 
					isSafe = false
					break
				end
			end
			if isSafe then table.insert(validOptions, potentialPoint) end
		end
	end
	return #validOptions > 0 and validOptions[math.random(1, #validOptions)] or (rootPart.Position + rootPart.CFrame.LookVector * 15)
end

-- =============================================================================
-- INTERFAZ GRÁFICA V6.0
-- =============================================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LurkerControlGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 240, 0, 420) 
mainFrame.Position = UDim2.new(0.05, 0, 0.35, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(15, 12, 12)
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Parent = screenGui

local uiCorner = Instance.new("UICorner")
uiCorner.CornerRadius = UDim.new(0, 8)
uiCorner.Parent = mainFrame

local uiStroke = Instance.new("UIStroke")
uiStroke.Color = Color3.fromRGB(75, 35, 35)
uiStroke.Thickness = 1
uiStroke.Parent = mainFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -40, 0, 35)
titleLabel.Position = UDim2.new(0, 12, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Ramirez BOT Behavior V6.0"
titleLabel.TextColor3 = Color3.fromRGB(255, 65, 65)
titleLabel.TextSize = 12
titleLabel.Font = Enum.Font.Code
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = mainFrame

local contentFrame = Instance.new("Frame")
contentFrame.Name = "ContentFrame"
contentFrame.Size = UDim2.new(1, 0, 1, -35)
contentFrame.Position = UDim2.new(0, 0, 0, 35)
contentFrame.BackgroundTransparency = 1
contentFrame.Parent = mainFrame

local toggleButton = Instance.new("TextButton")
toggleButton.Size = UDim2.new(0, 200, 0, 35)
toggleButton.Position = UDim2.new(0, 20, 0, 5)
toggleButton.BackgroundColor3 = Color3.fromRGB(35, 25, 25)
toggleButton.Text = "SYSTEM: DISABLED"
toggleButton.TextColor3 = Color3.fromRGB(200, 100, 100)
toggleButton.TextSize = 13
toggleButton.Font = Enum.Font.SourceSansBold
toggleButton.Parent = contentFrame

local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, 5)
buttonCorner.Parent = toggleButton

local buttonStroke = Instance.new("UIStroke")
buttonStroke.Color = Color3.fromRGB(100, 40, 40)
buttonStroke.Thickness = 1
buttonStroke.Parent = toggleButton

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(0, 200, 0, 25)
statusLabel.Position = UDim2.new(0, 20, 0, 45)
statusLabel.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
statusLabel.Text = "Status: Idle"
statusLabel.TextColor3 = Color3.fromRGB(130, 130, 130)
statusLabel.TextSize = 12
statusLabel.Font = Enum.Font.SourceSansItalic
statusLabel.Parent = contentFrame

local statusCorner = Instance.new("UICorner")
statusCorner.CornerRadius = UDim.new(0, 4)
statusCorner.Parent = statusLabel

local weaponLabel = Instance.new("TextLabel")
weaponLabel.Size = UDim2.new(0, 200, 0, 25)
weaponLabel.Position = UDim2.new(0, 20, 0, 75)
weaponLabel.BackgroundColor3 = Color3.fromRGB(20, 15, 25)
weaponLabel.Text = "Weapon: Scanning..."
weaponLabel.TextColor3 = Color3.fromRGB(210, 150, 255)
weaponLabel.TextSize = 11
weaponLabel.Font = Enum.Font.Code
weaponLabel.Parent = contentFrame

local weaponCorner = Instance.new("UICorner")
weaponCorner.CornerRadius = UDim.new(0, 4)
weaponCorner.Parent = weaponLabel

local weaponStroke = Instance.new("UIStroke")
weaponStroke.Color = Color3.fromRGB(90, 50, 130)
weaponStroke.Thickness = 1
weaponStroke.Parent = weaponLabel

local fovToggleButton = Instance.new("TextButton")
fovToggleButton.Size = UDim2.new(0, 200, 0, 25)
fovToggleButton.Position = UDim2.new(0, 20, 0, 105)
fovToggleButton.BackgroundColor3 = Color3.fromRGB(25, 30, 40)
fovToggleButton.Text = "VISUAL FOV: ENABLED"
fovToggleButton.TextColor3 = Color3.fromRGB(100, 150, 255)
fovToggleButton.TextSize = 11
fovToggleButton.Font = Enum.Font.SourceSansBold
fovToggleButton.Parent = contentFrame

local fovCorner = Instance.new("UICorner")
fovCorner.CornerRadius = UDim.new(0, 4)
fovCorner.Parent = fovToggleButton

local fovStroke = Instance.new("UIStroke")
fovStroke.Color = Color3.fromRGB(40, 70, 120)
fovStroke.Thickness = 1
fovStroke.Parent = fovToggleButton

local speedLabel = Instance.new("TextLabel")
speedLabel.Size = UDim2.new(1, 0, 0, 25)
speedLabel.Position = UDim2.new(0, 0, 0, 135) 
speedLabel.BackgroundTransparency = 1
speedLabel.Text = "Footstep Frequency: " .. string.format("%.1f", getgenv().GilbertFootSpeed)
speedLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
speedLabel.TextSize = 13
speedLabel.Font = Enum.Font.SourceSans
speedLabel.Parent = contentFrame

local minusButton = Instance.new("TextButton")
minusButton.Size = UDim2.new(0, 45, 0, 30)
minusButton.Position = UDim2.new(0, 50, 0, 165) 
minusButton.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
minusButton.Text = "-"
minusButton.TextColor3 = Color3.fromRGB(200, 200, 200)
minusButton.TextSize = 18
minusButton.Font = Enum.Font.SourceSansBold
minusButton.Parent = contentFrame

local minusCorner = Instance.new("UICorner")
minusCorner.CornerRadius = UDim.new(0, 4)
minusCorner.Parent = minusButton

local plusButton = Instance.new("TextButton")
plusButton.Size = UDim2.new(0, 45, 0, 30)
plusButton.Position = UDim2.new(0, 145, 0, 165) 
plusButton.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
plusButton.Text = "+"
plusButton.TextColor3 = Color3.fromRGB(200, 200, 200)
plusButton.TextSize = 18
plusButton.Font = Enum.Font.SourceSansBold
plusButton.Parent = contentFrame

local plusCorner = Instance.new("UICorner")
plusCorner.CornerRadius = UDim.new(0, 4)
plusCorner.Parent = plusButton

local updatesFrame = Instance.new("Frame")
updatesFrame.Size = UDim2.new(0, 200, 0, 135)
updatesFrame.Position = UDim2.new(0, 20, 0, 230) 
updatesFrame.BackgroundColor3 = Color3.fromRGB(10, 8, 8)
updatesFrame.BorderSizePixel = 0
updatesFrame.Parent = contentFrame

local logLabel = Instance.new("TextLabel")
logLabel.Size = UDim2.new(1, -12, 1, -10)
logLabel.Position = UDim2.new(0, 6, 0, 5)
logLabel.BackgroundTransparency = 1
logLabel.Text = "[+] RESTORE V6.0:\n• FIXED AI Patrolling & Raycast path generation loop.\n• RESTORED Lateral laser FOV bounds calculation.\n• FIXED Override resume trigger to force immediate new node detection."
logLabel.TextColor3 = Color3.fromRGB(165, 150, 150)
logLabel.TextSize = 11
logLabel.Font = Enum.Font.Code
logLabel.TextWrapped = true
logLabel.TextYAlignment = Enum.TextYAlignment.Top
logLabel.TextXAlignment = Enum.TextXAlignment.Left
logLabel.Parent = updatesFrame

local minimizeButton = Instance.new("TextButton")
minimizeButton.Size = UDim2.new(0, 25, 0, 25)
minimizeButton.Position = UDim2.new(1, -30, 0, 5)
minimizeButton.BackgroundTransparency = 1
minimizeButton.Text = "-"
minimizeButton.TextColor3 = Color3.fromRGB(150, 150, 150)
minimizeButton.TextSize = 18
minimizeButton.Font = Enum.Font.SourceSansBold
minimizeButton.Parent = mainFrame

local isMinimized = false
minimizeButton.MouseButton1Click:Connect(function()
	isMinimized = not isMinimized
	if isMinimized then
		mainFrame.Size = UDim2.new(0, 240, 0, 35)
		minimizeButton.Text = "+"
		contentFrame.Visible = false
	else
		mainFrame.Size = UDim2.new(0, 240, 0, 420)
		minimizeButton.Text = "-"
		contentFrame.Visible = true
	end
end)

fovToggleButton.MouseButton1Click:Connect(function()
	getgenv().Ramirez_ShowFOV = not getgenv().Ramirez_ShowFOV
	if getgenv().Ramirez_ShowFOV then
		fovToggleButton.Text = "VISUAL FOV: ENABLED"
		fovToggleButton.BackgroundColor3 = Color3.fromRGB(25, 30, 40)
		fovToggleButton.TextColor3 = Color3.fromRGB(100, 150, 255)
	else
		fovToggleButton.Text = "VISUAL FOV: DISABLED"
		fovToggleButton.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
		fovToggleButton.TextColor3 = Color3.fromRGB(150, 150, 150)
		if leftLaserPart then leftLaserPart:Destroy() leftLaserPart = nil end
		if rightLaserPart then rightLaserPart:Destroy() rightLaserPart = nil end
	end
end)

minusButton.MouseButton1Click:Connect(function()
	if getgenv().GilbertFootSpeed > 0.5 then
		getgenv().GilbertFootSpeed = math.max(0.5, getgenv().GilbertFootSpeed - 0.1)
		speedLabel.Text = "Footstep Frequency: " .. string.format("%.1f", getgenv().GilbertFootSpeed)
	end
end)

plusButton.MouseButton1Click:Connect(function()
	if getgenv().GilbertFootSpeed < 5.0 then
		getgenv().GilbertFootSpeed = math.min(5.0, getgenv().GilbertFootSpeed + 0.1)
		speedLabel.Text = "Footstep Frequency: " .. string.format("%.1f", getgenv().GilbertFootSpeed)
	end
end)

local function disableSystemFully()
	getgenv().LurkerAI_Enabled = false
	toggleButton.Text = "SYSTEM: DISABLED"
	toggleButton.BackgroundColor3 = Color3.fromRGB(35, 25, 25)
	toggleButton.TextColor3 = Color3.fromRGB(200, 100, 100)
	buttonStroke.Color = Color3.fromRGB(100, 40, 40)
	isResting = false
	currentEnemyTarget = nil
	overrideActive = false
	if isAimingADS then
		isAimingADS = false
		VirtualInputManager:SendMouseButtonEvent(0, 0, 1, false, game, 0)
	end
	if leftLaserPart then leftLaserPart:Destroy() leftLaserPart = nil end
	if rightLaserPart then rightLaserPart:Destroy() rightLaserPart = nil end
	pcall(function() rootPart.AssemblyLinearVelocity = Vector3.new() end)
end

humanoid.HealthChanged:Connect(function(currentHealth)
	if not getgenv().LurkerAI_Enabled or internalManualHandover then 
		lastKnownHealth = currentHealth
		return 
	end
	if currentHealth < lastKnownHealth and currentHealth > 0 then
		lastKnownHealth = currentHealth
		if currentEnemyTarget then return end
		statusLabel.Text = "AMBUSH DETECTED! SWEEPING..."
		statusLabel.TextColor3 = Color3.fromRGB(255, 0, 100)
		task.spawn(function()
			for i = 1, 4 do
				if currentEnemyTarget then break end 
				rootPart.CFrame = rootPart.CFrame * CFrame.Angles(0, math.rad(90), 0)
				task.wait(0.05) 
			end
		end)
	else
		lastKnownHealth = currentHealth
	end
end)

toggleButton.MouseButton1Click:Connect(function()
	if getgenv().LurkerAI_Enabled then
		disableSystemFully()
		statusLabel.Text = "Status: Manual Control"
		statusLabel.TextColor3 = Color3.fromRGB(130, 130, 130)
	else
		getgenv().LurkerAI_Enabled = true
		internalManualHandover = false
		overrideActive = false
		lastKnownHealth = humanoid.Health
		toggleButton.Text = "SYSTEM: ACTIVE"
		toggleButton.BackgroundColor3 = Color3.fromRGB(25, 40, 25)
		toggleButton.TextColor3 = Color3.fromRGB(100, 220, 100)
		buttonStroke.Color = Color3.fromRGB(40, 120, 40)
		statusLabel.Text = "Sweeping Corridors..."
		statusLabel.TextColor3 = Color3.fromRGB(100, 200, 100)
		
		pcall(function() rootPart.AssemblyLinearVelocity = Vector3.new() end)
		dangerousZones = {}
		isResting = false
		currentEnemyTarget = nil
		targetPosition = calculateSmartLurkerPath()
	end
end)

-- SCANNER CONO VISUAL Y REGISTRO DE ARMAS LIVE
task.spawn(function()
	while true do
		task.wait(0.1) 
		scanEquippedWeapon() 
		weaponLabel.Text = "Weapon: " .. currentWeaponName
		
		if getgenv().LurkerAI_Enabled and character and character:FindFirstChild("HumanoidRootPart") and not internalManualHandover then
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
		elseif not getgenv().LurkerAI_Enabled or internalManualHandover then
			currentEnemyTarget = nil
		end
	end
end)

-- =============================================================================
-- EXEC_CORE COMPLETAMENTE RESTAURADO V6.0
-- =============================================================================
RunService.Heartbeat:Connect(function(deltaTime)
	if not getgenv().LurkerAI_Enabled or not humanoid or humanoid.Health <= 0 or internalManualHandover then 
		if leftLaserPart then leftLaserPart:Destroy() leftLaserPart = nil end
		if rightLaserPart then rightLaserPart:Destroy() rightLaserPart = nil end
		return 
	end
	
	updateVisionLasers()
	
	-- Comprobación manual: Interrumpe patrulla si te movés vos
	if isPlayerMovingInput() and not currentEnemyTarget then
		overrideActive = true 
		statusLabel.Text = "User Override: Moving..."
		statusLabel.TextColor3 = Color3.fromRGB(140, 170, 230)
		return 
	end

	-- Trigger de reanudación: Cuando te frenás, fuerza una ruta nueva al instante
	if overrideActive and not isPlayerMovingInput() then
		overrideActive = false
		isResting = false
		targetPosition = calculateSmartLurkerPath() 
		statusLabel.Text = "Resuming AI Patrolling..."
		statusLabel.TextColor3 = Color3.fromRGB(255, 165, 0)
		return
	end

	-- COMBATE ADAPTATIVO ACTIVADO
	if currentEnemyTarget and currentEnemyTarget.Parent then
		local enemyPos = currentEnemyTarget.Position
		local distanceToEnemy = (rootPart.Position - enemyPos).Magnitude
		
		statusLabel.Text = "ENGAGING WITH " .. string.upper(currentWeaponName)
		statusLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
		
		local lookTarget = Vector3.new(enemyPos.X, rootPart.Position.Y, enemyPos.Z)
		rootPart.CFrame = rootPart.CFrame:Lerp(CFrame.lookAt(rootPart.Position, lookTarget), 24 * deltaTime)
		
		local moveDir = Vector3.new()
		if distanceToEnemy > (optimalKeepDistance + 3) then
			moveDir = (Vector3.new(enemyPos.X, 0, enemyPos.Z) - Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z)).Unit
			pcall(function() rootPart.AssemblyLinearVelocity = moveDir * 8.5 end)
		elseif distanceToEnemy < (optimalKeepDistance - 3) then
			moveDir = -(Vector3.new(enemyPos.X, 0, enemyPos.Z) - Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z)).Unit
			pcall(function() rootPart.AssemblyLinearVelocity = moveDir * 7.5 end)
		else
			pcall(function() rootPart.AssemblyLinearVelocity = Vector3.new() end)
		end

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

	-- LÓGICA DE PATRULLA PRINCIPAL RESTAURADA
	local currentSpeed = 7.2
	local moveDirection = Vector3.new()
	local isCurrentlyMoving = false
	
	if isResting then
		restTimer = restTimer - deltaTime
		statusLabel.Text = "Prowling Pause: " .. string.format("%.1f", restTimer) .. "s"
		statusLabel.TextColor3 = Color3.fromRGB(240, 200, 80)
		if restTimer <= 0 then
			isResting = false
			targetPosition = calculateSmartLurkerPath()
		end
		pcall(function() rootPart.AssemblyLinearVelocity = Vector3.new() end)
		return
	end
	
	local flatChar = Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z)
	local flatTarget = Vector3.new(targetPosition.X, 0, targetPosition.Z)
	local distance = (flatChar - flatTarget).Magnitude
	
	if distance > 3.5 then
		moveDirection = (flatTarget - flatChar).Unit
		isCurrentlyMoving = true
		statusLabel.Text = "Sweeping Corridors..."
		statusLabel.TextColor3 = Color3.fromRGB(100, 200, 100)
	else
		isResting = true
		restTimer = math.random(10, 30) / 10
		return
	end
	
	if isCurrentlyMoving and moveDirection.Magnitude > 0 then
		local nextPosition = rootPart.Position + moveDirection * (currentSpeed * deltaTime)
		currentVisualHeading = currentVisualHeading:Lerp(moveDirection, 14 * deltaTime).Unit
		rootPart.CFrame = CFrame.lookAt(nextPosition, rootPart.Position + currentVisualHeading)
		
		pcall(function() 
			rootPart.AssemblyLinearVelocity = moveDirection * currentSpeed 
			if humanoid:GetState() ~= Enum.HumanoidStateType.Running then
				humanoid:ChangeState(Enum.HumanoidStateType.Running)
			end
		end)
		
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
				if track.Name == "WalkAnim" or track.Name == "RunAnim" or string.find(string.lower(track.Name), "walk") or string.find(string.lower(track.Name), "run") then
					track:AdjustSpeed(getgenv().GilbertFootSpeed)
				end
			end
		end
	end
end)

humanoid.Died:Connect(function() 
	if leftLaserPart then leftLaserPart:Destroy() end
	if rightLaserPart then rightLaserPart:Destroy() end
	screenGui:Destroy() 
end)
