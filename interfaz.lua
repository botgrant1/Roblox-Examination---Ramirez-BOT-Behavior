--[[
    PARTE 1: MENU VISUAL Y OYENTE DE VOICELINES Z
--]]

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()

getgenv().LurkerAI_Enabled = false
getgenv().LeaderCharacter = nil
getgenv().LastLeaderMoveTime = 0
getgenv().LeaderLastPos = Vector3.new()

-- Interfaz Gráfica
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

toggleButton.MouseButton1Click:Connect(function()
	getgenv().LurkerAI_Enabled = not getgenv().LurkerAI_Enabled
	if getgenv().LurkerAI_Enabled then
		toggleButton.Text = "ESTADO: ACTIVO"
		toggleButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
		getgenv().LeaderCharacter = nil
		print("[AI] Menú Inicializado con Éxito.")
	else
		toggleButton.Text = "ESTADO: DESACTIVADO"
		toggleButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
		getgenv().LeaderCharacter = nil
	end
end)

-- Sistema de Escucha Táctica Z
local function setupVoiceListener(otherPlayer)
	otherPlayer.Chatted:Connect(function(message)
		if not getgenv().LurkerAI_Enabled or otherPlayer == player then return end
		local otherChar = otherPlayer.Character
		if not otherChar or not otherChar:FindFirstChild("HumanoidRootPart") then return end
		
		local myRoot = character:FindFirstChild("HumanoidRootPart")
		if not myRoot then return end
		
		local distance = (myRoot.Position - otherChar.HumanoidRootPart.Position).Magnitude
		if distance <= 45 then
			if message == "Follow Me!" or message == "Follow me!" or message == "Sígueme!" or message == "Sigueme!" then
				getgenv().LeaderCharacter = otherChar
				getgenv().LeaderLastPos = otherChar.HumanoidRootPart.Position
				getgenv().LastLeaderMoveTime = os.clock()
				print("[Voiceline Z] Escortando a: " .. otherPlayer.Name)
			end
		end
	end)
end

for _, p in ipairs(Players:GetPlayers()) do setupVoiceListener(p) end
Players.PlayerAdded:Connect(setupVoiceListener)

character:WaitForChild("Humanoid").Died:Connect(function() screenGui:Destroy() end)
