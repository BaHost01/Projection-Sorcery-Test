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
    RNG_CHANCE          = 1.00, -- Set to 100% for verification
    PREDICTION_FRAMES   = 24,   
    MIRROR_LIFESPAN     = 0.8,  
    SUCCESS_HITS_NEEDED = 6,    
    WAVE_INTERVAL       = 3.0,  
    ABILITY_DURATION    = 5.0,  
    MEMORY_FILE         = "PredictionsMemory.txt",
    DEBUG_MODE          = true, -- Enable detailed console logging

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
local function getSafeParent()
    local success, _ = pcall(function() return CoreGui.Name end)
    if success then return CoreGui end
    return localPlayer:WaitForChild("PlayerGui")
end

local safeParent = getSafeParent()

if safeParent:FindFirstChild("ProjectionSorceryUI") then 
    safeParent.ProjectionSorceryUI:Destroy() 
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ProjectionSorceryUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true 
screenGui.Parent = safeParent

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
    projecaoActive   = false,
    abilityStartTime = 0,
    rngDone          = false,
    waveTimer        = 0,
    fpsBuffer        = table.create(30, 0),
    fpsIdx           = 0,
    fpsSum           = 0,
    fpsUpdateTimer   = 0,
    playerHistory  = {}, -- Store history for enhanced prediction
    activeWaves    = {}, -- Store active waves for spatial hit detection
    memoryLoaded   = false
    }

    -- [ PERSISTENCE & UTILITIES ]

    local HttpService = game:GetService("HttpService")

    local function logDebug(...)
        if CONFIG.DEBUG_MODE then
            print("[PROJECTION DEBUG]", ...)
        end
    end

    local function saveMemory()
        logDebug("Saving memory...")
        local data = {}
        for userId, hist in pairs(state.playerHistory) do
            if #hist.velocityHistory > 5 then
                data[tostring(userId)] = {
                    lastPos = {hist.lastPos.X, hist.lastPos.Y, hist.lastPos.Z}
                }
            end
        end

        local success, encoded = pcall(function() return HttpService:JSONEncode(data) end)
        if success and typeof(writefile) == "function" then
            local writeSuccess, err = pcall(function() writefile(CONFIG.MEMORY_FILE, encoded) end)
            if writeSuccess then
                logDebug("Memory saved successfully.")
            else
                logDebug("Failed to write memory file:", err)
            end
        else
            logDebug("JSON Encode failed or writefile unavailable.")
        end
    end

    local function loadMemory()
        logDebug("Loading memory...")
        if typeof(readfile) == "function" and typeof(isfile) == "function" then
            local exists = false
            pcall(function() exists = isfile(CONFIG.MEMORY_FILE) end)

            if exists then
                local success, content = pcall(function() return readfile(CONFIG.MEMORY_FILE) end)
                if success then
                    local s, decoded = pcall(function() return HttpService:JSONDecode(content) end)
                    if s then
                        for userIdStr, data in pairs(decoded) do
                            local userId = tonumber(userIdStr)
                            state.playerHistory[userId] = {
                                lastPos = Vector3.new(data.lastPos[1], data.lastPos[2], data.lastPos[3]),
                                velocityHistory = {}
                            }
                        end
                        state.memoryLoaded = true
                        logDebug("Memory loaded successfully. Targets tracked:", #state.playerHistory)
                    else
                        logDebug("JSON Decode failed for memory file.")
                    end
                else
                    logDebug("Failed to read memory file.")
                end
            else
                logDebug("Memory file does not exist.")
            end
        else
            logDebug("readfile/isfile not supported by executor.")
        end
    end

    local function notify(title, text, color)
    task.spawn(function()
        local originalText = infoLabel.Text
        local originalColor = infoLabel.TextColor3

        infoLabel.Text = "<b>[" .. title:upper() .. "]</b> " .. text
        infoLabel.TextColor3 = color or CONFIG.COLORS.CYAN

        task.wait(3)
        if infoLabel.Text == "<b>[" .. title:upper() .. "]</b> " .. text then
            infoLabel.Text = originalText
            infoLabel.TextColor3 = originalColor
        end
    end)
    end

    -- [ UTILITIES ]


local function updatePlayerHistory(dt)
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= localPlayer then
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
        logDebug("Clone retrieved from pool. Remaining available:", #pool.available)
    else
        logDebug("Pool empty! No clones available.")
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
    logDebug("Clone released to pool. Current available:", #pool.available)
end

-- Improved shatterAndRelease for pooling
local function shatterAndRelease(cloneModel)
    if not cloneModel then return end
    logDebug("Shattering clone...")
    
    local tweenDuration = 0.5
    local tweenInfo = TweenInfo.new(tweenDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    for _, part in ipairs(cloneModel:GetDescendants()) do
        if part:IsA("BasePart") then
            if part.Name == "HumanoidRootPart" then continue end
            
            local explodeOffset = Vector3.new(math.random(-10, 10), math.random(5, 20), math.random(-10, 10))
            local targetCFrame = part.CFrame + explodeOffset

            TweenService:Create(part, tweenInfo, {
                CFrame = targetCFrame,
                Size = Vector3.new(0.1, 0.1, 0.1),
                Transparency = 1
            }):Play()
        end
    end

    task.delay(tweenDuration + 0.05, function()
        releaseToPool(cloneModel)
    end)
end

-- Lightweight template creator
local function createLightweightTemplate(character)
    if not character then return nil end
    character.Archivable = true
    local success, template = pcall(function() return character:Clone() end)
    character.Archivable = false
    
    if not success or not template then return nil end

    for _, child in ipairs(template:GetDescendants()) do
        if child:IsA("Accessory") or child:IsA("Clothing") or child:IsA("ShirtGraphic") or child:IsA("Decal") or child:IsA("Script") or child:IsA("LocalScript") or child:IsA("Sound") or child:IsA("ParticleEmitter") then
            child:Destroy()
        elseif child:IsA("BasePart") then
            child.Anchored = true
            child.CanCollide = false
            child.CastShadow = false
            child.Material = Enum.Material.Neon
            child.Color = CONFIG.COLORS.CYAN
            child.Transparency = 0.4
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
    if not template then return end
    
    for i = 1, pool.MAX_SIZE do
        local clone = template:Clone()
        clone.Name = "PooledClone"
        clone.Parent = nil
        table.insert(pool.available, clone)
    end
    template:Destroy()
end

-- Reset clone state before reuse
local function resetClone(clone)
    for _, part in ipairs(clone:GetDescendants()) do
        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
            part.Size = Vector3.new(1, 2, 1) -- Approximated standard part size, will be refined if needed
            part.Transparency = 0.4
            part.Color = CONFIG.COLORS.CYAN
        end
    end
    -- Specifically reset HRP
    local hrp = clone:FindFirstChild("HumanoidRootPart")
    if hrp then
        hrp.Size = Vector3.new(2, 2, 1)
        hrp.Transparency = 1
    end
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
    logDebug("Triggering Projection Wave...")
    for _, targetPlayer in ipairs(Players:GetPlayers()) do
        if targetPlayer ~= localPlayer then
            local sourceChar = targetPlayer.Character
            local hrp = sourceChar and sourceChar:FindFirstChild("HumanoidRootPart")
            local hum = sourceChar and sourceChar:FindFirstChild("Humanoid")
            
            if hrp and hum and hum.Health > 0 then 
                logDebug("Generating path for:", targetPlayer.Name)
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
                    if clone then
                        resetClone(clone) -- Ensure clone is in a clean state
                        
                        local cloneHrp = clone:FindFirstChild("HumanoidRootPart")
                        if cloneHrp then
                            table.insert(activeClones, clone)
                            
                            -- SAFETY: Avoid NaN by ensuring predVel is not zero
                            local targetLook = predVel.Magnitude > 0.01 and predVel.Unit or hrp.CFrame.LookVector
                            cloneHrp.CFrame = CFrame.new(predictedPos, predictedPos + targetLook)
                            applyFakePose(clone, isJumping, i)
                            
                            -- HITBOX SETUP (for spatial query)
                            cloneHrp.Size = Vector3.new(4, 6, 4) -- Large hitbox
                            cloneHrp.Transparency = 1 
                        else
                            releaseToPool(clone)
                        end
                    end
                end

                logDebug("Wave clones deployed:", #activeClones)
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
                    logDebug("Wave expired for player:", targetPlayer.Name)
                    for _, clone in ipairs(activeClones) do
                        shatterAndRelease(clone)
                    end
                    
                    if infoLabel.Text ~= "" then
                        task.delay(1.5, function() infoLabel.Text = "" end)
                    end
                end)
            else
                logDebug("Target invalid for player:", targetPlayer.Name)
            end
        end
    end
end

-- [ INITIALIZATION ]

task.spawn(function()
    logDebug("Starting Initialization...")
    pcall(loadMemory)
    notify("System", "Memory loaded successfully", CONFIG.COLORS.GREEN)
    
    local function init()
        logDebug("Waiting for local character...")
        local char = localPlayer.Character or localPlayer.CharacterAdded:Wait()
        logDebug("Character found, initializing pool...")
        initializePool(char)
        notify("System", "Pool Initialized", CONFIG.COLORS.GREEN)
        logDebug("Pool Initialization Complete.")
    end
    
    -- Ensure pool initializes even if first attempt fails
    local success, err = pcall(init)
    if not success then
        logDebug("Pool Init Failed Error:", tostring(err))
        -- Try one more time after a short delay
        task.delay(5, function() 
            logDebug("Retrying pool initialization...")
            pcall(init) 
        end)
    end
end)

-- Save memory every 60 seconds
task.spawn(function()
    while true do
        task.wait(60)
        saveMemory()
    end
end)

-- RNG Activation Logic (Restored and Upgraded)
task.delay(1, function()
    logDebug("Attempting RNG Activation...")
    if not state.rngDone then
        state.rngDone = true
        modeLabel.Text = "<i>Sorteando habilidade...</i>"
        modeLabel.TextColor3 = CONFIG.COLORS.YELLOW
        
        task.wait(1.5)
        
        local roll = math.random()
        local success = roll < CONFIG.RNG_CHANCE
        logDebug("RNG Roll:", roll, "Target:", CONFIG.RNG_CHANCE, "Success:", success)
        
        if success then
            state.projecaoActive = true
            state.abilityStartTime = os.clock()
            modeLabel.Text = "<b>◈ ARTE DE PROJEÇÃO: ATIVA</b>"
            modeLabel.TextColor3 = CONFIG.COLORS.PURPLE
            
            notify("Ability", "Projection Sorcery Activated!", CONFIG.COLORS.PURPLE)
            logDebug("Ability Activated. Start Time:", state.abilityStartTime)
            
            -- Cool "Rainbow" effect for Active status
            task.spawn(function()
                while state.projecaoActive do
                    for i = 0, 1, 0.01 do
                        if not state.projecaoActive then break end
                        modeLabel.TextColor3 = Color3.fromHSV(i, 0.8, 1)
                        task.wait(0.05)
                    end
                end
            end)
            
            -- Auto-deactivate after 5 seconds
            task.delay(CONFIG.ABILITY_DURATION, function()
                if state.projecaoActive then
                    state.projecaoActive = false
                    modeLabel.Text = "<font color='#FF4646'>◈ ARTE DE PROJEÇÃO: EXPIRADA</font>"
                    task.delay(2, function() 
                        modeLabel.Text = "A aguardar..." 
                        modeLabel.TextColor3 = CONFIG.COLORS.PURPLE 
                    end)
                end
            end)
        else 
            modeLabel.Text = "<font color='#FF4646'>✗ FALHA NA ATIVAÇÃO</font>"
            task.delay(2, function() modeLabel.Text = "A aguardar..." end)
        end
    end
end)

-- [ MAIN LOOP ]

-- Helper to get ping without developer-only methods
local function getPing()
    -- localPlayer:GetNetworkPing() is often restricted or inaccurate in some environments.
    -- We can use a fallback or simply keep it if the environment supports it, 
    -- but let's use a safer check.
    local success, ping = pcall(function() return localPlayer:GetNetworkPing() end)
    return success and math.floor(ping * 1000) or 0
end

RunService.RenderStepped:Connect(function(dt)
    updatePlayerHistory(dt) -- Update player movement history
    
    -- Spatial Hit Detection for Active Waves
    for i = #state.activeWaves, 1, -1 do
        local wave = state.activeWaves[i]
        if os.clock() > wave.expireTime then
            table.remove(state.activeWaves, i)
        else
            if not wave.isSuccessTriggered then
                local targetChar = wave.targetPlayer.Character
                local targetHrp = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
                
                if targetHrp then
                    for idx, clone in ipairs(wave.clones) do
                        if not wave.touchedIndexes[idx] then
                            local cloneHrp = clone:FindFirstChild("HumanoidRootPart")
                            if cloneHrp then
                                -- Efficient spatial check: Is target within clone's expanded hitbox?
                                local diff = (targetHrp.Position - cloneHrp.Position)
                                if math.abs(diff.X) < cloneHrp.Size.X/2 and math.abs(diff.Y) < cloneHrp.Size.Y/2 and math.abs(diff.Z) < cloneHrp.Size.Z/2 then
                                    logDebug("Spatial Hit Detected! Player:", wave.targetPlayer.Name, "Clone Index:", idx)
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
                                        
                                        -- Ability ends on success
                                        if state.projecaoActive then
                                            state.projecaoActive = false
                                            modeLabel.Text = "<font color='#50FF78'>◈ ARTE DE PROJEÇÃO: CONCLUÍDA</font>"
                                            task.delay(2, function() 
                                                modeLabel.Text = "A aguardar..." 
                                                modeLabel.TextColor3 = CONFIG.COLORS.PURPLE 
                                            end)
                                        end
                                    end
                                end
                            end
                        end
                    end
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
        local ping = getPing()
        pingLabel.Text = "Ping: " .. ping .. "ms"
        pingLabel.TextColor3 = (ping > 0 and ping < 100) and CONFIG.COLORS.GREEN or (ping >= 100 and ping < 200) and CONFIG.COLORS.YELLOW or CONFIG.COLORS.RED
        if ping == 0 then pingLabel.Text = "Ping: --" end
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
