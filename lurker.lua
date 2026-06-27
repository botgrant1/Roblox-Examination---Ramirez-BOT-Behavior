--[[
    LURKER AUTOPILOT - REAL ENGINE CALIBRATION & LERP SMOOTHING
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

-- Variables de control de patrulla calibradas
local targetPosition = rootPart.Position
local isResting = false
local restTimer = 0
local currentVisualHeading = rootPart.CFrame.LookVector

toggleButton.MouseButton1Click:Connect(function()
	getgenv().LurkerAI_Enabled = not getgenv().LurkerAI_Enabled
	
	if getgenv().LurkerAI_Enabled then
		toggleButton.Text = "ESTADO: ACTIVO"
		toggleButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
		targetPosition = rootPart.Position
		currentVisualHeading = rootPart.CFrame.LookVector
		isResting = false
	else
		toggleButton.Text = "ESTADO: DESACTIVADO"
		toggleButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	end
end)

-- =========================================================================
-- ESCÁNER DE PASILLOS LARGOS Y DETECCIÓN DE OBJETOS REFORZADA
-- =========================================================================
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function calculateNewPatrolPoint()
	rayParams.FilterDescendantsInstances = {character}
	
	local bestPoint = rootPart.Position
	local maxFreeSpace = 0
	
	-- Escaneamos 16 direcciones para encontrar las rutas más largas del Sector 1
	for i = 1, 16 do
		local angle = math.rad(i * (360 / 16))
		local distance = math.random(55, 90) -- Trayectos notablemente más largos
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle)).Unit
		
		-- SISTEMA MULTI-RAYO: Lanzamos un rayo bajo (objetos/cajas) y uno alto (paredes/puertas)
		local originLow = rootPart.Position + Vector3.new(0, -0.6, 0)
		local originHigh = rootPart.Position + Vector3.new(0, 1, 0)
		
		local rayLow = Workspace:Raycast(originLow, direction * distance, rayParams)
		local rayHigh = Workspace:Raycast(originHigh, direction * distance, rayParams)
		
		local distLow = rayLow and (rayLow.Position - rootPart.Position).Magnitude or distance
		local distHigh = rayHigh and (rayHigh.Position - rootPart.Position).Magnitude or distance
		
		-- Tomamos la distancia del objeto más cercano que obstruya el paso
		local effectiveDistance = math.min(distLow, distHigh)
		
		-- Si detectamos un objeto o caja decorativa muy cerca del frente, preparamos salto reactivo
		if effectiveDistance < 4.5 then
			humanoid.Jump = true
		end
		
		-- Buscador estricto de pasillos limpios y amplios del Sector 1
		if effectiveDistance > maxFreeSpace and effectiveDistance > 18 then
			maxFreeSpace = effectiveDistance
			-- Guardamos la coordenada final con margen de seguridad para no rozar esquinas
			bestPoint = rootPart.Position + direction * (effectiveDistance - 6)
		end
	end
	return bestPoint
end

-- =========================================================================
-- MOTOR DE DESLIZAMIENTO CON INTERPOLACIÓN (LERP) Y ANIMACIÓN
-- =========================================================================
RunService.Heartbeat:Connect(function(deltaTime)
	if not getgenv().LurkerAI_Enabled or not humanoid or humanoid.Health <= 0 then return end
	
	if isResting then
		restTimer = restTimer - deltaTime
		if restTimer <= 0 then
			isResting = false
			targetPosition = calculateNewPatrolPoint()
		end
		return
	end
	
	local flatCharacterPos = Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z)
	local flatTargetPos = Vector3.new(targetPosition.X, 0, targetPosition.Z)
	local distance = (flatCharacterPos - flatTargetPos).Magnitude
	
	if distance > 3.5 then
		-- CALIBRACIÓN EXACTA: 9.8 studs/sec es la velocidad real de caminata pasiva del Lurker
		local speed = 9.8 
		local moveDirection = (flatTargetPos - flatCharacterPos).Unit
		
		-- Desplazamiento matemático continuo
		local nextPosition = rootPart.Position + moveDirection * (speed * deltaTime)
		
		-- TRUCO DE FLUIDEZ DE IA (LERP): Suavizamos el giro del cuerpo.
		-- El personaje alineará su torso gradualmente (0.15 por cuadro) simulando un movimiento orgánico.
		currentVisualHeading = currentVisualHeading:Lerp(moveDirection, 12 * deltaTime).Unit
		rootPart.CFrame = CFrame.lookAt(nextPosition, rootPart.Position + currentVisualHeading)
		
		-- Sincronización forzada de la animación de caminata lenta
		pcall(function()
			humanoid.RootPart.AssemblyLinearVelocity = moveDirection * speed
		end)
	else
		-- Pausa estática característica al terminar una caminata larga
		isResting = true
		restTimer = math.random(18, 30) / 10 -- Entre 1.8 y 3.0 segundos acechando completamente quieto
		
		pcall(function()
			humanoid.RootPart.AssemblyLinearVelocity = Vector3.new()
		end)
	end
end)

humanoid.Died:Connect(function()
	screenGui:Destroy()
end)

