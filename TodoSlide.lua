local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- clean up the previous run, if any
if _G.SlideTest then
	for _, conn in ipairs(_G.SlideTest.connections) do
		conn:Disconnect()
	end
	if _G.SlideTest.slideTrack then
		_G.SlideTest.slideTrack:Stop(0)
	end
	if _G.SlideTest.rig then
		_G.SlideTest.rig.align:Destroy()
		_G.SlideTest.rig.attachment:Destroy()
	end
	if _G.SlideTest.mobileGui then
		_G.SlideTest.mobileGui:Destroy()
	end
end
_G.SlideTest = { connections = {}, slideTrack = nil, rig = nil, mobileGui = nil }
local state = _G.SlideTest

local lp = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- CONFIG
local SLIDE_KEY = Enum.KeyCode.E
local SLIDE_TIME = 0.35 -- total slide duration (seconds), raise to slow it down
local SLIDE_EXTRA = 5 -- studs the slide goes past the target
local FRONT_RANGE = 60
local SLIDE_ANIMATION_ID = "rbxassetid://100081544058065"
local SLIDE_POSE_TIME = 0 -- seconds into the animation to hold as the pose
local SHOW_MOBILE_BUTTON = true -- shows the SLIDE button (set false to hide it)
-- END CONFIG

local function findFrontTarget()
	local character = lp.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end

	local look = camera.CFrame.LookVector
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {character}

	local best, bestDist = nil, FRONT_RANGE
	for _, part in ipairs(workspace:GetPartBoundsInRadius(hrp.Position, FRONT_RANGE, params)) do
		local model = part:FindFirstAncestorOfClass("Model")
		local hum = model and model:FindFirstChildOfClass("Humanoid")
		local root = model and model:FindFirstChild("HumanoidRootPart")
		if hum and root and hum.Health > 0 then
			local offset = root.Position - hrp.Position
			local dist = offset.Magnitude
			if dist > 0.1 and offset.Unit:Dot(look) > 0.5 and dist < bestDist then
				bestDist = dist
				best = root
			end
		end
	end
	return best
end

local function playSlideAnimation()
	local character = lp.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then return nil end

	local anim = Instance.new("Animation")
	anim.AnimationId = SLIDE_ANIMATION_ID
	local track = animator:LoadAnimation(anim)
	track:Play(0.05)
	track.TimePosition = SLIDE_POSE_TIME
	track:AdjustSpeed(0)
	anim:Destroy()
	return track
end

local function easeOutCubic(t)
	return 1 - (1 - t) ^ 3
end

local function createSlideRig(hrp)
	local att = Instance.new("Attachment")
	att.Name = "SlideAttachment"
	att.Parent = hrp

	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.MaxTorque = math.huge
	align.Responsiveness = 200
	align.Enabled = false
	align.Parent = hrp

	return { attachment = att, align = align }
end

local function stopSlide()
	if state.slideTrack then
		state.slideTrack:Stop(0.1)
		state.slideTrack = nil
	end
	if state.rig then
		state.rig.align.Enabled = false
		state.rig.align:Destroy()
		state.rig.attachment:Destroy()
		state.rig = nil
	end
end

-- predicts the target's position only when it's grounded and not ragdolled
local function getAimPoint(targetRoot)
	local targetChar = targetRoot.Parent
	local targetHum = targetChar and targetChar:FindFirstChildOfClass("Humanoid")
	if not targetHum then return targetRoot.Position end

	local humState = targetHum:GetState()
	local grounded = targetHum.FloorMaterial ~= Enum.Material.Air
	local ragdolled = humState == Enum.HumanoidStateType.Physics or humState == Enum.HumanoidStateType.Ragdoll

	if grounded and not ragdolled then
		local vel = targetRoot.AssemblyLinearVelocity
		return targetRoot.Position + Vector3.new(vel.X, 0, vel.Z) * SLIDE_TIME
	end
	return targetRoot.Position
end

local function doSlide(targetRoot)
	local character = lp.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	stopSlide()

	local startPos = hrp.Position
	local start = os.clock()
	local passedTarget = false
	local endPos = startPos
	local dir = Vector3.new(0, 0, -1)

	state.slideTrack = playSlideAnimation()

	local rig = createSlideRig(hrp)
	state.rig = rig
	rig.align.Enabled = true

	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not targetRoot.Parent then
			stopSlide()
			conn:Disconnect()
			return
		end

		local elapsed = os.clock() - start
		local linear = math.clamp(elapsed / SLIDE_TIME, 0, 1)

		-- recalculate the destination every frame, so ragdoll/flying targets are followed
		local aim = getAimPoint(targetRoot)
		local offset = aim - startPos
		if offset.Magnitude > 0.01 then
			dir = offset.Unit
		end
		endPos = aim + dir * SLIDE_EXTRA

		local pos = startPos:Lerp(endPos, easeOutCubic(linear))
		hrp.CFrame = CFrame.new(pos)

		if not passedTarget and (pos - targetRoot.Position):Dot(dir) > 0 then
			passedTarget = true
		end

		if passedTarget then
			local goal = CFrame.lookAt(camera.CFrame.Position, targetRoot.Position)
			camera.CFrame = camera.CFrame:Lerp(goal, math.clamp(8 * dt, 0, 1))
		end

		if linear >= 1 then
			stopSlide()
			conn:Disconnect()
		end
	end)
	table.insert(state.connections, conn)
end

local function trySlide()
	local target = findFrontTarget()
	print("[Slide test] Target:", target and target.Parent.Name or "nil")
	if target then
		doSlide(target)
	end
end

table.insert(state.connections, UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode ~= SLIDE_KEY then return end
	trySlide()
end))

if SHOW_MOBILE_BUTTON then
	local playerGui = lp:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "SlideMobileGui"
	gui.ResetOnSpawn = false
	gui.Parent = playerGui
	state.mobileGui = gui

	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0, 90, 0, 90)
	button.Position = UDim2.new(1, -110, 1, -200)
	button.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	button.BackgroundTransparency = 0.3
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextSize = 18
	button.Font = Enum.Font.Code
	button.Text = "SLIDE"
	button.BorderSizePixel = 0
	button.Parent = gui
	Instance.new("UICorner", button).CornerRadius = UDim.new(1, 0)

	button.Activated:Connect(trySlide)
end