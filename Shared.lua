-- ============================================================
-- PROJECTION SORCERY: SHARED LIBRARY
-- ============================================================

local RunService   = game:GetService("RunService")
local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local CoreGui      = game:GetService("CoreGui")
local Debris       = game:GetService("Debris")

local ProjectionLibrary = {}
ProjectionLibrary.__index = ProjectionLibrary

-- [ CONSTANTS ]
local CONFIG = {
    DARK_BLUE = Color3.fromRGB(0, 0, 139),
    CYAN      = Color3.fromRGB(0, 220, 255),
    PURPLE    = Color3.fromRGB(180, 100, 255),
}

-- [ PRIVATE UTILITIES ]

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
            child.Color = CONFIG.CYAN
            child.Transparency = 0.4
        end
    end

    if template:FindFirstChild("Humanoid") then
        template.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        template.Humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
    end

    return template
end

-- [ PUBLIC API ]

-- Creates a new mirror model based on a character
function ProjectionLibrary.NewMirror(character)
    if not character then return nil end
    return createLightweightTemplate(character)
end

-- Specifically for targeting other players
function ProjectionLibrary.NewTargetMirror(targetPlayer)
    local char = targetPlayer.Character
    if not char then return nil end
    return ProjectionLibrary.NewMirror(char)
end

-- Applies the shatter effect and handles cleanup/repooling logic
function ProjectionLibrary.Shatter(model, duration)
    if not model then return end
    duration = duration or 0.5
    
    local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            if part.Name ~= "HumanoidRootPart" then
                local explodeOffset = Vector3.new(math.random(-10, 10), math.random(5, 20), math.random(-10, 10))
                local targetCFrame = part.CFrame + explodeOffset

                TweenService:Create(part, tweenInfo, {
                    CFrame = targetCFrame,
                    Size = Vector3.new(0.1, 0.1, 0.1),
                    Transparency = 1
                }):Play()
            end
        end
    end
end

-- Initializes the system and returns a status holder
function ProjectionLibrary.Start()
    -- Clean up old UI
    if CoreGui:FindFirstChild("ProjectionLibHolder") then 
        CoreGui.ProjectionLibHolder:Destroy() 
    end

    local SetUI = Instance.new("ScreenGui")
    SetUI.Name = "ProjectionLibHolder"
    SetUI.Parent = CoreGui
    SetUI.ResetOnSpawn = false
    SetUI.IgnoreGuiInset = true

    -- Status tag to indicate library is active
    local IsEnabled = Instance.new("BoolValue")
    IsEnabled.Name = "IsEnabled"
    IsEnabled.Parent = SetUI
    IsEnabled.Value = true
    
    print("[ProjectionLibrary] System Started Successfully")
    return SetUI
end

return ProjectionLibrary
