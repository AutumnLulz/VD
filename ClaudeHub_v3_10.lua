-- LocalScript | ClaudeHub v3.10
-- Gabungan + rapih. Sesuaikan KONFIGURASI kalau nama objek beda.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local VIM = game:GetService("VirtualInputManager")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- ===== KONFIGURASI =====
local SURVIVOR_TEAM = "Survivors"
local KILLER_TEAM = "Killer"
local GENERATOR_NAME = "Generator"
local GENERATOR_PROGRESS = "Progress"
local GENERATOR_DONE_VALUE = 100
local PROGRESS_NAMES = { GENERATOR_PROGRESS, "percent", "repair", "completion", "charge" }
local DONE_NAMES = { "completed", "complete", "done", "repaired", "finished" }
local PROGRESS_MAX = 100
local PROGRESS_DECIMALS = 0


local TOGGLE_KEY = Enum.KeyCode.RightAlt
local CONFIG_FOLDER = "ClaudeHubConfigs"

-- ===== STATE =====
local camera = workspace.CurrentCamera
local Settings = {
	FOV = math.clamp(math.floor(camera.FieldOfView + 0.5), 70, 120),
	PlayerESP = false,
	KillerColor = Color3.fromRGB(255, 0, 0),
	SurvivorColor = Color3.fromRGB(0, 40, 160),
	GenESP = false,
	GenColor = Color3.fromRGB(255, 200, 0),
	GenDoneColor = Color3.fromRGB(34, 197, 94),
	GenProgress = false,
	AutoSkill = false,
	CamStiff = false,
	CamStiffness = 8,
	Fullbright = false,
	NoFog = false,
}
local Controls = {}
local connections = {}
local function track(c) table.insert(connections, c) return c end

-- ===== CHAMS =====
local function makeChams(adornee, color)
	local hl = Instance.new("Highlight")
	hl.FillColor = color
	hl.OutlineColor = color
	hl.FillTransparency = 0.75
	hl.OutlineTransparency = 0.25
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Adornee = adornee
	return hl
end

-- ===== PLAYER ESP =====
local PlayerHL = {}
local function clearPlayer(p)
	if PlayerHL[p] then PlayerHL[p]:Destroy() PlayerHL[p] = nil end
end

local function refreshPlayers()
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer then
			local team = p.Team and p.Team.Name
			local color = (team == KILLER_TEAM and Settings.KillerColor)
				or (team == SURVIVOR_TEAM and Settings.SurvivorColor) or nil
			if Settings.PlayerESP and color and p.Character then
				local hl = PlayerHL[p]
				if not (hl and hl.Parent) then
					if hl then hl:Destroy() end
					hl = makeChams(p.Character, color)
					hl.Parent = p.Character
					PlayerHL[p] = hl
				end
				hl.FillColor, hl.OutlineColor = color, color
			else
				clearPlayer(p)
			end
		end
	end
end
track(Players.PlayerRemoving:Connect(clearPlayer))

-- ===== GENERATOR ESP + PROGRESS =====
local Gens = {}

local function isGenerator(i)
	return i.Name:lower() == GENERATOR_NAME:lower() and (i:IsA("Model") or i:IsA("BasePart"))
end

local function addGen(i)
	if isGenerator(i) and not Gens[i] then Gens[i] = {} end
end

for _, d in ipairs(workspace:GetDescendants()) do addGen(d) end
track(workspace.DescendantAdded:Connect(addGen))
track(workspace.DescendantRemoving:Connect(function(i)
	local g = Gens[i]
	if g then
		if g.hl then g.hl:Destroy() end
		if g.bb then g.bb:Destroy() end
		if g.conn then g.conn:Disconnect() end
		Gens[i] = nil
	end
end))

local function getPart(i)
	if i:IsA("BasePart") then return i end
	return i.PrimaryPart or i:FindFirstChildWhichIsA("BasePart", true)
end

local function nameHas(name, keys)
	name = name:lower()
	for _, k in ipairs(keys) do
		if name:find(k:lower(), 1, true) then return true end
	end
	return false
end

local function normalize(v)
	if PROGRESS_MAX then return math.clamp(v / PROGRESS_MAX * 100, 0, 100) end
	if v <= 1 then v = v * 100 end
	return math.clamp(v, 0, 100)
end

local function scanSources(inst)
	local src = {}
	local function consider(obj)
		for k, v in pairs(obj:GetAttributes()) do
			if type(v) == "number" and nameHas(k, PROGRESS_NAMES) then
				table.insert(src, { kind = "attr", obj = obj, key = k, role = "progress" })
			elseif type(v) == "boolean" and nameHas(k, DONE_NAMES) then
				table.insert(src, { kind = "attr", obj = obj, key = k, role = "done" })
			end
		end
		if obj:IsA("ValueBase") then
			if (obj:IsA("NumberValue") or obj:IsA("IntValue")) and nameHas(obj.Name, PROGRESS_NAMES) then
				table.insert(src, { kind = "val", obj = obj, role = "progress" })
			elseif obj:IsA("BoolValue") and nameHas(obj.Name, DONE_NAMES) then
				table.insert(src, { kind = "val", obj = obj, role = "done" })
			end
		end
	end
	consider(inst)
	for _, d in ipairs(inst:GetDescendants()) do consider(d) end
	if inst.Parent and inst.Parent ~= workspace then consider(inst.Parent) end
	return src
end

local function readState(inst, g)
	local now = os.clock()
	if not g.src or (now - (g.scanT or 0)) > (#g.src == 0 and 2 or 10) then
		g.src = scanSources(inst)
		g.scanT = now
	end
	local progress, done
	for _, s in ipairs(g.src) do
		local v = s.kind == "attr" and s.obj:GetAttribute(s.key) or s.obj.Value
		if s.role == "progress" and progress == nil and type(v) == "number" then
			progress = normalize(v)
		elseif s.role == "done" and v == true then
			done = true
		end
	end
	if progress and progress >= GENERATOR_DONE_VALUE then done = true end
	return progress, done or false
end

local function refreshGens()
	for inst, g in pairs(Gens) do
		local p, done = readState(inst, g)

		if Settings.GenESP then
			if not (g.hl and g.hl.Parent) then
				g.hl = makeChams(inst, Settings.GenColor)
				g.hl.Parent = inst
			end
			g.hl.FillColor = done and Settings.GenDoneColor or Settings.GenColor
			g.hl.OutlineColor = g.hl.FillColor
		elseif g.hl then
			g.hl:Destroy() g.hl = nil
		end

		if Settings.GenProgress then
			local part = getPart(inst)
			if part then
				if not (g.bb and g.bb.Parent) then
					g.bb = Instance.new("BillboardGui")
					g.bb.Size = UDim2.fromOffset(90, 22)
					g.bb.StudsOffset = Vector3.new(0, 3, 0)
					g.bb.AlwaysOnTop = true
					g.bb.Adornee = part
					g.bb.Parent = part
					g.lbl = Instance.new("TextLabel")
					g.lbl.Size = UDim2.fromScale(1, 1)
					g.lbl.BackgroundTransparency = 1
					g.lbl.TextStrokeTransparency = 0
					g.lbl.Font = Enum.Font.GothamBold
					g.lbl.TextScaled = true
					g.lbl.Parent = g.bb
				end
				local fmt = "%." .. PROGRESS_DECIMALS .. "f%%"
				if done then
					g.lbl.Text = string.format(fmt, p or 100)
					g.lbl.TextColor3 = Settings.GenDoneColor
				elseif p then
					g.lbl.Text = string.format(fmt, p)
					g.lbl.TextColor3 = Color3.new(1, 1, 1)
				else
					g.lbl.Text = "?"
					g.lbl.TextColor3 = Color3.new(1, 1, 1)
				end
			end
		elseif g.bb then
			g.bb:Destroy() g.bb = nil
		end
	end
end

local acc = 0
track(RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc >= 0.2 then
		acc = 0
		refreshPlayers()
		refreshGens()
	end
end))

-- ===== CAMERA FOV =====
RunService:BindToRenderStep("ClaudeHubFOV", Enum.RenderPriority.Camera.Value + 1, function()
	local c = workspace.CurrentCamera
	if c and c.FieldOfView ~= Settings.FOV then
		c.FieldOfView = Settings.FOV
	end
end)

-- ===== CAMERA STIFFNESS =====
-- Kamera menyusul karakter dengan delay. Stiffness tinggi = kaku/menempel, rendah = longgar/lambat menyusul.
local CAM_MAX_LAG = 8 -- batas jarak (studs) kamera tertinggal
local stiffPos = nil

RunService:BindToRenderStep("ClaudeHubStiff", Enum.RenderPriority.Camera.Value + 2, function(dt)
	local char = LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not Settings.CamStiff or not root then
		stiffPos = nil
		return
	end
	local target = root.Position
	if not stiffPos then stiffPos = target end
	stiffPos = stiffPos:Lerp(target, 1 - math.exp(-Settings.CamStiffness * dt))
	local lag = stiffPos - target
	if lag.Magnitude > CAM_MAX_LAG then
		lag = lag.Unit * CAM_MAX_LAG
		stiffPos = target + lag
	end
	camera.CFrame = camera.CFrame + lag
end)

-- ===== MISC: FULLBRIGHT & NO FOG =====
local origLight, origFog = nil, nil

local function restoreFullbright()
	if origLight then
		for k, v in pairs(origLight) do Lighting[k] = v end
		origLight = nil
	end
end

local function restoreFog()
	if origFog then
		Lighting.FogStart, Lighting.FogEnd = origFog.start, origFog.finish
		local a = Lighting:FindFirstChildOfClass("Atmosphere")
		if a and origFog.density then
			a.Density, a.Haze = origFog.density, origFog.haze
		end
		origFog = nil
	end
end

local function restoreLighting()
	restoreFullbright()
	restoreFog()
end

RunService:BindToRenderStep("ClaudeHubMisc", Enum.RenderPriority.Camera.Value + 3, function()
	if Settings.Fullbright then
		if not origLight then
			origLight = {
				Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime,
				Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
				GlobalShadows = Lighting.GlobalShadows,
			}
		end
		Lighting.Brightness = 2
		Lighting.ClockTime = 14
		Lighting.Ambient = Color3.new(1, 1, 1)
		Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
		Lighting.GlobalShadows = false
	else
		restoreFullbright()
	end

	if Settings.NoFog then
		local a = Lighting:FindFirstChildOfClass("Atmosphere")
		if not origFog then
			origFog = {
				start = Lighting.FogStart, finish = Lighting.FogEnd,
				density = a and a.Density, haze = a and a.Haze,
			}
		end
		Lighting.FogEnd = 1e6
		if a then a.Density, a.Haze = 0, 0 end
	else
		restoreFog()
	end
end)

-- ===== AUTO SKILL CHECK (improved) =====
local skillConn = nil

local function startSkillCheck()
	local function connectUI()
		local CheckGui = PlayerGui:FindFirstChild("SkillCheckPromptGui") or PlayerGui:WaitForChild("SkillCheckPromptGui", 8)
		if not CheckGui then return end

		local Check = CheckGui:FindFirstChild("Check")
		if not Check then return end

		local Line = Check:FindFirstChild("Line")
		local Goal = Check:FindFirstChild("Goal")
		if not (Line and Goal) then return end

		if skillConn then skillConn:Disconnect() skillConn = nil end

		skillConn = Check:GetPropertyChangedSignal("Visible"):Connect(function()
			if not Settings.AutoSkill then return end
			if not (LocalPlayer.Team and LocalPlayer.Team.Name:lower():find("survivor")) then return end

			if Check.Visible then
				local hb
				hb = RunService.Stepped:Connect(function()
					if not Settings.AutoSkill or not Check.Visible then
						if hb then hb:Disconnect() end
						return
					end
					if not (Line and Goal and Line.Parent and Goal.Parent) then return end

					local lr = Line.Rotation % 360
					local gr = Goal.Rotation % 360
					local gs = (gr + 104) % 360
					local ge = (gr + 114) % 360
					local isInside = (gs > ge) and (lr >= gs or lr <= ge) or (lr >= gs and lr <= ge)

					if isInside then
						VIM:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
						VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
						if hb then hb:Disconnect() end
					end
				end)
			end
		end)
	end

	LocalPlayer.CharacterAdded:Connect(function()
		task.wait(1.5)
		connectUI()
	end)
	connectUI()
end

startSkillCheck()

-- ===== UI HELPERS =====
local Theme = {
	Bg = Color3.fromRGB(16, 16, 22),
	Panel = Color3.fromRGB(24, 24, 32),
	Item = Color3.fromRGB(32, 32, 42),
	Accent = Color3.fromRGB(108, 92, 255),
	Text = Color3.fromRGB(240, 240, 245),
	Sub = Color3.fromRGB(140, 140, 160),
	Off = Color3.fromRGB(58, 58, 72),
	Red = Color3.fromRGB(217, 70, 79),
}

local function isTap(i)
	return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
end
local function isMove(i)
	return i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch
end

local function new(class, props, children)
	local inst = Instance.new(class)
	local parent = props.Parent
	props.Parent = nil
	for k, v in pairs(props) do inst[k] = v end
	for _, c in ipairs(children or {}) do c.Parent = inst end
	if parent then inst.Parent = parent end
	return inst
end

local function corner(r) return new("UICorner", { CornerRadius = UDim.new(0, r) }) end
local function pad(p) return new("UIPadding", {
	PaddingTop = UDim.new(0, p), PaddingBottom = UDim.new(0, p),
	PaddingLeft = UDim.new(0, p), PaddingRight = UDim.new(0, p)
}) end
local function tween(o, props, t, style)
	TweenService:Create(o, TweenInfo.new(t or 0.2, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out), props):Play()
end

local parentGui = PlayerGui
pcall(function() if gethui then parentGui = gethui() end end)
local old = parentGui:FindFirstChild("ClaudeHub")
if old then old:Destroy() end

local Gui = new("ScreenGui", {
	Name = "ClaudeHub", ResetOnSpawn = false, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = parentGui
})

local WIN_W, WIN_H, MINI_H = 470, 360, 40
local Window = new("CanvasGroup", {
	Size = UDim2.fromOffset(WIN_W, WIN_H), AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = Theme.Bg,
	BackgroundTransparency = 0, BorderSizePixel = 0, GroupTransparency = 0, Parent = Gui,
}, { corner(12), new("UIStroke", { Color = Theme.Accent, Transparency = 0.6 }) })

local function makeDraggable(handle, target)
	local dragging, dragStart, startPos
	track(handle.InputBegan:Connect(function(input)
		if isTap(input) then
			dragging = true
			dragStart = input.Position
			startPos = target.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end))
	track(UIS.InputChanged:Connect(function(input)
		if dragging and isMove(input) then
			local d = input.Position - dragStart
			target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end))
end

-- Title bar
local TitleBar = new("Frame", {
	Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = Theme.Panel, BorderSizePixel = 0, Parent = Window
})
new("TextLabel", {
	Text = "ClaudeHub", Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = Theme.Text,
	TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
	Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -90, 1, 0), Parent = TitleBar,
})

local function titleButton(text, x, color)
	return new("TextButton", {
		Text = text, Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = Theme.Text,
		BackgroundColor3 = color, Size = UDim2.fromOffset(26, 26),
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, x, 0.5, 0),
		AutoButtonColor = false, Parent = TitleBar,
	}, { corner(7) })
end

local CloseBtn = titleButton("X", -10, Theme.Red)
local MinBtn = titleButton("-", -42, Theme.Item)
makeDraggable(TitleBar, Window)

-- Grip
local Grip = new("Frame", {
	Size = UDim2.fromOffset(200, 32), AnchorPoint = Vector2.new(0.5, 0),
	BackgroundTransparency = 1, Active = true, Parent = Gui,
}, {
	new("Frame", {
		Size = UDim2.fromOffset(180, 7), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0,
	}, { corner(4) }),
})

local MinBtnMinimized = false
local function positionGrip()
	local p, s = Window.Position, Window.Size
	Grip.AnchorPoint = Vector2.new(Window.AnchorPoint.X, 0)
	Grip.Position = UDim2.new(p.X.Scale, p.X.Offset, p.Y.Scale,
		p.Y.Offset + s.Y.Offset * (1 - Window.AnchorPoint.Y) + 6)
end
positionGrip()
track(Window:GetPropertyChangedSignal("Position"):Connect(positionGrip))
track(Window:GetPropertyChangedSignal("Size"):Connect(positionGrip))
makeDraggable(Grip, Window)

-- Body
local Body = new("Frame", {
	Size = UDim2.new(1, 0, 1, -40), Position = UDim2.fromOffset(0, 40),
	BackgroundTransparency = 1, Parent = Window
})
local Sidebar = new("Frame", {
	Size = UDim2.new(0, 110, 1, 0), BackgroundColor3 = Theme.Panel, BorderSizePixel = 0, Parent = Body
}, { pad(8), new("UIListLayout", { Padding = UDim.new(0, 6) }) })
local Content = new("Frame", {
	Size = UDim2.new(1, -110, 1, 0), Position = UDim2.fromOffset(110, 0),
	BackgroundTransparency = 1, Parent = Body
})

-- Color Picker
local Picker = new("Frame", {
	Size = UDim2.fromOffset(190, 190), BackgroundColor3 = Theme.Panel,
	Visible = false, ZIndex = 50, Parent = Gui
}, { corner(10), new("UIStroke", { Color = Theme.Accent, Transparency = 0.4 }), pad(10) })

local SV = new("Frame", {
	Size = UDim2.fromOffset(170, 110), BackgroundColor3 = Color3.fromHSV(1, 1, 1),
	BorderSizePixel = 0, Parent = Picker
}, { corner(6) })
new("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = SV
}, { corner(6), new("UIGradient", {
	Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
}) })
local Dark = new("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Parent = SV
}, { corner(6), new("UIGradient", {
	Rotation = 90,
	Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
}) })
local SVMark = new("Frame", {
	Size = UDim2.fromOffset(10, 10), AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1, Parent = SV
}, { corner(5), new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2 }) })

local Hue = new("Frame", {
	Size = UDim2.fromOffset(170, 14), Position = UDim2.fromOffset(0, 122),
	BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = Picker
}, { corner(7), new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 1, 1)),
		ColorSequenceKeypoint.new(1/6, Color3.fromHSV(1/6, 1, 1)),
		ColorSequenceKeypoint.new(2/6, Color3.fromHSV(2/6, 1, 1)),
		ColorSequenceKeypoint.new(3/6, Color3.fromHSV(3/6, 1, 1)),
		ColorSequenceKeypoint.new(4/6, Color3.fromHSV(4/6, 1, 1)),
		ColorSequenceKeypoint.new(5/6, Color3.fromHSV(5/6, 1, 1)),
		ColorSequenceKeypoint.new(1, Color3.fromHSV(0, 1, 1)),
	})
}) })
local HueMark = new("Frame", {
	Size = UDim2.fromOffset(4, 18), AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = Hue
}, { corner(2) })

local ApplyBtn, CancelBtn
do
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 142),
		BackgroundTransparency = 1, Parent = Picker
	})
	ApplyBtn = new("TextButton", {
		Text = "Apply", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = Color3.new(1,1,1),
		BackgroundColor3 = Theme.Accent, AutoButtonColor = false,
		Size = UDim2.new(0.5, -3, 1, 0), Parent = row
	}, { corner(7) })
	CancelBtn = new("TextButton", {
		Text = "Batal", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = Theme.Sub,
		BackgroundColor3 = Theme.Off, AutoButtonColor = false,
		Size = UDim2.new(0.5, -3, 1, 0), Position = UDim2.new(0.5, 3, 0, 0), Parent = row
	}, { corner(7) })
end

local ph, ps, pv, pkey, dragMode = 0, 1, 1, nil, nil
local function marks()
	SV.BackgroundColor3 = Color3.fromHSV(ph, 1, 1)
	SVMark.Position = UDim2.fromScale(ps, 1 - pv)
	HueMark.Position = UDim2.fromScale(ph, 0.5)
	ApplyBtn.BackgroundColor3 = Color3.fromHSV(ph, ps, pv)
end
local function pickAt(pos)
	if dragMode == "sv" then
		ps = math.clamp((pos.X - SV.AbsolutePosition.X) / SV.AbsoluteSize.X, 0, 1)
		pv = 1 - math.clamp((pos.Y - SV.AbsolutePosition.Y) / SV.AbsoluteSize.Y, 0, 1)
	elseif dragMode == "hue" then
		ph = math.clamp((pos.X - Hue.AbsolutePosition.X) / Hue.AbsoluteSize.X, 0, 0.999)
	else return end
	marks()
end
track(Dark.InputBegan:Connect(function(i) if isTap(i) then dragMode = "sv" pickAt(i.Position) end end))
track(Hue.InputBegan:Connect(function(i) if isTap(i) then dragMode = "hue" pickAt(i.Position) end end))
track(UIS.InputChanged:Connect(function(i) if dragMode and isMove(i) then pickAt(i.Position) end end))
track(UIS.InputEnded:Connect(function(i) if isTap(i) then dragMode = nil end end))

local function openPicker(anchor, key)
	if Picker.Visible and pkey == key then Picker.Visible = false return end
	pkey = key
	ph, ps, pv = Settings[key]:ToHSV()
	marks()
	local ap, as = anchor.AbsolutePosition, anchor.AbsoluteSize
	Picker.AnchorPoint = Vector2.new(1, 0)
	Picker.Position = UDim2.fromOffset(ap.X + as.X, math.clamp(ap.Y + as.Y + 6, 0, Gui.AbsoluteSize.Y - 196))
	Picker.Visible = true
end
ApplyBtn.MouseButton1Click:Connect(function()
	if pkey and Controls[pkey] then Controls[pkey].set(Color3.fromHSV(ph, ps, pv)) end
	Picker.Visible = false
end)
CancelBtn.MouseButton1Click:Connect(function() Picker.Visible = false end)

-- ===== KOMPONEN UI =====
local pages, tabButtons = {}, {}
local function selectTab(name)
	Picker.Visible = false
	for n, p in pairs(pages) do p.Visible = (n == name) end
	for n, b in pairs(tabButtons) do
		local on = (n == name)
		tween(b, {
			BackgroundColor3 = on and Theme.Accent or Theme.Panel,
			TextColor3 = on and Theme.Text or Theme.Sub
		}, 0.15, Enum.EasingStyle.Quad)
	end
end

local function createTab(name)
	local btn = new("TextButton", {
		Text = name, Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = Theme.Sub,
		BackgroundColor3 = Theme.Panel, Size = UDim2.new(1, 0, 0, 34),
		AutoButtonColor = false, Parent = Sidebar
	}, { corner(7) })
	tabButtons[name] = btn
	local page = new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 3, ScrollBarImageColor3 = Theme.Accent,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
		Visible = false, Parent = Content,
	}, { pad(12), new("UIListLayout", { Padding = UDim.new(0, 8) }) })
	pages[name] = page
	btn.MouseButton1Click:Connect(function() selectTab(name) end)
	return page
end

local function row(page, h)
	return new("Frame", {
		Size = UDim2.new(1, 0, 0, h), BackgroundColor3 = Theme.Item, BorderSizePixel = 0, Parent = page
	}, { corner(8) })
end

local function label(parent, text, desc, widthMinus)
	new("TextLabel", {
		Text = text, Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, desc and 8 or 0),
		Size = UDim2.new(1, -widthMinus, 0, desc and 18 or 44), Parent = parent
	})
	if desc then
		new("TextLabel", {
			Text = desc, Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = Theme.Sub,
			TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
			Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -widthMinus, 0, 16), Parent = parent
		})
	end
end

local function addSwatch(parent, key, pos)
	local sw = new("TextButton", {
		Text = "", AutoButtonColor = false, BackgroundColor3 = Settings[key],
		Size = UDim2.fromOffset(26, 26), AnchorPoint = Vector2.new(1, 0.5), Position = pos, Parent = parent
	}, { corner(7), new("UIStroke", { Color = Theme.Text, Transparency = 0.7 }) })
	sw.MouseButton1Click:Connect(function() openPicker(sw, key) end)
	Controls[key] = { set = function(c) Settings[key] = c sw.BackgroundColor3 = c end }
end

local function createToggle(page, key, text, desc, colorKey)
	local r = row(page, 52)
	label(r, text, desc, colorKey and 125 or 80)
	local switch = new("TextButton", {
		Text = "", AutoButtonColor = false, BackgroundColor3 = Theme.Off,
		Size = UDim2.fromOffset(44, 24), AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0), Parent = r
	}, { corner(12) })
	local knob = new("Frame", {
		Size = UDim2.fromOffset(18, 18), AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0), BackgroundColor3 = Theme.Text,
		BorderSizePixel = 0, Parent = switch
	}, { corner(9) })
	local function set(v)
		Settings[key] = v
		tween(switch, { BackgroundColor3 = v and Theme.Accent or Theme.Off }, 0.15, Enum.EasingStyle.Quad)
		tween(knob, {
			Position = v and UDim2.new(1, -21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
		}, 0.15, Enum.EasingStyle.Quad)
	end
	switch.MouseButton1Click:Connect(function() set(not Settings[key]) end)
	Controls[key] = { set = set }
	set(Settings[key])
	if colorKey then addSwatch(r, colorKey, UDim2.new(1, -66, 0.5, 0)) end
end

local function createColor(page, key, text)
	local r = row(page, 44)
	label(r, text, nil, 60)
	addSwatch(r, key, UDim2.new(1, -12, 0.5, 0))
end

local function createSlider(page, key, text, min, max)
	local r = row(page, 58)
	label(r, text, nil, 70)
	r:FindFirstChildWhichIsA("TextLabel").Size = UDim2.new(1, -70, 0, 30)
	local val = new("TextLabel", {
		Text = "", Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = Theme.Accent,
		BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 0), Size = UDim2.fromOffset(50, 30), Parent = r
	})
	local hit = new("Frame", {
		Size = UDim2.new(1, -24, 0, 24), Position = UDim2.fromOffset(12, 30),
		BackgroundTransparency = 1, Parent = r
	})
	local bar = new("Frame", {
		Size = UDim2.new(1, 0, 0, 6), AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5), BackgroundColor3 = Theme.Off, BorderSizePixel = 0, Parent = hit
	}, { corner(3) })
	local fill = new("Frame", {
		Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Parent = bar
	}, { corner(3) })
	local knob = new("Frame", {
		Size = UDim2.fromOffset(16, 16), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5), BackgroundColor3 = Theme.Text, BorderSizePixel = 0, Parent = bar
	}, { corner(8) })
	local function set(v)
		v = math.clamp(math.floor(v + 0.5), min, max)
		Settings[key] = v
		local f = (v - min) / (max - min)
		fill.Size = UDim2.fromScale(f, 1)
		knob.Position = UDim2.fromScale(f, 0.5)
		val.Text = tostring(v)
	end
	local dragging = false
	local function fromX(x)
		set(min + math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1) * (max - min))
	end
	track(hit.InputBegan:Connect(function(i)
		if isTap(i) then dragging = true page.ScrollingEnabled = false fromX(i.Position.X) end
	end))
	track(UIS.InputChanged:Connect(function(i)
		if dragging and isMove(i) then fromX(i.Position.X) end
	end))
	track(UIS.InputEnded:Connect(function(i)
		if dragging and isTap(i) then dragging = false page.ScrollingEnabled = true end
	end))
	Controls[key] = { set = set }
	set(Settings[key])
end

-- ===== PROFIL ROBLOX (sidebar kiri bawah) =====
local Profile = new("Frame", {
	AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
	Size = UDim2.fromOffset(110, 76), BackgroundTransparency = 1, Parent = Body
})
new("Frame", { -- garis pemisah kecil
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0),
	Size = UDim2.new(1, -24, 0, 1), BackgroundColor3 = Theme.Off, BorderSizePixel = 0, Parent = Profile
})
local Avatar = new("ImageLabel", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 9),
	Size = UDim2.fromOffset(38, 38), BackgroundColor3 = Theme.Item, BorderSizePixel = 0,
	Image = "", Parent = Profile
}, { corner(19) })
new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 51),
	Size = UDim2.new(1, -12, 0, 16), BackgroundTransparency = 1, Text = LocalPlayer.DisplayName,
	Font = Enum.Font.GothamMedium, TextSize = 11, TextColor3 = Theme.Sub,
	TextTruncate = Enum.TextTruncate.AtEnd, Parent = Profile
})
task.spawn(function()
	local ok, img = pcall(function()
		return Players:GetUserThumbnailAsync(LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
	end)
	if ok and img and Avatar.Parent then Avatar.Image = img end
end)

-- ===== TAB VISUALS =====
local Visuals = createTab("Visuals")
createSlider(Visuals, "FOV", "Camera FOV", 70, 120)
createToggle(Visuals, "PlayerESP", "Player ESP", "Chams tipis, Killer & Survivor")
createColor(Visuals, "KillerColor", "Killer Color")
createColor(Visuals, "SurvivorColor", "Survivor Color")
createToggle(Visuals, "GenESP", "Generator ESP", "Kuning, hijau saat selesai", "GenColor")
createToggle(Visuals, "GenProgress", "Generator Progress", "Persen di atas generator")

-- ===== TAB SURVIVOR =====
local Survivor = createTab("Survivor")
createToggle(Survivor, "CamStiff", "Camera Stiffness", "Kamera menyusul karakter dengan delay halus")
createSlider(Survivor, "CamStiffness", "Stiffness (rendah = longgar)", 1, 20)
createToggle(Survivor, "AutoSkill", "Auto Skill Check", "Perfect skill check otomatis (Survivor)")

-- ===== TAB MISC =====
local Misc = createTab("Misc")
createToggle(Misc, "Fullbright", "Fullbright", "Terang penuh, tanpa bayangan gelap")
createToggle(Misc, "NoFog", "No Fog", "Hilangkan kabut dan haze")

-- ===== TAB CONFIG =====
local hasFS = type(writefile) == "function" and type(readfile) == "function"
	and type(listfiles) == "function" and type(isfolder) == "function"
	and type(makefolder) == "function" and type(delfile) == "function"

if hasFS then
	pcall(function() if not isfolder(CONFIG_FOLDER) then makefolder(CONFIG_FOLDER) end end)
end

local memConfigs = {}
local function listConfigs()
	local out = {}
	if hasFS then
		local ok, files = pcall(listfiles, CONFIG_FOLDER)
		if ok then
			for _, f in ipairs(files) do
				local n = f:match("([^/\\]+)%.json$")
				if n then table.insert(out, n) end
			end
		end
	else
		for n in pairs(memConfigs) do table.insert(out, n) end
	end
	table.sort(out)
	return out
end

local function serialize()
	local t = {}
	for k, v in pairs(Settings) do
		t[k] = typeof(v) == "Color3" and { r = v.R, g = v.G, b = v.B } or v
	end
	return HttpService:JSONEncode(t)
end

local function saveConfig(name)
	local data = serialize()
	if hasFS then
		writefile(CONFIG_FOLDER .. "/" .. name .. ".json", data)
	else
		memConfigs[name] = data
	end
end

local function loadConfig(name)
	local raw
	if hasFS then
		local ok, r = pcall(readfile, CONFIG_FOLDER .. "/" .. name .. ".json")
		raw = ok and r or nil
	else
		raw = memConfigs[name]
	end
	if not raw then return false end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok then return false end
	for k, v in pairs(data) do
		if Controls[k] then
			Controls[k].set(type(v) == "table" and Color3.new(v.r, v.g, v.b) or v)
		end
	end
	return true
end

local function deleteConfig(name)
	if hasFS then
		pcall(delfile, CONFIG_FOLDER .. "/" .. name .. ".json")
	else
		memConfigs[name] = nil
	end
end

local Config = createTab("Config")
local nameRow = new("Frame", {
	Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, Parent = Config
})
local NameBox = new("TextBox", {
	Text = "", PlaceholderText = "Config name", PlaceholderColor3 = Theme.Sub,
	Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = Theme.Text,
	ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left,
	BackgroundColor3 = Theme.Panel, Size = UDim2.new(1, -76, 1, 0), Parent = nameRow
}, { corner(7), new("UIPadding", { PaddingLeft = UDim.new(0, 10) }) })

local function makeButton(parent, text, color, size, pos, anchor)
	return new("TextButton", {
		Text = text, Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = Theme.Text,
		BackgroundColor3 = color, AutoButtonColor = false, Size = size,
		Position = pos or UDim2.new(), AnchorPoint = anchor or Vector2.new(), Parent = parent
	}, { corner(7) })
end

local SaveBtn = makeButton(nameRow, "Save", Theme.Accent, UDim2.new(0, 70, 1, 0), UDim2.fromScale(1, 0), Vector2.new(1, 0))
local ListFrame = new("ScrollingFrame", {
	Size = UDim2.new(1, 0, 0, 104), BackgroundColor3 = Theme.Item, BorderSizePixel = 0,
	ScrollBarThickness = 3, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = Config
}, { corner(8), pad(6), new("UIListLayout", { Padding = UDim.new(0, 4) }) })

local btnRow = new("Frame", {
	Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, Parent = Config
})
local LoadBtn = makeButton(btnRow, "Load", Theme.Accent, UDim2.new(0.5, -4, 1, 0))
local DelBtn = makeButton(btnRow, "Delete", Theme.Red, UDim2.new(0.5, -4, 1, 0), UDim2.fromScale(1, 0), Vector2.new(1, 0))

local Status = new("TextLabel", {
	Text = hasFS and "" or "Penyimpanan file tidak tersedia, config hanya sementara",
	Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = Theme.Sub,
	TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 16), Parent = Config
})

local selected
local function rebuildList()
	for _, c in ipairs(ListFrame:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
	for _, n in ipairs(listConfigs()) do
		local on = (n == selected)
		local b = new("TextButton", {
			Text = n, Font = Enum.Font.GothamMedium, TextSize = 12,
			TextColor3 = on and Theme.Text or Theme.Sub,
			BackgroundColor3 = on and Theme.Accent or Theme.Panel,
			Size = UDim2.new(1, 0, 0, 28), AutoButtonColor = false, Parent = ListFrame
		}, { corner(6) })
		b.MouseButton1Click:Connect(function()
			selected = n
			NameBox.Text = n
			rebuildList()
		end)
	end
end

SaveBtn.MouseButton1Click:Connect(function()
	local n = NameBox.Text:gsub("[^%w_%- ]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	if n == "" then Status.Text = "Isi nama config dulu" return end
	saveConfig(n)
	selected = n
	rebuildList()
	Status.Text = "Tersimpan: " .. n
end)
LoadBtn.MouseButton1Click:Connect(function()
	if not selected then Status.Text = "Pilih config dulu" return end
	Status.Text = loadConfig(selected) and ("Dimuat: " .. selected) or "Gagal memuat config"
end)
DelBtn.MouseButton1Click:Connect(function()
	if not selected then Status.Text = "Pilih config dulu" return end
	deleteConfig(selected)
	Status.Text = "Dihapus: " .. selected
	selected = nil
	rebuildList()
end)

rebuildList()
selectTab("Visuals")

-- ===== MINIMIZE / OPEN / CLOSE =====
local function setMini(v)
	MinBtnMinimized = v
	Picker.Visible = false
	tween(Window, {
		Size = v and UDim2.fromOffset(WIN_W, MINI_H) or UDim2.fromOffset(WIN_W, WIN_H)
	}, 0.22)
	task.delay(v and 0 or 0.05, function() Body.Visible = not v end)
	if v then
		task.delay(0.1, function() if MinBtnMinimized then Body.Visible = false end end)
	end
	task.spawn(function()
		for i = 1, 8 do task.wait(0.025) positionGrip() end
	end)
end
MinBtn.MouseButton1Click:Connect(function() setMini(not MinBtnMinimized) end)

local isOpen = true
local function setOpen(v)
	if v == isOpen then return end
	isOpen = v
	Picker.Visible = false
	if v then
		Window.Visible, Grip.Visible = true, true
		Window.Size = UDim2.fromOffset(1, MinBtnMinimized and MINI_H or 1)
		Window.GroupTransparency = 1
		tween(Window, {
			Size = UDim2.fromOffset(WIN_W, MinBtnMinimized and MINI_H or WIN_H),
			GroupTransparency = 0
		}, 0.22)
	else
		tween(Window, { Size = UDim2.fromOffset(1, 1), GroupTransparency = 1 }, 0.18)
		task.delay(0.18, function()
			if not isOpen then Window.Visible, Grip.Visible = false, false end
		end)
	end
end

local Float = new("TextButton", {
	Text = "≡", Font = Enum.Font.GothamBold, TextSize = 20, TextColor3 = Theme.Text,
	BackgroundColor3 = Theme.Accent, Size = UDim2.fromOffset(40, 40),
	Position = UDim2.new(0, 12, 0.5, -20), AutoButtonColor = false, Parent = Gui,
}, { corner(20) })
Float.MouseButton1Click:Connect(function() setOpen(not isOpen) end)

track(UIS.InputBegan:Connect(function(input)
	if input.KeyCode == TOGGLE_KEY and not UIS:GetFocusedTextBox() then
		setOpen(not isOpen)
	end
end))

CloseBtn.MouseButton1Click:Connect(function()
	pcall(function() RunService:UnbindFromRenderStep("ClaudeHubFOV") end)
	Settings.CamStiff = false
	Settings.Fullbright = false
	Settings.NoFog = false
	restoreLighting()
	pcall(function() RunService:UnbindFromRenderStep("ClaudeHubMisc") end)
	pcall(function() RunService:UnbindFromRenderStep("ClaudeHubStiff") end)
	Settings.PlayerESP = false
	Settings.GenESP = false
	Settings.GenProgress = false
	Settings.AutoSkill = false
	refreshPlayers()
	refreshGens()
	if skillConn then skillConn:Disconnect() end
	for _, c in ipairs(connections) do c:Disconnect() end
	Gui:Destroy()
end)
