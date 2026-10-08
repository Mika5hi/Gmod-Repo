--[[
	Green Flu: Reimagined - access window (Shift+E on something you built). Server side: sv_owners.lua
	Your access list (one for everything you build) and, on a turret, who it shoots.
]]
local function S(x) return math.Round(x * ScrH() / 1080) end

local colBg = Color(16, 16, 19, 248)
local colRow = Color(255, 255, 255, 14)
local colText = Color(232, 232, 232)
local colDim = Color(150, 150, 150)
local colAccent = Color(215, 175, 90)
local colGood = Color(110, 190, 110)
local colBad = Color(210, 80, 70)

local function Fonts()
	surface.CreateFont("GFR_Acc_Title", {font = "Roboto", size = S(24), weight = 800, extended = true})
	surface.CreateFont("GFR_Acc_Text", {font = "Roboto", size = S(17), weight = 600, extended = true})
	surface.CreateFont("GFR_Acc_Small", {font = "Roboto", size = S(15), weight = 600, extended = true})
end
Fonts()
hook.Add("OnScreenSizeChanged", "GFR_Access_Fonts", Fonts)

local frame, data

local function Request(action, ...)
	if !data or !IsValid(data.ent) then return end
	net.Start("GFR_AccessReq")
	net.WriteEntity(data.ent)
	net.WriteString(action)
	for _, v in ipairs({...}) do
		if isnumber(v) then net.WriteUInt(v, 2) else net.WriteString(v) end
	end
	net.SendToServer()
end

local function Btn(parent, text, col, w, onClick)
	local b = parent:Add("DButton")
	b:SetText("")
	b:SetWide(w)
	b.Paint = function(self, bw, bh)
		draw.RoundedBox(S(5), 0, 0, bw, bh, self:IsHovered() and ColorAlpha(col, 200) or ColorAlpha(col, 90))
		draw.SimpleText(text, "GFR_Acc_Small", bw / 2, bh / 2, colText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	b.DoClick = onClick
	return b
end

local function Header(parent, text)
	local l = parent:Add("DLabel")
	l:Dock(TOP)
	l:DockMargin(0, S(12), 0, S(4))
	l:SetFont("GFR_Acc_Text")
	l:SetTextColor(colAccent)
	l:SetText(text)
	l:SizeToContentsY()
end

local function Note(parent, text)
	local l = parent:Add("DLabel")
	l:Dock(TOP)
	l:DockMargin(0, 0, 0, S(4))
	l:SetFont("GFR_Acc_Small")
	l:SetTextColor(colDim)
	l:SetWrap(true)
	l:SetAutoStretchVertical(true)
	l:SetText(text)
end

local function Build()
	frame.Body:Clear()
	local body = frame.Body

	-- Turret: who it shoots
	if data.turret then
		Header(body, "Who it shoots (besides the dead and hostile people)")
		if !data.pvp then Note(body, "This server doesn't let turrets shoot players.") end
		local modes = {{0, "No players"}, {1, "Every player but me"}, {2, "Every player not on my list"}}
		local row = body:Add("DPanel")
		row:Dock(TOP)
		row:SetTall(S(38))
		row.Paint = nil
		for _, m in ipairs(modes) do
			local on = data.mode == m[1]
			local b = Btn(row, m[2], on and colAccent or Color(120, 120, 120), S(200), function() Request("mode", m[1]) end)
			b:Dock(LEFT)
			b:DockMargin(0, 0, S(6), 0)
		end
	end

	-- The access list
	Header(body, "My access list")
	Note(body, "One list for everything you build. These players can open your storage, use your beds and take your things down" ..
		(data.turret and ", and turrets on \"Every player not on my list\" leave them alone." or "."))
	local scroll = body:Add("DScrollPanel")
	scroll:Dock(TOP)
	scroll:SetTall(S(170))
	if #data.list == 0 then Note(scroll, "Nobody yet.") end
	for _, f in ipairs(data.list) do
		local r = scroll:Add("DPanel")
		r:Dock(TOP)
		r:DockMargin(0, 0, 0, S(4))
		r:SetTall(S(36))
		r.Paint = function(self, w, h)
			draw.RoundedBox(S(6), 0, 0, w, h, colRow)
			draw.SimpleText(f.name, "GFR_Acc_Text", S(10), h / 2, colText, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText(f.id, "GFR_Acc_Small", S(260), h / 2, colDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		local rm = Btn(r, "Remove", colBad, S(90), function() Request("remove", f.id) end)
		rm:Dock(RIGHT)
		rm:DockMargin(0, S(5), S(5), S(5))
	end

	-- Add: someone on the server, or a SteamID
	Header(body, "Add someone")
	local pick = body:Add("DPanel")
	pick:Dock(TOP)
	pick:SetTall(S(34))
	pick.Paint = nil
	local combo = pick:Add("DComboBox")
	combo:Dock(FILL)
	combo:DockMargin(0, 0, S(6), 0)
	combo:SetValue(#data.online > 0 and "Pick a player on the server..." or "Nobody else is on")
	for _, p in ipairs(data.online) do combo:AddChoice(p.name, p) end
	local addP = Btn(pick, "Add", colGood, S(90), function()
		local _, p = combo:GetSelected()
		if p then Request("add", p.id, p.name) end
	end)
	addP:Dock(RIGHT)

	local sid = body:Add("DPanel")
	sid:Dock(TOP)
	sid:DockMargin(0, S(6), 0, 0)
	sid:SetTall(S(34))
	sid.Paint = nil
	local entry = sid:Add("DTextEntry")
	entry:Dock(FILL)
	entry:DockMargin(0, 0, S(6), 0)
	entry:SetPlaceholderText("or a SteamID: STEAM_0:1:12345678")
	local addS = Btn(sid, "Add", colGood, S(90), function() Request("add", entry:GetValue(), "") end)
	addS:Dock(RIGHT)
end

local function Open()
	if IsValid(frame) then Build() return end
	frame = vgui.Create("DFrame")
	local f = frame
	f:SetSize(S(680), S(data.turret and 560 or 500))
	f:Center()
	f:SetTitle("")
	f:ShowCloseButton(false)
	f:MakePopup()
	f:DockPadding(S(20), S(56), S(20), S(20))
	f.Paint = function(self, w, h)
		draw.RoundedBox(S(10), 0, 0, w, h, colBg)
		local name = IsValid(data.ent) and (data.ent:GetNW2String("GFR_TurretName", "") != "" and data.ent:GetNW2String("GFR_TurretName")
			or data.ent:GetNW2String("GFR_BaseName", "") != "" and data.ent:GetNW2String("GFR_BaseName")
			or data.ent:GetNW2String("GFR_BuildName", "")) or ""
		draw.SimpleText(string.upper(name != "" and name or "Access"), "GFR_Acc_Title", S(20), S(16), colText)
		draw.SimpleText(data.isOwner and "Yours" or ("Owner: " .. data.owner), "GFR_Acc_Small", w - S(70), S(24), colDim, TEXT_ALIGN_RIGHT)
	end
	local close = f:Add("DButton")
	close:SetText("")
	close:SetSize(S(36), S(36))
	close:SetPos(f:GetWide() - S(52), S(12))
	close.Paint = function(self, w, h)
		draw.RoundedBox(S(6), 0, 0, w, h, self:IsHovered() and ColorAlpha(colBad, 200) or Color(255, 255, 255, 10))
		draw.SimpleText("X", "GFR_Acc_Text", w / 2, h / 2, colText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	close.DoClick = function() f:Remove() end
	f.Think = function(self)
		if !IsValid(data.ent) or !LocalPlayer():Alive() then self:Remove() end
	end
	f.Body = f:Add("DPanel")
	f.Body:Dock(FILL)
	f.Body.Paint = nil
	Build()
end

-- (Esc closes it instead of opening GMod's menu)
hook.Add("OnPauseMenuShow", "GFR_Access_Esc", function()
	if IsValid(frame) then frame:Remove() return false end
end)

net.Receive("GFR_Access", function()
	data = net.ReadTable()
	Open()
end)

-- Whose is it: shown under the usual prompts when you look at something someone built (cl_crafting.lua, cl_base.lua)
function GFR.OwnerPrompt(ent)
	local id = ent:GetNW2String("GFR_OwnerID", "")
	if id == "" then return end
	if id == LocalPlayer():SteamID() then return "Yours   [Shift+E] Access" end
	return "Owner: " .. ent:GetNW2String("GFR_OwnerName", "?")
end
