--[[
    LURKER SIMULATOR - VERSION DE DESLIZAMIENTO CARDINAL (ANTI-BLOQUEO)
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

-- Variables de control de patrulla
local targetPosition = rootPart.Position
local isResting = false
local restTimer = 0

toggleButton.MouseButton1Click:Connect(function()
	getgenv().LurkerAI_Enabled = not getgenv().LurkerAI_Enabled
	
	if getgenv().LurkerAI_Enabled then
		toggleButton.Text = "ESTADO: ACTIVO"
		toggleButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
		targetPosition = rootPart.Position
		isResting = false
	else
		toggleButton.Text = "ESTADO: DESACTIVADO"
		toggleButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	end
end)

-- =========================================================================
-- DETECTOR DE PASILLOS REALISTAS (SISTEMA CARDINAL ABIERTO)
-- =========================================================================
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function calculateNewPatrolPoint()
	rayParams.FilterDescendantsInstances = {character}
	local origin = rootPart.Position + Vector3.new(0, 0.5, 0)
	
	local bestPoint = rootPart.Position
	local maxFreeSpace = 0
	
	-- Escanea 12 direcciones fijas del mapa (Ignorando hacia dónde miras tú)
	for i = 1, 12 do
		local angle = math.rad(i * (360 / 12))
		local distance = math.random(40, 75) -- Trayectos largos estilo Lurker
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle)).Unit
		
		local rayResult = Workspace:Raycast(origin, direction * distance, rayParams)
		local freeDistance = rayResult and (rayResult.Position - rootPart.Position).Magnitude or distance
		
		-- Buscamos el pasillo más largo disponible
		if freeDistance > maxFreeSpace and freeDistance > 15 then
			maxFreeSpace = freeDistance
			bestPoint = rootPart.Position + direction * (freeDistance - 6) -- Dejamos margen para no chocar
		end
	end
	return bestPoint
end

-- =========================================================================
-- BUCLE MOTOR (CORRE EN CADA FOTOGRAMA - 0 TIRONES)
-- =========================================================================
RunService.Heartbeat:Connect(function(deltaTime)
	if not getgenv().LurkerAI_Enabled or not humanoid or humanoid.Health <= 0 then return end
	
	-- Si está en su pausa estática de acechando, reducimos el tiempo y no nos movemos
	if isResting then
		restTimer = restTimer - deltaTime
		if restTimer <= 0 then
			isResting = false
			targetPosition = calculateNewPatrolPoint() -- Elige pasillo al terminar de acechar
		end
		return
	end
	
	-- Calculamos la distancia en línea recta hacia el pasillo abierto elegido
	local flatCharacterPos = Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z)
	local flatTargetPos = Vector3.new(targetPosition.X, 0, targetPosition.Z)
	local distance = (flatCharacterPos - flatTargetPos).Magnitude
	
	if distance > 3 then
		-- Velocidad del Lurker al patrullar (16 studs por segundo)
		local speed = 16
		local moveDirection = (flatTargetPos - flatCharacterPos).Unit
		
		-- TRUCO DEFINITIVO: Desplazamos el CFrame del personaje de forma matemática.
		-- Esto ignora al 100% los controles de Roblox y hacia dónde apunte tu cámara.
		local nextPosition = rootPart.Position + moveDirection * (speed * deltaTime)
		
		-- Forzamos al cuerpo a mirar hacia donde avanza de forma fluida
		rootPart.CFrame = CFrame.lookAt(nextPosition, Vector3.new(targetPosition.X, rootPart.Position.Y, targetPosition.Z))
		
		-- Mini Raycast de emergencia por si hay un escalón o caja decorativa baja en medio, forzar salto
		local obstacleRay = Workspace:Raycast(rootPart.Position, moveDirection * 3, rayParams)
		if obstacleRay then
			humanoid.Jump = true
		end
	else
		-- ¡Llegamos al final del pasillo despejado! Iniciamos pausa estática estilo Lurker
		isResting = true
		restTimer = math.random(15, 25) / 10 -- Entre 1.5 y 2.5 segundos quieto acechando
	end
end)

humanoid.Died:Connect(function()
	screenGui:Destroy()
end)
