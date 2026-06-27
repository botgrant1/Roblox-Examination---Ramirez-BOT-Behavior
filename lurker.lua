--[[
    LURKER & CHIMERA BEHAVIOR SIMULATOR - VERSION 10 (STABLE NODE PATROL)
--]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local PathfindingService = game:GetService("PathfindingService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

-- Apagar controles locales para evitar interferencias
pcall(function()
	local playerModule = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
	if playerModule then playerModule:GetControls():Disable() end
end)

print("[IA Activa] Seleccionado estilo: LURKER. Moviéndose por nodos del servidor.")

-- =========================================================================
-- CONFIGURACIÓN DE ACTITUD (¡Puedes cambiar "Lurker" por "Chimera" aquí!)
-- =========================================================================
local IA_STYLE = "Lurker" -- Opciones: "Lurker" o "Chimera"

local patrolRadius = (IA_STYLE == "Lurker") and 70 or 20      -- Distancia de caminata
local restTime = (IA_STYLE == "Lurker") and 1.5 or 0.2       -- Pausa al llegar al punto
local patrolSpeed = (IA_STYLE == "Lurker") and 15 or 12      -- Velocidad al pasear
local chaseSpeed = 24                                        -- Velocidad de carrera Lurker

-- Configuración del creador de rutas nativo de Roblox
local path = PathfindingService:CreatePath({
	AgentRadius = 3,
	AgentHeight = 6,
	AgentCanJump = true,
})

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- 1. FILTRO DE LÍNEA DE VISIÓN REALISTA
local function hasLineOfSight(enemyRoot)
	rayParams.FilterDescendantsInstances = {character}
	local toEnemy = (enemyRoot.Position - rootPart.Position).Unit
	local dotProduct = rootPart.CFrame.LookVector:Dot(toEnemy)
	
	if dotProduct < 0.65 then return false end -- Cono frontal de visión
	
	local origin = rootPart.Position + Vector3.new(0, 2, 0)
	local direction = (enemyRoot.Position - origin)
	local rayResult = Workspace:Raycast(origin, direction, rayParams)
	
	if rayResult and rayResult.Instance:IsDescendantOf(enemyRoot.Parent) then
		return true
	end
	return false
end

-- 2. ESCÁNER DE ENTIDADES (Excluye jugadores reales)
local function getVisibleEntity()
	local target = nil
	local closestDistance = 110
	
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

-- 3. CAMINAR DE FORMA FLUIDA PUNTO POR PUNTO (Previene atascos en pasillos)
local function walkToDestination(targetPosition, speed)
	humanoid.WalkSpeed = speed
	
	local success, _ = pcall(function()
		path:ComputeAsync(rootPart.Position, targetPosition)
	end)
	
	if success and path.Status == Enum.PathStatus.Success then
		local waypoints = path:GetWaypoints()
		
		-- Recorremos la ruta punto por punto de forma nativa
		for i = 2, #waypoints do
			-- Si en medio del trayecto de patrulla aparece una entidad, rompemos la caminata para atacar
			if getVisibleEntity() then break end
			if not humanoid or humanoid.Health <= 0 then break end
			
			local currentPoint = waypoints[i]
			humanoid:MoveTo(currentPoint.Position)
			
			-- Si el mapa requiere saltar un objeto
			if currentPoint.Action == Enum.PathWaypointAction.Jump then
				humanoid.Jump = true
			end
			
			-- Espera de forma segura a que el motor físico llegue al nodo actual (Máximo 2 segundos por nodo)
			local reached = humanoid.MoveToFinished:Wait()
			if not reached then break end -- Si se traba, rompe la ruta para recalcular
		end
	else
		-- Respaldo físico directo si el Pathfinding del mapa falla
		humanoid:MoveTo(targetPosition)
		humanoid.MoveToFinished:Wait()
	end
end

-- 4. BUCLE PRINCIPAL DE COMPORTAMIENTO
task.spawn(function()
	while task.wait(0.1) do
		if not humanoid or humanoid.Health <= 0 then break end
		
		local currentTarget = getVisibleEntity()
		
		-- ESTADO 1: PERSIGUIENDO ENMIGO (Agresivo, corre a donde vaya)
		if currentTarget and currentTarget.Parent and currentTarget.Parent:FindFirstChild("Humanoid") and currentTarget.Parent.Humanoid.Health > 0 then
			local distance = (rootPart.Position - currentTarget.Position).Magnitude
			
			if distance <= 6.5 then
				-- Frenar y atacar si está en rango
				humanoid:MoveTo(rootPart.Position)
				local tool = character:FindFirstChildOfClass("Tool")
				if tool then tool:Activate() end
				task.wait(0.3)
			else
				-- Avanzar directamente hacia su posición actualizada
				humanoid.WalkSpeed = chaseSpeed
				humanoid:MoveTo(currentTarget.Position)
			end
			
		-- ESTADO 2: PATRULLA ORGÁNICA (Vagar por el mapa)
		else
			-- Elegimos un punto aleatorio en el mapa según el radio del estilo elegido
			local randomAngle = math.rad(math.random(0, 360))
			local randomDist = math.random(patrolRadius * 0.5, patrolRadius)
			local targetPos = rootPart.Position + Vector3.new(math.cos(randomAngle) * randomDist, 0, math.sin(randomAngle) * randomDist)
			
			-- Ejecuta la caminata completa de forma suave
			walkToDestination(targetPos, patrolSpeed)
			
			-- Al llegar a su destino, hace la pausa característica del NPC antes de cambiar de rumbo
			if not getVisibleEntity() then
				task.wait(restTime)
			end
		end
	end
end)
