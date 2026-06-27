--[[
    LURKER AUTOPILOT - VERSION 8 (NATIVE CONTROL & MULTI-RAY DETECTION)
--]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

print("[Lurker Exploit] Versión 8 Cargada: Movimiento nativo fluido a 60 FPS.")

-- Configuraciones de IA y rangos
local maxVisionDistance = 110
local currentTarget = nil
local patrolAngle = math.random(0, 360)

-- Parámetros de Raycast
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- 1. ESCÁNER DE OBSTÁCULOS MEJORADO (Evita choques con paredes y objetos)
local function getAvoidanceDirection(baseDirection)
	rayParams.FilterDescendantsInstances = {character}
	
	local origin = rootPart.Position + Vector3.new(0, -1, 0) -- Escaneo a la altura de las piernas/obstáculos bajos
	local forwardVector = baseDirection.Unit
	local rightVector = Vector3.new(-forwardVector.Z, 0, forwardVector.X) -- Vector derecho ortogonal
	
	-- Matriz de 3 rayos frontales (Centro, Izquierda, Derecha) para detección precisa
	local rayCenter = Workspace:Raycast(origin, forwardVector * 9, rayParams)
	local rayLeft = Workspace:Raycast(origin, (forwardVector - rightVector * 0.4).Unit * 8, rayParams)
	local rayRight = Workspace:Raycast(origin, (forwardVector + rightVector * 0.4).Unit * 8, rayParams)
	
	-- Si detecta algo al frente, desvía la trayectoria suavemente
	if rayCenter or rayLeft or rayRight then
		-- Salto automático si nos trabamos muy cerca de un objeto bajo (ej: barandas)
		local obstacle = rayCenter or rayLeft or rayRight
		if (obstacle.Position - rootPart.Position).Magnitude < 4.5 then
			humanoid.Jump = true
		end
		
		-- Analizar cuál lado está más libre para girar de forma limpia
		local checkLeft = Workspace:Raycast(origin, -rightVector * 12, rayParams)
		local checkRight = Workspace:Raycast(origin, rightVector * 12, rayParams)
		
		if not checkLeft then
			return (-rightVector + forwardVector * 0.3).Unit -- Desvío fluido a la izquierda
		elseif not checkRight then
			return (rightVector + forwardVector * 0.3).Unit -- Desvío fluido a la derecha
		else
			return -forwardVector -- Dar la vuelta si es un callejón sin salida
		end
	end
	
	return baseDirection -- Mantener rumbo si el camino está limpio
end

-- 2. FILTRO DE LÍNEA DE VISIÓN REALISTA
local function hasLineOfSight(enemyRoot)
	rayParams.FilterDescendantsInstances = {character}
	
	local toEnemy = (enemyRoot.Position - rootPart.Position).Unit
	local dotProduct = rootPart.CFrame.LookVector:Dot(toEnemy)
	
	if dotProduct < 0.65 then return false end -- Cono de visión de 90 grados frontal
	
	local origin = rootPart.Position + Vector3.new(0, 2, 0) -- Altura de los ojos
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

-- 4. BUCLE DE CONTROL INTEGRADO (Sincronizado a los FPS del juego para eliminar tirones)
local inputDirection = Vector3.new()

RunService.RenderStepped:Connect(function()
	if not humanoid or humanoid.Health <= 0 then return end
	
	-- Inyectamos de forma nativa nuestra dirección de caminata en el script de control predeterminado de Roblox
	humanoid:Move(inputDirection, false)
end)

-- Bucle de decisiones de IA (Cada 0.05 segundos para estabilidad total)
task.spawn(function()
	while task.wait(0.05) do
		if not humanoid or humanoid.Health <= 0 then break end
		
		local visibleEntity = getVisibleEntity()
		if visibleEntity then currentTarget = visibleEntity end
		
		-- COMPORTAMIENTO 1: CAZAR ENTIDAD DETECTADA
		if currentTarget and currentTarget.Parent and currentTarget.Parent:FindFirstChild("Humanoid") and currentTarget.Parent.Humanoid.Health > 0 then
			local distance = (rootPart.Position - currentTarget.Position).Magnitude
			
			if distance > 130 then
				currentTarget = nil
				inputDirection = Vector3.new()
			elseif distance <= 6.5 then
				-- Rango letal: Frenar y activar el arma automáticamente
				inputDirection = Vector3.new()
				local tool = character:FindFirstChildOfClass("Tool")
				if tool then tool:Activate() end
			else
				-- Avanzar de forma fluida hacia el objetivo alineando el torso hacia él
				humanoid.WalkSpeed = 23
				local targetDir = (currentTarget.Position - rootPart.Position).Unit
				rootPart.CFrame = CFrame.new(rootPart.Position, Vector3.new(currentTarget.Position.X, rootPart.Position.Y, currentTarget.Position.Z))
				
				-- Aplicar desvío si hay una pared en medio del trayecto
				inputDirection = getAvoidanceDirection(targetDir)
			end
			
		-- COMPORTAMIENTO 2: DEAMBULAR INTELIGENTE (Patrulla aleatoria por pasillos)
		else
			currentTarget = nil
			humanoid.WalkSpeed = 15
			
			-- Cambia el ángulo de patrulla sutilmente con el tiempo o si se topa con un muro
			if math.random(1, 100) <= 4 then
				patrolAngle = patrolAngle + math.random(-45, 45)
			end
			
			local rad = math.rad(patrolAngle)
			local desiredDirection = Vector3.new(math.cos(rad), 0, math.sin(rad)).Unit
			
			-- Analizar entorno con los rayos invisibles y corregir el rumbo antes de chocar
			local finalDirection = getAvoidanceDirection(desiredDirection)
			
			-- Si los rayos forzaron un desvío, actualizamos nuestro ángulo interno de patrulla
			if finalDirection ~= desiredDirection then
				patrolAngle = math.atan2(finalDirection.Z, finalDirection.X) * (180 / math.pi)
			end
			
			inputDirection = finalDirection
		end
	end
end)
