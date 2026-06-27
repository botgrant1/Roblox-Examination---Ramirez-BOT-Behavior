--[[
    LURKER AUTOPILOT - VERSION 4 (REALISTIC VISION & OPTIMIZED)
--]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local PathfindingService = game:GetService("PathfindingService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

print("[Lurker Exploit] Versión 4 Cargada: Campo de visión realista sin Wallhack.")

-- Configuración del Pathfinding
local path = PathfindingService:CreatePath({
	AgentRadius = 3,
	AgentHeight = 6,
	AgentCanJump = true,
})

-- Configuración de los parámetros de Raycast para la visión
local visionParams = RaycastParams.new()
visionParams.FilterType = Enum.RaycastFilterType.Exclude

-- Función matemática para verificar la línea de visión real
local function hasLineOfSight(enemyRoot)
	-- Actualizamos el filtro para ignorar a tu propio personaje al mirar
	visionParams.FilterDescendantsInstances = {character}
	
	-- 1. COMPROBACIÓN DE ÁNGULO (Field of View)
	local toEnemy = (enemyRoot.Position - rootPart.Position).Unit
	local lookDirection = rootPart.CFrame.LookVector
	local dotProduct = lookDirection:Dot(toEnemy)
	
	-- 0.7 significa aproximadamente un cono de visión de 90 grados al frente.
	-- Si el enemigo está detrás o muy a los lados, no lo ve.
	if dotProduct < 0.7 then 
		return false 
	end
	
	-- 2. COMPROBACIÓN DE OBSTÁCULOS (Raycast)
	local origin = rootPart.Position + Vector3.new(0, 2, 0) -- Mirar desde la altura de los ojos
	local direction = (enemyRoot.Position - origin)
	
	local rayResult = Workspace:Raycast(origin, direction, visionParams)
	
	-- Si el rayo choca con algo, verificamos si es el enemigo o una pared
	if rayResult then
		if rayResult.Instance:IsDescendantOf(enemyRoot.Parent) then
			return true -- El rayo llegó limpio al enemigo
		end
	end
	
	return false -- Había una pared, puerta u objeto en medio
end

-- Buscador de enemigos realista
local function getVisibleEnemy()
	local target = nil
	local maxDistance = 120 -- Rango máximo de la vista del jugador
	
	for _, obj in ipairs(Workspace:GetDescendants()) do
		if obj:IsA("Humanoid") and obj.Health > 0 then
			local enemyCharacter = obj.Parent
			if enemyCharacter and enemyCharacter:IsA("Model") and enemyCharacter ~= character then
				local enemyRoot = enemyCharacter:FindFirstChild("HumanoidRootPart")
				if enemyRoot then
					local distance = (rootPart.Position - enemyRoot.Position).Magnitude
					if distance < maxDistance then
						-- Aquí aplicamos el filtro de visión realista
						if hasLineOfSight(enemyRoot) then
							maxDistance = distance
							target = enemyRoot
						end
					end
				end
			end
		end
	end
	return target
end

-- Bucle principal (Consumo de FPS controlado)
local currentTarget = nil

task.spawn(function()
	while task.wait(0.2) do
		if not humanoid or humanoid.Health <= 0 then break end
		
		-- Buscamos si hay un enemigo visible en nuestro campo de visión
		local visibleEnemy = getVisibleEnemy()
		
		-- Si ya estábamos persiguiendo a alguien y lo perdimos de vista detrás de un muro,
		-- le damos 1.5 segundos de "memoria" antes de rendirnos, como una IA real.
		if visibleEnemy then
			currentTarget = visibleEnemy
		end
		
		if currentTarget and currentTarget.Parent and currentTarget.Parent:FindFirstChild("Humanoid") and currentTarget.Parent.Humanoid.Health > 0 then
			local distanceToEnemy = (rootPart.Position - currentTarget.Position).Magnitude
			
			-- Si se alejó demasiado o se escondió por completo, olvidamos el objetivo
			if distanceToEnemy > 150 then
				currentTarget = nil
			else
				if distanceToEnemy <= 7 then
					-- Rango de ataque
					local tool = character:FindFirstChildOfClass("Tool")
					if tool then
						tool:Activate()
					end
				else
					-- Movimiento inteligente esquivando paredes hacia el último punto visto
					humanoid.WalkSpeed = 24
					
					local success, _ = pcall(function()
						path:ComputeAsync(rootPart.Position, currentTarget.Position)
					end)
					
					if success and path.Status == Enum.PathStatus.Success then
						local waypoints = path:GetWaypoints()
						if waypoints and #waypoints > 1 then
							local nextPoint = waypoints[2]
							humanoid:MoveTo(nextPoint.Position)
							if nextPoint.Action == Enum.PathWaypointAction.Jump then
								humanoid.Jump = true
							end
						end
					else
						humanoid:MoveTo(currentTarget.Position)
					end
				end
			end
		else
			-- Si no ve a nadie, camina normal en velocidad de patrulla o espera
			currentTarget = nil
			humanoid.WalkSpeed = 16
		end
	end
end)
