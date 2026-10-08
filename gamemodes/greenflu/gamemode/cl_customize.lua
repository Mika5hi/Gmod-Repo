--[[
	Custom Apocalypse - character creation window (server side: sv_customize.lua)
	Opens by itself when you join (you can't close it until you press Start). "gfr_customize" in the console opens it
	again later. Left: every installed playermodel. Middle: your survivor (drag to turn, scroll to zoom).
	Right: skin, bodygroups (outfit parts) and clothes colour. Randomize rolls everything.
]]
local function S(x) return math.Round(x * ScrH() / 1080) end

surface.CreateFont("GFR_Cust_Title", {font = "Roboto", size = S(34), weight = 800, extended = true})
surface.CreateFont("GFR_Cust_Head", {font = "Roboto", size = S(18), weight = 700, extended = true})
surface.CreateFont("GFR_Cust_Text", {font = "Roboto", size = S(16), weight = 500, extended = true})
surface.CreateFont("GFR_Cust_Button", {font = "Roboto", size = S(24), weight = 800, extended = true})

local colBg = Color(14, 15, 16, 250)
local colPanel = Color(26, 28, 30, 235)
local colLine = Color(60, 64, 66)
local colText = Color(225, 222, 210)
local colDim = Color(140, 140, 132)
local colAccent = Color(196, 120, 52)
local colPick = Color(196, 120, 52, 90)

local frame

local function ModelList()
	local list = {}
	for name, path in pairs(player_manager.AllValidModels()) do
		if GFR.ModelAllowed(name) then list[#list + 1] = {name = name, path = path} end -- (SFW mode: stock only, sh_sfw.lua)
	end
	table.SortByMember(list, "name", true)
	return list
end

local function Section(parent, text)
	local l = parent:Add("DLabel")
	l:Dock(TOP)
	l:DockMargin(0, S(14), 0, S(6))
	l:SetFont("GFR_Cust_Head")
	l:SetTextColor(colAccent)
	l:SetText(string.upper(text))
	l:SizeToContentsY()
	return l
end

local function Slider(parent, text, max, value, onChange)
	local s = parent:Add("DNumSlider")
	s:Dock(TOP)
	s:DockMargin(0, 0, 0, S(2))
	s:SetTall(S(26))
	s:SetText(text)
	s:SetMinMax(0, max)
	s:SetDecimals(0)
	s:SetValue(value)
	s.Label:SetFont("GFR_Cust_Text")
	s.Label:SetTextColor(colText)
	s.TextArea:SetTextColor(colText)
	s.OnValueChanged = function(_, v) onChange(math.Round(v)) end
	return s
end

-- SFW mode switched while the menu is open: rebuilt with the right models
hook.Add("Think", "GFR_Customize_SFWRefresh", function()
	if IsValid(frame) && frame.GFR_SFW != GFR.SFWCharacter() then GFR.OpenCustomize(frame.GFR_Forced) end
end)

function GFR.OpenCustomize(forced)
	if IsValid(frame) then frame:Remove() end
	local cur = {
		name = GetConVar("cl_playermodel"):GetString(),
		skin = GetConVar("cl_playerskin"):GetInt(),
		groups = {},
		color = Vector(GetConVar("cl_playercolor"):GetString())
	}
	if !player_manager.AllValidModels()[cur.name] then cur.name = "kleiner" end
	if !GFR.ModelAllowed(cur.name) then cur.name = "male07" end
	local gi = 0 -- (bodygroup indexes start at 0)
	for v in string.gmatch(GetConVar("cl_playerbodygroups"):GetString(), "%d+") do
		cur.groups[gi] = tonumber(v)
		gi = gi + 1
	end

	frame = vgui.Create("DFrame")
	frame.GFR_Forced, frame.GFR_SFW = forced, GFR.SFWCharacter()
	frame:SetSize(ScrW(), ScrH())
	frame:SetPos(0, 0)
	frame:SetTitle("")
	frame:SetDraggable(false)
	frame:ShowCloseButton(!forced)
	frame:MakePopup()
	frame:SetKeyboardInputEnabled(true)
	frame.Paint = function(_, w, h)
		surface.SetDrawColor(colBg)
		surface.DrawRect(0, 0, w, h)
		draw.SimpleText("YOUR SURVIVOR", "GFR_Cust_Title", S(40), S(26), colText)
		draw.SimpleText("Who were you before it all went to hell?", "GFR_Cust_Text", S(42), S(66), colDim)
	end
	local top = S(100)

	-------------------------------------------------------------------------------------------------------------------------------------
	-- Middle: the preview
	local preview = vgui.Create("DModelPanel", frame)
	preview:SetPos(S(460), top)
	preview:SetSize(ScrW() - S(460) - S(420), ScrH() - top - S(40))
	preview:SetFOV(32)
	preview.yaw, preview.zoom = 20, 1
	preview.panY, preview.panZ = 0, 0 -- (right-drag moves the view around)
	preview.Paint2 = preview.Paint
	preview.Paint = function(self, w, h)
		surface.SetDrawColor(colPanel)
		surface.DrawRect(0, 0, w, h)
		self:Paint2(w, h)
		draw.SimpleText("Drag to turn  -  Right-drag to move  -  Scroll to zoom", "GFR_Cust_Text", w / 2, h - S(16), colDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	preview.OnMousePressed = function(self, code)
		if code == MOUSE_RIGHT then self.panFrom = {gui.MouseX(), gui.MouseY()} else self.dragX = gui.MouseX() end
		self:MouseCapture(true)
	end
	preview.OnMouseReleased = function(self, code)
		if code == MOUSE_RIGHT then self.panFrom = nil else self.dragX = nil end
		if !self.panFrom && !self.dragX then self:MouseCapture(false) end
	end
	preview.OnMouseWheeled = function(self, d) self.zoom = math.Clamp(self.zoom - d * 0.1, 0.3, 1.3) end
	preview.LayoutEntity = function(self, ent)
		if self.dragX then
			self.yaw = self.yaw + (gui.MouseX() - self.dragX) * 0.6
			self.dragX = gui.MouseX()
		end
		local z = self.zoom
		if self.panFrom then
			-- The model follows the mouse; further in, it moves less per pixel
			local mx, my = gui.MouseX(), gui.MouseY()
			local k = 0.12 * z * (1080 / ScrH())
			self.panY = math.Clamp(self.panY - (mx - self.panFrom[1]) * k, -45, 45)
			self.panZ = math.Clamp(self.panZ + (my - self.panFrom[2]) * k, -40, 40)
			self.panFrom = {mx, my}
		end
		ent:SetAngles(Angle(0, self.yaw, 0))
		local pan = Vector(0, self.panY, self.panZ)
		self:SetCamPos(Vector(110 * z, 0, 40 + 20 * (1 - z) + 8) + pan)
		self:SetLookAt(Vector(0, 0, 36 + 26 * (1 - z)) + pan)
		self:RunAnimation()
	end

	local right = vgui.Create("DScrollPanel", frame)
	right:SetPos(ScrW() - S(400), top)
	right:SetSize(S(370), ScrH() - top - S(130))
	right.Paint = function(_, w, h) surface.SetDrawColor(colPanel) surface.DrawRect(0, 0, w, h) end
	right:GetCanvas():DockPadding(S(14), S(4), S(14), S(14))

	local function ApplyPreview()
		local ent = preview.Entity
		if !IsValid(ent) then return end
		ent:SetSkin(cur.skin)
		for i = 0, ent:GetNumBodyGroups() - 1 do ent:SetBodygroup(i, cur.groups[i] or 0) end
	end

	local BuildRight -- below
	local function SetModel(name, keepLook)
		cur.name = name
		preview:SetModel(player_manager.TranslatePlayerModel(name))
		local ent = preview.Entity
		if !IsValid(ent) then return end
		ent.GetPlayerColor = function() return cur.color end
		local seq = ent:LookupSequence("idle_all_01")
		if seq >= 0 then ent:ResetSequence(seq) end
		if !keepLook then
			cur.skin = 0
			cur.groups = {}
		end
		cur.skin = math.min(cur.skin, math.max(ent:SkinCount() - 1, 0))
		ApplyPreview()
		BuildRight()
	end

	BuildRight = function()
		right:Clear()
		local ent = preview.Entity
		Section(right, "Appearance")
		local any = false
		if IsValid(ent) && ent:SkinCount() > 1 then
			any = true
			Slider(right, "Skin", ent:SkinCount() - 1, cur.skin, function(v) cur.skin = v ApplyPreview() end)
		end
		if IsValid(ent) then
			for i = 0, ent:GetNumBodyGroups() - 1 do
				local count = ent:GetBodygroupCount(i)
				if count > 1 then
					any = true
					local label = string.gsub(ent:GetBodygroupName(i) or ("Part " .. i), "_", " ")
					label = string.upper(string.sub(label, 1, 1)) .. string.sub(label, 2)
					Slider(right, label, count - 1, cur.groups[i] or 0, function(v) cur.groups[i] = v ApplyPreview() end)
				end
			end
		end
		if !any then
			local l = right:Add("DLabel")
			l:Dock(TOP)
			l:SetFont("GFR_Cust_Text")
			l:SetTextColor(colDim)
			l:SetText("This model has no outfit options.")
			l:SizeToContentsY()
		end

		Section(right, "Clothes colour")
		local mixer = right:Add("DColorMixer")
		mixer:Dock(TOP)
		mixer:SetTall(S(200))
		mixer:SetPalette(true)
		mixer:SetAlphaBar(false)
		mixer:SetWangs(false)
		mixer:SetVector(cur.color)
		mixer.ValueChanged = function(_, col) cur.color = Vector(col.r / 255, col.g / 255, col.b / 255) end
	end

	-------------------------------------------------------------------------------------------------------------------------------------
	-- Left: the models
	local left = vgui.Create("DPanel", frame)
	left:SetPos(S(30), top)
	left:SetSize(S(410), ScrH() - top - S(40))
	left.Paint = function(_, w, h) surface.SetDrawColor(colPanel) surface.DrawRect(0, 0, w, h) end
	left:DockPadding(S(10), S(10), S(10), S(10))

	local search = left:Add("DTextEntry")
	search:Dock(TOP)
	search:SetTall(S(30))
	search:SetFont("GFR_Cust_Text")
	search:SetPlaceholderText("Search models...")

	local scroll = left:Add("DScrollPanel")
	scroll:Dock(FILL)
	scroll:DockMargin(0, S(8), 0, 0)
	local grid = scroll:Add("DIconLayout")
	grid:Dock(FILL)
	grid:SetSpaceX(S(4))
	grid:SetSpaceY(S(4))

	local all = ModelList()
	local icons = {}
	for _, m in ipairs(all) do
		local icon = grid:Add("SpawnIcon")
		icon:SetSize(S(72), S(72))
		icon:SetModel(m.path)
		icon:SetTooltip(m.name)
		icon.GFR_Name = m.name
		icon.PaintOver = function(self, w, h)
			if cur.name == self.GFR_Name then
				surface.SetDrawColor(colPick)
				surface.DrawRect(0, 0, w, h)
				surface.SetDrawColor(colAccent)
				surface.DrawOutlinedRect(0, 0, w, h, 2)
			end
		end
		icon.DoClick = function() SetModel(m.name) surface.PlaySound("ui/buttonclick.wav") end
		icons[#icons + 1] = icon
	end
	search.OnChange = function(self)
		local q = string.lower(self:GetValue())
		for _, icon in ipairs(icons) do icon:SetVisible(q == "" or string.find(string.lower(icon.GFR_Name), q, 1, true) != nil) end
		grid:Layout()
	end

	-------------------------------------------------------------------------------------------------------------------------------------
	-- Buttons
	local function Button(text, y, primary, click)
		local b = vgui.Create("DButton", frame)
		b:SetPos(ScrW() - S(400), y)
		b:SetSize(S(370), primary and S(56) or S(40))
		b:SetText("")
		b.Paint = function(self, w, h)
			local hov = self:IsHovered()
			surface.SetDrawColor(primary and (hov and Color(220, 140, 64) or colAccent) or (hov and Color(52, 56, 58) or Color(38, 41, 43)))
			surface.DrawRect(0, 0, w, h)
			draw.SimpleText(text, primary and "GFR_Cust_Button" or "GFR_Cust_Head", w / 2, h / 2, primary and Color(20, 16, 12) or colText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		b.DoClick = click
		return b
	end

	Button("RANDOMIZE", ScrH() - S(124), false, function()
		local pick = all[math.random(#all)]
		cur.color = Vector(math.Rand(0, 1), math.Rand(0, 1), math.Rand(0, 1))
		SetModel(pick.name)
		local ent = preview.Entity
		if IsValid(ent) then
			cur.skin = math.random(0, math.max(ent:SkinCount() - 1, 0))
			for i = 0, ent:GetNumBodyGroups() - 1 do cur.groups[i] = math.random(0, math.max(ent:GetBodygroupCount(i) - 1, 0)) end
			ApplyPreview()
			BuildRight()
		end
	end)

	Button(forced and "START" or "APPLY", ScrH() - S(76), true, function()
		local ent = preview.Entity
		local n = IsValid(ent) and ent:GetNumBodyGroups() or 0
		local parts = {}
		for i = 0, n - 1 do parts[#parts + 1] = tostring(cur.groups[i] or 0) end
		local groups = table.concat(parts, " ")
		-- GMod's own settings: respawns use them, and they're filled in here next time
		RunConsoleCommand("cl_playermodel", cur.name)
		RunConsoleCommand("cl_playerskin", tostring(cur.skin))
		RunConsoleCommand("cl_playerbodygroups", groups)
		RunConsoleCommand("cl_playercolor", string.format("%.3f %.3f %.3f", cur.color.x, cur.color.y, cur.color.z))
		net.Start("GFR_Customize")
		net.WriteString(cur.name)
		net.WriteUInt(math.Clamp(cur.skin, 0, 255), 8)
		net.WriteString(groups)
		net.WriteVector(cur.color)
		net.SendToServer()
		surface.PlaySound("ui/buttonclickrelease.wav")
		frame:Remove()
	end)

	SetModel(cur.name, true)
end

concommand.Add("gfr_customize", function() GFR.OpenCustomize(false) end)

-- M belongs to us here: the War Zones NPC System addon (workshop 3649084776) opens its zone map on M
-- (zone_npc_cl_map_key). Its key is unbound while you play this gamemode; your own setting comes back when you leave.
local function FreeM()
	local cv = GetConVar("zone_npc_cl_map_key")
	if !cv then return end
	if cv:GetInt() == KEY_M then
		cookie.Set("gfr_zonemap_key_orig", tostring(KEY_M))
		RunConsoleCommand("zone_npc_cl_map_key", "0")
	end
end
hook.Add("InitPostEntity", "GFR_Customize_FreeM", FreeM)
timer.Simple(1, FreeM)
hook.Add("ShutDown", "GFR_Customize_RestoreM", function()
	local orig = cookie.GetString("gfr_zonemap_key_orig")
	if orig && GetConVar("zone_npc_cl_map_key") then
		RunConsoleCommand("zone_npc_cl_map_key", orig)
		cookie.Delete("gfr_zonemap_key_orig")
	end
end)

-- Hold M for 3 seconds: back to the character screen (a ring fills while you hold it)
local HOLD_TIME = 3
local holdStart -- nil: not holding; math.huge: done, waiting for you to let go
hook.Add("Think", "GFR_Customize_HoldM", function()
	local ply = LocalPlayer()
	local down = input.IsKeyDown(KEY_M) && IsValid(ply) && !ply:IsTyping() && !gui.IsGameUIVisible() && !vgui.GetKeyboardFocus()
	if !down then holdStart = nil return end
	if IsValid(frame) or ply:GetNW2Bool("GFR_IsZombie") then return end -- (no changing who you were once you've turned)
	holdStart = holdStart or CurTime()
	if CurTime() - holdStart >= HOLD_TIME then
		holdStart = math.huge
		surface.PlaySound("ui/buttonclick.wav")
		GFR.OpenCustomize(false)
	end
end)

hook.Add("HUDPaint", "GFR_Customize_HoldM", function()
	if !holdStart or holdStart == math.huge or IsValid(frame) then return end
	local frac = math.Clamp((CurTime() - holdStart) / HOLD_TIME, 0, 1)
	local cx, cy, r = ScrW() / 2, ScrH() * 0.62, S(26)
	-- Ring filling clockwise from the top
	draw.NoTexture()
	surface.SetDrawColor(0, 0, 0, 150)
	for i = 0, 63 do
		local a1, a2 = (i / 64) * math.pi * 2, ((i + 1) / 64) * math.pi * 2
		surface.DrawPoly({{x = cx, y = cy}, {x = cx + math.sin(a1) * r, y = cy - math.cos(a1) * r}, {x = cx + math.sin(a2) * r, y = cy - math.cos(a2) * r}})
	end
	surface.SetDrawColor(colAccent)
	local segs = math.floor(frac * 64)
	for i = 0, segs - 1 do
		local a1, a2 = (i / 64) * math.pi * 2, ((i + 1) / 64) * math.pi * 2
		surface.DrawPoly({{x = cx, y = cy}, {x = cx + math.sin(a1) * r, y = cy - math.cos(a1) * r}, {x = cx + math.sin(a2) * r, y = cy - math.cos(a2) * r}})
	end
	surface.SetDrawColor(0, 0, 0, 200)
	for i = 0, 63 do
		local a1, a2 = (i / 64) * math.pi * 2, ((i + 1) / 64) * math.pi * 2
		local rr = r * 0.62
		surface.DrawPoly({{x = cx, y = cy}, {x = cx + math.sin(a1) * rr, y = cy - math.cos(a1) * rr}, {x = cx + math.sin(a2) * rr, y = cy - math.cos(a2) * rr}})
	end
	draw.SimpleTextOutlined("Hold [M]: character", "GFR_Cust_Text", cx, cy + r + S(16), colText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 200))
end)

-- Joining: the server holds you until you've chosen (sv_customize.lua)
timer.Create("GFR_Customize_Watch", 0.5, 0, function()
	local ply = LocalPlayer()
	if IsValid(ply) && ply:GetNW2Bool("GFR_Customizing") && !IsValid(frame) then GFR.OpenCustomize(true) end
end)

-- Nothing else on screen meanwhile
hook.Add("HUDShouldDraw", "GFR_Customize_NoHUD", function()
	if IsValid(frame) && LocalPlayer():GetNW2Bool("GFR_Customizing") then return false end
end)
