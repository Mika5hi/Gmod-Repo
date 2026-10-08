--[[
	Custom Apocalypse - dialog, trade window, quest tracker, NPC speech subtitles
	Server side: sv_npc.lua, sv_surrender.lua (GFR_Say)
]]
local function S(x) return math.Round(x * ScrH() / 1080) end

local function Fonts()
	surface.CreateFont("GFR_Dlg_Name", {font = "Roboto", size = S(22), weight = 800, extended = true})
	surface.CreateFont("GFR_Dlg_Text", {font = "Roboto", size = S(18), weight = 500, extended = true})
	surface.CreateFont("GFR_Dlg_Small", {font = "Roboto", size = S(15), weight = 700, extended = true})
	surface.CreateFont("GFR_Say", {font = "Roboto", size = S(21), weight = 600, extended = true})
end
Fonts()

local colBg = Color(12, 12, 14, 235)
local colPanel = Color(255, 255, 255, 10)
local colHover = Color(255, 255, 255, 28)
local colText = Color(228, 228, 228)
local colDim = Color(150, 150, 150)
local colCaps = Color(225, 190, 90)
local factionCol = {survivor = Color(200, 180, 120), military = Color(120, 170, 120), bandit = Color(210, 80, 70)}
local factionName = {survivor = "Survivor", military = "Military", bandit = "Bandit"}

local function SendAction(npc, action, arg, argStr)
	net.Start("GFR_DialogAction")
	net.WriteEntity(npc)
	net.WriteString(action)
	net.WriteUInt(arg or 0, 16)
	net.WriteString(argStr or "")
	net.SendToServer()
end

local function Button(parent, text, col, fn)
	local b = parent:Add("DButton")
	b:SetText(text)
	b:SetFont("GFR_Dlg_Small")
	b:SetTextColor(colText)
	b.Paint = function(self, w, h)
		draw.RoundedBox(S(6), 0, 0, w, h, self:IsHovered() and Color(col.r, col.g, col.b, 150) or Color(col.r, col.g, col.b, 70))
	end
	b.DoClick = fn
	return b
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Dialog
local dialog

local function CloseDialog()
	if IsValid(dialog) then dialog:Remove() end
end
GFR.CloseDialog = CloseDialog -- the companion window closes it (cl_companions.lua)

net.Receive("GFR_Dialog", function()
	local npc = net.ReadEntity()
	local faction = net.ReadString()
	local text = net.ReadString()
	local canTrade = net.ReadBool()
	local offer = net.ReadTable()
	local myQuests = net.ReadTable()
	local recruit = net.ReadTable()
	if !IsValid(npc) then return end
	Fonts()
	CloseDialog()

	local w = S(620)
	dialog = vgui.Create("DFrame")
	dialog:SetTitle("")
	dialog:ShowCloseButton(false)
	dialog:SetDraggable(false)
	dialog:MakePopup()
	dialog.NPC = npc
	local col = factionCol[faction] or colText

	local body = dialog:Add("DPanel")
	body:Dock(FILL)
	body:DockPadding(S(18), S(46), S(18), S(14))
	body.Paint = function(self, pw, ph)
		draw.RoundedBox(S(10), 0, 0, pw, ph, colBg)
		draw.RoundedBox(0, 0, 0, S(4), ph, col)
		draw.SimpleText(factionName[faction] or faction, "GFR_Dlg_Name", S(18), S(12), col)
		draw.SimpleText(GFR_Caps_Text and GFR_Caps_Text() or "", "GFR_Dlg_Small", pw - S(18), S(16), colCaps, TEXT_ALIGN_RIGHT)
	end

	local say = body:Add("DLabel")
	say:Dock(TOP)
	say:SetFont("GFR_Dlg_Text")
	say:SetTextColor(colText)
	say:SetWrap(true)
	say:SetAutoStretchVertical(true)
	say:SetText("\"" .. text .. "\"")
	say:DockMargin(0, 0, 0, S(12))

	local options = {}
	local function Option(label, colr, fn)
		local b = Button(body, label, colr, fn)
		b:Dock(TOP)
		b:SetTall(S(34))
		b:DockMargin(0, 0, 0, S(6))
		b:SetContentAlignment(4)
		b:SetTextInset(S(12), 0)
		options[#options + 1] = b
	end

	local function Fit()
		dialog:SetSize(w, S(400))
		body:InvalidateLayout(true)
		body:SizeToChildren(false, true)
		dialog:SetTall(math.min(body:GetTall() + S(14), ScrH() * 0.8))
		dialog:SetPos((ScrW() - w) / 2, ScrH() - dialog:GetTall() - S(140))
	end

	local function Clear()
		for _, b in ipairs(options) do b:SetVisible(false) b:Remove() end -- (hidden first: removal waits for the frame end)
		options = {}
	end

	local Main
	-- Actions (sv_actions.lua): what you can do to them
	local function Actions()
		Clear()
		Option("Chat", Color(110, 110, 110), function() SendAction(npc, "talk") end)
		Option("Give food", Color(150, 130, 80), function() SendAction(npc, "givefood") end)
		Option("Push", Color(170, 70, 60), function() SendAction(npc, "push") CloseDialog() end)
		Option("Back", Color(80, 80, 80), Main)
		Fit()
	end

	function Main()
		Clear()
		Option("Actions  >", Color(110, 110, 110), Actions)
		if canTrade then Option("Trade", colCaps, function() SendAction(npc, "trade") end) end
		for _, q in ipairs(myQuests) do
			if q.ready then
				Option("Done: " .. q.text, Color(100, 180, 100), function() SendAction(npc, "turnin", q.index) end)
			else
				Option("Working on it (" .. q.status .. "): " .. q.text, Color(90, 90, 90), function() end)
			end
		end
		if offer.text then
			Option("Any work?  \"" .. offer.text .. "\"  [" .. offer.reward .. " caps]", Color(120, 150, 200), function() SendAction(npc, "accept") end)
		end
		if recruit.cost then
			Option("Come with me.  " .. (recruit.cost > 0 and ("[" .. recruit.cost .. " caps]") or "[you owe me one]"), Color(110, 170, 140), function() SendAction(npc, "recruit") end)
		end
		Option("Goodbye", Color(80, 80, 80), CloseDialog)
		Fit()
	end
	Main()
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Trade window
local trade

local function ItemRow(parent, d, priceText, priceCol, onClick, tooltip)
	local row = parent:Add("DButton")
	row:Dock(TOP)
	row:SetTall(S(48))
	row:DockMargin(0, 0, 0, S(4))
	row:SetText("")
	row:SetTooltip(tooltip)
	row.Paint = function(self, pw, ph)
		draw.RoundedBox(S(6), 0, 0, pw, ph, self:IsHovered() and colHover or colPanel)
		if d.contaminated then draw.RoundedBox(S(6), 0, 0, pw, ph, Color(150, 20, 20, 60)) end
		draw.SimpleText(d.name .. ((d.count or 1) > 1 and ("  x" .. d.count) or ""), "GFR_Dlg_Small", S(56), ph / 2, colText, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText(priceText, "GFR_Dlg_Small", pw - S(10), ph / 2, priceCol, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end
	row.DoClick = onClick
	if d.model then
		local icon = row:Add("SpawnIcon")
		icon:SetModel(d.model)
		icon:SetSize(S(40), S(40))
		icon:SetPos(S(6), S(4))
		icon:SetMouseInputEnabled(false)
	end
end

net.Receive("GFR_Trade", function()
	local npc = net.ReadEntity()
	local npcCaps = net.ReadUInt(16)
	local stock = net.ReadTable()
	local sell = net.ReadTable()
	local weps = net.ReadTable()
	if !IsValid(npc) then return end
	CloseDialog()
	Fonts()

	local scrollPos = {}
	if IsValid(trade) then
		scrollPos[1] = trade.Left:GetVBar():GetScroll()
		scrollPos[2] = trade.Right:GetVBar():GetScroll()
		trade:Remove()
	end

	local w, h = S(900), S(560)
	trade = vgui.Create("DFrame")
	trade:SetSize(w, h)
	trade:Center()
	trade:SetTitle("")
	trade:ShowCloseButton(false)
	trade:MakePopup()
	trade.Paint = function(self, pw, ph)
		draw.RoundedBox(S(10), 0, 0, pw, ph, colBg)
		draw.SimpleText("THEIR GOODS", "GFR_Dlg_Name", S(20), S(16), colText)
		draw.SimpleText(npcCaps .. " caps", "GFR_Dlg_Small", w / 2 - S(10), S(20), colCaps, TEXT_ALIGN_RIGHT)
		draw.SimpleText("YOUR STUFF", "GFR_Dlg_Name", w / 2 + S(10), S(16), colText)
		draw.SimpleText(LocalPlayer():GetNW2Int("GFR_Caps", 0) .. " caps", "GFR_Dlg_Small", w - S(56), S(20), colCaps, TEXT_ALIGN_RIGHT)
		draw.SimpleText("Click to buy / sell one", "GFR_Dlg_Small", pw / 2, ph - S(18), colDim, TEXT_ALIGN_CENTER)
	end

	local close = trade:Add("DButton")
	close:SetSize(S(30), S(30))
	close:SetPos(w - S(42), S(12))
	close:SetText("✕")
	close:SetFont("GFR_Dlg_Name")
	close:SetTextColor(colDim)
	close.Paint = nil
	close.DoClick = function() trade:Remove() end

	local left = trade:Add("DScrollPanel")
	left:SetPos(S(16), S(56))
	left:SetSize(w / 2 - S(26), h - S(96))
	local right = trade:Add("DScrollPanel")
	right:SetPos(w / 2 + S(10), S(56))
	right:SetSize(w / 2 - S(26), h - S(96))
	trade.Left, trade.Right = left, right

	local myCaps = LocalPlayer():GetNW2Int("GFR_Caps", 0)
	for i, s in ipairs(stock) do
		ItemRow(left, s, s.price .. " caps", myCaps >= s.price and colCaps or Color(200, 80, 70), function() SendAction(npc, "buy", i) end, "Buy " .. s.name)
	end
	if #stock == 0 then
		local l = left:Add("DLabel") l:Dock(TOP) l:SetFont("GFR_Dlg_Text") l:SetTextColor(colDim) l:SetText("  They have nothing left to trade.")
	end
	for _, wd in ipairs(weps) do
		ItemRow(right, wd, "+" .. wd.price, colCaps, function() SendAction(npc, "sellwep", 0, wd.class) end, "Sell " .. wd.name)
	end
	for i, e in ipairs(sell) do
		ItemRow(right, e, e.price > 0 and ("+" .. e.price) or "won't buy", e.price > 0 and colCaps or colDim, function() SendAction(npc, "sell", i) end, "Sell " .. e.name)
	end

	timer.Simple(0, function()
		if !IsValid(left) then return end
		if scrollPos[1] then left:GetVBar():SetScroll(scrollPos[1]) end
		if scrollPos[2] then right:GetVBar():SetScroll(scrollPos[2]) end
	end)
end)

-- Walk away or the person dies: close the windows
hook.Add("Think", "GFR_Dialog_AutoClose", function()
	local ply = LocalPlayer()
	if !IsValid(ply) then return end
	for _, pnl in ipairs({dialog, trade}) do
		if IsValid(pnl) && !ply:Alive() then pnl:Remove() end
	end
	if IsValid(dialog) && (!IsValid(dialog.NPC) or dialog.NPC:GetPos():DistToSqr(ply:GetPos()) > 260 * 260) then dialog:Remove() end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Quest tracker + markers
local quests = {}
net.Receive("GFR_Quests", function() quests = net.ReadTable() end)

hook.Add("HUDPaint", "GFR_Quests_Draw", function()
	local ply = LocalPlayer()
	if !IsValid(ply) or !ply:Alive() or #quests == 0 then return end
	local x, y = ScrW() - S(24), S(24)
	draw.SimpleTextOutlined("QUESTS", "GFR_Dlg_Small", x, y, colDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 160))
	y = y + S(22)
	for i, q in ipairs(quests) do
		local col = q.ready and Color(120, 210, 120) or colText
		local text = q.text
		if #text > 70 then text = string.sub(text, 1, 67) .. "..." end
		draw.SimpleTextOutlined(text, "GFR_Dlg_Small", x, y, col, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 160))
		draw.SimpleTextOutlined(q.ready and "Return to the " .. q.faction or q.status, "GFR_Dlg_Small", x, y + S(17), q.ready and col or colDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 160))
		y = y + S(42)

		if q.marker then
			local sp = q.marker:ToScreen()
			if sp.visible then
				local dist = math.Round(ply:GetPos():Distance(q.marker) * 0.019) -- units -> metres
				draw.RoundedBox(S(4), sp.x - S(5), sp.y - S(5), S(10), S(10), col)
				draw.SimpleTextOutlined(i .. "  " .. dist .. "m", "GFR_Dlg_Small", sp.x, sp.y - S(10), col, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, 180))
			end
		end
	end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- What people say (subtitles)
local subs = {}
net.Receive("GFR_Say", function()
	table.insert(subs, 1, {name = net.ReadString(), text = net.ReadString(), time = CurTime()})
	if #subs > 3 then subs[4] = nil end
end)

hook.Add("HUDPaint", "GFR_Say_Draw", function()
	local now = CurTime()
	local y = ScrH() * 0.82
	for i = #subs, 1, -1 do
		local s = subs[i]
		local age = now - s.time
		if age > 5 then
			table.remove(subs, i)
		else
			local a = math.Clamp(math.min(age * 5, (5 - age) * 1.5), 0, 1) * 255
			local text = s.name .. ": " .. s.text
			surface.SetFont("GFR_Say")
			local tw, th = surface.GetTextSize(text)
			local yy = y - (i - 1) * (th + S(8))
			draw.RoundedBox(S(4), ScrW() / 2 - tw / 2 - S(10), yy - S(4), tw + S(20), th + S(8), Color(0, 0, 0, 150 * a / 255))
			draw.SimpleText(text, "GFR_Say", ScrW() / 2, yy, Color(240, 230, 210, a), TEXT_ALIGN_CENTER)
		end
	end
end)

-- Caps text for the dialog header and inventory
function GFR_Caps_Text()
	return LocalPlayer():GetNW2Int("GFR_Caps", 0) .. " caps"
end
