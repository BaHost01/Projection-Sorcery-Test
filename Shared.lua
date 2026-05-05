local ProjectionLibrary = {}


function ProjectionLibrary.NewMirror()

end
function ProjectionLibrary.NewTargetMirror()

end
function ProjectionLibrary.Start()

local SetUI = Instance.New("ScreenGui")
SetUI.Parent = CoreGUI
-- SetUI Is An Holder That Says The Lib Is Loaded
local IsEnabled = Instance.New("BoolValue")
IsEnabled.Parent = SetUI
IsEnabled.Value = true
end
return ProjectionLibrary
