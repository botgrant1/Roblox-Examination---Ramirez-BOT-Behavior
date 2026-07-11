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

if player:WaitForChild("PlayerGui"):FindFirstChild("LurkerControlGui") then
	player.PlayerGui.LurkerControlGui:Destroy()
end

local targetPosition = rootPart.Position
local isResting = false
local restTimer = 0
local currentVisualHeading = rootPart.CFrame.LookVector
local dangerousZones = {} 

local currentEnemyTarget = nil
local combatScanRange = 30 
local attackTriggerRange = 9 
local lastMeleeStrikeTime = 0
local meleeCooldown = 2.4 
local internalManualHandover = false 

local function calculateSmartLurkerPath()
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {character}
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
			
			if isSafe then
				table.insert(validOptions, potentialPoint)
			end
		end
	end
	
	return #validOptions > 0 and validOptions[math.random(1, #validOptions)] or rootPart.Position
end

-- INTERFAZ GRÁFICA AMPLIADA (V5.0 con sección de actualizaciones)
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LurkerControlGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 240, 0, 360) -- Altura extendida para acomodar los parches
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
titleLabel.Text = "REACTIVE INTEGRATION V5.0"
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

local speedLabel = Instance.new("TextLabel")
speedLabel.Size = UDim2.new(1, 0, 0, 25)
speedLabel.Position = UDim2.new(0, 0, 0, 80)
speedLabel.BackgroundTransparency = 1
speedLabel.Text = "Footstep Frequency: " .. string.format("%.1f", getgenv().GilbertFootSpeed)
speedLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
speedLabel.TextSize = 13
speedLabel.Font = Enum.Font.SourceSans
speedLabel.Parent = contentFrame

local minusButton = Instance.new("TextButton")
minusButton.Size = UDim2.new(0, 45, 0, 30)
minusButton.Position = UDim2.new(0, 50, 0, 110)
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
plusButton.Position = UDim2.new(0, 145, 0, 110)
plusButton.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
plusButton.Text = "+"
plusButton.TextColor3 = Color3.fromRGB(200, 200, 200)
plusButton.TextSize = 18
plusButton.Font = Enum.Font.SourceSansBold
plusButton.Parent = contentFrame

local plusCorner = Instance.new("UICorner")
plusCorner.CornerRadius = UDim.new(0, 4)
plusCorner.Parent = plusButton

-- NUEVO APARTADO: UPDATES LOG (Historial de Cambios)
local updatesHeader = Instance.new("TextLabel")
updatesHeader.Size = UDim2.new(0, 200, 0, 20)
updatesHeader.Position = UDim2.new(0, 20, 0, 155)
updatesHeader.BackgroundTransparency = 1
updatesHeader.Text = "--- SYSTEM UPDATES ---"
updatesHeader.TextColor3 = Color3.fromRGB(140, 140, 140)
updatesHeader.TextSize = 11
updatesHeader.Font = Enum.Font.Code
updatesHeader.Parent = contentFrame

local updatesFrame = Instance.new("Frame")
updatesFrame.Size = UDim2.new(0, 200, 0, 135)
updatesFrame.Position = UDim2.new(0, 20, 0, 180)
updatesFrame.BackgroundColor3 = Color3.fromRGB(10, 8, 8)
updatesFrame.BorderSizePixel = 0
updatesFrame.Parent = contentFrame

local updatesCorner = Instance.new("UICorner")
updatesCorner.CornerRadius = UDim.new(0, 4)
updatesCorner.Parent = updatesFrame

local updatesStroke = Instance.new("UIStroke")
updatesStroke.Color = Color3.fromRGB(45, 25, 25)
updatesStroke.Thickness = 1
updatesStroke.Parent = updatesFrame

local logLabel = Instance.new("TextLabel")
logLabel.Size = UDim2.new(1, -12, 1, -10)
logLabel.Position = UDim2.new(0, 6, 0, 5)
logLabel.BackgroundTransparency = 1
logLabel.Text = "[+] CHANGELOG V5.0:\n• Handover: Auto-disables system on melee strike.\n• Pushback: Forced 0.22s micro-retreat after [G].\n• Physics: Removed buggy jump algorithms.\n• FPS: Cleaned loops to maximize game stability."
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
		mainFrame.Size = UDim2.new(0, 240, 0, 360)
		minimizeButton.Text = "-"
		contentFrame.Visible = true
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
	pcall(function() 
		humanoid.RootPart.AssemblyLinearVelocity = Vector3.new() 
	end)
end

task.spawn(function()
	while true do
		task.wait(1)
		local now = os.clock()
		for pos, timestamp in pairs(dangerousZones) do
			if now - timestamp > 8.0 then 
				dangerousZones[pos] = nil
			end
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(0.2)
		if getgenv().LurkerAI_Enabled and character and character:FindFirstChild("HumanoidRootPart") and not internalManualHandover then
			local closestEnemy = nil
			local shortestDistance = combatScanRange
			local originPoint = rootPart.Position + Vector3.new(0, 0.5, 0)
			
			local boxParams = OverlapParams.new()
			boxParams.FilterType = Enum.RaycastFilterType.Exclude
			boxParams.FilterDescendantsInstances = {character}
			
			local nearbyParts = Workspace:GetPartBoundsInBox(rootPart.CFrame, Vector3.new(combatScanRange, 12, combatScanRange), boxParams)
			local analyzedModels = {}
			
			local losParams = RaycastParams.new()
			losParams.FilterType = Enum.RaycastFilterType.Exclude
			local ignoreList = {character}
			for _, p in ipairs(Players:GetPlayers()) do
				if p.Character then table.insert(ignoreList, p.Character) end
			end
			losParams.FilterDescendantsInstances = ignoreList

			for _, part in ipairs(nearbyParts) do
				local model = part.Parent
				if model and model:IsA("Model") and not analyzedModels[model] and model ~= character then
					analyzedModels[model] = true
					
					local enemyHumanoid = model:FindFirstChildOfClass("Humanoid")
					local enemyRoot = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
					
					if enemyHumanoid and enemyRoot and enemyHumanoid.Health > 0 then
						local isAPlayer = Players:GetPlayerFromCharacter(model)
						if not isAPlayer then
							local targetPos = enemyRoot.Position
							local dist = (rootPart.Position - targetPos).Magnitude
							
							if dist < shortestDistance then
								local direction = (targetPos - originPoint)
								local losRay = Workspace:Raycast(originPoint, direction, losParams)
								
								if not losRay or losRay.Instance:IsDescendantOf(model) then
									shortestDistance = dist
									closestEnemy = enemyRoot
								end
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

toggleButton.MouseButton1Click:Connect(function()
	if getgenv().LurkerAI_Enabled then
		disableSystemFully()
		statusLabel.Text = "Status: Manual Control"
		statusLabel.TextColor3 = Color3.fromRGB(130, 130, 130)
	else
		getgenv().LurkerAI_Enabled = true
		internalManualHandover = false
		toggleButton.Text = "SYSTEM: ACTIVE"
		toggleButton.BackgroundColor3 = Color3.fromRGB(25, 40, 25)
		toggleButton.TextColor3 = Color3.fromRGB(100, 220, 100)
		buttonStroke.Color = Color3.fromRGB(40, 120, 40)
		statusLabel.Text = "Sweeping Corridors..."
		statusLabel.TextColor3 = Color3.fromRGB(100, 200, 100)
		
		pcall(function() humanoid.RootPart.AssemblyLinearVelocity = Vector3.new() end)
		targetPosition = rootPart.Position
		dangerousZones = {}
		isResting = false
		currentEnemyTarget = nil
		
		task.spawn(function()
			task.wait(0.1)
			if getgenv().LurkerAI_Enabled then targetPosition = calculateSmartLurkerPath() end
		end)
	end
end)

RunService.Heartbeat:Connect(function(deltaTime)
	if not getgenv().LurkerAI_Enabled or not humanoid or humanoid.Health <= 0 or internalManualHandover then return end
	
	-- PRIORIDAD 1: ATAQUE Y CESIÓN INMEDATA DEL CONTROL
	if currentEnemyTarget and currentEnemyTarget.Parent and currentEnemyTarget.Parent:FindFirstChildOfClass("Humanoid") and currentEnemyTarget.Parent:FindFirstChildOfClass("Humanoid").Health > 0 then
		local enemyPos = currentEnemyTarget.Position
		local distanceToEnemy = (rootPart.Position - enemyPos).Magnitude
		
		statusLabel.Text = "TARGET ACQUIRED!"
		statusLabel.TextColor3 = Color3.fromRGB(255, 100, 0)
		
		local lookTarget = Vector3.new(enemyPos.X, rootPart.Position.Y, enemyPos.Z)
		rootPart.CFrame = rootPart.CFrame:Lerp(CFrame.lookAt(rootPart.Position, lookTarget), 18 * deltaTime)
		
		if distanceToEnemy > (attackTriggerRange - 2) then
			local moveDir = (Vector3.new(enemyPos.X, 0, enemyPos.Z) - Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z)).Unit
			pcall(function() humanoid.RootPart.AssemblyLinearVelocity = moveDir * 9.8 end)
		else
			if os.clock() - lastMeleeStrikeTime >= meleeCooldown then
				lastMeleeStrikeTime = os.clock()
				internalManualHandover = true 
				
				statusLabel.Text = "STRIKING... [G]"
				statusLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
				pcall(function() humanoid.RootPart.AssemblyLinearVelocity = Vector3.new() end)
				
				VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.G, false, game)
				task.wait(0.04)
				VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.G, false, game)
				
				dangerousZones[enemyPos] = os.clock()
				
				statusLabel.Text = "HANDING OVER CONTROL!"
				statusLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
				
				local pushBackDirection = -(Vector3.new(enemyPos.X, 0, enemyPos.Z) - Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z)).Unit
				local backTime = 0.22 
				
				while backTime > 0 do
					backTime = backTime - task.wait()
					pcall(function() rootPart.AssemblyLinearVelocity = pushBackDirection * 15 end)
				end
				
				disableSystemFully()
				statusLabel.Text = "YOUR TURN! TAKE CONTROL"
				statusLabel.TextColor3 = Color3.fromRGB(50, 255, 50)
				internalManualHandover = false
			end
		end
		return
	end

	-- PRIORIDAD 2: PATRULLA ESTÁNDAR AUTOMÁTICA
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
		pcall(function() humanoid.RootPart.AssemblyLinearVelocity = Vector3.new() end)
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
		restTimer = math.random(15, 45) / 10
		return
	end
	
	if isCurrentlyMoving and moveDirection.Magnitude > 0 then
		local nextPosition = rootPart.Position + moveDirection * (currentSpeed * deltaTime)
		currentVisualHeading = currentVisualHeading:Lerp(moveDirection, 14 * deltaTime).Unit
		rootPart.CFrame = CFrame.lookAt(nextPosition, rootPart.Position + currentVisualHeading)
		
		pcall(function() humanoid.RootPart.AssemblyLinearVelocity = moveDirection * currentSpeed end)
		
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

humanoid.Died:Connect(function() screenGui:Destroy() end)
