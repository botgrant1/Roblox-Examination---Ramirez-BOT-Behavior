--[[
    LURKER AUTOPILOT - VERSION ESTABLE (PATRULLA SECTOR-1 REPARADA)
--]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

getgenv().LurkerAI_Enabled = false

-- =========================================================================
-- INTERFAZ GRÁFICA (MENÚ DE CONTROL)
-- =========================================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LurkerControlGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 220, 0, 130)
mainFrame.Position = UDim2.new(0.05, 0, 0.4, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Parent = screenGui

local uiCorner = Instance.new("UICorner")
uiCorner.CornerRadius = UDim.new(0, 8)
uiCorner.Parent = mainFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, 0, 0, 35)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "LURKER AUTOPILOT"
titleLabel.TextColor3 = Color3.fromRGB(200, 50, 50)
titleLabel.TextSize = 14
titleLabel.Font = Enum.Font.SourceSansBold
titleLabel.Parent = mainFrame

local toggleButton = Instance.new("TextButton")
toggleButton.Size = UDim2.new(0, 180, 0, 45)
toggleButton.Position = UDim2.new(0, 20, 0, 55)
toggleButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
toggleButton.Text = "ESTADO: DESACTIVADO"
toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleButton.TextSize = 14
toggleButton.Font = Enum.Font.SourceSans
toggleButton.Parent = mainFrame

local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, 6)
buttonCorner.Parent = toggleButton

-- Variables de control de la IA y Seguimiento
local targetPosition = rootPart.Position
local isResting = false
local restTimer = 0
local currentVisualHeading = rootPart.CFrame.LookVector

-- Variables del sistema de comandos de voz Z
local leaderCharacter = nil      
local lastLeaderMoveTime = 0     
local leaderLastPos = Vector3.new()
local voiceCommandRange = 45     

-- Sistema de memoria a corto plazo optimizado
local lastVisitedPosition = rootPart.Position

toggleButton.MouseButton1Click:Connect(function()
	getgenv().LurkerAI_Enabled = not getgenv().LurkerAI_Enabled
	
	if getgenv().LurkerAI_Enabled then
		toggleButton.Text = "ESTADO: ACTIVO"
		toggleButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
		targetPosition = rootPart.Position
		currentVisualHeading = rootPart.CFrame.LookVector
		isResting = false
		leaderCharacter = nil
		lastVisitedPosition = rootPart.Position
		print("[AI] Regresando a versión estable de patrulla infinita.")
	else
		toggleButton.Text = "ESTADO: DESACTIVADO"
		toggleButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
		leaderCharacter = nil
	end
end)

-- =========================================================================
-- OYENTE TÁCTICO DE VOICELINES Z
-- =========================================================================
local function setupVoiceCommandListener(otherPlayer)
	otherPlayer.Chatted:Connect(function(message)
		if not getgenv().LurkerAI_Enabled then return end
		if otherPlayer == player then return end 
		
		local otherChar = otherPlayer.Character
		if not otherChar or not otherChar:FindFirstChild("HumanoidRootPart") then return end
		
		local distanceToSpeaker = (rootPart.Position - otherChar.HumanoidRootPart.Position).Magnitude
		
		if distanceToSpeaker <= voiceCommandRange then
			if message == "Follow Me!" or message == "Follow me!" or message == "Sígueme!" or message == "Sigueme!" then
				leaderCharacter = otherChar
				leaderLastPos = otherChar.HumanoidRootPart.Position
				lastLeaderMoveTime = os.clock()
				isResting = false
				print("[Voiceline Z] Siguiendo a: " .. otherPlayer.Name)
			end
		end
	end)
end

for _, p in ipairs(Players:GetPlayers()) do setupVoiceCommandListener(p) end
Players.PlayerAdded:Connect(setupVoiceCommandListener)

-- =========================================================================
-- ESCÁNER INTELIGENTE DE PASILLOS (SECTOR-1)
-- =========================================================================
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function calculateSmartLurkerPath()
	rayParams.FilterDescendantsInstances = {character}
	local origin = rootPart.Position + Vector3.new(0, 0.5, 0)
	
	local validOptions = {} 
	local backupOptions = {}
	
	for i = 1, 12 do
		local angle = math.rad(i * (360 / 12))
		local distance = math.random(45, 80) 
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle)).Unit
		
		local originLow = rootPart.Position + Vector3.new(0, -0.6, 0)
		local originHigh = rootPart.Position + Vector3.new(0, 1, 0)
		
		local rayLow = Workspace:Raycast(originLow, direction * distance, rayParams)
		local rayHigh = Workspace:Raycast(originHigh, direction * distance, rayParams)
		
		local distLow = rayLow and (rayLow.Position - rootPart.Position).Magnitude or distance
		local distHigh = rayHigh and (rayHigh.Position - rootPart.Position).Magnitude or distance
		local effectiveDistance = math.min(distLow, distHigh)
		
		if effectiveDistance < 4.5 then humanoid.Jump = true end
		
		if effectiveDistance > 15 then
			local potentialPoint = rootPart.Position + direction * (effectiveDistance - 5)
			local isReturnPath = (potentialPoint - lastVisitedPosition).Magnitude < 25
			
			if not isReturnPath then
				table.insert(validOptions, potentialPoint)
			else
				table.insert(backupOptions, potentialPoint)
			end
		end
	end
	
	local selectedPoint = nil
	if #validOptions > 0 then
		selectedPoint = validOptions[math.random(1, #validOptions)]
	elseif #backupOptions > 0 then
		selectedPoint = backupOptions[math.random(1, #backupOptions)]
	else
		local randomAngle = math.rad(math.random(0, 360))
		selectedPoint = rootPart.Position + Vector3.new(math.cos(randomAngle) * 20, 0, math.sin(randomAngle) * 20)
	end
	
	lastVisitedPosition = rootPart.Position
	return selectedPoint
end

-- =========================================================================
-- MOTOR DE MOVIMIENTO GENERAL (SOLO PATRULLA Y SEGUIMIENTO Z)
-- =========================================================================
RunService.Heartbeat:Connect(function(deltaTime)
	if not getgenv().LurkerAI_Enabled or not humanoid or humanoid.Health <= 0 then return end
	
	local currentSpeed = 7.2 
	local moveDirection = Vector3.new()
	local destinationPos = nil
	
	-- ESCORTANDO A JUGADOR (ORDEN "FOLLOW ME")
	if leaderCharacter and leaderCharacter:FindFirstChild("HumanoidRootPart") and leaderCharacter:FindFirstChild("Humanoid") and leaderCharacter.Humanoid.Health > 0 then
		local leaderRoot = leaderCharacter.HumanoidRootPart
		local distanceToLeader = (rootPart.Position - leaderRoot.Position).Magnitude
		
		if (leaderRoot.Position - leaderLastPos).Magnitude > 1.5 then
			leaderLastPos = leaderRoot.Position
			lastLeaderMoveTime = os.clock() 
		end
		
		if (os.clock() - lastLeaderMoveTime) > 15 then
			leaderCharacter = nil
			targetPosition = calculateSmartLurkerPath()
			return
		end
		
		if distanceToLeader > 25 then currentSpeed = 15 end
		
		if distanceToLeader > 6.5 then
			destinationPos = leaderRoot.Position
			local flatChar = Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z)
			local flatLeader = Vector3.new(leaderRoot.Position.X, 0, leaderRoot.Position.Z)
			moveDirection = (flatLeader - flatChar).Unit
		else
			pcall(function() humanoid.RootPart.AssemblyLinearVelocity = Vector3.new() end)
			local lookTarget = Vector3.new(leaderRoot.Position.X, rootPart.Position.Y, leaderRoot.Position.Z)
			rootPart.CFrame = rootPart.CFrame:Lerp(CFrame.lookAt(rootPart.Position, lookTarget), 10 * deltaTime)
			return
		end
		
	-- PATRULLA DE ACECHO ESTÁNDAR
	else
		if isResting then
			restTimer = restTimer - deltaTime
			if restTimer <= 0 then
				isResting = false
				targetPosition = calculateSmartLurkerPath() 
			end
			return
		end
		
		local flatCharacterPos = Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z)
		local flatTargetPos = Vector3.new(targetPosition.X, 0, targetPosition.Z)
		local distance = (flatCharacterPos - flatTargetPos).Magnitude
		
		if distance > 3.5 then
			destinationPos = targetPosition
			moveDirection = (flatTargetPos - flatCharacterPos).Unit
		else
			isResting = true
			restTimer = math.random(3, 6) / 10 
			pcall(function() humanoid.RootPart.AssemblyLinearVelocity = Vector3.new() end)
			return
		end
	end
	
	-- Ejecución de traslación común en el mapa
	if destinationPos and moveDirection.Magnitude > 0 then
		local nextPosition = rootPart.Position + moveDirection * (currentSpeed * deltaTime)
		currentVisualHeading = currentVisualHeading:Lerp(moveDirection, 14 * deltaTime).Unit
		rootPart.CFrame = CFrame.lookAt(nextPosition, rootPart.Position + currentVisualHeading)
		
		pcall(function()
			humanoid.RootPart.AssemblyLinearVelocity = moveDirection * currentSpeed
		end)
		
		local obstacleRay = Workspace:Raycast(rootPart.Position, moveDirection * 4, rayParams)
		if obstacleRay then humanoid.Jump = true end
	end
end)

humanoid.Died:Connect(function()
	screenGui:Destroy()
end)
