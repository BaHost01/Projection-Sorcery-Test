-- ============================================================
-- FPS Display + Arte de Projeção (Trilha Temporal Otimizada)
-- ============================================================
local RunService   = game:GetService("RunService")
local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local CoreGui      = game:GetService("CoreGui")
local Debris       = game:GetService("Debris")

local localPlayer = Players.LocalPlayer

-- ============================================================
-- PREVINE DUPLICAÇÃO DE UI
-- ============================================================
if CoreGui:FindFirstChild("FPSSystem") then CoreGui.FPSSystem:Destroy() end

-- ============================================================
-- CONFIGURAÇÕES DA ARTE DE PROJEÇÃO
-- ============================================================
local RNG_CHANCE          = 0.40 -- 40% de chance de ativar a habilidade
local PREDICTION_FRAMES   = 24   -- Número de clones na trilha temporal
local MIRROR_LIFESPAN     = 0.8  -- Segundos até os clones estilhaçarem
local SUCCESS_HITS_NEEDED = 6    -- Toques necessários para confirmar a previsão
local WAVE_INTERVAL       = 3.0  -- Intervalo (segundos) entre cada onda de previsão

-- ============================================================
-- CORES E PALETA
-- ============================================================
local C_GREEN     = Color3.fromRGB(80, 255, 120)
local C_YELLOW    = Color3.fromRGB(255, 210, 50)
local C_RED       = Color3.fromRGB(255, 70, 70)
local C_PURPLE    = Color3.fromRGB(180, 100, 255)
local C_CYAN      = Color3.fromRGB(0, 220, 255)
local C_DARK_BLUE = Color3.fromRGB(0, 0, 139) -- Cor dos clones (Azul Escuro)

-- ============================================================
-- UI COMPLETA (HUD)
-- ============================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FPSSystem"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true 
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = CoreGui

-- Painel de FPS
local fpsFrame = Instance.new("Frame")
fpsFrame.Size = UDim2.new(0, 120, 0, 40)
fpsFrame.Position = UDim2.new(0, 20, 0, 20)
fpsFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
fpsFrame.BackgroundTransparency = 0.3
fpsFrame.BorderSizePixel = 0
fpsFrame.Parent = screenGui
Instance.new("UICorner", fpsFrame).CornerRadius = UDim.new(0, 8)

local fpsLabel = Instance.new("TextLabel")
fpsLabel.Size = UDim2.new(1, 0, 1, 0)
fpsLabel.BackgroundTransparency = 1
fpsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
fpsLabel.TextScaled = true
fpsLabel.Font = Enum.Font.GothamBold
fpsLabel.Text = "FPS: --"
fpsLabel.Parent = fpsFrame

-- Etiqueta de Status
local modeLabel = Instance.new("TextLabel")
modeLabel.Size = UDim2.new(0, 300, 0, 30)
modeLabel.Position = UDim2.new(0, 20, 0, 65)
modeLabel.BackgroundTransparency = 1
modeLabel.TextColor3 = C_PURPLE
modeLabel.TextScaled = true
modeLabel.Font = Enum.Font.GothamBold
modeLabel.Text = "A aguardar..."
modeLabel.TextXAlignment = Enum.TextXAlignment.Left
modeLabel.TextStrokeTransparency = 0.5
modeLabel.Parent = screenGui

-- Etiqueta de Confirmação de Sucesso
local infoLabel = Instance.new("TextLabel")
infoLabel.Size = UDim2.new(0, 300, 0, 20)
infoLabel.Position = UDim2.new(0, 20, 0, 95)
infoLabel.BackgroundTransparency = 1
infoLabel.TextColor3 = C_CYAN
infoLabel.TextScaled = true
infoLabel.Font = Enum.Font.Gotham
infoLabel.Text = ""
infoLabel.TextXAlignment = Enum.TextXAlignment.Left
infoLabel.TextStrokeTransparency = 0.5
infoLabel.Parent = screenGui

-- ============================================================
-- ESTADO DO SISTEMA
-- ============================================================
local projecaoActive = false
local rngDone        = false

-- Buffer para o cálculo da média de FPS
local SAMPLE_COUNT = 30
local fpsBuf = table.create(SAMPLE_COUNT, 0)
local bufIdx, bufSum, fpsTimer = 0, 0, 0

-- ============================================================
-- OTIMIZAÇÃO: CRIAR MOLDE LEVE DO PERSONAGEM
-- Limpa roupas e scripts antes de clonar 24 vezes, salvando memória.
-- ============================================================
local function createLightweightTemplate(character)
    character.Archivable = true
    local template = character:Clone()
    character.Archivable = false

    -- Limpeza rigorosa para performance
    for _, child in ipairs(template:GetDescendants()) do
        if child:IsA("Accessory") or child:IsA("Clothing") or child:IsA("ShirtGraphic") or child:IsA("Decal") or child:IsA("Script") or child:IsA("LocalScript") or child:IsA("Sound") or child:IsA("ParticleEmitter") then
            child:Destroy()
        elseif child:IsA("BasePart") then
            child.Anchored = true
            child.CanCollide = false
            child.CastShadow = false
            child.Material = Enum.Material.Neon
            child.Color = C_DARK_BLUE
            child.Transparency = 0.7
        end
    end

    if template:FindFirstChild("Humanoid") then
        template.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        template.Humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
    end

    return template
end

-- ============================================================
-- EFEITO: ESTILHAÇAR VISUALMENTE (Sem uso de Física para evitar lag)
-- ============================================================
local function shatterClone(cloneModel)
    if not cloneModel then return end
    
    local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    for _, part in ipairs(cloneModel:GetDescendants()) do
        if part:IsA("BasePart") then
            if part.Name == "HumanoidRootPart" then
                part:Destroy() -- Removemos a root para não atrapalhar visualmente
                continue
            end
            
            -- Em vez de física, usamos Tween para afastar e diminuir as peças (MUITO mais leve)
            local explodeOffset = Vector3.new(math.random(-10, 10), math.random(5, 20), math.random(-10, 10))
            local targetCFrame = part.CFrame + explodeOffset

            TweenService:Create(part, tweenInfo, {
                CFrame = targetCFrame,
                Size = Vector3.new(0.1, 0.1, 0.1),
                Transparency = 1
            }):Play()
        end
    end
    Debris:AddItem(cloneModel, 0.3) -- Remove totalmente da memória a seguir
end

-- ============================================================
-- POSES MANUAIS (Animação de Caminhada Estática)
-- ============================================================
local function applyFakePose(clone, isJumping, frameIndex)
    local rShoulder = clone:FindFirstChild("Right Shoulder", true) or clone:FindFirstChild("RightShoulder", true)
    local lShoulder = clone:FindFirstChild("Left Shoulder", true) or clone:FindFirstChild("LeftShoulder", true)
    local rHip = clone:FindFirstChild("Right Hip", true) or clone:FindFirstChild("RightHip", true)
    local lHip = clone:FindFirstChild("Left Hip", true) or clone:FindFirstChild("LeftHip", true)

    if isJumping then
        -- Mãos ao alto ao pular
        if rShoulder then rShoulder.C0 = rShoulder.C0 * CFrame.Angles(math.rad(120), 0, 0) end
        if lShoulder then lShoulder.C0 = lShoulder.C0 * CFrame.Angles(math.rad(120), 0, 0) end
    else
        -- Ciclo senoidal simulando pernas e braços a andar
        local walkCycle = math.sin((frameIndex / PREDICTION_FRAMES) * math.pi * 6) * 0.6
        if rHip then rHip.C0 = rHip.C0 * CFrame.Angles(walkCycle, 0, 0) end
        if lHip then lHip.C0 = lHip.C0 * CFrame.Angles(-walkCycle, 0, 0) end
        if rShoulder then rShoulder.C0 = rShoulder.C0 * CFrame.Angles(-walkCycle * 0.5, 0, 0) end
        if lShoulder then lShoulder.C0 = lShoulder.C0 * CFrame.Angles(walkCycle * 0.5, 0, 0) end
    end
end

-- ============================================================
-- GERAR A TRILHA TEMPORAL (ONDA DE PROJEÇÃO)
-- ============================================================
local function triggerProjectionWave()
    for _, targetPlayer in ipairs(Players:GetPlayers()) do
        if targetPlayer == localPlayer then continue end

        local sourceChar = targetPlayer.Character
        local hrp = sourceChar and sourceChar:FindFirstChild("HumanoidRootPart")
        local hum = sourceChar and sourceChar:FindFirstChild("Humanoid")
        
        if not hrp or not hum or hum.Health <= 0 then continue end

        local startPos = hrp.Position
        local actualVel = hrp.AssemblyLinearVelocity
        local isJumping = hum.FloorMaterial == Enum.Material.Air
        
        -- PREVISÃO COM JOGADOR PARADO: Se a velocidade for muito baixa, forçamos um vetor para a frente
        local predVel = actualVel
        if actualVel.Magnitude < 1 then
            local walkSpeed = (hum.WalkSpeed > 0) and hum.WalkSpeed or 16
            predVel = hrp.CFrame.LookVector * walkSpeed
        end

        local groupFolder = Instance.new("Folder")
        groupFolder.Name = "Previsao_" .. targetPlayer.Name
        groupFolder.Parent = workspace

        local hitCount = 0
        local touchedIndexes = {}
        local isSuccessTriggered = false

        -- Cria o molde base (Ultra Leve)
        local template = createLightweightTemplate(sourceChar)

        for i = 1, PREDICTION_FRAMES do
            local t = (i / PREDICTION_FRAMES) * MIRROR_LIFESPAN
            local gravity = isJumping and Vector3.new(0, -workspace.Gravity, 0) or Vector3.zero
            local predictedPos = startPos + (predVel * t) + (0.5 * gravity * (t * t))
            
            -- Clonamos a partir do molde leve (Muito mais rápido!)
            local clone = template:Clone()
            local cloneHrp = clone:FindFirstChild("HumanoidRootPart")
            if not cloneHrp then clone:Destroy(); continue end

            cloneHrp.CFrame = CFrame.new(predictedPos, predictedPos + predVel.Unit)
            applyFakePose(clone, isJumping, i)
            
            -- OTIMIZAÇÃO: Usar a própria HumanoidRootPart como Hitbox expandida
            cloneHrp.Size = cloneHrp.Size + Vector3.new(2, 4, 2) -- Hitbox generosa
            cloneHrp.Transparency = 1 -- Mantém a HRP invisível
            
            cloneHrp.Touched:Connect(function(hit)
                if isSuccessTriggered then return end
                
                local hitPlayer = Players:GetPlayerFromCharacter(hit.Parent)
                if hitPlayer == targetPlayer and not touchedIndexes[i] then
                    touchedIndexes[i] = true
                    hitCount += 1
                    
                    -- Feedback visual ao pisar na previsão (muda para Roxo)
                    for _, p in ipairs(clone:GetChildren()) do
                        if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
                            p.Color = C_PURPLE
                        end
                    end
                    
                    if hitCount >= SUCCESS_HITS_NEEDED then
                        isSuccessTriggered = true
                        infoLabel.Text = "★ PREVISÃO DE SUCESSO: " .. targetPlayer.Name .. " ★"
                        infoLabel.TextColor3 = C_GREEN
                        
                        -- Ação de acerto (Pode adicionar o dano aqui)
                        -- Ex: hum:TakeDamage(30)
                    end
                end
            end)

            clone.Parent = groupFolder
        end
        
        template:Destroy() -- O molde já não é necessário

        -- Estilhaça toda a trilha após 0.8 segundos exatos
        task.delay(MIRROR_LIFESPAN, function()
            for _, child in ipairs(groupFolder:GetChildren()) do
                if child:IsA("Model") then shatterClone(child) end
            end
            Debris:AddItem(groupFolder, 0.5)
            
            if infoLabel.Text ~= "" then
                task.delay(1.5, function() infoLabel.Text = "" end)
            end
        end)
    end
end

-- ============================================================
-- ATIVAÇÃO INICIAL E SORTEIO (RNG)
-- ============================================================
task.delay(2, function()
    if not rngDone then
        rngDone = true
        modeLabel.Text = "A sortear habilidade..."
        modeLabel.TextColor3 = C_YELLOW
        
        task.delay(1.5, function()
            local success = math.random() < RNG_CHANCE
            if success then
                projecaoActive = true
                modeLabel.Text = "◈ Arte de Projeção ATIVA"
                modeLabel.TextColor3 = C_PURPLE
            else 
                modeLabel.Text = "✗ Falha na Arte de Projeção"
                modeLabel.TextColor3 = C_RED
            end
        end)
    end
end)

-- ============================================================
-- LOOP PRINCIPAL (Conta FPS + Ativação das Ondas)
-- ============================================================
local waveTimer = 0

RunService.RenderStepped:Connect(function(dt)
    -- LÓGICA DO CONTADOR DE FPS
    bufIdx = bufIdx % SAMPLE_COUNT + 1
    bufSum = bufSum - fpsBuf[bufIdx] + (1 / dt)
    fpsBuf[bufIdx] = 1 / dt
    
    fpsTimer += dt
    if fpsTimer >= 0.5 then
        fpsTimer = 0
        local avgFps = math.floor(bufSum / SAMPLE_COUNT)
        fpsLabel.TextColor3 = avgFps >= 55 and C_GREEN or avgFps >= 30 and C_YELLOW or C_RED
        fpsLabel.Text = "FPS: " .. avgFps
    end

    -- LÓGICA DO TEMPORIZADOR DA ARTE DE PROJEÇÃO
    if projecaoActive then
        waveTimer += dt
        if waveTimer >= WAVE_INTERVAL then 
            waveTimer = 0
            triggerProjectionWave() -- Lança os 24 clones simulados
        end
    end
end)
