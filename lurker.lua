--[[
    LURKER AUTOPILOT - VERSION 18 (LONG RANGE PATROL CALIBRATION)
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

-- Variables de control de la IA para tramos largos
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
		print("[AI] Iniciando patrulla de largo alcance estilo Lurker.")
	else
		toggleButton.Text = "ESTADO: DESACTIVADO"
		toggleButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	end
end)

-- =========================================================================
-- ESCÁNER PROFUNDO DE SECTOR (Busca los pasillos más largos del mapa)
-- =========================================================================
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function calculateLongLurkerPath()
	rayParams.FilterDescendantsInstances = {character}
	local origin = rootPart.Position + Vector3.new(0, 0.5, 0)
	
	local bestPoint = rootPart.Position
	local maxFreeSpace = 0
	
	-- Incrementamos a 16 direcciones de barrido profundo para mapear pasillos distantes
	for i = 1, 16 do
		local angle = math.rad(i * (360 / 16))
		-- Calibración de distancia: Forzamos tramos largos de entre 45 y 85 unidades
		local distance = math.random(45, 85) 
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle)).Unit
		
		-- Sensores de dos niveles para escanear cajas decorativas y muros estructurales lejanos
		local originLow = rootPart.Position + Vector3.new(0, -0.6, 0)
		local originHigh = rootPart.Position + Vector3.new(0, 1, 0)
		
		local rayLow = Workspace:Raycast(originLow, direction * distance, rayParams)
		local rayHigh = Workspace:Raycast(originHigh, direction * distance, rayParams)
		
		local distLow = rayLow and (rayLow.Position - rootPart.Position).Magnitude or distance
		local distHigh = rayHigh and (rayHigh.Position - rootPart.Position).Magnitude or distance
		local effectiveDistance = math.min(distLow, distHigh)
		
		-- Salto predictivo si detectamos un obstáculo bajo en la ruta larga
		if effectiveDistance < 4.5 then
			humanoid.Jump = true
		end
		
		-- Filtro estricto: Prioriza de forma masiva los caminos largos sobre los callejones cortos
		if effectiveDistance > maxFreeSpace and effectiveDistance > 20 then
			maxFreeSpace = effectiveDistance
			-- Guardamos la coordenada final dejando un margen seguro de 5 unidades para girar la esquina fluidamente
			bestPoint = rootPart.Position + direction * (effectiveDistance - 5)
		end
	end
	
	-- Si el entorno inmediato está muy cerrado y el escáner largo no encuentra pasillos de más de 20 unidades,
	-- toma una ruta de escape media por defecto para salir de la habitación hacia el pasillo principal.
	if maxFreeSpace == 0 then
		for i = 1, 8 do
			local angle = math.rad(i * 45)
			local direction = Vector3.new(math.cos(angle), 0, math.sin(angle)).Unit
			local ray = Workspace:Raycast(origin, direction * 25, rayParams)
			local dist = ray and (ray.Position - rootPart.Position).Magnitude or 25
			if dist > maxFreeSpace then
				maxFreeSpace = dist
				bestPoint = rootPart.Position + direction * (dist - 4)
			end
		end
	end
	
	return bestPoint
end

-- =========================================================================
-- MOTOR SINCRÓNICO DE MOVIMIENTO FLUIDO
-- =========================================================================
RunService.Heartbeat:Connect(function(deltaTime)
	if not getgenv().LurkerAI_Enabled or not humanoid or humanoid.Health <= 0 then return end
	
	-- Estado de acecho estático al final del tramo largo
	if isResting then
		restTimer = restTimer - deltaTime
		if restTimer <= 0 then
			isResting = false
			targetPosition = calculateLongLurkerPath() -- Busca el siguiente tramo largo al instante
		end
		return
	end
	
	local flatCharacterPos = Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z)
	local flatTargetPos = Vector3.new(targetPosition.X, 0, targetPosition.Z)
	local distance = (flatCharacterPos - flatTargetPos).Magnitude
	
	if distance > 3 then
		local speed = 7.2 -- Velocidad de caminata acechante ajustada y natural
		local moveDirection = (flatTargetPos - flatCharacterPos).Unit
		
		-- Desplazamiento cardinal continuo por CFrame
		local nextPosition = rootPart.Position + moveDirection * (speed * deltaTime)
		
		-- Suavizado Lerp para giros orgánicos en las intersecciones del laboratorio
		currentVisualHeading = currentVisualHeading:Lerp(moveDirection, 14 * deltaTime).Unit
		rootPart.CFrame = CFrame.lookAt(nextPosition, rootPart.Position + currentVisualHeading)
		
		-- Mantenemos activa la animación nativa de caminata
		pcall(function()
			humanoid.RootPart.AssemblyLinearVelocity = moveDirection * speed
		end)
	else
		-- Al terminar la caminata larga, el Lurker se detiene a acechar la nueva zona
		isResting = true
		restTimer = math.random(12, 22) / 10 -- Pausa estática de 1.2 a 2.2 segundos
		
		pcall(function()
			humanoid.RootPart.AssemblyLinearVelocity = Vector3.new()
		end)
	end
end)

humanoid.Died:Connect(function()
	screenGui:Destroy()
end)
