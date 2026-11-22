-- HUD principal (v3), fiel ao mockup hud-v2.html aprovado (palco 1920x1080).
-- Mantém a mesma arquitetura e contrato de atributos da v2, refazendo toda a
-- camada visual com ImageLabels (PNGs brancos tingidos via ImageColor3) e
-- minimapa 3D real em ViewportFrame com culling espacial para StreamingEnabled.
--
-- Atributos no Player:
--   Bank, Cash (number)
--   WantedLevel (0-5), WantedState ("hollow" | "gray" | "white" | "flash" | "red")
--   CameraSeen, CarMarked (boolean) -> badges vermelhos
--   PartyJson (string JSON, até 4): [{"name":"Malandro","color":"#4BE08A","icon":"mask","hp":0.8}]
--   GpsText, GpsSub (string), GpsDir ("left" | "right" | "straight"), GpsTarget (Vector3)
-- Atributos no VehicleSeat (quando sentado): Fuel, Engine (0..1), Locked, Lights (boolean), Odometer (km)
-- Atributos na Tool: Weapon, Ammo, Reloading (já existem), Reserve, DisplayName (opcionais)
-- Pins no minimapa: tag "MapPin" em BasePart, atributos Icon (string) e Color (Color3)
local HudController = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponConfig = require(ReplicatedStorage.Weapons.Config)

local player = Players.LocalPlayer

-- IDs de imagem preenchidos pelo orquestrador (PNGs brancos tingidos via ImageColor3)
local IMG = {
	circle = "rbxassetid://112605615657145",
	glow_soft = "rbxassetid://103339733566500",
	gun = "rbxassetid://76902129797464",
	icon_atm = "rbxassetid://94444742745559",
	icon_bag = "rbxassetid://136655654623935",
	icon_bank = "rbxassetid://106293546671768",
	icon_camera = "rbxassetid://132231809228943",
	icon_car = "rbxassetid://91915019777420",
	icon_carFlag = "rbxassetid://128773341946083",
	icon_crowbar = "rbxassetid://114040304760003",
	icon_engine = "rbxassetid://85947314102486",
	icon_flag = "rbxassetid://103210334493405",
	icon_fuel = "rbxassetid://108667973068562",
	icon_house = "rbxassetid://118094755697564",
	icon_key = "rbxassetid://123358571255849",
	icon_light = "rbxassetid://101043625612896",
	icon_lock = "rbxassetid://131619603879316",
	icon_mask = "rbxassetid://113462074354674",
	icon_people = "rbxassetid://76588522656859",
	icon_sack = "rbxassetid://89940533848043",
	icon_shield = "rbxassetid://109480723605696",
	icon_shirt = "rbxassetid://98174217568288",
	icon_turnRight = "rbxassetid://113544172785646",
	icon_wallet = "rbxassetid://127908758155267",
	player_arrow = "rbxassetid://81465749495569",
	ring = "rbxassetid://82610300285660",
	star_fill = "rbxassetid://101477069091330",
	star_stroke = "rbxassetid://118597632005627",
	star_stroke_thick = "rbxassetid://84714655760875",
}

local REF_H = 1080
local MARGIN_X, MARGIN_Y = 56, 44
local BR_MARGIN_Y = 40
local MAP_W, MAP_H = 400, 260
local PLAYER_PX, PLAYER_PY = 200, 185
local STUD_M = 0.28

-- parâmetros do ViewportFrame do minimapa
local MAP_FOV = 35
local MAP_CAM_HEIGHT = 240 -- inclinação 45° + jogador exatamente em (200, 185)
local MAP_CAM_BACK = 183.5
local MAP_CAM_FWD = 56.5
local CELL_SIZE = 128
local VIEW_RADIUS = 400
local CULL_RADIUS = 464 -- histerese para não clonar/destruir na borda
local MAX_CLONES = 6000
local SCAN_BUDGET = 300 -- candidatos avaliados por frame
local CLONE_BUDGET = 40 -- clones instanciados por frame
local MIN_PART_SIZE = 3

local C = {
	white = Color3.new(1, 1, 1),
	black = Color3.new(0, 0, 0),
	gray = Color3.fromRGB(138, 143, 153),
	sweepGray = Color3.fromRGB(126, 131, 142),
	red = Color3.fromRGB(255, 59, 59),
	redStroke = Color3.fromRGB(42, 6, 6),
	lowAmmo = Color3.fromRGB(255, 90, 74),
	badge = Color3.fromRGB(194, 29, 29),
	badgeRing = Color3.fromRGB(20, 7, 10),
	gold = Color3.fromRGB(242, 179, 61),
	green = Color3.fromRGB(75, 224, 138),
	orange = Color3.fromRGB(255, 122, 26),
	amber = Color3.fromRGB(255, 178, 30),
	fuelRed = Color3.fromRGB(255, 74, 61),
	glass = Color3.fromRGB(10, 11, 15),
	barBg = Color3.fromRGB(8, 9, 12),
	strokeDark = Color3.fromRGB(10, 11, 14),
	pinIconDark = Color3.fromRGB(17, 17, 17),
	ink = Color3.fromRGB(23, 10, 2),
	routeDark = Color3.fromRGB(26, 12, 2),
}

-- paletas do minimapa por ciclo do dia (derivadas de PAL no HTML)
local PAL = {
	dia = {
		ground = Color3.fromRGB(200, 151, 122),
		ambient = Color3.fromRGB(165, 155, 145),
		lightColor = Color3.fromRGB(255, 245, 230),
		lightDir = Vector3.new(-0.4, -1, -0.3),
		tint = Color3.fromRGB(255, 250, 244),
	},
	tarde = {
		ground = Color3.fromRGB(184, 116, 88),
		ambient = Color3.fromRGB(160, 118, 102),
		lightColor = Color3.fromRGB(255, 185, 130),
		lightDir = Vector3.new(-0.7, -0.6, -0.3),
		tint = Color3.fromRGB(255, 224, 200),
	},
	noite = {
		ground = Color3.fromRGB(35, 42, 59),
		ambient = Color3.fromRGB(58, 72, 108),
		lightColor = Color3.fromRGB(110, 135, 190),
		lightDir = Vector3.new(0.2, -1, 0.4),
		tint = Color3.fromRGB(175, 195, 235),
	},
}

local FONT_NUM = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
local FONT_NUM_SEMI = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.SemiBold)
local FONT_UI_MED = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Medium)
local FONT_UI_SEMI = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.SemiBold)
local FONT_UI_BOLD = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold)
local FONT_UI_EXTRA = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.ExtraBold)

local COLLAPSE_TWEEN = TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

-- ---------- helpers ----------
local function make(class: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(class)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function corner(r: number): UICorner
	return make("UICorner", { CornerRadius = UDim.new(0, r) })
end

local function round(): UICorner
	return make("UICorner", { CornerRadius = UDim.new(1, 0) })
end

local function textShadow(label: TextLabel)
	make("UIStroke", {
		Color = C.black,
		Transparency = 0.6,
		Thickness = 1,
		Parent = label,
	})
end

local function text(props: { [string]: any }, shadow: boolean?): TextLabel
	if props.BackgroundTransparency == nil then
		props.BackgroundTransparency = 1
	end
	props.TextColor3 = props.TextColor3 or C.white
	props.FontFace = props.FontFace or FONT_UI_SEMI
	local lbl = make("TextLabel", props)
	if shadow then
		textShadow(lbl)
	end
	return lbl
end

local function imgLabel(props: { [string]: any }): ImageLabel
	if props.BackgroundTransparency == nil then
		props.BackgroundTransparency = 1
	end
	if props.ScaleType == nil then
		props.ScaleType = Enum.ScaleType.Fit
	end
	return make("ImageLabel", props)
end

local function iconAsset(name: string?): string
	if typeof(name) ~= "string" or name == "" then
		return "rbxassetid://0"
	end
	return IMG["icon_" .. name] or IMG[name] or "rbxassetid://0"
end

local function hlist(parent: Instance, align: Enum.HorizontalAlignment, pad: number, valign: Enum.VerticalAlignment?)
	return make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = align,
		VerticalAlignment = valign or Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, pad),
		Parent = parent,
	})
end

-- formato pt-BR sem espaço após $: "$40.924"
local function money(n: number): string
	local s = tostring(math.floor(math.abs(n) + 0.5))
	s = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	if s:sub(1, 1) == "." then
		s = s:sub(2)
	end
	return (if n < 0 then "-$" else "$") .. s
end

local function escapeRichText(s: string): string
	return s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
end

-- emula letter-spacing com thin space entre caracteres
local function spacedText(s: string): string
	local out = {}
	for _, code in utf8.codes(s) do
		table.insert(out, utf8.char(code))
	end
	return table.concat(out, "\u{2009}")
end

local function num(name: string, default: number): number
	local v = player:GetAttribute(name)
	return if typeof(v) == "number" then v else default
end

local function str(name: string, default: string): string
	local v = player:GetAttribute(name)
	return if typeof(v) == "string" then v else default
end

-- ponto na borda do minimapa (400x260) na direção angleDeg (0 = cima, sentido horário)
local function edgePos(angleDeg: number, inset: number): (number, number)
	local a = math.rad(angleDeg)
	local dx, dy = math.sin(a), -math.cos(a)
	local hw, hh = MAP_W / 2 - inset, MAP_H / 2 - inset
	local t = math.min(hw / math.max(math.abs(dx), 1e-4), hh / math.max(math.abs(dy), 1e-4))
	return dx * t, dy * t
end

-- projeção exata para a proporção 400x260 do ViewportFrame (independe de Camera.ViewportSize)
local HALF_TAN_Y = math.tan(math.rad(MAP_FOV * 0.5))
local HALF_TAN_X = HALF_TAN_Y * (MAP_W / MAP_H)

local function projectPoint(camCF: CFrame, worldPos: Vector3): (number, number, number)
	local rel = camCF:PointToObjectSpace(worldPos)
	local depth = -rel.Z
	if depth <= 0.1 then
		return 0, 0, depth
	end
	local sx = MAP_W * (0.5 + (rel.X / (depth * HALF_TAN_X)) * 0.5)
	local sy = MAP_H * (0.5 - (rel.Y / (depth * HALF_TAN_Y)) * 0.5)
	return sx, sy, depth
end

-- arco denso (~2° por segmento) para traço contínuo no velocímetro
local function buildArc(
	parent: Instance,
	cx: number,
	cy: number,
	radius: number,
	a0: number,
	a1: number,
	stepDeg: number,
	thickness: number,
	color: Color3,
	zIndex: number
): { Frame }
	local segs = {}
	local span = a1 - a0
	local count = math.max(1, math.ceil(math.abs(span) / stepDeg))
	local segArc = radius * math.rad(math.abs(span) / count)
	local segLen = math.max(thickness, segArc + thickness * 0.55)
	local radCorner = math.max(1, math.floor(thickness * 0.5 + 0.5))
	for i = 1, count do
		local a = a0 + span * (i - 0.5) / count
		local r = math.rad(a)
		segs[i] = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cx + radius * math.cos(r), cy + radius * math.sin(r)),
			Size = UDim2.fromOffset(segLen, thickness),
			Rotation = a + 90,
			BorderSizePixel = 0,
			BackgroundColor3 = color,
			ZIndex = zIndex,
			Parent = parent,
		}, { corner(radCorner) })
	end
	return segs
end

-- ---------- estado ----------
type StarSlot = {
	root: Frame,
	glow: ImageLabel,
	fill: ImageLabel,
	stroke: ImageLabel,
	grad: UIGradient,
}

type BadgeSlot = {
	root: Frame,
	ping: Frame,
	pingStroke: UIStroke,
}

type PinEntry = {
	root: Frame,
	ring: UIStroke,
	edgeRing: Frame,
	edgeStroke: UIStroke,
	icon: ImageLabel,
	isDot: boolean,
}

local ui: { [string]: any } = {}
local stars: { StarSlot } = {}
local wantedLevel, wantedState = 0, "white"
local partyRows: { { frame: Frame, fill: Frame, hp: number } } = {}
local pinUi: { [any]: PinEntry } = {}

local speedSegs: { Frame } = {}
local speedGlowSegs: { Frame } = {}
local fuelSegs: { Frame } = {}
local engineSegs: { Frame } = {}
local lastSpeedLit, lastFuelLit, lastEngLit = -1, -1, -1
local lastFuelLow: boolean? = nil
local lastEngCol: Color3? = nil

local lastCash: number? = nil
local cashAnimFrom, cashAnimTo, cashAnimStart = 0, 0, -10
local deltaStart = -10
local shownSpeed, odometerKm = 0, 0
local odoSeat: VehicleSeat? = nil
local palName = ""

-- estado do ViewportFrame espacial (StreamingEnabled)
local grid: { [number]: { [BasePart]: number } } = {}
local partCell: { [BasePart]: number } = {}
local clones: { [BasePart]: BasePart } = {}
local cloneCount = 0
local excludedModels: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local scanQueue: { BasePart } = {}
local scanHead = 1
local removeQueue: { BasePart } = {}
local removeHead = 1
local lastPlayerCellX, lastPlayerCellZ = math.huge, math.huge
local rescanTimer = 0
local mapRootsStatic = { MiamiCity = true, District_Blockout = true }

local function cellKey(cx: number, cz: number): number
	return (cx + 32768) * 65536 + (cz + 32768)
end

local function cellCoords(pos: Vector3): (number, number)
	return math.floor(pos.X / CELL_SIZE), math.floor(pos.Z / CELL_SIZE)
end

local function isPartExcluded(part: BasePart): boolean
	if part:IsA("Terrain") or part:IsA("VehicleSeat") then
		return true
	end
	if not part.Archivable or part.Transparency >= 0.9 then
		return true
	end
	local sz = part.Size
	if math.max(sz.X, sz.Y, sz.Z) < MIN_PART_SIZE then
		return true
	end
	local anc: Instance? = part.Parent
	while anc and anc ~= workspace do
		if excludedModels[anc] or anc:IsA("Tool") or anc:IsA("Camera") then
			return true
		end
		if anc:IsA("Model") then
			if Players:GetPlayerFromCharacter(anc) ~= nil then
				excludedModels[anc] = true
				return true
			end
			if not mapRootsStatic[anc.Name] then
				if anc:FindFirstChildOfClass("Humanoid") or anc:FindFirstChildOfClass("VehicleSeat") then
					excludedModels[anc] = true
					return true
				end
			end
		end
		anc = anc.Parent
	end
	return anc ~= workspace
end

local function destroyClone(part: BasePart)
	local c = clones[part]
	if c then
		c:Destroy()
		clones[part] = nil
		cloneCount -= 1
	end
end

local function unregisterPart(inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	local key = partCell[inst]
	if key then
		local bucket = grid[key]
		if bucket then
			bucket[inst] = nil
			if next(bucket) == nil then
				grid[key] = nil
			end
		end
		partCell[inst] = nil
	end
	destroyClone(inst)
end

local function registerPart(inst: Instance)
	if not inst:IsA("BasePart") or partCell[inst] then
		return
	end
	if isPartExcluded(inst) then
		return
	end
	local cx, cz = cellCoords(inst.Position)
	local key = cellKey(cx, cz)
	local bucket = grid[key]
	if not bucket then
		bucket = {}
		grid[key] = bucket
	end
	local sz = inst.Size
	bucket[inst] = math.max(sz.X, sz.Y, sz.Z)
	partCell[inst] = key
	-- se chegou já dentro das células ativas, entra na fila de scan
	if math.abs(cx - lastPlayerCellX) <= 3 and math.abs(cz - lastPlayerCellZ) <= 3 then
		table.insert(scanQueue, inst)
	end
end

local function markExcludedAncestor(inst: Instance)
	-- sobe até o Model imediatamente abaixo de workspace (ou do container de mapa) para excluir veículos/NPCs
	local target: Instance? = nil
	local anc: Instance? = inst.Parent
	while anc and anc ~= workspace do
		if anc:IsA("Model") and not mapRootsStatic[anc.Name] then
			target = anc
		end
		anc = anc.Parent
	end
	if target and not excludedModels[target] then
		excludedModels[target] = true
		for _, d in target:GetDescendants() do
			if d:IsA("BasePart") then
				unregisterPart(d)
			end
		end
	end
end

local function clonePartToViewport(part: BasePart): BasePart?
	if not part.Parent or not part.Archivable or isPartExcluded(part) then
		return nil
	end
	local ok, copy = pcall(part.Clone, part)
	if not ok or not copy then
		return nil
	end
	for _, child in copy:GetChildren() do
		if not child:IsA("SpecialMesh") then
			child:Destroy()
		end
	end
	copy.Anchored = true
	copy.CanCollide = false
	copy.CanTouch = false
	copy.CanQuery = false
	copy.CastShadow = false
	copy.Parent = ui.vp
	return copy
end

local function rebuildQueuesAround(pos: Vector3)
	local pcx, pcz = cellCoords(pos)
	lastPlayerCellX, lastPlayerCellZ = pcx, pcz

	-- agenda remoção de clones fora do raio de histerese
	table.clear(removeQueue)
	removeHead = 1
	local cullSq = CULL_RADIUS * CULL_RADIUS
	for src in clones do
		local d = src.Position - pos
		if not src.Parent or (d.X * d.X + d.Z * d.Z) > cullSq then
			table.insert(removeQueue, src)
		end
	end

	-- coleta candidatos das células 7x7 em 3 faixas de tamanho (prefere peças maiores até MAX_CLONES)
	table.clear(scanQueue)
	scanHead = 1
	local big, med, small = {}, {}, {}
	local cellRad = math.ceil(VIEW_RADIUS / CELL_SIZE)
	for dx = -cellRad, cellRad do
		for dz = -cellRad, cellRad do
			local bucket = grid[cellKey(pcx + dx, pcz + dz)]
			if bucket then
				for part, maxAxis in bucket do
					if not clones[part] then
						if maxAxis >= 16 then
							table.insert(big, part)
						elseif maxAxis >= 6 then
							table.insert(med, part)
						else
							table.insert(small, part)
						end
					end
				end
			end
		end
	end
	for _, p in big do table.insert(scanQueue, p) end
	for _, p in med do table.insert(scanQueue, p) end
	for _, p in small do table.insert(scanQueue, p) end
end

local function stepViewportQueue(playerPos: Vector3)
	local checked = 0
	-- 1) remove clones distantes
	while removeHead <= #removeQueue and checked < SCAN_BUDGET do
		local src = removeQueue[removeHead]
		removeHead += 1
		checked += 1
		destroyClone(src)
	end
	if removeHead > #removeQueue then
		table.clear(removeQueue)
		removeHead = 1
	end

	-- 2) clona peças próximas dentro do orçamento por frame e do teto MAX_CLONES
	local clonedNow = 0
	local radSq = VIEW_RADIUS * VIEW_RADIUS
	while scanHead <= #scanQueue and checked < SCAN_BUDGET and clonedNow < CLONE_BUDGET and cloneCount < MAX_CLONES do
		local src = scanQueue[scanHead]
		scanHead += 1
		checked += 1
		if not clones[src] and src.Parent then
			local d = src.Position - playerPos
			if (d.X * d.X + d.Z * d.Z) <= radSq then
				local copy = clonePartToViewport(src)
				if copy then
					clones[src] = copy
					cloneCount += 1
					clonedNow += 1
				end
			end
		end
	end
	if scanHead > #scanQueue then
		table.clear(scanQueue)
		scanHead = 1
	end
end

local function watchWorkspaceMap()
	local function onCharacter(char: Model)
		excludedModels[char] = true
		for _, d in char:GetDescendants() do
			if d:IsA("BasePart") then
				unregisterPart(d)
			end
		end
	end
	for _, plr in Players:GetPlayers() do
		if plr.Character then
			onCharacter(plr.Character)
		end
		plr.CharacterAdded:Connect(onCharacter)
	end
	Players.PlayerAdded:Connect(function(plr)
		plr.CharacterAdded:Connect(onCharacter)
	end)

	workspace.DescendantAdded:Connect(function(inst)
		if inst:IsA("Humanoid") or inst:IsA("VehicleSeat") then
			markExcludedAncestor(inst)
		elseif inst:IsA("BasePart") then
			registerPart(inst)
		end
	end)
	workspace.DescendantRemoving:Connect(function(inst)
		if inst:IsA("BasePart") then
			unregisterPart(inst)
		end
	end)

	-- indexação inicial fatiada para não travar em mapas com ~163k peças
	task.spawn(function()
		local budget = 0
		for _, top in workspace:GetChildren() do
			if top ~= workspace.Terrain and top ~= workspace.CurrentCamera and not Players:GetPlayerFromCharacter(top) then
				if top:IsA("BasePart") then
					registerPart(top)
				else
					for _, desc in top:GetDescendants() do
						if desc:IsA("Humanoid") or desc:IsA("VehicleSeat") then
							markExcludedAncestor(desc)
						elseif desc:IsA("BasePart") then
							registerPart(desc)
						end
						budget += 1
						if budget >= 2000 then
							budget = 0
							task.wait()
						end
					end
				end
			end
		end
		lastPlayerCellX = math.huge -- força montagem da fila ao terminar
	end)
end

-- ---------- canto superior direito: procurado + dinheiro ----------
local function buildTopRight(root: Frame)
	local box = make("Frame", {
		Name = "TopRight",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -MARGIN_X, 0, MARGIN_Y),
		Size = UDim2.fromOffset(520, 320),
		BackgroundTransparency = 1,
		Parent = root,
	})
	make("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 10),
		Parent = box,
	})

	-- bloco procurado colapsável (.collapse#wantedWrap)
	local wantedWrap = make("CanvasGroup", {
		Name = "WantedWrap",
		Size = UDim2.fromOffset(300, 0),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		ClipsDescendants = true,
		LayoutOrder = 1,
		Parent = box,
	})
	ui.wantedWrap = wantedWrap

	local wanted = make("Frame", {
		Name = "Wanted",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(292, 110),
		BackgroundTransparency = 1,
		Parent = wantedWrap,
	})
	make("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = wanted,
	})

	-- 5 slots de estrela sempre presentes (46px, gap 6)
	local starsRow = make("Frame", {
		Name = "Stars",
		Size = UDim2.fromOffset(5 * 46 + 4 * 6, 46),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = wanted,
	})
	hlist(starsRow, Enum.HorizontalAlignment.Right, 6)
	ui.starsRow = starsRow

	local flashSeq = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C.white),
		ColorSequenceKeypoint.new(0.4, C.white),
		ColorSequenceKeypoint.new(0.6, C.sweepGray),
		ColorSequenceKeypoint.new(1, C.sweepGray),
	})

	for i = 1, 5 do
		local slot = make("Frame", {
			Name = "Star" .. i,
			Size = UDim2.fromOffset(46, 46),
			BackgroundTransparency = 1,
			LayoutOrder = 6 - i, -- estrela 1 fica na direita: enchem da direita pra esquerda
			Parent = starsRow,
		})
		local glow = imgLabel({
			Name = "Glow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(66, 66),
			Image = IMG.glow_soft,
			ImageColor3 = C.red,
			ImageTransparency = 0.25,
			Visible = false,
			ZIndex = 1,
			Parent = slot,
		})
		local fill = imgLabel({
			Name = "Fill",
			Size = UDim2.fromScale(1, 1),
			Image = IMG.star_fill,
			ImageColor3 = C.white,
			ZIndex = 2,
			Parent = slot,
		})
		local grad = make("UIGradient", {
			Enabled = false,
			Color = flashSeq,
			Rotation = 17,
			Parent = fill,
		})
		local stroke = imgLabel({
			Name = "Stroke",
			Size = UDim2.fromScale(1, 1),
			Image = IMG.star_stroke,
			ImageColor3 = C.strokeDark,
			ZIndex = 3,
			Parent = slot,
		})
		stars[i] = { root = slot, glow = glow, fill = fill, stroke = stroke, grad = grad }
	end

	-- badges ABAIXO das estrelas (36px, gap 8)
	local badgesRow = make("Frame", {
		Name = "Badges",
		Size = UDim2.fromOffset(200, 36),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Visible = false,
		Parent = wanted,
	})
	hlist(badgesRow, Enum.HorizontalAlignment.Right, 8)
	ui.badgesRow = badgesRow

	local function makeBadge(name: string, imgId: string, order: number): BadgeSlot
		local b = make("Frame", {
			Name = name,
			Size = UDim2.fromOffset(36, 36),
			BackgroundColor3 = C.badge,
			LayoutOrder = order,
			Visible = false,
			Parent = badgesRow,
		}, {
			round(),
			make("UIStroke", { Color = C.badgeRing, Thickness = 2 }),
		})
		local ping = make("Frame", {
			Name = "Ping",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(36, 36),
			BackgroundTransparency = 1,
			ZIndex = 0,
			Parent = b,
		}, { round() })
		local pingStroke = make("UIStroke", { Color = C.red, Thickness = 2, Transparency = 0.3, Parent = ping })
		imgLabel({
			Name = "Icon",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(20, 20),
			Image = imgId,
			ImageColor3 = C.white,
			ZIndex = 2,
			Parent = b,
		})
		return { root = b, ping = ping, pingStroke = pingStroke }
	end
	ui.badgeCam = makeBadge("Camera", IMG.icon_camera, 1)
	ui.badgeCar = makeBadge("CarFlag", IMG.icon_carFlag, 2)

	-- dinheiro (.money): banco + carteira, valor branco à esquerda, caixa de ícone à direita
	local moneyCol = make("Frame", {
		Name = "Money",
		Size = UDim2.fromOffset(420, 100),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = box,
	})
	make("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = moneyCol,
	})

	local function makeMoneyRow(name: string, order: number, fontSize: number, accent: Color3, imgId: string)
		local row = make("Frame", {
			Name = name,
			Size = UDim2.fromOffset(420, 44),
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Parent = moneyCol,
		})
		local inner = make("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.fromOffset(0, 44),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Parent = row,
		})
		hlist(inner, Enum.HorizontalAlignment.Right, 12)
		local val = text({
			Name = "Value",
			Size = UDim2.fromOffset(0, 44),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = "$0",
			TextSize = fontSize,
			TextColor3 = C.white,
			FontFace = FONT_NUM,
			LayoutOrder = 1,
			Parent = inner,
		}, true)
		local icBox = make("Frame", {
			Name = "IconBox",
			Size = UDim2.fromOffset(40, 40),
			BackgroundColor3 = C.glass,
			BackgroundTransparency = 0.22,
			LayoutOrder = 2,
			Parent = inner,
		}, {
			corner(11),
			make("UIStroke", { Color = accent, Thickness = 1.5, Transparency = 0.45 }),
		})
		imgLabel({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(22, 22),
			Image = imgId,
			ImageColor3 = accent,
			Parent = icBox,
		})
		return row, val
	end

	local _, bankVal = makeMoneyRow("Bank", 1, 42, C.gold, IMG.icon_bank)
	ui.bank = bankVal
	local cashRow, cashVal = makeMoneyRow("Cash", 2, 38, C.green, IMG.icon_wallet)
	ui.wallet = cashVal

	-- delta "+$350" flutuando acima da carteira (right: 52px, top: -26px)
	ui.delta = text({
		Name = "Delta",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -52, 0, -26),
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "",
		TextSize = 22,
		TextColor3 = C.green,
		FontFace = FONT_NUM,
		TextTransparency = 1,
		ZIndex = 5,
		Parent = cashRow,
	}, true)
end

local wantedTween: Tween? = nil
local function refreshWanted()
	wantedLevel = math.clamp(math.floor(num("WantedLevel", 0)), 0, 5)
	wantedState = str("WantedState", "white")
	local cam = player:GetAttribute("CameraSeen") == true
	local car = player:GetAttribute("CarMarked") == true
	local hasBadges = cam or car

	ui.badgeCam.root.Visible = cam
	ui.badgeCar.root.Visible = car
	ui.badgesRow.Visible = hasBadges and wantedLevel > 0

	local showWanted = wantedLevel > 0
	-- altura acomoda estrelas + badges + folga de 16px para o ping ring não cortar
	local targetH = if not showWanted then 0 else (4 + 46 + (if hasBadges then 8 + 36 + 16 else 12))
	if wantedTween then
		wantedTween:Cancel()
	end
	wantedTween = TweenService:Create(ui.wantedWrap, COLLAPSE_TWEEN, {
		Size = UDim2.fromOffset(300, targetH),
		GroupTransparency = if showWanted then 0 else 1,
	})
	wantedTween:Play()

	for i, s in stars do
		local lit = i <= wantedLevel
		s.glow.Visible = false
		s.grad.Enabled = false
		s.fill.ImageTransparency = 0
		s.stroke.ImageTransparency = 0
		s.stroke.Image = IMG.star_stroke

		if not lit then
			-- estilo slot: fill branco .07, stroke branco .3
			s.fill.ImageColor3 = C.white
			s.fill.ImageTransparency = 0.93
			s.stroke.ImageColor3 = C.white
			s.stroke.ImageTransparency = 0.70
		elseif wantedState == "hollow" then
			-- vazada: fill preto .3, stroke branco 1.9
			s.fill.ImageColor3 = C.black
			s.fill.ImageTransparency = 0.70
			s.stroke.Image = IMG.star_stroke_thick
			s.stroke.ImageColor3 = C.white
			s.stroke.ImageTransparency = 0
		elseif wantedState == "gray" then
			s.fill.ImageColor3 = C.gray
			s.stroke.ImageColor3 = C.strokeDark
		elseif wantedState == "flash" then
			s.fill.ImageColor3 = C.white
			s.grad.Enabled = true
			s.stroke.ImageColor3 = C.strokeDark
		elseif wantedState == "red" then
			s.fill.ImageColor3 = C.red
			s.stroke.ImageColor3 = C.redStroke
			s.glow.Visible = true
		else
			-- white (padrão)
			s.fill.ImageColor3 = C.white
			s.stroke.ImageColor3 = C.strokeDark
		end
	end
end

local function refreshMoney()
	ui.bank.Text = money(num("Bank", 0))
	local cash = num("Cash", 0)
	if lastCash == nil then
		lastCash = cash
		cashAnimFrom = cash
		cashAnimTo = cash
		ui.wallet.Text = money(cash)
		return
	end
	if cash ~= lastCash then
		local d = cash - lastCash
		cashAnimFrom = lastCash
		cashAnimTo = cash
		cashAnimStart = os.clock()
		deltaStart = cashAnimStart
		ui.delta.Text = (if d > 0 then "+" else "-") .. money(math.abs(d))
		ui.delta.TextColor3 = if d > 0 then C.green else C.red
		lastCash = cash
	end
end

-- ---------- canto inferior esquerdo: party + GPS + minimapa ----------
local function buildBottomLeft(root: Frame)
	local box = make("Frame", {
		Name = "BottomLeft",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, MARGIN_X, 1, -MARGIN_Y),
		Size = UDim2.fromOffset(MAP_W, 620),
		BackgroundTransparency = 1,
		Parent = root,
	})
	make("UIListLayout", {
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 12),
		Parent = box,
	})

	-- party: grid 2 colunas, gap 10px linha x 16px coluna
	local party = make("Frame", {
		Name = "Party",
		Size = UDim2.fromOffset(MAP_W, 0),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Visible = false,
		Parent = box,
	})
	make("UIGridLayout", {
		CellSize = UDim2.fromOffset(192, 36),
		CellPadding = UDim2.fromOffset(16, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = party,
	})
	ui.party = party

	-- GPS colapsável (.collapse#gpsWrap -> .gps)
	local gpsWrap = make("CanvasGroup", {
		Name = "GpsWrap",
		Size = UDim2.fromOffset(MAP_W, 0),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		ClipsDescendants = true,
		LayoutOrder = 2,
		Parent = box,
	})
	ui.gpsWrap = gpsWrap

	local gps = make("Frame", {
		Name = "Gps",
		Size = UDim2.fromOffset(MAP_W, 66),
		BackgroundColor3 = C.glass,
		BackgroundTransparency = 0.22,
		ClipsDescendants = true,
		Parent = gpsWrap,
	}, { corner(12) })

	local gpsTxt = make("Frame", {
		Name = "Text",
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -66 - 32, 1, 0),
		BackgroundTransparency = 1,
		Parent = gps,
	})
	make("UIListLayout", {
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 3),
		Parent = gpsTxt,
	})
	ui.gpsTitle = text({
		Size = UDim2.new(1, 0, 0, 23),
		Text = "",
		TextSize = 21,
		FontFace = FONT_UI_BOLD,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 1,
		Parent = gpsTxt,
	})
	ui.gpsSub = text({
		Size = UDim2.new(1, 0, 0, 16),
		Text = "",
		TextSize = 14,
		FontFace = FONT_UI_MED,
		TextColor3 = C.white,
		TextTransparency = 0.28,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 2,
		Parent = gpsTxt,
	})

	-- caixa laranja 66x66 na DIREITA
	local arrowBox = make("Frame", {
		Name = "ArrowBox",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(66, 66),
		BackgroundColor3 = C.orange,
		BorderSizePixel = 0,
		Parent = gps,
	})
	ui.gpsArrow = imgLabel({
		Name = "Arrow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(36, 36),
		Image = IMG.icon_turnRight,
		ImageColor3 = C.ink,
		Parent = arrowBox,
	})

	-- minimapa (400x260, radius 16, contorno duplo)
	local holder = make("Frame", {
		Name = "Minimap",
		Size = UDim2.fromOffset(MAP_W, MAP_H),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Parent = box,
	})
	-- anel externo branco .16 (box-shadow 3.5px)
	make("Frame", {
		Name = "OuterRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 4, 1, 4),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = holder,
	}, {
		corner(18),
		make("UIStroke", { Color = C.white, Thickness = 1.5, Transparency = 0.84 }),
	})

	local view = make("CanvasGroup", {
		Name = "View",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.black,
		ZIndex = 2,
		Parent = holder,
	}, {
		corner(16),
		make("UIStroke", { Color = C.glass, Thickness = 2, Transparency = 0.1 }),
	})

	local vp = make("ViewportFrame", {
		Name = "MapViewport",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = PAL.dia.ground,
		BackgroundTransparency = 0,
		Ambient = PAL.dia.ambient,
		LightColor = PAL.dia.lightColor,
		LightDirection = PAL.dia.lightDir,
		ImageColor3 = PAL.dia.tint,
		ZIndex = 1,
		Parent = view,
	})
	local vpCam = make("Camera", {
		FieldOfView = MAP_FOV,
		Parent = vp,
	})
	vp.CurrentCamera = vpCam
	ui.vp = vp
	ui.vpCam = vpCam

	-- rota 2D sobre o viewport (contorno #1A0C02 15px + centro #FF7A1A 8px)
	local routeLayer = make("Frame", {
		Name = "RouteLayer",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = view,
	})
	ui.routeOutline = make("Frame", {
		Name = "Outline",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(0, 15),
		BackgroundColor3 = C.routeDark,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 2,
		Parent = routeLayer,
	}, { corner(8) })
	ui.routeFill = make("Frame", {
		Name = "Fill",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(0, 8),
		BackgroundColor3 = C.orange,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 3,
		Parent = routeLayer,
	}, { corner(4) })

	-- degradê escuro superior (.mm-view::after: preto .32 -> transparente em 32%)
	make("Frame", {
		Name = "TopFade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.black,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = view,
	}, {
		make("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.68),
				NumberSequenceKeypoint.new(0.32, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})

	-- seta do jogador em (200, 185), 30px
	ui.arrow = imgLabel({
		Name = "PlayerArrow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(PLAYER_PX, PLAYER_PY),
		Size = UDim2.fromOffset(30, 30),
		Image = IMG.player_arrow,
		ImageColor3 = C.white,
		ZIndex = 4,
		Parent = view,
	})

	-- pílula de status no canto superior direito (relógio + sinal + bateria)
	local pill = make("Frame", {
		Name = "StatusPill",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 9),
		Size = UDim2.fromOffset(0, 25),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.glass,
		BackgroundTransparency = 0.26,
		ZIndex = 5,
		Parent = view,
	}, {
		corner(8),
		make("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }),
	})
	hlist(pill, Enum.HorizontalAlignment.Left, 7)

	ui.clock = text({
		Size = UDim2.fromOffset(0, 15),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "13:20",
		TextSize = 13,
		FontFace = FONT_UI_SEMI,
		LayoutOrder = 1,
		ZIndex = 5,
		Parent = pill,
	})

	-- barras de sinal (18x13, conforme SVG SIGNAL)
	local sig = make("Frame", {
		Name = "Signal",
		Size = UDim2.fromOffset(18, 13),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		ZIndex = 5,
		Parent = pill,
	})
	local barHeights = { 4, 7, 10, 13 }
	for i = 1, 4 do
		make("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromOffset((i - 1) * 5, 13),
			Size = UDim2.fromOffset(3, barHeights[i]),
			BackgroundColor3 = C.white,
			BackgroundTransparency = if i == 4 then 0.7 else 0,
			BorderSizePixel = 0,
			ZIndex = 5,
			Parent = sig,
		}, { corner(1) })
	end

	-- bateria (24x12, conforme SVG BATT)
	local batt = make("Frame", {
		Name = "Battery",
		Size = UDim2.fromOffset(24, 12),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		ZIndex = 5,
		Parent = pill,
	})
	local battBody = make("Frame", {
		Position = UDim2.fromOffset(1, 1),
		Size = UDim2.fromOffset(20, 10),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = batt,
	}, {
		corner(2),
		make("UIStroke", { Color = C.white, Thickness = 1.5 }),
	})
	make("Frame", {
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.fromOffset(12, 6),
		BackgroundColor3 = C.white,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = battBody,
	}, { corner(1) })
	make("Frame", {
		Position = UDim2.fromOffset(22, 4),
		Size = UDim2.fromOffset(2, 4),
		BackgroundColor3 = C.white,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = batt,
	}, { corner(1) })

	-- pílula de distância no canto inferior esquerdo (ponto laranja + texto)
	local dist = make("Frame", {
		Name = "DistPill",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -9),
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.glass,
		BackgroundTransparency = 0.26,
		Visible = false,
		ZIndex = 5,
		Parent = view,
	}, {
		corner(8),
		make("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }),
	})
	hlist(dist, Enum.HorizontalAlignment.Left, 7)
	make("Frame", {
		Name = "Dot",
		Size = UDim2.fromOffset(8, 8),
		BackgroundColor3 = C.orange,
		LayoutOrder = 1,
		ZIndex = 5,
		Parent = dist,
	}, {
		round(),
		make("UIStroke", { Color = C.routeDark, Thickness = 2 }),
	})
	ui.distText = text({
		Size = UDim2.fromOffset(0, 16),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "",
		TextSize = 14,
		FontFace = FONT_UI_SEMI,
		TextColor3 = C.white,
		LayoutOrder = 2,
		ZIndex = 5,
		Parent = dist,
	})
	ui.dist = dist

	-- overlay sem recorte (badge N e pins na borda)
	local overlay = make("Frame", {
		Name = "Overlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 8,
		Parent = holder,
	})
	local north = make("Frame", {
		Name = "North",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(MAP_W / 2, 0),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = C.strokeDark,
		ZIndex = 10,
		Parent = overlay,
	}, {
		round(),
		make("UIStroke", { Color = C.white, Thickness = 2 }),
	})
	text({
		Size = UDim2.fromScale(1, 1),
		Text = "N",
		TextSize = 12,
		FontFace = FONT_UI_EXTRA,
		ZIndex = 10,
		Parent = north,
	})
	ui.north = north
	ui.overlay = overlay
end

local function refreshParty()
	for _, r in partyRows do
		r.frame:Destroy()
	end
	table.clear(partyRows)
	local list = {}
	local raw = player:GetAttribute("PartyJson")
	if typeof(raw) == "string" and raw ~= "" then
		local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok and type(data) == "table" then
			list = data
		end
	end
	local count = math.min(#list, 4)
	ui.party.Visible = count > 0
	local rows = math.ceil(count / 2)
	ui.party.Size = UDim2.fromOffset(MAP_W, rows * 36 + math.max(rows - 1, 0) * 10)
	for i = 1, count do
		local m = list[i]
		local ok, col = pcall(Color3.fromHex, tostring(m.color or "#FFFFFF"))
		if not ok then
			col = C.white
		end
		local f = make("Frame", {
			BackgroundTransparency = 1,
			LayoutOrder = i,
			Parent = ui.party,
		})
		local iconBox = make("Frame", {
			Size = UDim2.fromOffset(36, 36),
			BackgroundColor3 = C.glass,
			BackgroundTransparency = 0.22,
			Parent = f,
		}, {
			corner(9),
			make("UIStroke", { Color = col, Thickness = 1.5, Transparency = 0.5 }),
		})
		imgLabel({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(20, 20),
			Image = iconAsset(m.icon),
			ImageColor3 = col,
			Parent = iconBox,
		})
		-- corpo alinhado embaixo (gap 9 da caixa de ícone, gap 5 entre nome e barra)
		local body = make("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 45, 1, 0),
			Size = UDim2.new(1, -45, 0, 28),
			BackgroundTransparency = 1,
			Parent = f,
		})
		make("UIListLayout", {
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 5),
			Parent = body,
		})
		text({
			Size = UDim2.new(1, 0, 0, 15),
			Text = tostring(m.name or "?"),
			TextSize = 13,
			FontFace = FONT_UI_SEMI,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			LayoutOrder = 1,
			Parent = body,
		}, true)
		local barBg = make("Frame", {
			Size = UDim2.new(1, 0, 0, 8),
			BackgroundColor3 = C.barBg,
			BackgroundTransparency = 0.28,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			LayoutOrder = 2,
			Parent = body,
		}, {
			corner(2),
			make("UIStroke", { Color = C.white, Thickness = 1, Transparency = 0.92 }),
		})
		local hp = math.clamp(tonumber(m.hp) or 1, 0, 1)
		local fill = make("Frame", {
			Size = UDim2.fromScale(hp, 1),
			BackgroundColor3 = col,
			BorderSizePixel = 0,
			Parent = barBg,
		}, { corner(2) })
		table.insert(partyRows, { frame = f, fill = fill, hp = hp })
	end
end

local gpsTween: Tween? = nil
local function refreshGps()
	local title = str("GpsText", "")
	local show = title ~= ""
	ui.gpsTitle.Text = title

	local sub = str("GpsSub", "")
	local sepIdx = string.find(sub, " · ", 1, true)
	if sepIdx then
		local distPart = escapeRichText(string.sub(sub, 1, sepIdx - 1))
		local restPart = escapeRichText(string.sub(sub, sepIdx))
		ui.gpsSub.Text = string.format('<font color="#FFFFFF"><b>%s</b></font>%s', distPart, restPart)
	else
		ui.gpsSub.Text = escapeRichText(sub)
	end

	local dir = str("GpsDir", "right")
	ui.gpsArrow.Rotation = if dir == "left" then 180 elseif dir == "straight" then -90 else 0

	if gpsTween then
		gpsTween:Cancel()
	end
	gpsTween = TweenService:Create(ui.gpsWrap, COLLAPSE_TWEEN, {
		Size = UDim2.fromOffset(MAP_W, if show then 66 else 0),
		GroupTransparency = if show then 0 else 1,
	})
	gpsTween:Play()
end

local function pinFor(key: any, iconName: string?, color: Color3, isEdge: boolean): PinEntry
	local isDot = iconName == nil or iconName == "" or iconName == "dot"
	local entry = pinUi[key]
	if not entry then
		local root = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(32, 32),
			BackgroundColor3 = color,
			ZIndex = 9,
			Parent = ui.overlay,
		}, { corner(9) })
		local ring = make("UIStroke", { Color = C.strokeDark, Thickness = 2, Parent = root })
		local edgeRing = make("Frame", {
			Name = "EdgeRing",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 10, 1, 10),
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 8,
			Parent = root,
		}, { corner(12) })
		local edgeStroke = make("UIStroke", { Color = color, Thickness = 2, Transparency = 0.5, Parent = edgeRing })
		local icon = imgLabel({
			Name = "Icon",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(18, 18),
			Image = iconAsset(iconName),
			ImageColor3 = C.pinIconDark,
			ZIndex = 9,
			Parent = root,
		})
		entry = { root = root, ring = ring, edgeRing = edgeRing, edgeStroke = edgeStroke, icon = icon, isDot = false }
		pinUi[key] = entry
	end

	entry.root.BackgroundColor3 = color
	entry.edgeStroke.Color = color
	entry.edgeRing.Visible = isEdge and not isDot
	if entry.isDot ~= isDot then
		entry.isDot = isDot
		local c = entry.root:FindFirstChildOfClass("UICorner")
		if isDot then
			entry.root.Size = UDim2.fromOffset(16, 16)
			if c then c.CornerRadius = UDim.new(1, 0) end
			entry.icon.Visible = false
		else
			entry.root.Size = UDim2.fromOffset(32, 32)
			if c then c.CornerRadius = UDim.new(0, 9) end
			entry.icon.Visible = true
		end
	end
	if not isDot then
		entry.icon.Image = iconAsset(iconName)
	end
	return entry
end

-- ---------- canto inferior direito: arma / velocímetro ----------
local function buildBottomRight(root: Frame)
	-- arma (a pé): right 56, bottom 40, coluna alinhada à direita, gap 6
	local weapon = make("Frame", {
		Name = "Weapon",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -MARGIN_X, 1, -BR_MARGIN_Y),
		Size = UDim2.fromOffset(320, 186),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = root,
	})
	make("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = weapon,
	})

	ui.weaponName = text({
		Size = UDim2.fromOffset(320, 16),
		Text = "",
		TextSize = 12,
		FontFace = FONT_UI_SEMI,
		TextColor3 = C.white,
		TextTransparency = 0.22,
		TextXAlignment = Enum.TextXAlignment.Right,
		LayoutOrder = 1,
		Parent = weapon,
	}, true)

	local ammoRow = make("Frame", {
		Size = UDim2.fromOffset(320, 60),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = weapon,
	})
	hlist(ammoRow, Enum.HorizontalAlignment.Right, 8, Enum.VerticalAlignment.Bottom)
	ui.mag = text({
		Size = UDim2.fromOffset(0, 60),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "0",
		TextSize = 66,
		FontFace = FONT_NUM,
		LayoutOrder = 1,
		Parent = ammoRow,
	}, true)
	ui.reserve = text({
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "/ 0",
		TextSize = 28,
		FontFace = FONT_NUM_SEMI,
		TextColor3 = C.white,
		TextTransparency = 0.30,
		LayoutOrder = 2,
		Parent = ammoRow,
	}, true)

	imgLabel({
		Name = "Gun",
		Size = UDim2.fromOffset(132, 66),
		Image = IMG.gun,
		ImageColor3 = C.white,
		LayoutOrder = 3,
		Parent = weapon,
	})

	local pipRow = make("Frame", {
		Name = "Pips",
		Size = UDim2.fromOffset(12 * 6 + 11 * 3, 16),
		BackgroundTransparency = 1,
		LayoutOrder = 4,
		Parent = weapon,
	})
	hlist(pipRow, Enum.HorizontalAlignment.Right, 3)
	ui.pips = {}
	for i = 1, 12 do
		local p = make("Frame", {
			Size = UDim2.fromOffset(6, 16),
			BackgroundColor3 = C.white,
			BorderSizePixel = 0,
			LayoutOrder = i,
			Parent = pipRow,
		}, {
			corner(2),
			make("UIStroke", { Color = C.black, Thickness = 1, Transparency = 0.45 }),
		})
		ui.pips[i] = p
	end
	ui.weapon = weapon

	-- velocímetro (no carro): viewBox 300 escalado para 320px + ícones abaixo
	local S = 320
	local SC = S / 300
	local CX = S / 2

	local speedo = make("Frame", {
		Name = "Speedometer",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -MARGIN_X, 1, -BR_MARGIN_Y),
		Size = UDim2.fromOffset(S, S + 8),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = root,
	})
	local dial = make("Frame", {
		Name = "Dial",
		Size = UDim2.fromOffset(S, S),
		BackgroundTransparency = 1,
		Parent = speedo,
	})

	-- círculo de fundo r124 rgba(10,11,15,.55)
	make("Frame", {
		Name = "Bg",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(CX, CX),
		Size = UDim2.fromOffset(248 * SC, 248 * SC),
		BackgroundColor3 = C.glass,
		BackgroundTransparency = 0.45,
		ZIndex = 1,
		Parent = dial,
	}, { round() })

	-- trilhas semitransparentes em CanvasGroup para não acumular alpha nos segmentos sobrepostos
	local trackGroup = make("CanvasGroup", {
		Name = "TrackGroup",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 0.86, -- opacity 0.14
		ZIndex = 2,
		Parent = dial,
	})
	buildArc(trackGroup, CX, CX, 118 * SC, 135, 405, 2, 7 * SC, C.white, 2)
	buildArc(trackGroup, CX, CX, 136 * SC, 115, 185, 2, 6 * SC, C.white, 2)
	buildArc(trackGroup, CX, CX, 136 * SC, 65, -5, 2, 6 * SC, C.white, 2)

	-- zona vermelha 200..240 (360°..405°) rgba(255,74,61,.35)
	local redZoneGroup = make("CanvasGroup", {
		Name = "RedZoneGroup",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 0.65,
		ZIndex = 3,
		Parent = dial,
	})
	buildArc(redZoneGroup, CX, CX, 118 * SC, 360, 405, 2, 7 * SC, C.fuelRed, 3)

	-- brilho atrás do arco de velocidade ativo (emula feGaussianBlur)
	local speedGlowGroup = make("CanvasGroup", {
		Name = "SpeedGlowGroup",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 0.72,
		ZIndex = 4,
		Parent = dial,
	})
	speedGlowSegs = buildArc(speedGlowGroup, CX, CX, 118 * SC, 135, 405, 2, 13 * SC, C.white, 4)

	-- arco ativo de velocidade (branco, width 7)
	speedSegs = buildArc(dial, CX, CX, 118 * SC, 135, 405, 2, 7 * SC, C.white, 5)
	for i = 1, #speedSegs do
		speedSegs[i].Visible = false
		speedGlowSegs[i].Visible = false
	end

	-- arco ativo de gasolina (em CanvasGroup para piscar uniformemente na reserva)
	local fuelGroup = make("CanvasGroup", {
		Name = "FuelGroup",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 0,
		ZIndex = 5,
		Parent = dial,
	})
	fuelSegs = buildArc(fuelGroup, CX, CX, 136 * SC, 115, 185, 2, 6 * SC, C.amber, 5)
	ui.fuelGroup = fuelGroup

	-- arco ativo do motor
	engineSegs = buildArc(dial, CX, CX, 136 * SC, 65, -5, 2, 6 * SC, C.green, 5)

	-- marcações (ticks) a cada 10 km/h e rótulos a cada 40 km/h
	for v = 0, 240, 10 do
		local maj = v % 40 == 0
		local a = 135 + (v / 240) * 270
		local rad = math.rad(a)
		local r0 = if maj then 100 else 106
		local r1 = 114
		local rMid = (r0 + r1) * 0.5 * SC
		local tickLen = (r1 - r0) * SC
		local tickW = if maj then 2.6 * SC else 1.4 * SC
		make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(CX + rMid * math.cos(rad), CX + rMid * math.sin(rad)),
			Size = UDim2.fromOffset(tickLen, tickW),
			Rotation = a,
			BorderSizePixel = 0,
			BackgroundColor3 = if v >= 200 then C.lowAmmo else C.white,
			BackgroundTransparency = if maj then 0.05 else 0.5,
			ZIndex = 6,
			Parent = dial,
		})
		if maj then
			local lr = 86 * SC
			text({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(CX + lr * math.cos(rad), CX + lr * math.sin(rad)),
				Size = UDim2.fromOffset(32, 18),
				Text = tostring(v),
				TextSize = 15,
				FontFace = FONT_NUM_SEMI,
				TextColor3 = C.white,
				TextTransparency = 0.3,
				ZIndex = 6,
				Parent = dial,
			})
		end
	end

	-- ícones de gasolina e motor na base de cada arco
	ui.fuelIcon = imgLabel({
		Name = "FuelIcon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset((58 + 10.2) * SC, (262 + 10.2) * SC),
		Size = UDim2.fromOffset(22, 22),
		Image = IMG.icon_fuel,
		ImageColor3 = C.amber,
		ZIndex = 6,
		Parent = dial,
	})
	ui.engineIcon = imgLabel({
		Name = "EngineIcon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset((222 + 10.2) * SC, (262 + 10.2) * SC),
		Size = UDim2.fromOffset(22, 22),
		Image = IMG.icon_engine,
		ImageColor3 = C.green,
		ZIndex = 6,
		Parent = dial,
	})

	-- caixa da marcha (26x18, rx 4, branco .12) no topo
	local gearBox = make("Frame", {
		Name = "GearBox",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(150 * SC, 109 * SC),
		Size = UDim2.fromOffset(26 * SC, 18 * SC),
		BackgroundColor3 = C.white,
		BackgroundTransparency = 0.88,
		ZIndex = 6,
		Parent = dial,
	}, { corner(4) })
	ui.gear = text({
		Size = UDim2.fromScale(1, 1),
		Text = "P",
		TextSize = 12,
		FontFace = FONT_UI_BOLD,
		TextColor3 = C.white,
		ZIndex = 7,
		Parent = gearBox,
	})

	-- velocidade 66px, KM/H 11px, odômetro 11px
	ui.speed = text({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(150 * SC, 152 * SC),
		Size = UDim2.fromOffset(160, 70),
		Text = "0",
		TextSize = 66,
		FontFace = FONT_NUM,
		ZIndex = 6,
		Parent = dial,
	})
	text({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(150 * SC, 188 * SC),
		Size = UDim2.fromOffset(80, 14),
		Text = spacedText("KM/H"),
		TextSize = 11,
		FontFace = FONT_UI_SEMI,
		TextColor3 = C.white,
		TextTransparency = 0.4,
		ZIndex = 6,
		Parent = dial,
	})
	ui.odo = text({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(150 * SC, 212 * SC),
		Size = UDim2.fromOffset(120, 14),
		Text = "000.000 km",
		TextSize = 11,
		FontFace = FONT_UI_MED,
		TextColor3 = C.white,
		TextTransparency = 0.55,
		ZIndex = 6,
		Parent = dial,
	})

	-- ícones de trava e farol abaixo do mostrador (34px, gap 22, margin-top -26)
	local spIcons = make("Frame", {
		Name = "StatusIcons",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(CX, S - 26),
		Size = UDim2.fromOffset(34 * 2 + 22, 34),
		BackgroundTransparency = 1,
		ZIndex = 7,
		Parent = speedo,
	})
	hlist(spIcons, Enum.HorizontalAlignment.Center, 22)
	ui.lock = imgLabel({
		Name = "Lock",
		Size = UDim2.fromOffset(34, 34),
		Image = IMG.icon_lock,
		ImageColor3 = C.white,
		ImageTransparency = 0.7,
		LayoutOrder = 1,
		ZIndex = 7,
		Parent = spIcons,
	})
	ui.lights = imgLabel({
		Name = "Lights",
		Size = UDim2.fromOffset(34, 34),
		Image = IMG.icon_light,
		ImageColor3 = C.white,
		ImageTransparency = 0.7,
		LayoutOrder = 2,
		ZIndex = 7,
		Parent = spIcons,
	})
	ui.speedo = speedo
end

-- ---------- atualização da rota 2D sobre o ViewportFrame ----------
local function updateRouteLine(camCF: CFrame, p1: Vector3, p2: Vector3)
	local r1 = camCF:PointToObjectSpace(p1)
	local r2 = camCF:PointToObjectSpace(p2)
	local nearZ = -2
	-- recorta o segmento no plano próximo caso o destino esteja atrás da câmera
	if r1.Z > nearZ and r2.Z > nearZ then
		ui.routeOutline.Visible = false
		ui.routeFill.Visible = false
		return
	end
	if r2.Z > nearZ then
		local k = (nearZ - r1.Z) / (r2.Z - r1.Z)
		r2 = r1:Lerp(r2, k)
	elseif r1.Z > nearZ then
		local k = (nearZ - r2.Z) / (r1.Z - r2.Z)
		r1 = r2:Lerp(r1, k)
	end

	local d1, d2 = -r1.Z, -r2.Z
	local x1 = MAP_W * (0.5 + (r1.X / (d1 * HALF_TAN_X)) * 0.5)
	local y1 = MAP_H * (0.5 - (r1.Y / (d1 * HALF_TAN_Y)) * 0.5)
	local x2 = MAP_W * (0.5 + (r2.X / (d2 * HALF_TAN_X)) * 0.5)
	local y2 = MAP_H * (0.5 - (r2.Y / (d2 * HALF_TAN_Y)) * 0.5)

	local dx, dy = x2 - x1, y2 - y1
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 2 then
		ui.routeOutline.Visible = false
		ui.routeFill.Visible = false
		return
	end
	local pos = UDim2.fromOffset((x1 + x2) * 0.5, (y1 + y2) * 0.5)
	local rot = math.deg(math.atan2(dy, dx))
	ui.routeOutline.Position = pos
	ui.routeOutline.Size = UDim2.fromOffset(len + 8, 15)
	ui.routeOutline.Rotation = rot
	ui.routeOutline.Visible = true
	ui.routeFill.Position = pos
	ui.routeFill.Size = UDim2.fromOffset(len + 4, 8)
	ui.routeFill.Rotation = rot
	ui.routeFill.Visible = true
end

-- ---------- loop ----------
local function update(dt: number)
	local t = os.clock()
	local camera = workspace.CurrentCamera
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local rootPart = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?

	-- estrela piscando: sweep branco->cinza nos primeiros 60% de 1.6s + blink (0-55% 1, 70% .3, 85-100% 1)
	if wantedState == "flash" and wantedLevel > 0 then
		local phase = (t % 1.6) / 1.6
		local sweepOffset = if phase <= 0.6 then (1 - (phase / 0.6) * 2) else -1
		local opacity = 1
		if phase > 0.55 and phase <= 0.70 then
			opacity = 1 - 0.7 * ((phase - 0.55) / 0.15)
		elseif phase > 0.70 and phase < 0.85 then
			opacity = 0.3 + 0.7 * ((phase - 0.70) / 0.15)
		end
		local transp = 1 - opacity
		for i = 1, wantedLevel do
			local s = stars[i]
			s.grad.Offset = Vector2.new(sweepOffset, 0)
			s.fill.ImageTransparency = transp
			s.stroke.ImageTransparency = transp
		end
	end

	-- ping dos badges: 0 -> +14px cada lado (36 -> 64px) nos primeiros 70% de 2.4s
	local pp = (t % 2.4) / 2.4
	for _, b in { ui.badgeCam, ui.badgeCar } do
		if b.root.Visible then
			if pp <= 0.7 then
				local k = pp / 0.7
				local sz = 36 + 28 * k
				b.ping.Size = UDim2.fromOffset(sz, sz)
				b.pingStroke.Transparency = 0.3 + 0.7 * k
			else
				b.pingStroke.Transparency = 1
			end
		end
	end

	-- contagem animada da carteira (0.6s) + delta flutuante (1.4s)
	local cashElapsed = t - cashAnimStart
	if cashElapsed >= 0 and cashElapsed <= 0.65 then
		local k = math.min(1, cashElapsed / 0.6)
		ui.wallet.Text = money(cashAnimFrom + (cashAnimTo - cashAnimFrom) * k)
	end
	local deltaElapsed = t - deltaStart
	if deltaElapsed >= 0 and deltaElapsed <= 1.45 then
		local p = math.min(1, deltaElapsed / 1.4)
		local op, dy = 0, 0
		if p < 0.15 then
			local k = p / 0.15
			op = k
			dy = 8 * (1 - k)
		elseif p < 0.75 then
			op = 1
			dy = 0
		else
			local k = (p - 0.75) / 0.25
			op = 1 - k
			dy = -6 * k
		end
		ui.delta.TextTransparency = 1 - op
		ui.delta.Position = UDim2.new(1, -52, 0, -26 + dy)
	elseif ui.delta.TextTransparency < 1 then
		ui.delta.TextTransparency = 1
	end

	-- party: barra pisca suavemente (0.7s alternado até opacidade .35) quando hp < .3
	local lowWave = 0.5 - 0.5 * math.cos(t * math.pi / 0.7) -- 0..1..0 em 1.4s
	for _, r in partyRows do
		r.fill.BackgroundTransparency = if r.hp < 0.3 then (0.65 * lowWave) else 0
	end

	-- minimapa (ViewportFrame real)
	if rootPart and camera then
		local p = rootPart.Position
		local look = camera.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		if flatLook.Magnitude < 1e-4 then
			flatLook = Vector3.new(0, 0, -1)
		else
			flatLook = flatLook.Unit
		end

		local camPos = p - flatLook * MAP_CAM_BACK + Vector3.new(0, MAP_CAM_HEIGHT, 0)
		local camTarget = p + flatLook * MAP_CAM_FWD
		local vpCF = CFrame.lookAt(camPos, camTarget, Vector3.yAxis)
		ui.vpCam.CFrame = vpCF

		local rot = -math.deg(math.atan2(flatLook.X, -flatLook.Z))
		local fl = rootPart.CFrame.LookVector
		ui.arrow.Rotation = math.deg(math.atan2(fl.X, -fl.Z)) + rot
		local nx, ny = edgePos(rot, 0)
		ui.north.Position = UDim2.new(0.5, nx, 0.5, ny)

		-- atualização fatiada das peças clonadas por célula espacial
		local pcx, pcz = cellCoords(p)
		rescanTimer += dt
		if pcx ~= lastPlayerCellX or pcz ~= lastPlayerCellZ or rescanTimer > 1.5 then
			rescanTimer = 0
			rebuildQueuesAround(p)
		end
		stepViewportQueue(p)

		-- pins (tag MapPin + destino GPS) projetados pela câmera do ViewportFrame
		local targets = {}
		for _, part in CollectionService:GetTagged("MapPin") do
			if part:IsA("BasePart") then
				local col = part:GetAttribute("Color")
				local ic = part:GetAttribute("Icon")
				table.insert(targets, {
					key = part,
					pos = part.Position,
					icon = if typeof(ic) == "string" then ic else nil,
					color = if typeof(col) == "Color3" then col else C.gold,
				})
			end
		end

		local gpsTarget = player:GetAttribute("GpsTarget")
		if typeof(gpsTarget) == "Vector3" then
			table.insert(targets, { key = "gps", pos = gpsTarget, icon = "flag", color = C.orange })
			local m = (gpsTarget - p).Magnitude * STUD_M
			ui.distText.Text = if m >= 1000
				then string.format("%.1f km", m / 1000):gsub("%.", ",")
				else string.format("%d m", math.floor(m + 0.5))
			ui.dist.Visible = true
			updateRouteLine(vpCF, p, gpsTarget)
		else
			ui.dist.Visible = false
			ui.routeOutline.Visible = false
			ui.routeFill.Visible = false
		end

		local seen = {}
		local rRad = math.rad(rot)
		local cs, sn = math.cos(rRad), math.sin(rRad)
		for _, tg in targets do
			local sx, sy, depth = projectPoint(vpCF, tg.pos)
			local isEdge = depth <= 1 or sx < 14 or sx > MAP_W - 14 or sy < 14 or sy > MAP_H - 14
			if isEdge then
				local wx, wz = tg.pos.X - p.X, tg.pos.Z - p.Z
				local rx = wx * cs - wz * sn
				local ry = wx * sn + wz * cs
				local ex, ey = edgePos(math.deg(math.atan2(rx, -ry)), 0)
				sx, sy = MAP_W * 0.5 + ex, MAP_H * 0.5 + ey
			end
			local pin = pinFor(tg.key, tg.icon, tg.color, isEdge)
			pin.root.Position = UDim2.fromOffset(sx, sy)
			pin.root.Visible = true
			seen[tg.key] = true
		end
		for key, pin in pinUi do
			if not seen[key] then
				pin.root.Visible = false
			end
		end
	end

	-- paleta por hora do dia + relógio
	local clock = Lighting.ClockTime
	local name = if clock >= 6.5 and clock < 16.5 then "dia" elseif clock >= 16.5 and clock < 19 then "tarde" else "noite"
	if name ~= palName then
		palName = name
		local pal = PAL[name]
		ui.vp.BackgroundColor3 = pal.ground
		ui.vp.Ambient = pal.ambient
		ui.vp.LightColor = pal.lightColor
		ui.vp.LightDirection = pal.lightDir
		ui.vp.ImageColor3 = pal.tint
	end
	ui.clock.Text = string.format("%02d:%02d", math.floor(clock), math.floor((clock % 1) * 60))

	-- veículo x arma
	local seat = hum and hum.SeatPart
	local inVehicle = seat ~= nil and seat:IsA("VehicleSeat")
	ui.speedo.Visible = inVehicle
	if inVehicle then
		local s = seat :: VehicleSeat
		if odoSeat ~= s then
			odoSeat = s
			local base = s:GetAttribute("Odometer")
			odometerKm = if typeof(base) == "number" then base else 0
		end
		local vel = s.AssemblyLinearVelocity
		local kmh = vel.Magnitude * STUD_M * 3.6
		shownSpeed += (kmh - shownSpeed) * math.min(1, dt * 10)
		odometerKm += vel.Magnitude * STUD_M * dt / 1000

		local spRound = math.floor(shownSpeed + 0.5)
		ui.speed.Text = tostring(spRound)
		ui.gear.Text = if shownSpeed < 1 then "P" elseif vel:Dot(s.CFrame.LookVector) < 0 then "R" else "D"
		ui.odo.Text = string.format("%07.3f km", odometerKm)

		-- arco de velocidade (atualiza somente se mudou quantidade acesa)
		local speedLit = if spRound <= 0 then 0 else math.clamp(math.floor((math.min(shownSpeed, 240) / 240) * #speedSegs + 0.5), 1, #speedSegs)
		if speedLit ~= lastSpeedLit then
			lastSpeedLit = speedLit
			for i = 1, #speedSegs do
				local on = i <= speedLit
				speedSegs[i].Visible = on
				speedGlowSegs[i].Visible = on
			end
		end

		-- arco de gasolina (pisca vermelho quando < 0.15)
		local fuelAttr = s:GetAttribute("Fuel")
		local fuel = if typeof(fuelAttr) == "number" then math.clamp(fuelAttr, 0, 1) else 1
		local lowFuel = fuel < 0.15
		local fuelLit = if fuel <= 0 then 0 else math.clamp(math.floor(fuel * #fuelSegs + 0.5), 1, #fuelSegs)
		local fcol = if lowFuel then C.fuelRed else C.amber
		if fuelLit ~= lastFuelLit or lowFuel ~= lastFuelLow then
			lastFuelLit = fuelLit
			lastFuelLow = lowFuel
			ui.fuelIcon.ImageColor3 = fcol
			for i = 1, #fuelSegs do
				local seg = fuelSegs[i]
				seg.Visible = i <= fuelLit
				seg.BackgroundColor3 = fcol
			end
		end
		if lowFuel then
			local fuelWave = 0.5 - 0.5 * math.cos(t * math.pi / 0.6)
			ui.fuelGroup.GroupTransparency = 0.65 * fuelWave
		elseif ui.fuelGroup.GroupTransparency ~= 0 then
			ui.fuelGroup.GroupTransparency = 0
		end

		-- arco do motor
		local engAttr = s:GetAttribute("Engine")
		local engine = if typeof(engAttr) == "number" then math.clamp(engAttr, 0, 1) else 1
		local ecol = if engine > 0.6 then C.green elseif engine > 0.3 then C.amber else C.fuelRed
		local engLit = if engine <= 0 then 0 else math.clamp(math.floor(engine * #engineSegs + 0.5), 1, #engineSegs)
		if engLit ~= lastEngLit or ecol ~= lastEngCol then
			lastEngLit = engLit
			lastEngCol = ecol
			ui.engineIcon.ImageColor3 = ecol
			for i = 1, #engineSegs do
				local seg = engineSegs[i]
				seg.Visible = i <= engLit
				seg.BackgroundColor3 = ecol
			end
		end

		ui.lock.ImageTransparency = if s:GetAttribute("Locked") == true then 0 else 0.7
		ui.lights.ImageTransparency = if s:GetAttribute("Lights") == true then 0 else 0.7
	else
		shownSpeed = 0
	end

	-- arma (a pé)
	local tool = char and char:FindFirstChildOfClass("Tool")
	local wname = tool and tool:GetAttribute("Weapon")
	local wcfg = if typeof(wname) == "string" then WeaponConfig[wname] else nil
	ui.weapon.Visible = wcfg ~= nil and not inVehicle
	if wcfg and tool then
		local ammoAttr = tool:GetAttribute("Ammo")
		local ammo = if typeof(ammoAttr) == "number" then ammoAttr else 0
		local reserveAttr = tool:GetAttribute("Reserve")
		local displayAttr = tool:GetAttribute("DisplayName")
		local labelStr = if tool:GetAttribute("Reloading")
			then "RECARREGANDO..."
			else string.upper(if typeof(displayAttr) == "string" then displayAttr else wname)
		ui.weaponName.Text = spacedText(labelStr)
		ui.mag.Text = tostring(ammo)
		ui.mag.TextColor3 = if ammo <= 3 then C.lowAmmo else C.white
		ui.reserve.Text = "/ " .. tostring(if typeof(reserveAttr) == "number" then reserveAttr else wcfg.MagSize)
		local lit = math.clamp(math.ceil((ammo / math.max(wcfg.MagSize, 1)) * 12), 0, 12)
		for i, pip in ui.pips do
			pip.BackgroundTransparency = if i <= lit then 0 else 0.8
		end
	end
end

function HudController:Init()
	local gui = make("ScreenGui", {
		Name = "MainHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	-- tudo desenhado em referência 1920x1080 e escalado pela altura do viewport
	local root = make("Frame", { Name = "Root", BackgroundTransparency = 1, Parent = gui })
	local scale = make("UIScale", { Parent = root })

	local vpConn: RBXScriptConnection? = nil
	local function fit()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local vp = cam.ViewportSize
		local s = math.max(vp.Y, 1) / REF_H
		scale.Scale = s
		root.Size = UDim2.fromOffset(vp.X / s, vp.Y / s)
	end
	local function bindCamera()
		if vpConn then
			vpConn:Disconnect()
			vpConn = nil
		end
		local cam = workspace.CurrentCamera
		if cam then
			fit()
			vpConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
		end
	end
	bindCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)

	buildTopRight(root)
	buildBottomLeft(root)
	buildBottomRight(root)
	watchWorkspaceMap()
end

function HudController:Start()
	local handlers = {
		WantedLevel = refreshWanted,
		WantedState = refreshWanted,
		CameraSeen = refreshWanted,
		CarMarked = refreshWanted,
		Bank = refreshMoney,
		Cash = refreshMoney,
		PartyJson = refreshParty,
		GpsText = refreshGps,
		GpsSub = refreshGps,
		GpsDir = refreshGps,
	}
	player.AttributeChanged:Connect(function(name)
		local h = handlers[name]
		if h then
			h()
		end
	end)
	refreshWanted()
	refreshMoney()
	refreshParty()
	refreshGps()
	RunService.RenderStepped:Connect(update)
end

return HudController
