--[[
	Green Flu: Reimagined - staff menu window (!gfr in chat). Server side, who may do what: sv_admin.lua
]]
local function S(x) return math.Round(x * ScrH() / 1080) end

local colBg = Color(16, 16, 19, 248)
local colPanel = Color(255, 255, 255, 10)
local colRow = Color(255, 255, 255, 14)
local colRowHover = Color(255, 255, 255, 30)
local colText = Color(232, 232, 232)
local colDim = Color(150, 150, 150)
local colAccent = Color(215, 175, 90)
local colGood = Color(110, 190, 110)
local colBad = Color(210, 80, 70)
local roleNames = {[1] = "Moderator", [2] = "Admin", [3] = "Owner"}

local function Fonts()
	surface.CreateFont("GFR_Admin_Title", {font = "Roboto", size = S(26), weight = 800, extended = true})
	surface.CreateFont("GFR_Admin_Text", {font = "Roboto", size = S(17), weight = 600, extended = true})
	surface.CreateFont("GFR_Admin_Small", {font = "Roboto", size = S(15), weight = 600, extended = true})
end
Fonts()
hook.Add("OnScreenSizeChanged", "GFR_Admin_Fonts", Fonts)

local frame, data, tab = nil, nil, "players"

local function Request(action, ...)
	net.Start("GFR_AdminReq")
	net.WriteString(action)
	for _, v in ipairs({...}) do net.WriteString(tostring(v)) end
	net.SendToServer()
end

local function Button(parent, text, col, onClick)
	local b = parent:Add("DButton")
	b:SetText("")
	b:SetWide(S(96))
	b:Dock(RIGHT)
	b:DockMargin(S(6), S(6), 0, S(6))
	b.Paint = function(self, w, h)
		draw.RoundedBox(S(5), 0, 0, w, h, self:IsHovered() and ColorAlpha(col, 200) or ColorAlpha(col, 90))
		draw.SimpleText(text, "GFR_Admin_Small", w / 2, h / 2, colText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	b.DoClick = onClick
	return b
end

local function Header(parent, text)
	local l = parent:Add("DLabel")
	l:Dock(TOP)
	l:DockMargin(0, S(10), 0, S(4))
	l:SetFont("GFR_Admin_Text")
	l:SetTextColor(colAccent)
	l:SetText(text)
	l:SizeToContentsY()
end

-- One line of a player row: what it's about, their status, its buttons
local function Line(row, title, status, statusCol)
	local line = row:Add("DPanel")
	line:Dock(TOP)
	line:SetTall(S(36))
	line:DockPadding(S(330), 0, S(6), 0)
	line.Paint = function(self, w, h)
		draw.SimpleText(title, "GFR_Admin_Small", S(190), h / 2, colDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText(status, "GFR_Admin_Small", S(330), h / 2, statusCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	return line
end

-- One player: name, then a line for playing as a zombie and one for character models
local function PlayerRow(parent, p)
	local row = parent:Add("DPanel")
	row:Dock(TOP)
	row:DockMargin(0, 0, 0, S(6))
	row:DockPadding(0, S(2), 0, S(2))
	row:SetTall(S(76))
	row.Paint = function(self, w, h)
		draw.RoundedBox(S(6), 0, 0, w, h, colRow)
		draw.SimpleText(p.name, "GFR_Admin_Text", S(12), S(10), colText)
		draw.SimpleText(p.id .. (p.zombie and "   ·   zombie now" or ""), "GFR_Admin_Small", S(12), S(32), p.zombie and colBad or colDim)
	end

	local status, statusCol
	if p.list == "black" then status, statusCol = "Blacklisted", colBad
	elseif p.list == "white" then status, statusCol = "Whitelisted", colGood
	elseif p.allowed == false then status, statusCol = "Not allowed", colDim
	else status, statusCol = "Allowed", colDim end
	local z = Line(row, "Zombie", status, statusCol)
	if p.zombie then Button(z, "Take zombie", colBad, function() Request("release", p.id) end):SetWide(S(110)) end
	if p.list then Button(z, "Clear", Color(120, 120, 120), function() Request("list", p.id, p.name, "") end) end
	if p.list != "black" then Button(z, "Blacklist", colBad, function() Request("list", p.id, p.name, "black") end) end
	if p.list != "white" then Button(z, "Whitelist", colGood, function() Request("list", p.id, p.name, "white") end) end

	local mStatus, mCol = "Server setting", colDim
	if p.models == "white" then mStatus, mCol = "Any model", colGood elseif p.models == "black" then mStatus, mCol = "Stock only", colBad end
	local m = Line(row, "Models", mStatus, mCol)
	if p.models then Button(m, "Clear", Color(120, 120, 120), function() Request("models", p.id, p.name, "") end) end
	if p.models != "black" then Button(m, "Stock only", colBad, function() Request("models", p.id, p.name, "black") end) end
	if p.models != "white" then Button(m, "Any model", colGood, function() Request("models", p.id, p.name, "white") end) end
end

local function FillPlayers(body)
	local scroll = body:Add("DScrollPanel")
	scroll:Dock(FILL)
	Header(scroll, "Online")
	for _, p in ipairs(data.players or {}) do PlayerRow(scroll, p) end
	if #(data.listed or {}) > 0 then
		Header(scroll, "On the lists, not online")
		for _, p in ipairs(data.listed) do PlayerRow(scroll, p) end
	end
	local note = scroll:Add("DLabel")
	note:Dock(TOP)
	note:DockMargin(0, S(12), 0, 0)
	note:SetFont("GFR_Admin_Small")
	note:SetTextColor(colDim)
	note:SetWrap(true)
	note:SetAutoStretchVertical(true)
	note:SetText("Zombie - Blacklisted: when they turn, their body gets up as an AI zombie with their gear and they respawn. "
		.. "Whitelist only matters when \"Whitelisted players only\" is on (Server tab). Take zombie: they lose control "
		.. "of it this once.\nModels - Any model: every installed playermodel, even with SFW mode on. Stock only: GMod's "
		.. "own models, even with SFW mode off (someone wearing another is changed at once). Clear: the server's setting.")
end

-- One setting: a checkbox or a slider; greyed out when your role can't change it
local function SettingRow(parent, s)
	local can = (data.level or 0) >= (s.need or 2)
	local row = parent:Add("DPanel")
	row:Dock(TOP)
	row:DockMargin(0, 0, 0, S(4))
	row:SetTall(S(40))
	row.Paint = function(self, w, h)
		draw.RoundedBox(S(6), 0, 0, w, h, colRow)
		draw.SimpleText(s.label .. ((s.need or 2) >= 3 and "  (owner)" or ""), "GFR_Admin_Small", S(12), h / 2, can and colText or colDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	if s.kind == "bool" then
		local cb = row:Add("DCheckBox")
		cb:SetSize(S(20), S(20))
		cb:SetChecked(tonumber(s.value) != 0 && s.value != "")
		cb:SetEnabled(can)
		row.PerformLayout = function(self, w, h) cb:SetPos(w - S(34), (h - S(20)) / 2) end
		cb.OnChange = function(_, v) Request("cvar", s.name, v and "1" or "0") end
	else
		local sl = row:Add("DNumSlider")
		sl:SetText("")
		sl:SetMinMax(s.min or 0, s.max or 100)
		sl:SetDecimals(s.kind == "float" and 1 or 0)
		sl:SetValue(tonumber(s.value) or 0)
		sl:SetEnabled(can)
		sl.TextArea:SetTextColor(colText)
		row.PerformLayout = function(self, w, h)
			sl:SetSize(S(360), h)
			sl:SetPos(w - S(370), 0)
		end
		-- Sent when you let go of the slider (or finish typing), not on every step
		local last = sl:GetValue()
		sl.Think = function(self)
			if self:IsEditing() then return end
			local v = math.Round(self:GetValue(), s.kind == "float" and 1 or 0)
			if v != last then
				last = v
				Request("cvar", s.name, v)
			end
		end
	end
end

local function FillServer(body)
	-- Owner: everything below back to the defaults (asks first)
	if (data.level or 0) >= 3 then
		local bar = body:Add("DPanel")
		bar:Dock(BOTTOM)
		bar:SetTall(S(46))
		bar:DockMargin(0, S(8), 0, 0)
		bar.Paint = function(self, w, h)
			draw.SimpleText("Settings are saved on whoever hosts.", "GFR_Admin_Small", 0, h / 2, colDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		Button(bar, "Restore defaults", colBad, function()
			Derma_Query("Put every setting on this tab back to its default?", "Restore defaults",
				"Restore", function() Request("reset") end, "Cancel")
		end):SetWide(S(170))
	end
	local scroll = body:Add("DScrollPanel")
	scroll:Dock(FILL)
	local group
	for _, s in ipairs(data.settings or {}) do
		if s.group != group then group = s.group Header(scroll, group) end
		SettingRow(scroll, s)
	end
end

local function Build()
	if !IsValid(frame) or !data then return end
	frame.Body:Clear()
	if tab == "server" && (data.level or 0) >= 2 then FillServer(frame.Body) else tab = "players" FillPlayers(frame.Body) end
end

local function Open()
	if IsValid(frame) then Build() return end
	local f = vgui.Create("DFrame")
	frame = f
	f:SetSize(S(900), S(680))
	f:Center()
	f:SetTitle("")
	f:ShowCloseButton(false)
	f:MakePopup()
	f:DockPadding(S(20), S(64), S(20), S(20))
	f.Paint = function(self, w, h)
		draw.RoundedBox(S(10), 0, 0, w, h, colBg)
		draw.SimpleText("GREEN FLU: STAFF", "GFR_Admin_Title", S(22), S(18), colText)
		draw.SimpleText((roleNames[data and data.level or 0] or "") .. "   ·   Esc to close", "GFR_Admin_Small", w - S(70), S(26), colDim, TEXT_ALIGN_RIGHT)
	end
	local close = f:Add("DButton")
	close:SetText("")
	close:SetSize(S(36), S(36))
	close:SetPos(f:GetWide() - S(54), S(14))
	close.Paint = function(self, w, h)
		draw.RoundedBox(S(6), 0, 0, w, h, self:IsHovered() and ColorAlpha(colBad, 200) or colPanel)
		draw.SimpleText("X", "GFR_Admin_Text", w / 2, h / 2, colText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	close.DoClick = function() f:Remove() end

	local tabs = f:Add("DPanel")
	tabs:Dock(TOP)
	tabs:SetTall(S(36))
	tabs:DockMargin(0, 0, 0, S(8))
	tabs.Paint = nil
	local function Tab(id, text)
		local b = tabs:Add("DButton")
		b:Dock(LEFT)
		b:SetWide(S(140))
		b:DockMargin(0, 0, S(6), 0)
		b:SetText("")
		b.Paint = function(self, w, h)
			local on = tab == id
			draw.RoundedBox(S(6), 0, 0, w, h, on and ColorAlpha(colAccent, 120) or (self:IsHovered() and colRowHover or colPanel))
			draw.SimpleText(text, "GFR_Admin_Text", w / 2, h / 2, colText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		b.DoClick = function() tab = id Build() end
	end
	Tab("players", "Players")
	if (data.level or 0) >= 2 then Tab("server", "Server") end

	f.Body = f:Add("DPanel")
	f.Body:Dock(FILL)
	f.Body.Paint = nil
	Build()
end

-- Esc opens GMod's pause menu before the window ever hears it: while the window is open, Esc closes it instead
hook.Add("OnPauseMenuShow", "GFR_Admin_Esc", function()
	if IsValid(frame) then frame:Remove() return false end
end)

net.Receive("GFR_Admin", function()
	data = net.ReadTable()
	Open()
end)
