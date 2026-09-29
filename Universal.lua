local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer
local UserInputService = game:GetService("UserInputService")

local CONFIG = {
    AimbotEnabled = false,
    AimbotSmoothing = 0.75,
    AimbotMode = "HEAD",
    FOVRadius = 80,
    HeadOffsetY = -0.3,
    ESPEnabled = false,
    ESPType = "BOX",
    ESPColor = Color3.new(1, 1, 1),
    ESPTransparency = 0.3,
    ESPHealthEnabled = true,
    HitboxExpanderEnabled = false,
    HitboxExpanderTeamCheckEnabled = false,
    HitboxSize = 5,
    HitboxTransparency = 0.5,
    WalkSpeedEnabled = false,
    WalkSpeed = 16,
    TeamCheckEnabled = true,
    WallCheckEnabled = true,
    FPSCounterEnabled = false,
    DetectionAvoidanceEnabled = false,
    CameraFOV = 70,
}

local ESPCache = {}
local FOVCircle = nil
local HitboxCache = {}
local WalkSpeedLoop = nil
local aimbotLoop = nil
local espLoop = nil
local hitboxLoop = nil
local fpsLoop = nil
local cameraFOVLoop = nil
local UIMinimized = false
local MainUI = nil
local FPSCounter = 0
local FPSDisplay = nil

local HotKeys = {
    Aimbot = Enum.KeyCode.Five,
    ESP = Enum.KeyCode.Six,
    Teamcheck = Enum.KeyCode.Seven,
    Hitbox = Enum.KeyCode.Eight,
    Walkspeed = Enum.KeyCode.Nine,
}

local function IsSameTeam(player1, player2)
    if not player1 or not player2 then return false end
    if player1.Team and player2.Team then
        return player1.Team == player2.Team
    end
    return false
end

local function IsVisible(targetHead)
    if not CONFIG.WallCheckEnabled then return true end
    if not LocalPlayer.Character then return false end
    
    local origin = Camera.CFrame.Position
    local direction = (targetHead.Position - origin)
    local distance = direction.Magnitude
    
    if distance < 0.1 then return true end
    
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = {LocalPlayer.Character}
    
    local result = workspace:Raycast(origin, direction.Unit * distance, raycastParams)
    
    if result then
        local hitModel = result.Instance:FindFirstAncestorWhichIsA("Model")
        return hitModel == targetHead.Parent
    end
    
    return true
end

local function IsPlayerAlive(player)
    if not player or not player.Character then return false end
    if player == LocalPlayer then return false end
    if CONFIG.TeamCheckEnabled and IsSameTeam(LocalPlayer, player) then return false end
    
    local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
    return humanoid and humanoid.Health > 0
end

local function GetAllPlayers()
    local alivePlayers = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if IsPlayerAlive(player) then
            table.insert(alivePlayers, player)
        end
    end
    return alivePlayers
end

local function GetAimTarget()
    local players = GetAllPlayers()
    if #players == 0 then return nil end
    
    local nearestPlayer = nil
    local nearestDistance = math.huge
    local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    
    for _, player in ipairs(players) do
        local head = player.Character:FindFirstChild("Head")
        if head then
            local screenPos, onScreen = Camera:WorldToViewportPoint(head.Position)
            
            if onScreen and screenPos.Z > 0 then
                local distance = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
                
                if distance < CONFIG.FOVRadius and distance < nearestDistance then
                    if IsVisible(head) then
                        nearestDistance = distance
                        nearestPlayer = player
                    end
                end
            end
        end
    end
    
    return nearestPlayer
end

local function CreateFOVCircle()
    if FOVCircle then pcall(function() FOVCircle:Remove() end) end
    
    FOVCircle = Drawing.new("Circle")
    FOVCircle.Radius = CONFIG.FOVRadius
    FOVCircle.Color = Color3.fromRGB(255, 255, 255)
    FOVCircle.Thickness = 2
    FOVCircle.Filled = false
    FOVCircle.Transparency = 0.7
    FOVCircle.Visible = CONFIG.AimbotEnabled
end

local function UpdateFOVCircle()
    if not FOVCircle then return end
    
    local screenSize = Camera.ViewportSize
    local centerX = screenSize.X / 2
    local centerY = screenSize.Y / 2
    
    FOVCircle.Position = Vector2.new(centerX, centerY)
    FOVCircle.Radius = CONFIG.FOVRadius
    FOVCircle.Visible = CONFIG.AimbotEnabled
end

local function StartAimbot()
    if aimbotLoop then aimbotLoop:Disconnect() end
    
    CreateFOVCircle()
    
    aimbotLoop = RunService.RenderStepped:Connect(function()
        if not CONFIG.AimbotEnabled or not LocalPlayer.Character then return end
        
        UpdateFOVCircle()
        
        local targetPlayer = GetAimTarget()
        if not targetPlayer or not targetPlayer.Character then return end
        
        local head = targetPlayer.Character:FindFirstChild("Head")
        if not head then return end
        
        local targetPos
        if CONFIG.AimbotMode == "TORSO" then
            local torso = targetPlayer.Character:FindFirstChild("Torso") or targetPlayer.Character:FindFirstChild("UpperTorso")
            targetPos = torso and torso.Position or head.Position
        else
            targetPos = head.Position + Vector3.new(0, CONFIG.HeadOffsetY, 0)
        end
        
        local currentCFrame = Camera.CFrame
        local newCFrame = CFrame.new(currentCFrame.Position, targetPos)
        
        Camera.CFrame = currentCFrame:Lerp(newCFrame, CONFIG.AimbotSmoothing)
    end)
end

local function StopAimbot()
    if aimbotLoop then
        aimbotLoop:Disconnect()
        aimbotLoop = nil
    end
    
    if FOVCircle then
        pcall(function() FOVCircle:Remove() end)
        FOVCircle = nil
    end
end

local function SafeRemoveDrawing(drawing)
    if drawing then
        pcall(function() drawing:Remove() end)
    end
end

local function CleanESPCache()
    for playerId, data in pairs(ESPCache) do
        SafeRemoveDrawing(data.box)
        SafeRemoveDrawing(data.health)
    end
    ESPCache = {}
    collectgarbage("collect")
end

local function RemoveFromCache(playerId)
    if ESPCache[playerId] then
        SafeRemoveDrawing(ESPCache[playerId].box)
        SafeRemoveDrawing(ESPCache[playerId].health)
        ESPCache[playerId] = nil
    end
end

local espCleanupCounter = 0

local function DrawBox2D(screenPos, size, color, thickness, transparency)
    local box = Drawing.new("Square")
    box.Position = screenPos - Vector2.new(size / 2, size / 2)
    box.Size = Vector2.new(size, size)
    box.Color = color
    box.Thickness = thickness
    box.Filled = false
    box.Transparency = transparency
    box.Visible = true
    return box
end

local function StartESP()
    if espLoop then espLoop:Disconnect() end
    
    espCleanupCounter = 0
    
    espLoop = RunService.RenderStepped:Connect(function()
        if not CONFIG.ESPEnabled then
            CleanESPCache()
            return
        end
        
        espCleanupCounter = espCleanupCounter + 1
        
        if espCleanupCounter >= 100 then
            espCleanupCounter = 0
            collectgarbage("step", 10)
        end
        
        local players = GetAllPlayers()
        local activePlayers = {}
        
        for _, player in ipairs(players) do
            local head = player.Character:FindFirstChild("Head")
            local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
            
            if head then
                local screenPos, onScreen = Camera:WorldToViewportPoint(head.Position)
                
                if onScreen and screenPos.Z > 0 then
                    activePlayers[player.UserId] = true
                    
                    if not ESPCache[player.UserId] then
                        ESPCache[player.UserId] = {
                            box = nil,
                            health = nil,
                            type = nil
                        }
                    end
                    
                    local cache = ESPCache[player.UserId]
                    local screenVec = Vector2.new(screenPos.X, screenPos.Y)
                    
                    if cache.type ~= CONFIG.ESPType then
                        SafeRemoveDrawing(cache.box)
                        SafeRemoveDrawing(cache.health)
                        cache.box = nil
                        cache.health = nil
                        cache.type = CONFIG.ESPType
                    end
                    
                    if CONFIG.ESPType == "BOX" then
                        if not cache.box or not pcall(function() return cache.box.Visible end) then
                            cache.box = DrawBox2D(screenVec, 20, CONFIG.ESPColor, 2, CONFIG.ESPTransparency)
                        else
                            cache.box.Position = screenVec - Vector2.new(10, 10)
                            cache.box.Size = Vector2.new(20, 20)
                            cache.box.Color = CONFIG.ESPColor
                            cache.box.Transparency = CONFIG.ESPTransparency
                        end
                    else
                        if not cache.box or not pcall(function() return cache.box.Visible end) then
                            cache.box = Drawing.new("Circle")
                        end
                        
                        cache.box.Position = screenVec
                        cache.box.Radius = 8
                        cache.box.Color = CONFIG.ESPColor
                        cache.box.Thickness = 2
                        cache.box.Filled = false
                        cache.box.Transparency = CONFIG.ESPTransparency
                        cache.box.Visible = true
                    end
                    
                    if CONFIG.ESPHealthEnabled and humanoid then
                        if not cache.health then
                            cache.health = Drawing.new("Text")
                        end
                        
                        if cache.health and pcall(function() return cache.health.Visible end) then
                            cache.health.Position = screenVec + Vector2.new(0, 15)
                            cache.health.Size = 12
                            cache.health.Color = Color3.fromRGB(255, 255, 255)
                            cache.health.Text = "HP: " .. math.floor(humanoid.Health)
                            cache.health.Font = 2
                            cache.health.Transparency = 0.5
                            cache.health.Visible = true
                        end
                    end
                else
                    RemoveFromCache(player.UserId)
                end
            end
        end
        
        local removeCount = 0
        for playerId, data in pairs(ESPCache) do
            if removeCount >= 10 then break end
            if not activePlayers[playerId] then
                RemoveFromCache(playerId)
                removeCount = removeCount + 1
            end
        end
    end)
end

local function StopESP()
    if espLoop then
        espLoop:Disconnect()
        espLoop = nil
    end
    CleanESPCache()
end

local hitboxCleanupCounter = 0

local function RestoreHead(playerId)
    if not HitboxCache[playerId] then return end
    
    local data = HitboxCache[playerId]
    if data.head and data.head.Parent then
        pcall(function()
            data.head.Size = data.originalSize
            data.head.Transparency = data.originalTransparency
            data.head.BrickColor = data.originalColor
            data.head.Material = data.originalMaterial
            data.head.CanCollide = data.originalCanCollide
            data.head.TopSurface = data.originalTopSurface
            data.head.BottomSurface = data.originalBottomSurface
        end)
    end
    HitboxCache[playerId] = nil
end

local function CleanHitboxCache()
    for playerId, _ in pairs(HitboxCache) do
        RestoreHead(playerId)
    end
    HitboxCache = {}
    collectgarbage("collect")
end

local function ExpandHead(player)
    if not player or not player.Character then return end
    
    local head = player.Character:FindFirstChild("Head")
    if not head then return end
    
    local playerId = player.UserId
    
    if HitboxCache[playerId] and HitboxCache[playerId].head ~= head then
        RestoreHead(playerId)
    end
    
    if not HitboxCache[playerId] then
        HitboxCache[playerId] = {
            head = head,
            originalSize = head.Size,
            originalTransparency = head.Transparency,
            originalColor = head.BrickColor,
            originalMaterial = head.Material,
            originalCanCollide = head.CanCollide,
            originalTopSurface = head.TopSurface,
            originalBottomSurface = head.BottomSurface
        }
    end
    
    pcall(function()
        head.Size = Vector3.new(CONFIG.HitboxSize, CONFIG.HitboxSize, CONFIG.HitboxSize)
        head.Transparency = CONFIG.HitboxTransparency
        head.BrickColor = BrickColor.new("Really blue")
        head.Material = "Neon"
        head.CanCollide = false
        head.TopSurface = Enum.SurfaceType.Smooth
        head.BottomSurface = Enum.SurfaceType.Smooth
    end)
end

local function StartHitboxExpander()
    if hitboxLoop then hitboxLoop:Disconnect() end
    
    hitboxCleanupCounter = 0
    
    hitboxLoop = RunService.RenderStepped:Connect(function()
        if not CONFIG.HitboxExpanderEnabled then return end
        
        hitboxCleanupCounter = hitboxCleanupCounter + 1
        
        if hitboxCleanupCounter >= 150 then
            hitboxCleanupCounter = 0
            collectgarbage("step", 5)
        end
        
        local players = Players:GetPlayers()
        local activePlayers = {}
        
        for _, player in ipairs(players) do
            if player.Name ~= LocalPlayer.Name then
                pcall(function()
                    if CONFIG.HitboxExpanderTeamCheckEnabled then
                        if IsSameTeam(LocalPlayer, player) then
                            RestoreHead(player.UserId)
                            return
                        end
                    end
                    
                    if player.Character then
                        activePlayers[player.UserId] = true
                        ExpandHead(player)
                    end
                end)
            end
        end
        
        local removeCount = 0
        for playerId, data in pairs(HitboxCache) do
            if removeCount >= 5 then break end
            if not activePlayers[playerId] then
                if not data.head or not data.head.Parent then
                    RestoreHead(playerId)
                    removeCount = removeCount + 1
                end
            end
        end
    end)
end

local function StopHitboxExpander()
    if hitboxLoop then
        hitboxLoop:Disconnect()
        hitboxLoop = nil
    end
    CleanHitboxCache()
end

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(character)
        if CONFIG.HitboxExpanderEnabled then
            wait(0.1)
            ExpandHead(player)
        end
    end)
    
    if player.Character then
        player.CharacterAdded:Connect(function(character)
            if CONFIG.HitboxExpanderEnabled then
                wait(0.1)
                ExpandHead(player)
            end
        end)
    end
end)

local function StartWalkSpeed()
    if WalkSpeedLoop then WalkSpeedLoop:Disconnect() end
    
    WalkSpeedLoop = RunService.RenderStepped:Connect(function()
        if not CONFIG.WalkSpeedEnabled or not LocalPlayer.Character then return end
        
        pcall(function()
            local humanoid = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if humanoid then
                sethiddenproperty(humanoid, "WalkSpeed", CONFIG.WalkSpeed)
            end
        end)
    end)
end

local function StopWalkSpeed()
    if WalkSpeedLoop then
        WalkSpeedLoop:Disconnect()
        WalkSpeedLoop = nil
    end
    
    pcall(function()
        if LocalPlayer.Character then
            local humanoid = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if humanoid then
                sethiddenproperty(humanoid, "WalkSpeed", 16)
            end
        end
    end)
end

local function StartFPSCounter()
    if fpsLoop then fpsLoop:Disconnect() end
    
    local frameCount = 0
    local lastUpdate = tick()
    
    fpsLoop = RunService.RenderStepped:Connect(function()
        if not CONFIG.FPSCounterEnabled then return end
        
        frameCount = frameCount + 1
        local currentTime = tick()
        local deltaTime = currentTime - lastUpdate
        
        if deltaTime >= 1 then
            FPSCounter = frameCount
            frameCount = 0
            lastUpdate = currentTime
            
            if FPSDisplay then
                FPSDisplay.Text = "FPS: " .. FPSCounter
            end
        end
    end)
end

local function StopFPSCounter()
    if fpsLoop then
        fpsLoop:Disconnect()
        fpsLoop = nil
    end
    if FPSDisplay then
        SafeRemoveDrawing(FPSDisplay)
        FPSDisplay = nil
    end
end

local function CreateFPSDisplay()
    if FPSDisplay then
        SafeRemoveDrawing(FPSDisplay)
    end
    
    FPSDisplay = Drawing.new("Text")
    FPSDisplay.Position = Vector2.new(10, 10)
    FPSDisplay.Size = 18
    FPSDisplay.Color = Color3.fromRGB(0, 255, 0)
    FPSDisplay.Text = "FPS: 0"
    FPSDisplay.Font = 2
    FPSDisplay.Transparency = 0.8
    FPSDisplay.Visible = CONFIG.FPSCounterEnabled
end

local function StartCameraFOV()
    if cameraFOVLoop then cameraFOVLoop:Disconnect() end
    
    cameraFOVLoop = RunService.RenderStepped:Connect(function()
        if not LocalPlayer.Character then return end
        pcall(function()
            Camera.FieldOfView = CONFIG.CameraFOV
        end)
    end)
end

local function StopCameraFOV()
    if cameraFOVLoop then
        cameraFOVLoop:Disconnect()
        cameraFOVLoop = nil
    end
    pcall(function()
        Camera.FieldOfView = 70
    end)
end

local UIElements = {}

local function UpdateUIStatus()
    if UIElements.AimbotStatusLabel then
        UIElements.AimbotStatusLabel.Text = CONFIG.AimbotEnabled and "ON" or "OFF"
    end
    if UIElements.ESPStatusLabel then
        UIElements.ESPStatusLabel.Text = CONFIG.ESPEnabled and "ON" or "OFF"
    end
    if UIElements.AimbotModeLabel then
        UIElements.AimbotModeLabel.Text = "Aim: " .. CONFIG.AimbotMode
    end
    if UIElements.ESPTypeLabel then
        UIElements.ESPTypeLabel.Text = "ESP: " .. CONFIG.ESPType
    end
    if UIElements.TeamCheckLabel then
        UIElements.TeamCheckLabel.Text = CONFIG.TeamCheckEnabled and "ON" or "OFF"
    end
    if UIElements.HitboxExpanderLabel then
        UIElements.HitboxExpanderLabel.Text = CONFIG.HitboxExpanderEnabled and "ON" or "OFF"
    end
    if UIElements.WalkSpeedLabel then
        UIElements.WalkSpeedLabel.Text = CONFIG.WalkSpeedEnabled and "ON" or "OFF"
    end
    if UIElements.FPSCounterLabel then
        UIElements.FPSCounterLabel.Text = CONFIG.FPSCounterEnabled and "ON" or "OFF"
    end
    if UIElements.DetectionAvoidanceLabel then
        UIElements.DetectionAvoidanceLabel.Text = CONFIG.DetectionAvoidanceEnabled and "ON" or "OFF"
    end
    if UIElements.SmoothLabel then
        UIElements.SmoothLabel.Text = "Smooth: " .. string.format("%.2f", CONFIG.AimbotSmoothing)
    end
    if UIElements.FOVLabel then
        UIElements.FOVLabel.Text = "FOV: " .. CONFIG.FOVRadius
    end
    if UIElements.WalkSpeedSliderLabel then
        UIElements.WalkSpeedSliderLabel.Text = "Speed: " .. CONFIG.WalkSpeed
    end
    if UIElements.CameraFOVLabel then
        UIElements.CameraFOVLabel.Text = "Cam FOV: " .. CONFIG.CameraFOV
    end
end

local function CreateUI()
    MainUI = Instance.new("ScreenGui")
    MainUI.Name = "AimbotAdvancedUI"
    MainUI.Parent = game:GetService("CoreGui")
    MainUI.ResetOnSpawn = false

    local MainFrame = Instance.new("Frame")
    MainFrame.Name = "MainFrame"
    MainFrame.Size = UDim2.new(0, 240, 0, 380)
    MainFrame.Position = UDim2.new(0, 10, 0, 50)
    MainFrame.BackgroundColor3 = Color3.fromRGB(12, 12, 20)
    MainFrame.BorderSizePixel = 0
    MainFrame.Draggable = true
    MainFrame.Active = true
    MainFrame.Parent = MainUI
    UIElements.MainFrame = MainFrame

    local Header = Instance.new("TextLabel")
    Header.Size = UDim2.new(1, 0, 0, 32)
    Header.Position = UDim2.new(0, 0, 0, 0)
    Header.BackgroundColor3 = Color3.fromRGB(25, 25, 40)
    Header.TextColor3 = Color3.fromRGB(120, 160, 255)
    Header.Text = "⚡ AIMBOT v3.1"
    Header.Font = Enum.Font.GothamBold
    Header.TextSize = 12
    Header.Parent = MainFrame

    local MinimizeBtn = Instance.new("TextButton")
    MinimizeBtn.Size = UDim2.new(0, 28, 0, 32)
    MinimizeBtn.Position = UDim2.new(1, -56, 0, 0)
    MinimizeBtn.BackgroundColor3 = Color3.fromRGB(25, 25, 40)
    MinimizeBtn.TextColor3 = Color3.fromRGB(150, 150, 150)
    MinimizeBtn.Text = "−"
    MinimizeBtn.Font = Enum.Font.GothamBold
    MinimizeBtn.TextSize = 18
    MinimizeBtn.Parent = MainFrame
    UIElements.MinimizeBtn = MinimizeBtn

    local CloseBtn = Instance.new("TextButton")
    CloseBtn.Size = UDim2.new(0, 28, 0, 32)
    CloseBtn.Position = UDim2.new(1, -28, 0, 0)
    CloseBtn.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
    CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    CloseBtn.Text = "✕"
    CloseBtn.Font = Enum.Font.GothamBold
    CloseBtn.TextSize = 14
    CloseBtn.Parent = MainFrame
    UIElements.CloseBtn = CloseBtn

    local MainContent = Instance.new("ScrollingFrame")
    MainContent.Name = "MainContent"
    MainContent.Size = UDim2.new(1, 0, 1, -32)
    MainContent.Position = UDim2.new(0, 0, 0, 32)
    MainContent.BackgroundColor3 = Color3.fromRGB(12, 12, 20)
    MainContent.BorderSizePixel = 0
    MainContent.ScrollBarThickness = 3
    MainContent.CanvasSize = UDim2.new(0, 0, 0, 630)
    MainContent.Parent = MainFrame
    UIElements.Content = MainContent

    local yPos = 8

    local function CreateButton(labelText, yPosition)
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(0.65, -5, 0, 20)
        label.Position = UDim2.new(0, 8, 0, yPosition)
        label.BackgroundTransparency = 1
        label.TextColor3 = Color3.fromRGB(180, 180, 200)
        label.Text = labelText
        label.Font = Enum.Font.Gotham
        label.TextSize = 9
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = MainContent

        local button = Instance.new("TextButton")
        button.Size = UDim2.new(0.3, -5, 0, 16)
        button.Position = UDim2.new(0.68, 0, 0, yPosition + 2)
        button.BackgroundColor3 = Color3.fromRGB(35, 35, 55)
        button.TextColor3 = Color3.fromRGB(120, 160, 255)
        button.Text = "OFF"
        button.Font = Enum.Font.GothamBold
        button.TextSize = 8
        button.Parent = MainContent

        return label, button
    end

    local AimbotLabel, AimbotButton = CreateButton("⚡ AIMBOT", yPos)
    UIElements.AimbotStatusLabel = AimbotButton
    AimbotButton.MouseButton1Click:Connect(function()
        CONFIG.AimbotEnabled = not CONFIG.AimbotEnabled
        if CONFIG.AimbotEnabled then StartAimbot() else StopAimbot() end
        UpdateUIStatus()
    end)
    yPos = yPos + 26

    local ESPLabel, ESPButton = CreateButton("👁 ESP", yPos)
    UIElements.ESPStatusLabel = ESPButton
    ESPButton.MouseButton1Click:Connect(function()
        CONFIG.ESPEnabled = not CONFIG.ESPEnabled
        if CONFIG.ESPEnabled then StartESP() else StopESP() end
        UpdateUIStatus()
    end)
    yPos = yPos + 26

    local AimbotModeLabel = Instance.new("TextLabel")
    AimbotModeLabel.Size = UDim2.new(1, -16, 0, 14)
    AimbotModeLabel.Position = UDim2.new(0, 8, 0, yPos)
    AimbotModeLabel.BackgroundTransparency = 1
    AimbotModeLabel.TextColor3 = Color3.fromRGB(140, 140, 160)
    AimbotModeLabel.Text = "Aim: HEAD"
    AimbotModeLabel.Font = Enum.Font.Gotham
    AimbotModeLabel.TextSize = 8
    AimbotModeLabel.TextXAlignment = Enum.TextXAlignment.Left
    AimbotModeLabel.Parent = MainContent
    UIElements.AimbotModeLabel = AimbotModeLabel

    local ModeBtn = Instance.new("TextButton")
    ModeBtn.Size = UDim2.new(1, -16, 0, 14)
    ModeBtn.Position = UDim2.new(0, 8, 0, yPos + 15)
    ModeBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 55)
    ModeBtn.TextColor3 = Color3.fromRGB(120, 160, 255)
    ModeBtn.Text = "HEAD / TORSO"
    ModeBtn.Font = Enum.Font.Gotham
    ModeBtn.TextSize = 7
    ModeBtn.Parent = MainContent

    ModeBtn.MouseButton1Click:Connect(function()
        CONFIG.AimbotMode = (CONFIG.AimbotMode == "HEAD") and "TORSO" or "HEAD"
        UpdateUIStatus()
    end)
    yPos = yPos + 33

    local ESPTypeLabel = Instance.new("TextLabel")
    ESPTypeLabel.Size = UDim2.new(1, -16, 0, 14)
    ESPTypeLabel.Position = UDim2.new(0, 8, 0, yPos)
    ESPTypeLabel.BackgroundTransparency = 1
    ESPTypeLabel.TextColor3 = Color3.fromRGB(140, 140, 160)
    ESPTypeLabel.Text = "ESP: BOX"
    ESPTypeLabel.Font = Enum.Font.Gotham
    ESPTypeLabel.TextSize = 8
    ESPTypeLabel.TextXAlignment = Enum.TextXAlignment.Left
    ESPTypeLabel.Parent = MainContent
    UIElements.ESPTypeLabel = ESPTypeLabel

    local ESPTypeBtn = Instance.new("TextButton")
    ESPTypeBtn.Size = UDim2.new(1, -16, 0, 14)
    ESPTypeBtn.Position = UDim2.new(0, 8, 0, yPos + 15)
    ESPTypeBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 55)
    ESPTypeBtn.TextColor3 = Color3.fromRGB(120, 160, 255)
    ESPTypeBtn.Text = "BOX / CIRCLE"
    ESPTypeBtn.Font = Enum.Font.Gotham
    ESPTypeBtn.TextSize = 7
    ESPTypeBtn.Parent = MainContent

    ESPTypeBtn.MouseButton1Click:Connect(function()
        CONFIG.ESPType = (CONFIG.ESPType == "BOX") and "CIRCLE" or "BOX"
        UpdateUIStatus()
    end)
    yPos = yPos + 33

    -- ✅ SLIDERS EMBAIXO DO AIMBOT
    UIElements.SmoothLabel = Instance.new("TextLabel")
    UIElements.SmoothLabel.Size = UDim2.new(1, -16, 0, 12)
    UIElements.SmoothLabel.Position = UDim2.new(0, 8, 0, yPos)
    UIElements.SmoothLabel.BackgroundTransparency = 1
    UIElements.SmoothLabel.TextColor3 = Color3.fromRGB(140, 140, 160)
    UIElements.SmoothLabel.Text = "Smooth: 0.75"
    UIElements.SmoothLabel.Font = Enum.Font.Gotham
    UIElements.SmoothLabel.TextSize = 7
    UIElements.SmoothLabel.Parent = MainContent

    local SmoothSlider = Instance.new("TextBox")
    SmoothSlider.Size = UDim2.new(1, -16, 0, 14)
    SmoothSlider.Position = UDim2.new(0, 8, 0, yPos + 13)
    SmoothSlider.BackgroundColor3 = Color3.fromRGB(35, 35, 55)
    SmoothSlider.TextColor3 = Color3.fromRGB(120, 160, 255)
    SmoothSlider.Text = string.format("%.2f", CONFIG.AimbotSmoothing)
    SmoothSlider.Font = Enum.Font.Gotham
    SmoothSlider.TextSize = 8
    SmoothSlider.Parent = MainContent

    SmoothSlider.FocusLost:Connect(function()
        local value = tonumber(SmoothSlider.Text)
        if value then
            CONFIG.AimbotSmoothing = math.clamp(value, 0.1, 1.0)
            SmoothSlider.Text = string.format("%.2f", CONFIG.AimbotSmoothing)
            UpdateUIStatus()
        end
    end)
    yPos = yPos + 30

    UIElements.FOVLabel = Instance.new("TextLabel")
    UIElements.FOVLabel.Size = UDim2.new(1, -16, 0, 12)
    UIElements.FOVLabel.Position = UDim2.new(0, 8, 0, yPos)
    UIElements.FOVLabel.BackgroundTransparency = 1
    UIElements.FOVLabel.TextColor3 = Color3.fromRGB(140, 140, 160)
    UIElements.FOVLabel.Text = "FOV: 80"
    UIElements.FOVLabel.Font = Enum.Font.Gotham
    UIElements.FOVLabel.TextSize = 7
    UIElements.FOVLabel.Parent = MainContent

    local FOVSlider = Instance.new("TextBox")
    FOVSlider.Size = UDim2.new(1, -16, 0, 14)
    FOVSlider.Position = UDim2.new(0, 8, 0, yPos + 13)
    FOVSlider.BackgroundColor3 = Color3.fromRGB(35, 35, 55)
    FOVSlider.TextColor3 = Color3.fromRGB(120, 160, 255)
    FOVSlider.Text = tostring(CONFIG.FOVRadius)
    FOVSlider.Font = Enum.Font.Gotham
    FOVSlider.TextSize = 8
    FOVSlider.Parent = MainContent

    FOVSlider.FocusLost:Connect(function()
        local value = tonumber(FOVSlider.Text)
        if value then
            CONFIG.FOVRadius = math.clamp(value, 10, 500)
            FOVSlider.Text = tostring(CONFIG.FOVRadius)
            UpdateUIStatus()
        end
    end)
    yPos = yPos + 30

    -- ✅ CAMERA FOV SLIDER
    UIElements.CameraFOVLabel = Instance.new("TextLabel")
    UIElements.CameraFOVLabel.Size = UDim2.new(1, -16, 0, 12)
    UIElements.CameraFOVLabel.Position = UDim2.new(0, 8, 0, yPos)
    UIElements.CameraFOVLabel.BackgroundTransparency = 1
    UIElements.CameraFOVLabel.TextColor3 = Color3.fromRGB(140, 140, 160)
    UIElements.CameraFOVLabel.Text = "Cam FOV: 70"
    UIElements.CameraFOVLabel.Font = Enum.Font.Gotham
    UIElements.CameraFOVLabel.TextSize = 7
    UIElements.CameraFOVLabel.Parent = MainContent

    local CameraFOVSlider = Instance.new("TextBox")
    CameraFOVSlider.Size = UDim2.new(1, -16, 0, 14)
    CameraFOVSlider.Position = UDim2.new(0, 8, 0, yPos + 13)
    CameraFOVSlider.BackgroundColor3 = Color3.fromRGB(35, 35, 55)
    CameraFOVSlider.TextColor3 = Color3.fromRGB(120, 160, 255)
    CameraFOVSlider.Text = tostring(CONFIG.CameraFOV)
    CameraFOVSlider.Font = Enum.Font.Gotham
    CameraFOVSlider.TextSize = 8
    CameraFOVSlider.Parent = MainContent

    CameraFOVSlider.FocusLost:Connect(function()
        local value = tonumber(CameraFOVSlider.Text)
        if value then
            CONFIG.CameraFOV = math.clamp(value, 1, 120)
            CameraFOVSlider.Text = tostring(CONFIG.CameraFOV)
            StartCameraFOV()
            UpdateUIStatus()
        end
    end)
    yPos = yPos + 30

    -- ✅ RESTO DOS BOTÕES
    local TeamCheckLabel, TeamCheckButton = CreateButton("🛡 TEAMCHECK", yPos)
    UIElements.TeamCheckLabel = TeamCheckButton
    TeamCheckButton.MouseButton1Click:Connect(function()
        CONFIG.TeamCheckEnabled = not CONFIG.TeamCheckEnabled
        UpdateUIStatus()
    end)
    yPos = yPos + 26

    local HitboxLabel, HitboxButton = CreateButton("📦 HEAD HITBOX", yPos)
    UIElements.HitboxExpanderLabel = HitboxButton
    HitboxButton.MouseButton1Click:Connect(function()
        CONFIG.HitboxExpanderEnabled = not CONFIG.HitboxExpanderEnabled
        if CONFIG.HitboxExpanderEnabled then StartHitboxExpander() else StopHitboxExpander() end
        UpdateUIStatus()
    end)
    yPos = yPos + 26

    local WalkspeedLabel, WalkspeedButton = CreateButton("🏃 WALKSPEED", yPos)
    UIElements.WalkSpeedLabel = WalkspeedButton
    WalkspeedButton.MouseButton1Click:Connect(function()
        CONFIG.WalkSpeedEnabled = not CONFIG.WalkSpeedEnabled
        if CONFIG.WalkSpeedEnabled then StartWalkSpeed() else StopWalkSpeed() end
        UpdateUIStatus()
    end)
    yPos = yPos + 26

    local FPSLabel, FPSButton = CreateButton("📊 FPS", yPos)
    UIElements.FPSCounterLabel = FPSButton
    FPSButton.MouseButton1Click:Connect(function()
        CONFIG.FPSCounterEnabled = not CONFIG.FPSCounterEnabled
        CreateFPSDisplay()
        if CONFIG.FPSCounterEnabled then StartFPSCounter() else StopFPSCounter() end
        UpdateUIStatus()
    end)
    yPos = yPos + 26

    local HumLabel, HumButton = CreateButton("🤖 HUMANIZE", yPos)
    UIElements.DetectionAvoidanceLabel = HumButton
    HumButton.MouseButton1Click:Connect(function()
        CONFIG.DetectionAvoidanceEnabled = not CONFIG.DetectionAvoidanceEnabled
        UpdateUIStatus()
    end)
    yPos = yPos + 26

    UIElements.WalkSpeedSliderLabel = Instance.new("TextLabel")
    UIElements.WalkSpeedSliderLabel.Size = UDim2.new(1, -16, 0, 12)
    UIElements.WalkSpeedSliderLabel.Position = UDim2.new(0, 8, 0, yPos)
    UIElements.WalkSpeedSliderLabel.BackgroundTransparency = 1
    UIElements.WalkSpeedSliderLabel.TextColor3 = Color3.fromRGB(140, 140, 160)
    UIElements.WalkSpeedSliderLabel.Text = "Speed: 16"
    UIElements.WalkSpeedSliderLabel.Font = Enum.Font.Gotham
    UIElements.WalkSpeedSliderLabel.TextSize = 7
    UIElements.WalkSpeedSliderLabel.Parent = MainContent

    local WalkSpeedSlider = Instance.new("TextBox")
    WalkSpeedSlider.Size = UDim2.new(1, -16, 0, 14)
    WalkSpeedSlider.Position = UDim2.new(0, 8, 0, yPos + 13)
    WalkSpeedSlider.BackgroundColor3 = Color3.fromRGB(35, 35, 55)
    WalkSpeedSlider.TextColor3 = Color3.fromRGB(120, 160, 255)
    WalkSpeedSlider.Text = tostring(CONFIG.WalkSpeed)
    WalkSpeedSlider.Font = Enum.Font.Gotham
    WalkSpeedSlider.TextSize = 8
    WalkSpeedSlider.Parent = MainContent

    WalkSpeedSlider.FocusLost:Connect(function()
        local value = tonumber(WalkSpeedSlider.Text)
        if value then
            CONFIG.WalkSpeed = math.clamp(value, 1, 100)
            WalkSpeedSlider.Text = tostring(CONFIG.WalkSpeed)
            UpdateUIStatus()
        end
    end)

    -- ✅ MINIMIZE
    MinimizeBtn.MouseButton1Click:Connect(function()
        UIMinimized = not UIMinimized
        MainContent.Visible = not UIMinimized
        MinimizeBtn.Text = UIMinimized and "+" or "−"
        MainFrame.Size = UIMinimized and UDim2.new(0, 240, 0, 32) or UDim2.new(0, 240, 0, 380)
    end)

    -- ✅ CLOSE
    CloseBtn.MouseButton1Click:Connect(function()
        pcall(function()
            MainUI:Destroy()
        end)
        StopAimbot()
        StopHitboxExpander()
        StopWalkSpeed()
        StopESP()
        StopFPSCounter()
        StopCameraFOV()
        collectgarbage("collect")
    end)

    -- ✅ HOTKEY SYSTEM
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end

        if input.KeyCode == HotKeys.Aimbot then
            CONFIG.AimbotEnabled = not CONFIG.AimbotEnabled
            if CONFIG.AimbotEnabled then StartAimbot() else StopAimbot() end
            UpdateUIStatus()
        elseif input.KeyCode == HotKeys.ESP then
            CONFIG.ESPEnabled = not CONFIG.ESPEnabled
            if CONFIG.ESPEnabled then StartESP() else StopESP() end
            UpdateUIStatus()
        elseif input.KeyCode == HotKeys.Teamcheck then
            CONFIG.TeamCheckEnabled = not CONFIG.TeamCheckEnabled
            UpdateUIStatus()
        elseif input.KeyCode == HotKeys.Hitbox then
            CONFIG.HitboxExpanderEnabled = not CONFIG.HitboxExpanderEnabled
            if CONFIG.HitboxExpanderEnabled then StartHitboxExpander() else StopHitboxExpander() end
            UpdateUIStatus()
        elseif input.KeyCode == HotKeys.Walkspeed then
            CONFIG.WalkSpeedEnabled = not CONFIG.WalkSpeedEnabled
            if CONFIG.WalkSpeedEnabled then StartWalkSpeed() else StopWalkSpeed() end
            UpdateUIStatus()
        end
    end)

    UpdateUIStatus()
    CreateFPSDisplay()
    StartESP()
    StartCameraFOV()
end


CreateUI()
