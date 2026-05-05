-- ============================================================
-- PROJECTION SORCERY: COMPLETE REWORK
-- ============================================================

-- [ SERVICES ]
local RunService   = game:GetService("RunService")
local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local CoreGui      = game:GetService("CoreGui")
local Debris       = game:GetService("Debris")

local localPlayer = Players.LocalPlayer

-- [ CONFIGURATION ]
local CONFIG = {
    RNG_CHANCE          = 0.40, -- 40% chance to activate
    PREDICTION_FRAMES   = 24,   -- Number of clones
    MIRROR_LIFESPAN     = 0.8,  -- Lifespan of clones
    SUCCESS_HITS_NEEDED = 6,    -- Hits for success
    WAVE_INTERVAL       = 3.0,  -- Interval between waves
    
    COLORS = {
        GREEN     = Color3.fromRGB(80, 255, 120),
        YELLOW    = Color3.fromRGB(255, 210, 50),
        RED       = Color3.fromRGB(255, 70, 70),
        PURPLE    = Color3.fromRGB(180, 100, 255),
        CYAN      = Color3.fromRGB(0, 220, 255),
        DARK_BLUE = Color3.fromRGB(0, 0, 139),
    }
}

-- [ UI SETUP ]
if CoreGui:FindFirstChild("ProjectionSorceryUI") then 
    CoreGui.ProjectionSorceryUI:Destroy() 
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ProjectionSorceryUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true 
screenGui.Parent = CoreGui

local function createBeautifulLabel(name, position, size, color)
    local label = Instance.new("TextLabel")
    label.Name = name
    label.Position = position
    label.Size = size
    label.BackgroundTransparency = 1 -- Invisible Background
    label.TextColor3 = color
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.TextStrokeTransparency = 0.5
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.RichText = true -- Enable beautiful text options
    label.Parent = screenGui
    return label
end

local fpsLabel = createBeautifulLabel("FPSLabel", UDim2.new(0, 20, 0, 20), UDim2.new(0, 120, 0, 30), Color3.new(1, 1, 1))
local pingLabel = createBeautifulLabel("PingLabel", UDim2.new(0, 20, 0, 50), UDim2.new(0, 120, 0, 30), Color3.new(1, 1, 1))
local modeLabel = createBeautifulLabel("ModeLabel", UDim2.new(0, 20, 0, 85), UDim2.new(0, 300, 0, 30), CONFIG.COLORS.PURPLE)
local infoLabel = createBeautifulLabel("InfoLabel", UDim2.new(0, 20, 0, 115), UDim2.new(0, 400, 0, 25), CONFIG.COLORS.CYAN)

modeLabel.Text = "A aguardar..."
infoLabel.Text = ""

-- [ STATE ]
local state = {
    projecaoActive = false,
    rngDone        = false,
    waveTimer      = 0,
    fpsBuffer      = table.create(30, 0),
    fpsIdx         = 0,
    fpsSum         = 0,
    fpsUpdateTimer = 0,
    playerHistory  = {}, -- Store history for enhanced prediction
    activeWaves    = {}  -- Store active waves for spatial hit detection
}

-- [ UTILITIES ]

local function updatePlayerHistory(dt)
    for _, player in ipairs(Players:GetPlayers()) do
        if player == localPlayer then continue end
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            if not state.playerHistory[player.UserId] then
                state.playerHistory[player.UserId] = {
                    lastPos = hrp.Position,
                    velocityHistory = {}
                }
            end
            local hist = state.playerHistory[player.UserId]
            local currentVel = (hrp.Position - hist.lastPos) / dt
            table.insert(hist.velocityHistory, 1, currentVel)
            if #hist.velocityHistory > 10 then table.remove(hist.velocityHistory) end
            hist.lastPos = hrp.Position
        end
    end
end

local function getSmoothedVelocity(userId)
    local hist = state.playerHistory[userId]
    if not hist or #hist.velocityHistory == 0 then return Vector3.zero end
    local sum = Vector3.zero
    for _, v in ipairs(hist.velocityHistory) do
        sum += v
    end
    return sum / #hist.velocityHistory
end

-- Object Pool State
local pool = {
    available = {},
    active = {},
    MAX_SIZE = CONFIG.PREDICTION_FRAMES * 5
}

local function getFromPool()
    local clone = table.remove(pool.available)
    if clone then
        table.insert(pool.active, clone)
        clone.Parent = workspace
    end
    return clone
end

local function releaseToPool(clone)
    for i, v in ipairs(pool.active) do
        if v == clone then
            table.remove(pool.active, i)
            break
        end
    end
    clone.Parent = nil
    table.insert(pool.available, clone)
end

-- Improved shatterAndRelease for pooling
local function shatterAndRelease(cloneModel)
    if not cloneModel then return end
    
    local tweenDuration = 0.5
    local tweenInfo = TweenInfo.new(tweenDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local partsToReset = {}

    for _, part in ipairs(cloneModel:GetDescendants()) do
        if part:IsA("BasePart") then
            if part.Name == "HumanoidRootPart" then continue end
            
            table.insert(partsToReset, {
                part = part,
                originalSize = part.Size,
                originalTransparency = part.Transparency,
                originalColor = part.Color
            })

            local explodeOffset = Vector3.new(math.random(-10, 10), math.random(5, 20), math.random(-10, 10))
            local targetCFrame = part.CFrame + explodeOffset

            TweenService:Create(part, tweenInfo, {
                CFrame = targetCFrame,
                Size = Vector3.new(0.1, 0.1, 0.1),
                Transparency = 1
            }):Play()
        end
    end

    task.delay(tweenDuration, function()
        for _, data in ipairs(partsToReset) do
            data.part.Size = data.originalSize
            data.part.Transparency = data.originalTransparency
            data.part.Color = data.originalColor
        end
        releaseToPool(cloneModel)
    end)
end

-- Lightweight template creator
local function createLightweightTemplate(character)
    character.Archivable = true
    local template = character:Clone()
    character.Archivable = false

    for _, child in ipairs(template:GetDescendants()) do
        if child:IsA("Accessory") or child:IsA("Clothing") or child:IsA("ShirtGraphic") or child:IsA("Decal") or child:IsA("Script") or child:IsA("LocalScript") or child:IsA("Sound") or child:IsA("ParticleEmitter") then
            child:Destroy()
        elseif child:IsA("BasePart") then
            child.Anchored = true
            child.CanCollide = false
            child.CastShadow = false
            child.Material = Enum.Material.Neon
            child.Color = CONFIG.COLORS.CYAN -- Changed to CYAN for visibility
            child.Transparency = 0.4 -- Reduced transparency
        end
    end

    if template:FindFirstChild("Humanoid") then
        template.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        template.Humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
    end

    return template
end

-- Initialize pool
local function initializePool(templateChar)
    local template = createLightweightTemplate(templateChar)
    for i = 1, pool.MAX_SIZE do
        local clone = template:Clone()
        clone.Name = "PooledClone"
        clone.Parent = nil
        table.insert(pool.available, clone)
    end
    template:Destroy()
end

-- Pose application
local function applyFakePose(clone, isJumping, frameIndex)
    local rShoulder = clone:FindFirstChild("Right Shoulder", true) or clone:FindFirstChild("RightShoulder", true)
    local lShoulder = clone:FindFirstChild("Left Shoulder", true) or clone:FindFirstChild("LeftShoulder", true)
    local rHip = clone:FindFirstChild("Right Hip", true) or clone:FindFirstChild("RightHip", true)
    local lHip = clone:FindFirstChild("Left Hip", true) or clone:FindFirstChild("LeftHip", true)

    if isJumping then
        if rShoulder then rShoulder.C0 = rShoulder.C0 * CFrame.Angles(math.rad(120), 0, 0) end
        if lShoulder then lShoulder.C0 = lShoulder.C0 * CFrame.Angles(math.rad(120), 0, 0) end
    else
        local walkCycle = math.sin((frameIndex / CONFIG.PREDICTION_FRAMES) * math.pi * 6) * 0.6
        if rHip then rHip.C0 = rHip.C0 * CFrame.Angles(walkCycle, 0, 0) end
        if lHip then lHip.C0 = lHip.C0 * CFrame.Angles(-walkCycle, 0, 0) end
        if rShoulder then rShoulder.C0 = rShoulder.C0 * CFrame.Angles(-walkCycle * 0.5, 0, 0) end
        if lShoulder then lShoulder.C0 = lShoulder.C0 * CFrame.Angles(walkCycle * 0.5, 0, 0) end
    end
end

-- [ PREDICTION LOGIC ]

local function triggerProjectionWave()
    for _, targetPlayer in ipairs(Players:GetPlayers()) do
        if targetPlayer == localPlayer then continue end

        local sourceChar = targetPlayer.Character
        local hrp = sourceChar and sourceChar:FindFirstChild("HumanoidRootPart")
        local hum = sourceChar and sourceChar:FindFirstChild("Humanoid")
        
        if not hrp or not hum or hum.Health <= 0 then continue end

        local startPos = hrp.Position
        local smoothedVel = getSmoothedVelocity(targetPlayer.UserId)
        local isJumping = hum.FloorMaterial == Enum.Material.Air
        
        -- PREVISÃO COM JOGADOR PARADO: Se a velocidade for muito baixa, forçamos um vetor para a frente
        local predVel = smoothedVel
        if smoothedVel.Magnitude < 1 then
            local walkSpeed = (hum.WalkSpeed > 0) and hum.WalkSpeed or 16
            predVel = hrp.CFrame.LookVector * walkSpeed
        end

        local activeClones = {}
        for i = 1, CONFIG.PREDICTION_FRAMES do
            local t = (i / CONFIG.PREDICTION_FRAMES) * CONFIG.MIRROR_LIFESPAN
            local gravity = isJumping and Vector3.new(0, -workspace.Gravity, 0) or Vector3.zero
            local predictedPos = startPos + (predVel * t) + (0.5 * gravity * (t * t))
            
            local clone = getFromPool()
            if not clone then continue end
            
            local cloneHrp = clone:FindFirstChild("HumanoidRootPart")
            if not cloneHrp then releaseToPool(clone); continue end

            table.insert(activeClones, clone)
            cloneHrp.CFrame = CFrame.new(predictedPos, predictedPos + predVel.Unit)
            applyFakePose(clone, isJumping, i)
            
            -- HITBOX SETUP (for spatial query)
            cloneHrp.Size = Vector3.new(4, 6, 4) -- Large hitbox
            cloneHrp.Transparency = 1 
        end

        local waveData = {
            targetPlayer = targetPlayer,
            clones = activeClones,
            hitCount = 0,
            touchedIndexes = {},
            isSuccessTriggered = false,
            expireTime = os.clock() + CONFIG.MIRROR_LIFESPAN
        }
        table.insert(state.activeWaves, waveData)
        
        task.delay(CONFIG.MIRROR_LIFESPAN, function()
            for _, clone in ipairs(activeClones) do
                shatterAndRelease(clone)
            end
            
            if infoLabel.Text ~= "" then
                task.delay(1.5, function() infoLabel.Text = "" end)
            end
        end)
    end
end

-- [ INITIALIZATION ]

task.spawn(function()
    local char = localPlayer.Character or localPlayer.CharacterAdded:Wait()
    initializePool(char)
end)


    -- [ MAIN LOOP ]

RunService.RenderStepped:Connect(function(dt)
    updatePlayerHistory(dt) -- Update player movement history
    
    -- Spatial Hit Detection for Active Waves
    for i = #state.activeWaves, 1, -1 do
        local wave = state.activeWaves[i]
        if os.clock() > wave.expireTime then
            table.remove(state.activeWaves, i)
            continue
        end
        
        if wave.isSuccessTriggered then continue end

        local targetChar = wave.targetPlayer.Character
        local targetHrp = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
        if not targetHrp then continue end

        for idx, clone in ipairs(wave.clones) do
            if wave.touchedIndexes[idx] then continue end
            
            local cloneHrp = clone:FindFirstChild("HumanoidRootPart")
            if not cloneHrp then continue end

            -- Efficient spatial check: Is target within clone's expanded hitbox?
            local diff = (targetHrp.Position - cloneHrp.Position)
            if math.abs(diff.X) < cloneHrp.Size.X/2 and math.abs(diff.Y) < cloneHrp.Size.Y/2 and math.abs(diff.Z) < cloneHrp.Size.Z/2 then
                wave.touchedIndexes[idx] = true
                wave.hitCount += 1
                
                -- Feedback visual
                for _, p in ipairs(clone:GetChildren()) do
                    if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
                        p.Color = CONFIG.COLORS.PURPLE
                    end
                end
                
                if wave.hitCount >= CONFIG.SUCCESS_HITS_NEEDED then
                    wave.isSuccessTriggered = true
                    infoLabel.Text = "★ PREVISÃO DE SUCESSO: " .. wave.targetPlayer.Name .. " ★"
                    infoLabel.TextColor3 = CONFIG.COLORS.GREEN
                end
            end
        end
    end

    -- FPS Counter Logic
    state.fpsIdx = state.fpsIdx % 30 + 1
    state.fpsSum = state.fpsSum - state.fpsBuffer[state.fpsIdx] + (1 / dt)
    state.fpsBuffer[state.fpsIdx] = 1 / dt
    
    state.fpsUpdateTimer += dt
    if state.fpsUpdateTimer >= 0.5 then
        state.fpsUpdateTimer = 0
        local avgFps = math.floor(state.fpsSum / 30)
        fpsLabel.TextColor3 = avgFps >= 55 and CONFIG.COLORS.GREEN or avgFps >= 30 and CONFIG.COLORS.YELLOW or CONFIG.COLORS.RED
        fpsLabel.Text = "FPS: " .. avgFps
        
        -- Ping Counter Logic (Updated every 0.5s with FPS)
        local ping = math.floor(localPlayer:GetNetworkPing() * 1000)
        pingLabel.Text = "Ping: " .. ping .. "ms"
        pingLabel.TextColor3 = ping < 100 and CONFIG.COLORS.GREEN or ping < 200 and CONFIG.COLORS.YELLOW or CONFIG.COLORS.RED
    end

    -- Projection Wave Logic
    if state.projecaoActive then
        state.waveTimer += dt
        if state.waveTimer >= CONFIG.WAVE_INTERVAL then 
            state.waveTimer = 0
            triggerProjectionWave()
        end
    end
end)
