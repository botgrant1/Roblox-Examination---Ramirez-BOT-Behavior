--[[
    PARTE 2: RADAR DE ESCAPE, ESCANER SECTOR-1 Y FISICAS DEL MOTOR
--]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

local targetPosition = rootPart.Position
local isResting = false
local restTimer = 0
local currentVisualHeading = rootPart.CFrame.LookVector
local lastVisitedPosition = rootPart.Position

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- 1. DETECTOR DE ENTIDADES HOSTILES (Radar de Escape)
local function getNearbyDangerousEntity()
	local dangerTarget = nil
	local closestDistance = 85
	
	for _, obj in ipairs(Workspace:GetDescendants()) do
		if obj:IsA("Humanoid") and obj.Health > 0 then
			local enemyCharacter = obj.Parent
			if enemyCharacter and enemyCharacter:IsA("Model") and enemyCharacter ~= character then
				if not Players:GetPlayerFromCharacter(enemyCharacter) then
					local enemyRoot = enemyCharacter:FindFirstChild("HumanoidRootPart")
					if enemyRoot then
						local distance = (rootPart.Position - enemyRoot.Position).Magnitude
						if distance < closestDistance then
							closestDistance = distance
							dangerTarget = enemyRoot
						end
					end
				end
			end
		end
	end
	return dangerTarget
end

-- 2. ESCÁNER INTELIGENTE DE PASILLOS (Sector-1)
local function calculateSmartLurkerPath()
	rayParams.FilterDescendantsInstances = {character}
	local origin = rootPart.Position + Vector3.new(0, 0.5, 0)
	local validOptions = {}
	local backupOptions = {}
	
	for i = 1, 12 do
		local angle = math.rad(i * (360 / 12))
		local distance = math.random(45, 80)
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle)).Unit
		
		local rayLow = Workspace:Raycast(origin - Vector3.new(0,0.6,0), direction * distance, rayParams)
		local rayHigh = Workspace:Raycast(origin + Vector3.new(0,0.5,0), direction * distance, rayParams)
		local effectiveDistance = math.min(rayLow and (rayLow.Position - rootPart.Position).Magnitude or distance, rayHigh and (rayHigh.Position - rootPart.Position).Magnitude or distance)
		
		if effectiveDistance < 4.5 then humanoid.Jump = true end
		if effectiveDistance > 15 then
			local potentialPoint = rootPart.Position + direction * (effectiveDistance - 5)
			if (potentialPoint - lastVisitedPosition).Magnitude < 25 then
				table.insert(backupOptions, potentialPoint)
			else
				table.insert(validOptions, potentialPoint)
			end
		end
	end
	
	local selectedPoint = validOptions[math.random(1, #validOptions)] or backupOptions[math.random(1, #backupOptions)]
	if not selectedPoint then
		selectedPoint = rootPart.Position + Vector3.new(math.random(-20,20), 0, math.random(-20,20))
	end
	lastVisitedPosition = rootPart.Position
	return selectedPoint
end

-- 3. INTERPOLADOR DE DESPLAZAMIENTO FLUIDO (Heartbeat)
RunService.Heartbeat:Connect(function(deltaTime)
	if not getgenv().LurkerAI_Enabled or not humanoid or humanoid.Health <= 0 then return end
	
	local currentSpeed = 7.2
	local moveDirection = Vector3.new()
	local destinationPos = nil
	local activeDanger = getNearbyDangerousEntity()
	
	-- COMPORTAMIENTO A: HUIR DE LA ENTIDAD (Pánico)
	if activeDanger then
		getgenv().LeaderCharacter = nil
		isResting = false
		currentSpeed = 23 -- Carrera
		local escapeDirection = (Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z) - Vector3.new(activeDanger.Position.X, 0, activeDanger.Position.Z)).Unit
		moveDirection = escapeDirection
		targetPosition = rootPart.Position + escapeDirection * 30
		destinationPos = targetPosition
		
	-- COMPORTAMIENTO B: SEGUIR JUGADOR ("FOLLOW ME")
	elseif getgenv().LeaderCharacter and getgenv().LeaderCharacter:FindFirstChild("HumanoidRootPart") and getgenv().LeaderCharacter.Humanoid.Health > 0 then
		local leaderRoot = getgenv().LeaderCharacter.HumanoidRootPart
		local distanceToLeader = (rootPart.Position - leaderRoot.Position).Magnitude
		
		if (leaderRoot.Position - getgenv().LeaderLastPos).Magnitude > 1.5 then
			getgenv().LeaderLastPos = leaderRoot.Position
			getgenv().LastLeaderMoveTime = os.clock()
		end
		if (os.clock() - getgenv().LastLeaderMoveTime) > 15 then
			getgenv().LeaderCharacter = nil
			targetPosition = calculateSmartLurkerPath()
			return
		end
		
		if distanceToLeader > 25 then currentSpeed = 15 end
		if distanceToLeader > 6.5 then
			destinationPos = leaderRoot.Position
			moveDirection = (Vector3.new(leaderRoot.Position.X,0,leaderRoot.Position.Z) - Vector3.new(rootPart.Position.X,0,rootPart.Position.Z)).Unit
		else
			pcall(function() humanoid.RootPart.AssemblyLinearVelocity = Vector3.new() end)
			rootPart.CFrame = rootPart.CFrame:Lerp(CFrame.lookAt(rootPart.Position, Vector3.new(leaderRoot.Position.X, rootPart.Position.Y, leaderRoot.Position.Z)), 10 * deltaTime)
			return
		end
		
	-- COMPORTAMIENTO C: PATRULLA ACECHANTE TRADICIONAL
	else
		if isResting then
			restTimer = restTimer - deltaTime
			if restTimer <= 0 then isResting = false targetPosition = calculateSmartLurkerPath() end
			return
		end
		local distance = (Vector3.new(rootPart.Position.X,0,rootPart.Position.Z) - Vector3.new(targetPosition.X,0,targetPosition.Z)).Magnitude
		if distance > 3.5 then
			destinationPos = targetPosition
			moveDirection = (Vector3.new(targetPosition.X,0,targetPosition.Z) - Vector3.new(rootPart.Position.X,0,rootPart.Position.Z)).Unit
		else
			isResting = true
			restTimer = math.random(3, 6) / 10
			pcall(function() humanoid.RootPart.AssemblyLinearVelocity = Vector3.new() end)
			return
		end
	end
	
	-- Aplicar físicas de traslación
	if destinationPos and moveDirection.Magnitude > 0 then
		local nextPosition = rootPart.Position + moveDirection * (currentSpeed * deltaTime)
		currentVisualHeading = currentVisualHeading:Lerp(moveDirection, 14 * deltaTime).Unit
		rootPart.CFrame = CFrame.lookAt(nextPosition, rootPart.Position + currentVisualHeading)
		pcall(function() humanoid.RootPart.AssemblyLinearVelocity = moveDirection * currentSpeed end)
		local obs = Workspace:Raycast(rootPart.Position, moveDirection * 3.5, rayParams)
		if obs then humanoid.Jump = true end
	end
end)
