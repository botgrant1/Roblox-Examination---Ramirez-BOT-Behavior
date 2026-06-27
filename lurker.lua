--[[
    LURKER AUTOPILOT - VERSION 5 (STABLE PATHFINDING, RANDOM PATROL & ENTITY FILTER)
--]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local PathfindingService = game:GetService("PathfindingService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

print("[Lurker Exploit] Versión 5 Cargada: Patrulla aleatoria fluida y filtro estricto de Entidades.")

-- Configuración del Pathfinding
local path = PathfindingService:CreatePath({
	AgentRadius = 3,
	AgentHeight = 6,
	AgentCanJump = true,
})

local visionParams = RaycastParams.new()
visionParams.FilterType = Enum.RaycastFilterType.Exclude

-- Función para verificar línea de visión real
local function hasLineOfSight(enemyRoot)
	visionParams.FilterDescendantsInstances = {character}
	
	local toEnemy = (enemyRoot.Position - rootPart.Position).Unit
	local lookDirection = rootPart.CFrame.LookVector
	local dotProduct = lookDirection:Dot(toEnemy)
	
	if dotProduct < 0.65 then return false end -- Cono de visión amplio al frente
	
	local origin = rootPart.Position + Vector3.new(0, 2, 0)
	local direction = (enemyRoot.Position - origin)
	local rayResult = Workspace:Raycast(origin, direction, visionParams)
	
	if rayResult and rayResult.Instance:IsDescendantOf(enemyRoot.Parent) then
		return true
	end
	return false
end

-- Buscador de ENTIDADES reales (Ignora jugadores)
local function getVisibleEntity()
	local target = nil
	local maxDistance = 120
	
	for _, obj in ipairs(Workspace:GetDescendants()) do
		if obj:IsA("Humanoid") and obj.Health > 0 then
			local enemyCharacter = obj.Parent
			
			-- FILTRO ESTRICTO: Debe ser un modelo vivo, que NO seas tú y NO debe ser un jugador real
			if enemyCharacter and enemyCharacter:IsA("Model") and enemyCharacter ~= character then
				local isRealPlayer = Players:GetPlayerFromCharacter(enemyCharacter)
				
				if not isRealPlayer then -- Si no es un jugador, es una entidad/NPC del mapa
					local enemyRoot = enemyCharacter:FindFirstChild("HumanoidRootPart")
					if enemyRoot and hasLineOfSight(enemyRoot) then
						local distance = (rootPart.Position - enemyRoot.Position).Magnitude
						if distance < maxDistance then
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

-- Variables de control de movimiento fluido
local currentTarget = nil
local lastTargetPos = Vector3.new()
local patrolPoint = nil
local currentWaypointIndex = 1
local waypoints = {}

-- Función auxiliar para seguir rutas de forma fluida y sin tirones
local function followPath(destination, speed)
	humanoid.WalkSpeed = speed
	
	-- Solo calculamos una ruta nueva si el destino cambió considerablemente (Evita tirones)
	if (destination - lastTargetPos).Magnitude > 5 or #waypoints == 0 then
		lastTargetPos = destination
		local success, _ = pcall(function()
			path:ComputeAsync(rootPart.Position, destination)
		end)
		
		if success and path.Status == Enum.PathStatus.Success then
			waypoints = path:GetWaypoints()
			currentWaypointIndex = 2 -- Empezamos en el segundo punto para evitar micro-pausas
		else
			humanoid:MoveTo(destination) -- Respaldo directo en caso de fallo
			return
		end
	end
	
	-- Navegación fluida punto por punto de la ruta actual
	if waypoints and currentWaypointIndex <= #waypoints then
		local currentWaypoint = waypoints[currentWaypointIndex]
		humanoid:MoveTo(currentWaypoint.Position)
		
		if currentWaypoint.Action == Enum.PathWaypointAction.Jump then
			humanoid.Jump = true
		end
		
		-- Si estamos lo suficientemente cerca del punto de control actual, avanzamos al siguiente
		if (rootPart.Position - currentWaypoint.Position).Magnitude < 4 then
			currentWaypointIndex = currentWaypointIndex + 1
		end
	else
		humanoid:MoveTo(destination)
	end
end

-- Bucle principal optimizado
task.spawn(function()
	while task.wait(0.1) do
		if not humanoid or humanoid.Health <= 0 then break end
		
		local visibleEntity = getVisibleEntity()
		if visibleEntity then
			currentTarget = visibleEntity
			patrolPoint = nil -- Cancelamos patrulla si hay acción
		end
		
		-- ESTADO 1: PERSEGUIR ENTIDAD DETECTADA
		if currentTarget and currentTarget.Parent and currentTarget.Parent:FindFirstChild("Humanoid") and currentTarget.Parent.Humanoid.Health > 0 then
			local distanceToEnemy = (rootPart.Position - currentTarget.Position).Magnitude
			
			if distanceToEnemy > 140 then -- Si se escapó muy lejos, lo pierde de vista
				currentTarget = nil
			elseif distanceToEnemy <= 7 then
				-- Rango de ataque automático
				local tool = character:FindFirstChildOfClass("Tool")
				if tool then tool:Activate() end
				humanoid:MoveTo(currentTarget.Position)
			else
				-- Persecución fluida a velocidad de Lurker (24)
				followPath(currentTarget.Position, 24)
			end
			
		-- ESTADO 2: DEAMBULAR RANDOM (PATRULLA PASIVA)
		else
			currentTarget = nil
			
			-- Si no tenemos un punto de patrulla asignado o ya casi llegamos al actual, elegimos uno nuevo
			if not patrolPoint or (rootPart.Position - patrolPoint).Magnitude < 5 then
				waypoints = {} -- Reseteamos ruta anterior
				-- Elige una dirección aleatoria en un radio de 40 a 60 unidades a la redonda
				local randomAngle = math.rad(math.random(0, 360))
				local randomDistance = math.random(40, 60)
				local offset = Vector3.new(math.cos(randomAngle) * randomDistance, 0, math.sin(randomAngle) * randomDistance)
				patrolPoint = rootPart.Position + offset
			end
			
			-- Camina de forma realista hacia el punto aleatorio respetando las paredes (Velocidad normal: 16)
			followPath(patrolPoint, 16)
		end
	end
end)
