--[[
    LURKER AUTOPILOT - VERSION 9 (SECTOR BOUNDS & ZERO-LAG SYSTEM)
--]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

-- Intentamos desactivar los scripts de control predeterminados de Roblox para eliminar el 100% de los tirones
local playerModule
local successControls, _ = pcall(function()
	playerModule = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
	if playerModule then
		playerModule:GetControls():Disable() -- Apaga tus teclas normales para que no peleen con el bot
	end
end)

print("[Lurker Exploit] Versión 9 Cargada: Control de sector libre de tirones.")

-- Configuraciones de IA de Examination
local maxVisionDistance = 110
local currentTarget = nil
local spawnPoint = rootPart.Position -- Registra el centro del Sector actual
local patrolRadius = 75 -- Límite de patrulla dentro del Sector
local currentDirection = rootPart.CFrame.LookVector

-- Parámetros de Raycast
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- 1. NAVEGACIÓN DE SECTOR AVANZADA (Busca espacios libres y evita quedarse atrapado)
local function calculateNextStep()
	rayParams.FilterDescendantsInstances = {character}
	
	local origin = rootPart.Position + Vector3.new(0, -0.5, 0) -- Escaneo a nivel del suelo/obstáculos
	local forward = currentDirection.Unit
	local right = Vector3.new(-forward.Z, 0, forward.X)
	
	-- Sensor de largo alcance para esquinas y paredes lejanas
	local frontRay = Workspace:Raycast(origin, forward * 11, rayParams)
	local leftRay = Workspace:Raycast(origin, (forward - right * 0.5).Unit * 9, rayParams)
	local rightRay = Workspace:Raycast(origin, (forward + right * 0.5).Unit * 9, rayParams)
	
	-- Si el camino está bloqueado por estructuras de la planta nuclear
	if frontRay or leftRay or rightRay then
		-- Salto reactivo si hay un objeto muy pegado a las piernas
		local closestObstacle = frontRay or leftRay or rightRay
		if (closestObstacle.Position - rootPart.Position).Magnitude < 4.5 then
			humanoid.Jump = true
		end
		
		-- Escaneo de 360 grados sutil para buscar el "pasillo libre" más cercano
		local bestAngle = nil
		local maxFreeDistance = 0
		
		for i = 1, 8 do -- Evalúa 8 direcciones a la redonda
			local angle = math.rad(i * 45)
			local testDir = Vector3.new(math.cos(angle), 0, math.sin(angle)).Unit
			local testRay = Workspace:Raycast(origin, testDir * 16, rayParams)
			
			local freeDistance = testRay and (testRay.Position - rootPart.Position).Magnitude or 16
			if freeDistance > maxFreeDistance then
				maxFreeDistance = freeDistance
				bestAngle = testDir
			end
		end
		
		if bestAngle then
			currentDirection = bestAngle
		end
	else
		-- MECÁNICA DE SECTOR: Si deambulando se aleja demasiado de su zona original, lo forzamos a girar de vuelta
		local distanceFromZone = (rootPart.Position - spawnPoint).Magnitude
		if distanceFromZone > patrolRadius and math.random(1, 100) <= 8 then
			local vectorToCenter = (spawnPoint - rootPart.Position).Unit
			currentDirection = (currentDirection + vectorToCenter * 0.6).Unit
		end
		
		-- Pequeñas variaciones aleatorias para simular una caminata orgánica de búsqueda
		if math.random(1, 100) <= 3 then
			local driftAngle = math.rad(math.random(-35, 35))
			local driftDir = Vector3.new(math.cos(driftAngle), 0, math.sin(driftAngle))
			currentDirection = (currentDirection + driftDir * 0.3).Unit
		end
	end
end

-- 2. FILTRO DE LÍNEA DE VISIÓN PARA RECONOCER ENTIDADES
local function hasLineOfSight(enemyRoot)
	rayParams.FilterDescendantsInstances = {character}
	
	local toEnemy = (enemyRoot.Position - rootPart.Position).Unit
	local dotProduct = rootPart.CFrame.LookVector:Dot(toEnemy)
	
	if dotProduct < 0.65 then return false end -- Cono de visión de 90 grados frontal
	
	local origin = rootPart.Position + Vector3.new(0, 2, 0)
	local direction = (enemyRoot.Position - origin)
	local rayResult = Workspace:Raycast(origin, direction, rayParams)
	
	if rayResult and rayResult.Instance:IsDescendantOf(enemyRoot.Parent) then
		return true
	end
	return false
end

-- 3. ESCÁNER DE ENTIDADES (Excluye jugadores reales)
local function getVisibleEntity()
	local target = nil
	local closestDistance = maxVisionDistance
	
	for _, obj in ipairs(Workspace:GetDescendants()) do
		if obj:IsA("Humanoid") and obj.Health > 0 then
			local enemyCharacter = obj.Parent
			if enemyCharacter and enemyCharacter:IsA("Model") and enemyCharacter ~= character then
				if not Players:GetPlayerFromCharacter(enemyCharacter) then
					local enemyRoot = enemyCharacter:FindFirstChild("HumanoidRootPart")
					if enemyRoot and hasLineOfSight(enemyRoot) then
						local distance = (rootPart.Position - enemyRoot.Position).Magnitude
						if distance < closestDistance then
							closestDistance = distance
							target = enemyRoot
						end
					end
				end
			end
		end
	end
	return target
end

-- 4. BUCLE DE CONTROL INTEGRADO EN EL RENDER (Elimina la fricción de controles)
local finalMoveVector = Vector3.new()

RunService.RenderStepped:Connect(function()
	if not humanoid or humanoid.Health <= 0 then return end
	
	-- Inyección directa al motor de caminata nativo libre de tirones
	humanoid:Move(finalMoveVector, false)
end)

-- Bucle de comportamiento lógico de la IA
task.spawn(function()
	while task.wait(0.05) do
		if not humanoid or humanoid.Health <= 0 then break end
		
		local visibleEntity = getVisibleEntity()
		if visibleEntity then currentTarget = visibleEntity end
		
		-- COMPORTAMIENTO 1: CAZA AGRESIVA (Ignora los límites del Sector si ve una entidad)
		if currentTarget and currentTarget.Parent and currentTarget.Parent:FindFirstChild("Humanoid") and currentTarget.Parent.Humanoid.Health > 0 then
			local distance = (rootPart.Position - currentTarget.Position).Magnitude
			
			if distance > 140 then
				currentTarget = nil
				finalMoveVector = Vector3.new()
			elseif distance <= 6.5 then
				finalMoveVector = Vector3.new()
				local tool = character:FindFirstChildOfClass("Tool")
				if tool then tool:Activate() end
			else
				-- El bot corre a máxima velocidad persiguiendo el objetivo a donde sea que vaya
				humanoid.WalkSpeed = 24
				local targetDir = (currentTarget.Position - rootPart.Position).Unit
				rootPart.CFrame = CFrame.new(rootPart.Position, Vector3.new(currentTarget.Position.X, rootPart.Position.Y, currentTarget.Position.Z))
				
				-- Si persiguiéndolo se topa con un muro, calcula un leve desvío lateral
				finalMoveVector = targetDir
			end
			
		-- COMPORTAMIENTO 2: PATRULLA DE SECTOR (Deambular solo en zonas habilitadas)
		else
			currentTarget = nil
			humanoid.WalkSpeed = 15
			
			-- Ejecuta el cálculo de sensores para buscar pasillos abiertos y respetar el sector
			calculateNextStep()
			
			-- Alínea el cuerpo hacia donde va a caminar para un look 100% natural de IA
			if currentDirection.Magnitude > 0 then
				local targetLook = rootPart.Position + currentDirection
				rootPart.CFrame = CFrame.new(rootPart.Position, Vector3.new(targetLook.X, rootPart.Position.Y, targetLook.Z))
			end
			
			finalMoveVector = currentDirection
		end
	end
end)

-- Función de seguridad por si te matan o desactivas el script: restablece tus controles normales
humanoid.Died:Connect(function()
	if playerModule then
		playerModule:GetControls():Enable()
	end
end)
