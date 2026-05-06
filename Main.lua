-- ============================================================
-- PROJECTION SORCERY: COMPLETE REWORK (FIXED)
-- ============================================================

-- [ SERVICES ]
local RunService   = game:GetService("RunService")
local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local CoreGui      = game:GetService("CoreGui")
local Debris       = game:GetService("Debris")
local HttpService  = game:GetService("HttpService")

local localPlayer = Players.LocalPlayer

-- [ CONFIGURATION ]
local CONFIG = {
    RNG_CHANCE          = 1.00,
    PREDICTION_FRAMES   = 24,
    MIRROR_LIFESPAN     = 0.8,
    SUCCESS_HITS_NEEDED = 6,
    WAVE_INTERVAL       = 3.0,
    ABILITY_DURATION    = 5.0,
    MEMORY_FILE         = "PredictionsMemory.txt",
    DEBUG_MODE          = true,

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
    local ok = pcall(function() return CoreGui.Name end)
    return ok and CoreGui or localPlayer:WaitForChild("PlayerGui")
end

local safeParent = getSafeParent()
if safeParent:FindFirstChild("ProjectionSorceryUI") then
    safeParent.ProjectionSorceryUI:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "ProjectionSorceryUI"
screenGui.ResetOnSpawn   = false
screenGui.IgnoreGuiInset = true
screenGui.Parent         = safeParent

local function createLabel(name, pos, size, color)
    local lbl = Instance.new("TextLabel")
    lbl.Name                   = name
    lbl.Position               = pos
    lbl.Size                   = size
    lbl.BackgroundTransparency = 1
    lbl.TextColor3             = color
    lbl.TextScaled             = true
    lbl.Font                   = Enum.Font.GothamBold
    lbl.TextStrokeTransparency = 0.5
    lbl.TextStrokeColor3       = Color3.new(0, 0, 0)
    lbl.TextXAlignment         = Enum.TextXAlignment.Left
    lbl.RichText               = true
    lbl.Parent                 = screenGui
    return lbl
end

local fpsLabel  = createLabel("FPSLabel",  UDim2.new(0,20,0,20),  UDim2.new(0,120,0,30), Color3.new(1,1,1))
local pingLabel = createLabel("PingLabel", UDim2.new(0,20,0,50),  UDim2.new(0,120,0,30), Color3.new(1,1,1))
local modeLabel = createLabel("ModeLabel", UDim2.new(0,20,0,85),  UDim2.new(0,300,0,30), CONFIG.COLORS.PURPLE)
local infoLabel = createLabel("InfoLabel", UDim2.new(0,20,0,115), UDim2.new(0,400,0,25), CONFIG.COLORS.CYAN)

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
    playerHistory    = {},
    activeWaves      = {},
    memoryLoaded     = false,
}

-- ============================================================
-- TEMPLATE DATA
-- Stores per-part CFrame offsets, sizes, and joint C0s from
-- the original template so resetClone can fully reconstruct
-- every clone visually on each reuse from the pool.
-- This is the root fix for invisible clones.
-- ============================================================
local templateData = {
    partOffsets = {}, -- [partName]  = CFrame  (object-space from HRP)
    partSizes   = {}, -- [partName]  = Vector3 (original size)
    jointC0s    = {}, -- [jointName] = CFrame  (original C0)
}

-- [ DEBUG ]
local function logDebug(...)
    if CONFIG.DEBUG_MODE then print("[PROJECTION DEBUG]", ...) end
end

-- [ PERSISTENCE ]
local function saveMemory()
    local data = {}
    for userId, hist in pairs(state.playerHistory) do
        if #hist.velocityHistory > 5 then
            -- BUG FIX #6: save velocityHistory (was missing before)
            local velArr = {}
            for _, v in ipairs(hist.velocityHistory) do
                table.insert(velArr, {v.X, v.Y, v.Z})
            end
            data[tostring(userId)] = {
                lastPos         = {hist.lastPos.X, hist.lastPos.Y, hist.lastPos.Z},
                velocityHistory = velArr,
            }
        end
    end
    local ok, encoded = pcall(function() return HttpService:JSONEncode(data) end)
    if ok and typeof(writefile) == "function" then
        pcall(function() writefile(CONFIG.MEMORY_FILE, encoded) end)
        logDebug("Memory saved.")
    end
end

local function loadMemory()
    if typeof(readfile) ~= "function" or typeof(isfile) ~= "function" then
        logDebug("readfile/isfile not supported."); return
    end
    local exists = false
    pcall(function() exists = isfile(CONFIG.MEMORY_FILE) end)
    if not exists then logDebug("Memory file not found."); return end

    local ok, content = pcall(function() return readfile(CONFIG.MEMORY_FILE) end)
    if not ok then logDebug("Failed to read memory file."); return end

    local s, decoded = pcall(function() return HttpService:JSONDecode(content) end)
    if not s then logDebug("JSON decode failed."); return end

    local count = 0
    for userIdStr, data in pairs(decoded) do
        local userId  = tonumber(userIdStr)
        local velHist = {}
        -- BUG FIX #6: restore velocityHistory on load (was discarded before)
        if data.velocityHistory then
            for _, v in ipairs(data.velocityHistory) do
                table.insert(velHist, Vector3.new(v[1], v[2], v[3]))
            end
        end
        state.playerHistory[userId] = {
            lastPos         = Vector3.new(data.lastPos[1], data.lastPos[2], data.lastPos[3]),
            velocityHistory = velHist,
        }
        count += 1
    end
    state.memoryLoaded = true
    -- BUG FIX #5: was `#state.playerHistory` which always returns 0 on a dict
    logDebug("Memory loaded. Targets tracked:", count)
end

local function notify(title, text, color)
    task.spawn(function()
        local msg = "<b>[" .. title:upper() .. "]</b> " .. text
        infoLabel.Text       = msg
        infoLabel.TextColor3 = color or CONFIG.COLORS.CYAN
        task.wait(3)
        if infoLabel.Text == msg then
            infoLabel.Text       = ""
            infoLabel.TextColor3 = CONFIG.COLORS.CYAN
        end
    end)
end

-- [ PLAYER HISTORY / VELOCITY ]
local function updatePlayerHistory(dt)
    for _, player in ipairs(Players:GetPlayers()) do
        if player == localPlayer then continue end
        local char = player.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            if not state.playerHistory[player.UserId] then
                state.playerHistory[player.UserId] = {lastPos = hrp.Position, velocityHistory = {}}
            end
            local hist = state.playerHistory[player.UserId]
            local vel  = (hrp.Position - hist.lastPos) / dt
            table.insert(hist.velocityHistory, 1, vel)
            if #hist.velocityHistory > 10 then table.remove(hist.velocityHistory) end
            hist.lastPos = hrp.Position
        end
    end
end

local function getSmoothedVelocity(userId)
    local hist = state.playerHistory[userId]
    if not hist or #hist.velocityHistory == 0 then return Vector3.zero end
    local sum = Vector3.zero
    for _, v in ipairs(hist.velocityHistory) do sum += v end
    return sum / #hist.velocityHistory
end

-- [ OBJECT POOL ]
local pool = {
    available = {},
    active    = {},
    MAX_SIZE  = CONFIG.PREDICTION_FRAMES * 5,
}

local function getFromPool()
    local clone = table.remove(pool.available)
    if clone then
        clone.Parent = workspace
        table.insert(pool.active, clone)
    end
    return clone
end

local function releaseToPool(clone)
    for i, v in ipairs(pool.active) do
        if v == clone then table.remove(pool.active, i); break end
    end
    clone.Parent = nil
    table.insert(pool.available, clone)
end

-- ============================================================
-- BUG FIX #1: shatterAndRelease
--
-- OLD BEHAVIOUR: tweened the real pool clone's parts to
-- scattered CFrames + size 0.1, then returned the broken
-- clone to pool. On next reuse, HRP was repositioned but
-- body parts remained scattered across the world → invisible.
--
-- FIX: Clone the model for VFX BEFORE releasing (so the copy
-- has correct world CFrames). Release the real clone immediately
-- so it stays clean. Run shatter tween only on the disposable
-- copy, then let Debris destroy it.
-- ============================================================
local function shatterAndRelease(cloneModel)
    if not cloneModel then return end

    -- Snapshot correct world CFrames for VFX before we touch the clone
    cloneModel.Archivable = true
    local vfxCopy = cloneModel:Clone()
    cloneModel.Archivable = false

    -- Release real clone immediately — untouched, ready for reuse
    releaseToPool(cloneModel)

    if not vfxCopy then return end
    vfxCopy.Parent = workspace

    local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    for _, part in ipairs(vfxCopy:GetDescendants()) do
        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
            local offset = Vector3.new(math.random(-10,10), math.random(5,20), math.random(-10,10))
            TweenService:Create(part, tweenInfo, {
                CFrame       = part.CFrame + offset,
                Size         = Vector3.new(0.1, 0.1, 0.1),
                Transparency = 1,
            }):Play()
        end
    end

    -- Disposable VFX copy auto-cleaned after tween finishes
    Debris:AddItem(vfxCopy, 0.6)
end

-- ============================================================
-- BUG FIX #1 + #2: resetClone(clone, newHrpCFrame)
--
-- Now accepts the target HRP CFrame and:
--  • Positions HRP at the correct world location
--  • Repositions EVERY anchored body part using stored
--    template offsets  →  fixes scattered-parts invisibility
--  • Restores original part sizes from templateData
--    →  fixes hardcoded (1,2,1) for all parts
--  • Restores Motor6D C0s from templateData
--    →  prerequisite for fix #3 (clean pose base)
-- ============================================================
local function resetClone(clone, newHrpCFrame)
    local hrp = clone:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    hrp.CFrame       = newHrpCFrame
    hrp.Size         = Vector3.new(2, 2, 1)
    hrp.Transparency = 1

    for _, child in ipairs(clone:GetDescendants()) do
        if child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" then
            child.Transparency = 0.4
            child.Color        = CONFIG.COLORS.CYAN
            child.Material     = Enum.Material.Neon

            -- Restore correct size (was hardcoded to 1,2,1 for every part)
            local origSize = templateData.partSizes[child.Name]
            if origSize then child.Size = origSize end

            -- Reposition in world space using stored HRP-relative offset
            local offset = templateData.partOffsets[child.Name]
            if offset then child.CFrame = newHrpCFrame * offset end

        elseif child:IsA("Motor6D") then
            -- Restore clean C0 so applyFakePose starts from a known base each time
            local origC0 = templateData.jointC0s[child.Name]
            if origC0 then child.C0 = origC0 end
        end
    end
end

-- ============================================================
-- BUG FIX #3: applyFakePose
--
-- OLD: `joint.C0 = joint.C0 * CFrame.Angles(...)` accumulates
-- rotation on every pool reuse. After 2-3 reuses joints are
-- completely twisted.
--
-- FIX: Use the stored original C0 from templateData as the
-- base and apply an ABSOLUTE offset each time.
-- resetClone already restores C0s, so the two are consistent.
-- ============================================================
local function applyFakePose(clone, isJumping, frameIndex)
    local function getJoint(a, b)
        return clone:FindFirstChild(a, true) or clone:FindFirstChild(b, true)
    end

    local rShoulder = getJoint("Right Shoulder", "RightShoulder")
    local lShoulder = getJoint("Left Shoulder",  "LeftShoulder")
    local rHip      = getJoint("Right Hip",      "RightHip")
    local lHip      = getJoint("Left Hip",       "LeftHip")

    local function baseC0(name)
        return templateData.jointC0s[name] or CFrame.identity
    end

    if isJumping then
        -- Absolute assignment — no cumulative drift
        if rShoulder then rShoulder.C0 = baseC0("Right Shoulder") * CFrame.Angles(math.rad(120), 0, 0) end
        if lShoulder then lShoulder.C0 = baseC0("Left Shoulder")  * CFrame.Angles(math.rad(120), 0, 0) end
    else
        local cycle = math.sin((frameIndex / CONFIG.PREDICTION_FRAMES) * math.pi * 6) * 0.6
        if rHip      then rHip.C0      = baseC0("Right Hip")      * CFrame.Angles( cycle,       0, 0) end
        if lHip      then lHip.C0      = baseC0("Left Hip")       * CFrame.Angles(-cycle,       0, 0) end
        if rShoulder then rShoulder.C0 = baseC0("Right Shoulder") * CFrame.Angles(-cycle * 0.5, 0, 0) end
        if lShoulder then lShoulder.C0 = baseC0("Left Shoulder")  * CFrame.Angles( cycle * 0.5, 0, 0) end
    end
end

-- [ TEMPLATE CREATION ]
local function createLightweightTemplate(character)
    if not character then return nil end
    character.Archivable = true
    local ok, template = pcall(function() return character:Clone() end)
    character.Archivable = false
    if not ok or not template then return nil end

    for _, child in ipairs(template:GetDescendants()) do
        if child:IsA("Accessory") or child:IsA("Clothing") or child:IsA("ShirtGraphic")
            or child:IsA("Decal") or child:IsA("Script") or child:IsA("LocalScript")
            or child:IsA("Sound") or child:IsA("ParticleEmitter") then
            child:Destroy()
        elseif child:IsA("BasePart") then
            child.Anchored    = true
            child.CanCollide  = false
            child.CastShadow  = false
            child.Material    = Enum.Material.Neon
            child.Color       = CONFIG.COLORS.CYAN
            child.Transparency = 0.4
        end
    end

    if template:FindFirstChild("Humanoid") then
        template.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        template.Humanoid.HealthDisplayType   = Enum.HumanoidHealthDisplayType.AlwaysOff
    end

    return template
end

local function initializePool(templateChar)
    local template = createLightweightTemplate(templateChar)
    if not template then logDebug("Template creation failed!"); return end

    local templateHrp = template:FindFirstChild("HumanoidRootPart")
    if not templateHrp then
        logDebug("Template HRP not found!")
        template:Destroy(); return
    end

    -- Record offsets/sizes/C0s BEFORE cloning into pool
    for _, desc in ipairs(template:GetDescendants()) do
        if desc:IsA("BasePart") and desc.Name ~= "HumanoidRootPart" then
            templateData.partOffsets[desc.Name] = templateHrp.CFrame:ToObjectSpace(desc.CFrame)
            templateData.partSizes[desc.Name]   = desc.Size
        elseif desc:IsA("Motor6D") then
            templateData.jointC0s[desc.Name] = desc.C0
        end
    end
    logDebug("Template data recorded.")

    for _ = 1, pool.MAX_SIZE do
        local clone = template:Clone()
        clone.Name   = "PooledClone"
        clone.Parent = nil
        table.insert(pool.available, clone)
    end
    template:Destroy()
    logDebug("Pool initialized:", pool.MAX_SIZE, "clones ready.")
end

-- [ PREDICTION WAVE ]
local function triggerProjectionWave()
    logDebug("Triggering Projection Wave...")
    for _, targetPlayer in ipairs(Players:GetPlayers()) do
        if targetPlayer == localPlayer then continue end

        local sourceChar = targetPlayer.Character
        local hrp = sourceChar and sourceChar:FindFirstChild("HumanoidRootPart")
        local hum = sourceChar and sourceChar:FindFirstChild("Humanoid")

        if not (hrp and hum and hum.Health > 0) then
            logDebug("Target invalid:", targetPlayer.Name); continue
        end

        local startPos    = hrp.Position
        local smoothedVel = getSmoothedVelocity(targetPlayer.UserId)
        local isJumping   = hum.FloorMaterial == Enum.Material.Air

        local predVel = smoothedVel
        if smoothedVel.Magnitude < 1 then
            predVel = hrp.CFrame.LookVector * math.max(hum.WalkSpeed, 16)
        end

        local activeClones = {}
        for i = 1, CONFIG.PREDICTION_FRAMES do
            local clone = getFromPool()
            if not clone then logDebug("Pool exhausted at frame", i); break end

            local t            = (i / CONFIG.PREDICTION_FRAMES) * CONFIG.MIRROR_LIFESPAN
            local gravity      = isJumping and Vector3.new(0, -workspace.Gravity, 0) or Vector3.zero
            local predictedPos = startPos + (predVel * t) + (0.5 * gravity * (t * t))
            local lookDir      = predVel.Magnitude > 0.01 and predVel.Unit or hrp.CFrame.LookVector
            local targetCF     = CFrame.new(predictedPos, predictedPos + lookDir)

            -- Pass target CFrame so resetClone positions ALL parts correctly
            resetClone(clone, targetCF)
            applyFakePose(clone, isJumping, i)

            -- Expand HRP hitbox for spatial detection (invisible)
            local cloneHrp = clone:FindFirstChild("HumanoidRootPart")
            if cloneHrp then
                cloneHrp.Size = Vector3.new(4, 6, 4)
                table.insert(activeClones, clone)
            else
                releaseToPool(clone)
            end
        end

        logDebug("Wave deployed:", #activeClones, "clones for", targetPlayer.Name)

        local waveData = {
            targetPlayer       = targetPlayer,
            clones             = activeClones,
            hitCount           = 0,
            touchedIndexes     = {},
            isSuccessTriggered = false,
            expireTime         = os.clock() + CONFIG.MIRROR_LIFESPAN,
        }
        table.insert(state.activeWaves, waveData)

        task.delay(CONFIG.MIRROR_LIFESPAN, function()
            logDebug("Wave expired for:", targetPlayer.Name)
            for _, clone in ipairs(activeClones) do
                shatterAndRelease(clone)
            end
        end)
    end
end

-- [ INITIALIZATION ]
task.spawn(function()
    pcall(loadMemory)
    notify("System", "Memória carregada", CONFIG.COLORS.GREEN)

    local function init()
        local char = localPlayer.Character or localPlayer.CharacterAdded:Wait()
        char:WaitForChild("HumanoidRootPart", 10)
        task.wait(0.5) -- Let accessories finish loading
        initializePool(char)
        notify("System", "Pool Inicializado", CONFIG.COLORS.GREEN)
    end

    local ok, err = pcall(init)
    if not ok then
        logDebug("Pool init failed:", err)
        task.delay(5, function() pcall(init) end)
    end
end)

-- Auto-save every 60s
task.spawn(function()
    while true do task.wait(60); saveMemory() end
end)

-- [ RNG / ABILITY ACTIVATION ]
task.delay(1, function()
    if state.rngDone then return end
    state.rngDone        = true
    modeLabel.Text       = "<i>Sorteando habilidade...</i>"
    modeLabel.TextColor3 = CONFIG.COLORS.YELLOW
    task.wait(1.5)

    local roll    = math.random()
    local success = roll < CONFIG.RNG_CHANCE
    logDebug("RNG Roll:", roll, "Success:", success)

    if success then
        state.projecaoActive   = true
        state.abilityStartTime = os.clock()
        -- BUG FIX #4: pre-fill waveTimer so first wave fires immediately
        -- (old code waited 3s into a 5s window — only 1 wave ever fired)
        state.waveTimer        = CONFIG.WAVE_INTERVAL

        modeLabel.Text       = "<b>◈ ARTE DE PROJEÇÃO: ATIVA</b>"
        modeLabel.TextColor3 = CONFIG.COLORS.PURPLE
        notify("Ability", "Projection Sorcery Activated!", CONFIG.COLORS.PURPLE)

        task.spawn(function()
            local h = 0
            while state.projecaoActive do
                h = (h + 0.01) % 1
                modeLabel.TextColor3 = Color3.fromHSV(h, 0.8, 1)
                task.wait(0.05)
            end
        end)

        task.delay(CONFIG.ABILITY_DURATION, function()
            if state.projecaoActive then
                state.projecaoActive = false
                modeLabel.Text = "<font color='#FF4646'>◈ ARTE DE PROJEÇÃO: EXPIRADA</font>"
                task.delay(2, function()
                    modeLabel.Text       = "A aguardar..."
                    modeLabel.TextColor3 = CONFIG.COLORS.PURPLE
                end)
            end
        end)
    else
        modeLabel.Text = "<font color='#FF4646'>✗ FALHA NA ATIVAÇÃO</font>"
        task.delay(2, function() modeLabel.Text = "A aguardar..." end)
    end
end)

-- [ PING HELPER ]
local function getPing()
    local ok, ping = pcall(function() return localPlayer:GetNetworkPing() end)
    return ok and math.floor(ping * 1000) or 0
end

-- [ MAIN LOOP ]
RunService.RenderStepped:Connect(function(dt)
    updatePlayerHistory(dt)

    -- Spatial hit detection for active waves
    for i = #state.activeWaves, 1, -1 do
        local wave = state.activeWaves[i]
        if os.clock() > wave.expireTime then
            table.remove(state.activeWaves, i)
            continue
        end
        if wave.isSuccessTriggered then continue end

        local targetChar = wave.targetPlayer.Character
        local targetHrp  = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
        if not targetHrp then continue end

        for idx, clone in ipairs(wave.clones) do
            if wave.touchedIndexes[idx] then continue end
            local cloneHrp = clone:FindFirstChild("HumanoidRootPart")
            if not cloneHrp then continue end

            local diff = targetHrp.Position - cloneHrp.Position
            if math.abs(diff.X) < cloneHrp.Size.X / 2
            and math.abs(diff.Y) < cloneHrp.Size.Y / 2
            and math.abs(diff.Z) < cloneHrp.Size.Z / 2 then
                logDebug("Hit! Player:", wave.targetPlayer.Name, "Clone idx:", idx)
                wave.touchedIndexes[idx] = true
                wave.hitCount += 1

                for _, p in ipairs(clone:GetChildren()) do
                    if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
                        p.Color = CONFIG.COLORS.PURPLE
                    end
                end

                if wave.hitCount >= CONFIG.SUCCESS_HITS_NEEDED then
                    wave.isSuccessTriggered = true
                    infoLabel.Text       = "★ PREVISÃO DE SUCESSO: " .. wave.targetPlayer.Name .. " ★"
                    infoLabel.TextColor3 = CONFIG.COLORS.GREEN

                    if state.projecaoActive then
                        state.projecaoActive = false
                        modeLabel.Text = "<font color='#50FF78'>◈ ARTE DE PROJEÇÃO: CONCLUÍDA</font>"
                        task.delay(2, function()
                            modeLabel.Text       = "A aguardar..."
                            modeLabel.TextColor3 = CONFIG.COLORS.PURPLE
                        end)
                    end
                end
            end
        end
    end

    -- FPS counter (rolling 30-frame average)
    state.fpsIdx = state.fpsIdx % 30 + 1
    state.fpsSum = state.fpsSum - state.fpsBuffer[state.fpsIdx] + (1 / dt)
    state.fpsBuffer[state.fpsIdx] = 1 / dt
    state.fpsUpdateTimer += dt

    if state.fpsUpdateTimer >= 0.5 then
        state.fpsUpdateTimer = 0
        local fps = math.floor(state.fpsSum / 30)
        fpsLabel.Text      = "FPS: " .. fps
        fpsLabel.TextColor3 = fps >= 55 and CONFIG.COLORS.GREEN
                           or fps >= 30 and CONFIG.COLORS.YELLOW
                           or CONFIG.COLORS.RED

        local ping = getPing()
        pingLabel.Text      = ping > 0 and ("Ping: " .. ping .. "ms") or "Ping: --"
        pingLabel.TextColor3 = (ping > 0 and ping < 100)   and CONFIG.COLORS.GREEN
                            or (ping >= 100 and ping < 200) and CONFIG.COLORS.YELLOW
                            or CONFIG.COLORS.RED
    end

    -- Projection wave trigger
    if state.projecaoActive then
        state.waveTimer += dt
        if state.waveTimer >= CONFIG.WAVE_INTERVAL then
            state.waveTimer = 0
            triggerProjectionWave()
        end
    end
end)
