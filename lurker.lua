--[[
    LURKER AUTOPILOT - VERSION 16 (SECTOR-1 CLOSE QUARTERS CALIBRATION)
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

-- Variables de control adaptadas a pasillos cerrados
local targetPosition = rootPart.Position
local isResting = false
local restTimer = 0
local currentVisualHeading = rootPart.CFrame.LookVector

toggleButton.MouseButton1Click:Connect(function()
	getgenv().LurkerAI_Enabled = not getgenv().LurzenAI_Enabled
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
-- ESCÁNER DE PASILLOS CERRADOS Y ÁNGULOS RECTOS (SECTOR-1)
-- =========================================================================
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function calculateSector1Point()
	rayParams.FilterDescendantsInstances = {character}
	
	local bestPoint = rootPart.Position
	local maxFreeSpace = 0
	
	-- Escaneamos 12 direcciones a distancias cortas para adaptarnos a las esquinas del Sector-1
	for i = 1, 12 do
		local angle = math.rad(i * (360 / 12))
		-- Buscamos rutas de 20 a 35 unidades (el tamaño promedio de los pasillos cerrados)
		local distance = math.random(20, 35) 
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle)).Unit
		
		-- Doble sensor de barrido bajo y alto para registrar decorados y muros
		local originLow = rootPart.Position + Vector3.new(0, -0.7, 0)
		local originHigh = rootPart.Position + Vector3.new(0, 0.8, 0)
		
		local rayLow = Workspace:Raycast(originLow, direction * distance, rayParams)
		local rayHigh = Workspace:Raycast(originHigh, direction * distance, rayParams)
		
		local distLow = rayLow and (rayLow.Position - rootPart.Position).Magnitude or distance
		local distHigh = rayHigh and (rayHigh.Position - rootPart.Position).Magnitude or distance
		local effectiveDistance = math.min(distLow, distHigh)
		
		-- Si detectamos una caja o baranda baja en el camino corto, saltamos de inmediato
		if effectiveDistance < 4 then
			humanoid.Jump = true
		end
		
		-- Elige el pasillo habilitado disponible más óptimo en el entorno cerrado
		if effectiveDistance > maxFreeSpace and effectiveDistance > 8 then
			maxFreeSpace = effectiveDistance
			-- Dejamos un margen de 4 unidades para no chocar de frente al girar en las esquinas
			bestPoint = rootPart.Position + direction * (effectiveDistance - 4)
		end
	end
	return bestPoint
end

-- =========================================================================
-- MOTOR DE MOVIMIENTO FLUIDO Y CALIBRACIÓN DE PASO LENTO
-- =========================================================================
RunService.Heartbeat:Connect(function(deltaTime)
	if not getgenv().LurkerAI_Enabled or not humanoid or humanoid.Health <= 0 then return end
	
	-- Estado de acecho estático breve en la esquina del pasillo
	if isResting then
		renderMoveDirection = Vector3.new()
		restTimer = restTimer - deltaTime
		if restTimer <= 0 then
			isResting = false
			targetPosition = calculateSector1Point() -- Reacción instantánea al buscar nueva ruta
		end
		return
	end
	
	local flatCharacterPos = Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z)
	local flatTargetPos = Vector3.new(targetPosition.X, 0, targetPosition.Z)
	local distance = (flatCharacterPos - flatTargetPos).Magnitude
	
	if distance > 2.5 then
		-- VELOCIDAD CALIBRADA: 6.5 es el paso real de caminata lenta de los bots en pasillos cerrados
		local speed = 6.5 
		local moveDirection = (flatTargetPos - flatCharacterPos).Unit
		
		-- Desplazamiento cardinal continuo libre de lag
		local nextPosition = rootPart.Position + moveDirection * (speed * deltaTime)
		
		-- Suavizado Lerp incrementado (18 * deltaTime) para que gire el cuerpo rápido en esquinas de 90°
		currentVisualHeading = currentVisualHeading:Lerp(moveDirection, 18 * deltaTime).Unit
		rootPart.CFrame = CFrame.lookAt(nextPosition, rootPart.Position + currentVisualHeading)
		
		-- Activación constante de las animaciones nativas de caminar
		pcall(function()
			humanoid.RootPart.AssemblyLinearVelocity = moveDirection * speed
		end)
	else
		-- Al llegar a la esquina, se detiene brevemente a acechar (estilo Lurker del Sector-1)
		isResting = true
		restTimer = math.random(5, 12) / 10 -- Pausa muy corta de 0.5 a 1.2 segundos
		
		pcall(function()
			humanoid.RootPart.AssemblyLinearVelocity = Vector3.new()
		end)
	end
end)

humanoid.Died:Connect(function()
	screenGui:Destroy()
end)

