--!nocheck
--[[
	Welcome to the script, in this script you might need to adjust settings based on your need.
	Scroll down to see flags to adjust settings.

	targetUPS: the maximum updates per second you can do.
	mapCenter: set this to the center position of your full map.

	Current version: 3.5

	What's new:
	- Fixed ragdoll tracking system
	- Yesn't for fixing full map
	- Added more code that works but shouldn't
	- Bug fix, that's all
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local TrackRagdoll = ReplicatedStorage:WaitForChild("TrackRagdoll")

local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
local Camera = workspace.CurrentCamera

-- UI references
local Frame = script.Parent.MiniMapV3:WaitForChild("MapFrame")
local FullFrame = script.Parent.MiniMapV3.Frame:WaitForChild("FullMapFrame")
local MapArrow = Frame:WaitForChild("MapArrow")
local PlrDirection = MapArrow:WaitForChild("PlrDirection")
local PlrDirectionImage = PlrDirection:WaitForChild("PlrDirection")
local DeathPlr = MapArrow:WaitForChild("DeathImage")
local FPSLabel = script.Parent.MiniMapV3:WaitForChild("FPSLabel")
local UPSLabel = script.Parent.MiniMapV3:WaitForChild("UPSLabel")
-------------------------------------------------------------|
-- Flags
local isV3 = true --set false to use V2
local lastUpdate = 0
local targetUPS = 200
local updateInterval = 1 / targetUPS
local upsCount = 0
local upsTimer = 0
local smoothedFPS = 60
local timeSinceLastFPSUpdate = 0
local timeSinceLastUPSUpdate = 0
local mapScale = 1.5
local FullmapScale = 0.3
local mapCenter = Vector3.new(-143.81, 0, -186.231)
-------------------------------------------------------------|
local v2 = script.Parent:WaitForChild("MiniMapV2")
local v3 = script.Parent:WaitForChild("MiniMapV3")
local function updateUI()
	v2.Visible = not useV3
	v3.Visible = useV3
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Z then
		useV3 = not useV3
		updateUI()
		warn("Switched to " .. (useV3 and "MiniMapV3 (Beta)" or "MiniMapV2 (Live)"))
	end
end)

-- Initialize once
updateUI()



if isV3 then
	script.Parent.MiniMapV3.Visible = true
	script.Parent.MiniMapV2.Visible = false
else
	script.Parent.MiniMapV3.Visible = false
	script.Parent.MiniMapV2.Visible = true
end

-- Arrow setup
local ArrowsFolder = Instance.new("Folder")
ArrowsFolder.Name = "PlayerArrows"
ArrowsFolder.Parent = MapArrow

local LocalArrow = MapArrow:WaitForChild("LocalArrow")
LocalArrow.Visible = true
DeathPlr.Visible = false
PlrDirectionImage.Visible = true
local FullArrow = LocalArrow:Clone()
FullArrow.Name = "FullArrow"
FullArrow.Parent = FullFrame
FullArrow.Size = UDim2.new(0, 8, 0, 12)
FullArrow.Visible = false
local scale = Frame:FindFirstChildOfClass("UIScale")
if scale then
	scale.Scale = mapOpen and 1 or 0.75
end
local scale = FullFrame:FindFirstChildOfClass("UIScale")
if scale then
	scale.Scale = mapOpen and 1 or 0.75
end


-- Folder references
local ViewingFolder = workspace:WaitForChild("ViewerFolder")
local ViewingFolder2 = ReplicatedStorage:WaitForChild("ViewerFolder2")

-- Cameras
local MiniCam = Instance.new("Camera")
MiniCam.Name = "ViewportCam"
MiniCam.CameraType = Enum.CameraType.Scriptable
MiniCam.FieldOfView = 10
MiniCam.Parent = Frame
Frame.CurrentCamera = MiniCam

local FullCam = Instance.new("Camera")
FullCam.Name = "FullMapCam"
FullCam.CameraType = Enum.CameraType.Scriptable
FullCam.FieldOfView = 10
FullCam.Parent = FullFrame
FullFrame.CurrentCamera = FullCam

-- Tracked objects
local trackedMini = {}
local trackedFull = {}

-- Utility functions
local function isFarFromPlayer(pos: Vector3)
	return (HumanoidRootPart.Position - pos).Magnitude > 250
end

local function isTooHeavy(model)
	local parts = model:GetDescendants()
	local count = 0
	for _, p in ipairs(parts) do
		if p:IsA("BasePart") then
			count += 1
			if count > 50 then return true end
		end
	end
	return false
end
wait(1)
local function setupClone(original, clone, parentTable, parentFrame)
	if clone:IsA("BasePart") then
		clone.Anchored = true
		clone.CanCollide = false
		clone.Parent = parentFrame
		parentTable[original] = clone
	elseif clone:IsA("Model") then
		local root = original.PrimaryPart or original:FindFirstChildWhichIsA("BasePart")
		if root then
			original.PrimaryPart = root
			local cloneRoot = clone:FindFirstChild(root.Name)
			if cloneRoot then
				clone.PrimaryPart = cloneRoot
			end
			for _, part in ipairs(clone:GetDescendants()) do
				if part:IsA("BasePart") then
					part.CastShadow = false
					part.Material = Enum.Material.SmoothPlastic
					part.Color = part.Color -- preserve color
					part.Anchored = true
					part.CanCollide = true
				end
			end
			clone.Parent = parentFrame
			parentTable[original] = clone
		end
	end
end

local function cloneAndTrack(obj)
	if obj:IsA("Model") and isTooHeavy(obj) then return end

	local cloneMini = obj:Clone()
	setupClone(obj, cloneMini, trackedMini, Frame)

	local cloneFull = obj:Clone()
	setupClone(obj, cloneFull, trackedFull, FullFrame)
end

for _, obj in ipairs(ViewingFolder:GetChildren()) do cloneAndTrack(obj) end
for _, obj in ipairs(ViewingFolder2:GetChildren()) do cloneAndTrack(obj) end

ViewingFolder.ChildAdded:Connect(cloneAndTrack)
ViewingFolder2.ChildAdded:Connect(cloneAndTrack)
TrackRagdoll.OnClientEvent:Connect(function(ragdoll)
	if ragdoll then
		local pos = ragdoll:FindFirstChild("HumanoidRootPart") and ragdoll.HumanoidRootPart.Position
		print("[Client] Received ragdoll model at:", pos or "No HRP")

		if not trackedMini[ragdoll] and not trackedFull[ragdoll] then
			cloneAndTrack(ragdoll)
		end
	else
		warn("[Client] Invalid ragdoll received:", ragdoll)
	end
end)



ViewingFolder.ChildRemoved:Connect(function(obj)
	if trackedMini[obj] then trackedMini[obj]:Destroy() trackedMini[obj] = nil end
	if trackedFull[obj] then trackedFull[obj]:Destroy() trackedFull[obj] = nil end
end)

ViewingFolder2.ChildRemoved:Connect(function(obj)
	if trackedMini[obj] then trackedMini[obj]:Destroy() trackedMini[obj] = nil end
	if trackedFull[obj] then trackedFull[obj]:Destroy() trackedFull[obj] = nil end
end)


-- Multiplayer arrows
local playerArrows = {}

local function createArrowForPlayer(plr)
	if plr == Player then return end
	local arrow = LocalArrow:Clone()
	arrow.Name = plr.Name .. "Arrow"
	arrow.Visible = true
	arrow.Parent = ArrowsFolder
	playerArrows[plr] = arrow
end

local function removeArrowForPlayer(plr)
	if playerArrows[plr] then
		playerArrows[plr]:Destroy()
		playerArrows[plr] = nil
	end
end

for _, plr in ipairs(Players:GetPlayers()) do createArrowForPlayer(plr) end
Players.PlayerAdded:Connect(createArrowForPlayer)
Players.PlayerRemoving:Connect(removeArrowForPlayer)


-- Arrows
RunService.RenderStepped:Connect(function(dt)

	LocalArrow.Rotation = -HumanoidRootPart.Orientation.Y - 90
	FullArrow.Rotation = LocalArrow.Rotation
	FullArrow.Visible = FullFrame.Visible

	local offset = HumanoidRootPart.Position - mapCenter
	FullArrow.Position = UDim2.new(0.5, offset.Z * FullmapScale, 0.5, -offset.X * FullmapScale)
	

	local camYaw = math.deg(math.atan2(-Camera.CFrame.LookVector.X, -Camera.CFrame.LookVector.Z)) % 360
	PlrDirection.Rotation = (-camYaw) % 360

	MiniCam.CFrame = CFrame.new(HumanoidRootPart.Position + Vector3.new(0, 600, 0), HumanoidRootPart.Position)
	
	FullCam.CFrame = CFrame.new(mapCenter + Vector3.new(0, 9000, 0), mapCenter)
	

	local maxX = Frame.AbsoluteSize.X / 2
	local maxY = Frame.AbsoluteSize.Y / 2
	local fadeMargin = 20

	for plr, arrow in pairs(playerArrows) do
		local char = plr.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			local hrp = char.HumanoidRootPart
			arrow.Rotation = -hrp.Orientation.Y - 90

			local offset = hrp.Position - HumanoidRootPart.Position
			local pixelX = offset.Z * mapScale
			local pixelY = -offset.X * mapScale

			local clampedX = math.clamp(pixelX, -maxX, maxX)
			local clampedY = math.clamp(pixelY, -maxY, maxY)
			arrow.Position = UDim2.new(0.5, clampedX, 0.5, clampedY)

			local alphaX = 1 - math.clamp((math.abs(pixelX) - (maxX - fadeMargin)) / fadeMargin, 0, 1)
			local alphaY = 1 - math.clamp((math.abs(pixelY) - (maxY - fadeMargin)) / fadeMargin, 0, 1)
			local fadeAlpha = 1 - math.min(alphaX, alphaY)

			if arrow:IsA("ImageLabel") then
				arrow.ImageTransparency = fadeAlpha
			else
				arrow.BackgroundTransparency = fadeAlpha
			end
		end
	end
end)

-- Realtime updates
RunService.Heartbeat:Connect(function(dt)
	lastUpdate += dt
	local updatesHappened = 0

	while lastUpdate >= updateInterval do
		lastUpdate -= updateInterval
		updatesHappened += 1
		

		-- your update code here
		-- in the for loop over trackedMini
		for original, clone in pairs(trackedMini) do
			if original:IsA("Model") and original.PrimaryPart and clone:IsA("Model") and clone.PrimaryPart then
				local origCFrame = original:GetPrimaryPartCFrame()
				if not isFarFromPlayer(origCFrame.Position) and not origCFrame:FuzzyEq(clone:GetPrimaryPartCFrame(), 0.01) then
					clone:SetPrimaryPartCFrame(origCFrame)
				end

				-- ? Only sync ragdoll parts by tag or name
				if original.Name:lower():find("ragdoll") or CollectionService:HasTag(original, "Ragdoll") then
					for _, origPart in ipairs(original:GetDescendants()) do
						if origPart:IsA("BasePart") then
							local clonePart = clone:FindFirstChild(origPart.Name)
							if clonePart and clonePart:IsA("BasePart") then
								if not origPart.CFrame:FuzzyEq(clonePart.CFrame, 0.01) then
									clonePart.CFrame = origPart.CFrame
								end
							end
						end
					end
				end
			end
		end
	end

	-- Count total UPS attempts, not just successful updates
	upsCount += updatesHappened
	upsTimer += dt

	-- Realtime UPS display (even if update didn't run)
	local avgUPS = upsCount / math.max(upsTimer, 0.01)
	UPSLabel.Text = string.format("UPS: %.1f / %.0f", avgUPS,targetUPS)
	UPSLabel.TextColor3 = (avgUPS >= targetUPS * 0.9) and Color3.fromRGB(0, 255, 0)
		or (avgUPS >= targetUPS * 0.6) and Color3.fromRGB(255, 165, 0)
		or Color3.fromRGB(255, 0, 0)
	-- FPS display (updates once per second)
	local safeDt = math.max(dt, 0.0001)
	smoothedFPS = smoothedFPS * 0.9 + (1 / safeDt) * 0.1

	-- Adjust UPS target based on FPS
	local rawFPS = 1/safeDt
	targetUPS = math.clamp(smoothedFPS*2, 20, targetUPS)
	updateInterval = 1 / targetUPS

	-- Realtime FPS display
	FPSLabel.Text = string.format("FPS: %.1f", smoothedFPS)
	if smoothedFPS >= 50 then
		FPSLabel.TextColor3 = Color3.fromRGB(0, 255, 0) -- Green
	elseif smoothedFPS >= 30 then
		FPSLabel.TextColor3 = Color3.fromRGB(255, 165, 0) -- Orange
	else
		FPSLabel.TextColor3 = Color3.fromRGB(255, 0, 0) -- Red
	end


	-- Reset after 1 second

end)


-- Death
Humanoid.Died:Connect(function()
	LocalArrow.Visible = true
	DeathPlr.Visible = false
end)

-- Toggle fullscreen map with M key
local mapOpen = false
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.M then
		mapOpen = not mapOpen
		FullFrame.Visible = mapOpen
		Frame.Visible = not mapOpen
		for _, arrow in pairs(ArrowsFolder:GetChildren()) do
			if arrow:IsA("ImageLabel") then
				arrow.Visible = not mapOpen
			end
		end
	end
end)
