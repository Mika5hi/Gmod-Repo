--[[
	Custom Apocalypse - companion window and HUD
	E on a companion: orders (follow / hold / part ways), their weapon (take it, hand them one, give ammo),
	their pockets (hand items over, take them back). Their names and health sit on the left of the screen.
	Server side: sv_companions.lua
]]
local function S(x) return math.Round(x * ScrH() / 1080) end
local function Fonts()
	surface.CreateFont("GFR_Comp_Title", {font = "Roboto", size = S(26), weight = 800, extended = true})
	surface.CreateFont("GFR_Comp_Name", {font = "Roboto", size = S(18), weight = 700, extended = true})
	surface.CreateFont("GFR_Comp_Text", {font = "Roboto", size = S(15), weight = 600, extended = true})
	surface.CreateFont("GFR_Comp_Small", {font = "Roboto", size = S(13), weight = 700, extended = true})
	surface.CreateFont("GFR_Comp_HUD", {font = "Roboto", size = S(15), weight = 700, extended = true})
end
Fonts()

local colBg = Color(14, 14, 17, 245)
local colPanel = Color(0, 0, 0, 90)
local colStripe = Color(255, 255, 255, 14)
local colCard = Color(255, 255, 255, 10)
local colHover = Color(255, 255, 255, 26)
local colText = Color(232, 232, 232)
local colDim = Color(145, 145, 145)
local colGood = Color(120, 205, 120)
local colBad = Color(220, 95, 85)
local colWarn = Color(220, 175, 80)
local colComp = Color(110, 190, 150)

local win

local function Send(npc, action, arg)
	net.Start("GFR_CompAction")
	net.WriteEntity(npc)
	net.WriteString(action)
	net.WriteString(arg or "")
	net.SendToServer()
end

local function ItemName(class)
	local w = weapons.Get(class)
	if w then return w.PrintName or class end
	return GFR.ItemDisplayName and GFR.ItemDisplayName(class) or class
end

local function WepModel(class)
	local w = weapons.Get(class)
	return w && w.WorldModel
end

local function Icon(parent, mdl, size, x, y)
	if !mdl or mdl == "" or !util.IsValidModel(mdl) then return end
	local icon = parent:Add("SpawnIcon")
	icon:SetModel(mdl)
	icon:SetSize(size, size)
	icon:SetPos(x, y)
	icon:SetMouseInputEnabled(false)
	return icon
end

local function Box(parent, title, x, y, w, h)
	local p = parent:Add("DPanel")
	p:SetPos(x, y)
	p:SetSize(w, h)
	p.Paint = function(self, pw, ph)
		draw.RoundedBox(S(6), 0, 0, pw, ph, colPanel)
		draw.RoundedBoxEx(S(6), 0, 0, pw, S(28), colStripe, true, true, false, false)
		draw.SimpleText(string.upper(title), "GFR_Comp_Small", S(10), S(14), colDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	p:DockPadding(S(8), S(36), S(8), S(8))
	return p
end

local function Btn(parent, text, col, fn, tall)
	local b = parent:Add("DButton")
	b:Dock(TOP)
	b:DockMargin(0, 0, 0, S(6))
	b:SetTall(tall or S(36))
	b:SetText("")
	b.Paint = function(self, pw, ph)
		local c = self.Disabled and Color(80, 80, 80) or col
		draw.RoundedBox(S(5), 0, 0, pw, ph, Color(c.r, c.g, c.b, self:IsHovered() && !self.Disabled and 150 or 70))
		draw.SimpleText(text, "GFR_Comp_Text", S(12), ph / 2, self.Disabled and colDim or colText, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	b.DoClick = function(self) if !self.Disabled then fn() end end
	return b
end

-- A row in a list: icon, name, a small line under it
local function Row(parent, mdl, name, sub, subCol, fn, tooltip)
	local row = parent:Add("DButton")
	row:Dock(TOP)
	row:DockMargin(0, 0, 0, S(4))
	row:SetTall(S(46))
	row:SetText("")
	Icon(row, mdl, S(38), S(4), S(4))
	row.Paint = function(self, pw, ph)
		draw.RoundedBox(S(4), 0, 0, pw, ph, self:IsHovered() and colHover or colCard)
		draw.SimpleText(name, "GFR_Comp_Text", S(50), S(7), colText)
		draw.SimpleText(sub, "GFR_Comp_Small", S(50), S(26), subCol or colDim)
	end
	row.DoClick = fn
	if tooltip then row:SetTooltip(tooltip) end
	return row
end

local function CloseWin() if IsValid(win) then win:Remove() end end

net.Receive("GFR_Comp", function()
	local npc = net.ReadEntity()
	local d = net.ReadTable()
	if GFR.CloseDialog then GFR.CloseDialog() end
	if !IsValid(npc) or !d.name then CloseWin() return end
	Fonts()

	local scroll = {}
	if IsValid(win) && win.Scrolls then
		for k, sp in pairs(win.Scrolls) do if IsValid(sp) then scroll[k] = sp:GetVBar():GetScroll() end end
	end
	CloseWin()

	local w, h = math.min(S(1000), ScrW() - S(40)), math.min(S(600), ScrH() - S(40))
	win = vgui.Create("DFrame")
	win:SetSize(w, h)
	win:Center()
	win:SetTitle("")
	win:ShowCloseButton(false)
	win:SetDraggable(false)
	win:MakePopup()
	win:SetKeyboardInputEnabled(false)
	win.NPC = npc
	win.Scrolls = {}
	local pad, gap = S(16), S(10)
	local headH = S(64)

	win.Paint = function(self, pw, ph)
		draw.RoundedBox(S(10), 0, 0, pw, ph, colBg)
		draw.RoundedBox(0, 0, S(10), S(4), ph - S(20), colComp)
		draw.SimpleText(d.name, "GFR_Comp_Title", pad, S(10), colText)
		local order = d.order == "stay" and "Holding position" or "Following you"
		surface.SetFont("GFR_Comp_Title")
		local nw = surface.GetTextSize(d.name)
		draw.SimpleText("Companion  ·  " .. order, "GFR_Comp_Small", pad + nw + S(14), S(22), colComp)
		-- Health
		local hp = IsValid(npc) and npc:GetNW2Int("GFR_HP", d.hp) or d.hp
		local f = math.Clamp(hp / math.max(d.maxhp, 1), 0, 1)
		local bw = S(260)
		draw.RoundedBox(S(3), pad, S(44), bw, S(8), Color(0, 0, 0, 160))
		draw.RoundedBox(S(3), pad, S(44), bw * f, S(8), f > 0.5 and colGood or (f > 0.25 and colWarn or colBad))
		draw.SimpleText(hp .. " / " .. d.maxhp, "GFR_Comp_Small", pad + bw + S(8), S(48), colDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	local close = win:Add("DButton")
	close:SetSize(S(32), S(32))
	close:SetPos(w - S(44), S(14))
	close:SetText("✕")
	close:SetFont("GFR_Comp_Name")
	close:SetTextColor(colDim)
	close.Paint = nil
	close.DoClick = CloseWin

	local bodyH = h - headH - pad
	local ordersW = S(210)
	local colW = math.floor((w - pad * 2 - ordersW - gap * 2) / 2)

	-- Orders
	local orders = Box(win, "Orders", pad, headH, ordersW, bodyH)
	local follow = Btn(orders, (d.order != "stay" and "● " or "○ ") .. "Follow me", colComp, function() Send(npc, "follow") end)
	local stay = Btn(orders, (d.order == "stay" and "● " or "○ ") .. "Hold this position", colWarn, function() Send(npc, "stay") end)
	local spacer = orders:Add("DPanel")
	spacer:Dock(TOP)
	spacer:SetTall(S(10))
	spacer.Paint = nil
	Btn(orders, "Part ways", colBad, function()
		Derma_Query("Send " .. d.name .. " off on their own? They keep what they're carrying.", "Part ways", "Yes", function() Send(npc, "dismiss") end, "No")
	end)
	local tip = orders:Add("DLabel")
	tip:Dock(BOTTOM)
	tip:SetWrap(true)
	tip:SetAutoStretchVertical(true)
	tip:SetFont("GFR_Comp_Small")
	tip:SetTextColor(colDim)
	tip:SetText("Crouch+E on them flips between follow and hold.\n\nThey patch themselves up with medicine in their pockets when badly hurt.")

	-- Weapon
	local wbox = Box(win, "Weapon", pad + ordersW + gap, headH, colW, bodyH)
	local card = wbox:Add("DPanel")
	card:Dock(TOP)
	card:SetTall(S(92))
	card:DockMargin(0, 0, 0, S(8))
	local wep = d.wep
	if wep then Icon(card, WepModel(wep.class), S(80), S(6), S(6)) end
	card.Paint = function(self, pw, ph)
		draw.RoundedBox(S(5), 0, 0, pw, ph, colCard)
		if !wep then
			draw.SimpleText("Unarmed", "GFR_Comp_Name", S(14), S(16), colDim)
			draw.SimpleText("Hand them a gun from the list below.", "GFR_Comp_Small", S(14), S(44), colDim)
			return
		end
		local x = S(96)
		draw.SimpleText(ItemName(wep.class), "GFR_Comp_Name", x, S(10), colText)
		draw.SimpleText("In the gun: " .. math.max(wep.clip, 0) .. "    Spare magazines: " .. wep.mags, "GFR_Comp_Small", x, S(38), wep.mags > 0 and colText or colWarn)
		if wep.out then
			draw.SimpleText("OUT OF AMMO: fighting with a crowbar", "GFR_Comp_Small", x, S(60), colBad)
		elseif wep.ammo != "" then
			draw.SimpleText("Ammo: " .. wep.ammo .. "  (you have " .. wep.have .. ")", "GFR_Comp_Small", x, S(60), colDim)
		end
	end
	if wep then
		local row = wbox:Add("DPanel")
		row:Dock(TOP)
		row:SetTall(S(36))
		row:DockMargin(0, 0, 0, S(10))
		row.Paint = nil
		local half = (colW - S(16) - S(6)) / 2
		local take = row:Add("DButton")
		take:Dock(LEFT)
		take:SetWide(half)
		take:SetText("")
		take.Paint = function(self, pw, ph)
			draw.RoundedBox(S(5), 0, 0, pw, ph, Color(150, 160, 180, self:IsHovered() and 150 or 70))
			draw.SimpleText("Take it", "GFR_Comp_Text", pw / 2, ph / 2, colText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		take.DoClick = function() Send(npc, "takewep") end
		take:SetTooltip("Into your bag, with their spare magazines as your ammo")
		local ammo = row:Add("DButton")
		ammo:Dock(RIGHT)
		ammo:SetWide(half)
		ammo:SetText("")
		ammo.Paint = function(self, pw, ph)
			draw.RoundedBox(S(5), 0, 0, pw, ph, Color(205, 180, 90, self:IsHovered() and 150 or 70))
			draw.SimpleText("Give a magazine", "GFR_Comp_Text", pw / 2, ph / 2, colText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		ammo.DoClick = function() Send(npc, "giveammo") end
		ammo:SetTooltip("One magazine's worth from your ammo (or an ammo box in your bag)")
	end
	local lbl = wbox:Add("DLabel")
	lbl:Dock(TOP)
	lbl:SetTall(S(22))
	lbl:SetFont("GFR_Comp_Small")
	lbl:SetTextColor(colDim)
	lbl:SetText(wep and "SWAP FOR ONE OF YOUR GUNS" or "HAND THEM A GUN")
	local wlist = wbox:Add("DScrollPanel")
	wlist:Dock(FILL)
	win.Scrolls.w = wlist
	for _, mw in ipairs(d.myWeps or {}) do
		Row(wlist, WepModel(mw.class), ItemName(mw.class), (mw.where == "carried" and "Carried" or "In your bag") .. "  ·  " .. math.max(mw.clip or 0, 0) .. " in the gun",
			nil, function() Send(npc, "givewep", mw.src) end, "Give it to " .. d.name)
	end
	if #(d.myWeps or {}) == 0 then
		local l = wlist:Add("DLabel") l:Dock(TOP) l:SetFont("GFR_Comp_Small") l:SetTextColor(colDim) l:SetText("You have no guns they can use (handguns, rifles, shotguns...).")
	end

	-- Pockets
	local pbox = Box(win, "Pockets  (" .. #d.pockets .. " / " .. d.slots .. ")", pad + ordersW + gap * 2 + colW, headH, colW, bodyH)
	local grid = pbox:Add("DIconLayout")
	grid:Dock(TOP)
	grid:SetSpaceX(S(6))
	grid:SetSpaceY(S(6))
	local ts = math.floor((colW - S(16) - S(6) * 5) / 6)
	for i = 1, d.slots do
		local it = d.pockets[i]
		local slot = grid:Add("DButton")
		slot:SetSize(ts, ts)
		slot:SetText("")
		if it then Icon(slot, it.model, ts - S(8), S(4), S(4)) end
		slot.Paint = function(self, pw, ph)
			draw.RoundedBox(S(4), 0, 0, pw, ph, it and (self:IsHovered() and colHover or colCard) or Color(255, 255, 255, 4))
			if it && it.contaminated then draw.RoundedBox(S(4), 0, 0, pw, ph, Color(150, 20, 20, 60)) end
		end
		slot.PaintOver = function(self, pw, ph)
			if it && it.count > 1 then draw.SimpleTextOutlined(it.count, "GFR_Comp_Small", pw - S(4), ph - S(4), colText, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, 200)) end
		end
		if it then
			slot:SetTooltip(ItemName(it.class) .. "\nClick: take one back")
			slot.DoClick = function() Send(npc, "takeitem", tostring(i)) end
		end
	end
	grid:InvalidateLayout(true)
	grid:SizeToChildren(false, true)
	local lbl2 = pbox:Add("DLabel")
	lbl2:Dock(TOP)
	lbl2:DockMargin(0, S(10), 0, 0)
	lbl2:SetTall(S(22))
	lbl2:SetFont("GFR_Comp_Small")
	lbl2:SetTextColor(colDim)
	lbl2:SetText("YOUR BAG  (click to hand over one)")
	local ilist = pbox:Add("DScrollPanel")
	ilist:Dock(FILL)
	win.Scrolls.i = ilist
	local hurt = d.hp < d.maxhp
	for _, e in ipairs(d.myItems or {}) do
		local sub = "x" .. e.count
		local col
		if e.heal > 0 then
			sub = sub .. (hurt and ("  ·  heals them now (+" .. e.heal .. ")") or "  ·  they'll use it when hurt")
			col = colGood
		end
		Row(ilist, e.model, ItemName(e.class), sub, col, function() Send(npc, "giveitem", tostring(e.index)) end)
	end
	if #(d.myItems or {}) == 0 then
		local l = ilist:Add("DLabel") l:Dock(TOP) l:SetFont("GFR_Comp_Small") l:SetTextColor(colDim) l:SetText("Your bag is empty.")
	end

	timer.Simple(0, function()
		for k, sp in pairs(win.Scrolls or {}) do
			if IsValid(sp) && scroll[k] then sp:GetVBar():SetScroll(scroll[k]) end
		end
	end)
end)

-- Walk away, die, or they die: close it
hook.Add("Think", "GFR_Comp_AutoClose", function()
	if !IsValid(win) then return end
	local ply = LocalPlayer()
	if !IsValid(ply) or !ply:Alive() or !IsValid(win.NPC) or win.NPC:GetPos():DistToSqr(ply:GetPos()) > 320 * 320 then win:Remove() end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- HUD: your people, on the left
local mine, nextScan = {}, 0
hook.Add("HUDPaint", "GFR_Comp_HUD", function()
	local ply = LocalPlayer()
	if !IsValid(ply) or !ply:Alive() then return end
	if CurTime() > nextScan then
		nextScan = CurTime() + 1
		mine = {}
		for _, e in ipairs(ents.GetAll()) do
			if e:IsNPC() && e:GetNW2Entity("GFR_CompOwner") == ply then mine[#mine + 1] = e end
		end
	end
	if #mine == 0 then return end
	local x, y = S(20), ScrH() * 0.34
	draw.SimpleTextOutlined("COMPANIONS", "GFR_Comp_Small", x, y, colDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 160))
	y = y + S(20)
	for _, e in ipairs(mine) do
		if !IsValid(e) then continue end
		local hp, max = e:GetNW2Int("GFR_HP", 100), math.max(e:GetNW2Int("GFR_MaxHP", 100), 1)
		local f = math.Clamp(hp / max, 0, 1)
		local order = e:GetNW2String("GFR_Order", "follow") == "stay" and "holding" or "following"
		local dist = math.Round(ply:GetPos():Distance(e:GetPos()) * 0.019)
		draw.SimpleTextOutlined(e:GetNW2String("GFR_Name", "?") .. "   " .. order .. "  " .. dist .. "m", "GFR_Comp_HUD", x, y, colText, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 180))
		draw.RoundedBox(S(2), x, y + S(19), S(150), S(5), Color(0, 0, 0, 160))
		draw.RoundedBox(S(2), x, y + S(19), S(150) * f, S(5), f > 0.5 and colGood or (f > 0.25 and colWarn or colBad))
		y = y + S(34)
	end
end)
