--[[
	Custom Apocalypse - base building UI: storage window, sleep menu, look-at prompts
	Server side: sv_base.lua
]]
local function S(x) return math.Round(x * ScrH() / 1080) end

local colBg = Color(16, 16, 19, 248)
local colPanel = Color(255, 255, 255, 10)
local colSlot = Color(255, 255, 255, 22)
local colSlotEmpty = Color(255, 255, 255, 7)
local colSlotHover = Color(255, 255, 255, 42)
local colText = Color(232, 232, 232)
local colDim = Color(150, 150, 150)
local colAccent = Color(215, 175, 90)
local colBlood = Color(160, 20, 20, 90)

local catColor = {
	food = Color(215, 135, 55), drink = Color(70, 170, 225), medical = Color(205, 70, 70), ammo = Color(200, 185, 110),
	armor = Color(70, 130, 210), misc = Color(150, 150, 150), material = Color(160, 140, 110), deployable = Color(130, 110, 170)
}

local function Fonts()
	surface.CreateFont("GFR_Base_Title", {font = "Roboto", size = S(26), weight = 800, extended = true})
	surface.CreateFont("GFR_Base_Text", {font = "Roboto", size = S(17), weight = 600, extended = true})
	surface.CreateFont("GFR_Base_Tiny", {font = "Roboto", size = S(13), weight = 600, extended = true})
	surface.CreateFont("GFR_Base_Small", {font = "Roboto", size = S(15), weight = 700, extended = true})
end
Fonts()
hook.Add("OnScreenSizeChanged", "GFR_Base_Fonts", Fonts)

local function CleanName(class)
	local rounds = string.match(class, "^ammo:(.+)$")
	if rounds then return GFR.AmmoGroups && GFR.AmmoGroups[rounds] or rounds end
	if GFR.CustomItems && GFR.CustomItems[class] then return GFR.CustomItems[class].name end
	-- A gun carried in the bag
	local wtab = weapons.Get(class)
	if wtab then
		local pn = wtab.PrintName or class
		if ARC9 && ARC9.GetPhrase && isstring(pn) then pn = ARC9:GetPhrase(pn) or pn end
		return pn
	end
	local stored = scripted_ents.GetStored(class)
	local name = stored && stored.t.PrintName or class
	name = string.gsub(name, "%s*%(%+*%d+%a*P%)", "")
	return string.match(name, "^.-%s%-%s(.+)$") or name
end

local function ShortName(name, font, maxW)
	surface.SetFont(font)
	if surface.GetTextSize(name) <= maxW then return name end
	while #name > 3 && surface.GetTextSize(name .. "...") > maxW do name = string.sub(name, 1, -2) end
	return name .. "..."
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Storage window: your inventory on the left, the box on the right. Click a stack to move it across.
local storeFrame, storeEnt, storeItems = nil, nil, {}

local function FillGrid(grid, items, slots, onClick)
	grid:Clear()
	local size = S(96)
	for i = 1, math.max(slots, #items) do
		local e = items[i]
		local slot = grid:Add("DButton")
		slot:SetSize(size, size)
		slot:SetText("")
		if !e then
			slot:SetMouseInputEnabled(false)
			slot.Paint = function(self, w, h)
				draw.RoundedBox(S(8), 0, 0, w, h, colSlotEmpty)
				surface.SetDrawColor(255, 255, 255, 14)
				surface.DrawOutlinedRect(0, 0, w, h, 1)
			end
			continue
		end
		local col = catColor[e.cat] or catColor.misc
		local name = CleanName(e.class)
		slot:SetTooltip(name .. "  (" .. e.count .. ")")
		slot.Paint = function(self, w, h)
			draw.RoundedBox(S(8), 0, 0, w, h, self:IsHovered() and colSlotHover or colSlot)
			draw.RoundedBox(0, S(8), 0, w - S(16), S(4), col)
		end
		slot.PaintOver = function(self, w, h)
			if e.contaminated then draw.RoundedBox(S(8), 0, 0, w, h, colBlood) end
			draw.SimpleTextOutlined(ShortName(name, "GFR_Base_Tiny", w - S(8)), "GFR_Base_Tiny", w / 2, h - S(5), colText, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, 220))
			if (e.stack or 1) > 1 then
				draw.SimpleTextOutlined(e.count .. "/" .. e.stack, "GFR_Base_Small", w - S(5), S(6), colText, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 220))
			end
		end
		local icon = slot:Add("SpawnIcon")
		icon:SetModel(e.model or "models/props_junk/cardboard_box004a.mdl")
		icon:SetSize(size - S(30), size - S(30))
		icon:SetPos(S(15), S(8))
		icon:SetMouseInputEnabled(false)
		slot.DoClick = function() onClick(i) end
	end
end

local function SendStorageAction(action, index)
	if !IsValid(storeEnt) then return end
	net.Start("GFR_StorageAction")
	net.WriteEntity(storeEnt)
	net.WriteString(action)
	net.WriteUInt(index, 8)
	net.SendToServer()
end

local function RefreshStorage()
	if !IsValid(storeFrame) then return end
	local inv = GFR.InvData or {}
	FillGrid(storeFrame.Left, inv, GFR.InvCap or #inv, function(i) SendStorageAction("put", i) end)
	FillGrid(storeFrame.Right, storeItems, storeEnt:GetNW2Int("GFR_StorageSlots", 0), function(i) SendStorageAction("take", i) end)
	storeFrame.RightCount = #storeItems .. " / " .. storeEnt:GetNW2Int("GFR_StorageSlots", 0) .. " slots"
end

local function Column(parent, title, getSub)
	local col = parent:Add("DPanel")
	col:Dock(LEFT)
	col:DockMargin(0, 0, S(14), 0)
	col:SetWide(S(560))
	col.Paint = function(self, w, h)
		draw.RoundedBox(S(8), 0, 0, w, h, colPanel)
		draw.SimpleText(title, "GFR_Base_Text", S(14), S(12), colAccent)
		local sub = getSub()
		if sub then draw.SimpleText(sub, "GFR_Base_Small", w - S(14), S(14), colDim, TEXT_ALIGN_RIGHT) end
	end
	local scroll = col:Add("DScrollPanel")
	scroll:Dock(FILL)
	scroll:DockMargin(S(12), S(42), S(12), S(12))
	local grid = scroll:Add("DIconLayout")
	grid:Dock(FILL)
	grid:SetSpaceX(S(8))
	grid:SetSpaceY(S(8))
	return grid
end

local function OpenStorage(ent)
	if IsValid(storeFrame) then storeFrame:Remove() end
	storeEnt = ent
	local f = vgui.Create("DFrame")
	storeFrame = f
	f:SetSize(S(1180), S(640))
	f:Center()
	f:SetTitle("")
	f:ShowCloseButton(false)
	f:MakePopup()
	f:DockPadding(S(20), S(64), S(20), S(20))
	local name = ent:GetNW2String("GFR_BaseName", "Storage")
	f.Paint = function(self, w, h)
		draw.RoundedBox(S(10), 0, 0, w, h, colBg)
		draw.SimpleText(string.upper(name), "GFR_Base_Title", S(22), S(18), colText)
		draw.SimpleText("Click a stack to move it   ·   Tab / E / Esc to close", "GFR_Base_Small", w - S(22), S(26), colDim, TEXT_ALIGN_RIGHT)
	end
	f.Think = function(self)
		if !IsValid(storeEnt) or !LocalPlayer():Alive() or LocalPlayer():EyePos():DistToSqr(storeEnt:WorldSpaceCenter()) > 200 * 200 then self:Remove() end
	end
	f.OnKeyCodePressed = function(self, key)
		if key == KEY_E or key == KEY_TAB or key == KEY_ESCAPE then self:Remove() end
	end
	f.Left = Column(f, "YOUR INVENTORY", function() return #(GFR.InvData or {}) .. " / " .. (GFR.InvCap or 0) .. " slots" end)
	f.Right = Column(f, string.upper(name), function() return f.RightCount end)
	RefreshStorage()
end

net.Receive("GFR_Storage", function()
	local ent = net.ReadEntity()
	local open = net.ReadBool()
	storeItems = net.ReadTable()
	if open then
		OpenStorage(ent)
	elseif IsValid(storeFrame) && storeEnt == ent then
		RefreshStorage()
	end
end)

hook.Add("GFR_InventoryChanged", "GFR_Base_Storage", function()
	if IsValid(storeFrame) then RefreshStorage() end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Sleep menu (only when gfr_timeskip is on: sv_base.lua): sleep until 08:00 or 18:00. You lie down and wait until
-- enough of the living players want the same hour.
local CHOICES = {8, 18} -- (the same as GFR.SkipChoices on the server)
-- (replicated from the server's: the client has to create them too to read them)
local cvSkip = CreateConVar("gfr_timeskip", "0", bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED), "Sleeping in a bed can skip time (to 08:00 or 18:00, by vote)")
CreateConVar("gfr_timeskip_pct", "75", bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED), "% of living players who must choose the same hour to skip to it")
local choiceNames = {[8] = "Until morning (08:00)", [18] = "Until evening (18:00)"}

local function HoursUntil(target)
	local d = (target - GFR.Hour()) % 24
	if d < 0.1 then d = d + 24 end
	return math.Round(d)
end

local function OpenSleep(bed)
	local f = vgui.Create("DFrame")
	f:SetSize(S(460), S(250))
	f:Center()
	f:SetTitle("")
	f:ShowCloseButton(false)
	f:MakePopup()
	f:DockPadding(S(20), S(96), S(20), S(20))
	local quality = bed:GetNW2Int("GFR_Bed")
	f.Paint = function(self, w, h)
		draw.RoundedBox(S(10), 0, 0, w, h, colBg)
		draw.SimpleText("SLEEP", "GFR_Base_Title", S(22), S(16), colText)
		local now = GFR.Hour()
		draw.SimpleText(string.format("Day %d   %02d:%02d", GFR.Day(), math.floor(now), math.floor((now % 1) * 60)), "GFR_Base_Small", w - S(22), S(24), colDim, TEXT_ALIGN_RIGHT)
		draw.SimpleText(quality >= 2 and "Bed: good rest, heals well" or "Sleeping mat: some rest", "GFR_Base_Small", S(22), S(46), colAccent)
		if !game.SinglePlayer() then
			local pct = GetConVar("gfr_timeskip_pct")
			draw.SimpleText((pct and pct:GetInt() or 75) .. "% of living players must pick the same time", "GFR_Base_Small", S(22), S(66), colDim)
		end
	end
	f.Think = function(self)
		if !IsValid(bed) or !LocalPlayer():Alive() then self:Remove() end
	end
	f.OnKeyCodePressed = function(self, key)
		if key == KEY_E or key == KEY_ESCAPE then self:Remove() end
	end
	for i, hour in ipairs(CHOICES) do
		local b = f:Add("DButton")
		b:Dock(TOP)
		b:DockMargin(0, 0, 0, S(8))
		b:SetTall(S(46))
		b:SetText("")
		b.Paint = function(self, w, h)
			draw.RoundedBox(S(6), 0, 0, w, h, self:IsHovered() and Color(160, 140, 110, 170) or Color(255, 255, 255, 16))
			draw.SimpleText(choiceNames[hour], "GFR_Base_Text", S(14), h / 2, colText, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText(HoursUntil(hour) .. " h", "GFR_Base_Small", w - S(14), h / 2, colDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
		b.DoClick = function()
			net.Start("GFR_Sleep")
			net.WriteEntity(bed)
			net.WriteUInt(i, 2)
			net.SendToServer()
			f:Remove()
		end
	end
end

net.Receive("GFR_SleepMenu", function()
	local bed = net.ReadEntity()
	if IsValid(bed) then OpenSleep(bed) end
end)

-- Lying in bed waiting for the others: dark screen, who wants what
hook.Add("HUDPaint", "GFR_Base_SleepWait", function()
	local ply = LocalPlayer()
	local v = IsValid(ply) && ply:GetNW2Int("GFR_SleepVote", 0) or 0
	if v <= 0 then return end
	surface.SetDrawColor(0, 0, 0, 245)
	surface.DrawRect(0, 0, ScrW(), ScrH())
	local voters = math.max(GetGlobal2Int("GFR_SleepVoters", 1), 1)
	local cx, cy = ScrW() / 2, ScrH() / 2
	draw.SimpleText("Sleeping " .. string.lower(choiceNames[CHOICES[v]] or ""), "GFR_Base_Title", cx, cy - S(40), colText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	for i, hour in ipairs(CHOICES) do
		draw.SimpleText(string.format("%02d:00   %d / %d", hour, GetGlobal2Int("GFR_SleepVotes" .. i, 0), voters), "GFR_Base_Text",
			cx, cy + S(i * 26 - 10), i == v and colAccent or colDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	draw.SimpleText("Waiting for the others...   [JUMP] get up", "GFR_Base_Small", cx, cy + S(90), colDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Look-at prompts
hook.Add("HUDPaint", "GFR_Base_Prompt", function()
	local ply = LocalPlayer()
	if !IsValid(ply) or !ply:Alive() or IsValid(storeFrame) or ply:GetNW2Bool("GFR_IsZombie") then return end
	local tr = ply:GetEyeTrace()
	local ent = tr.Entity
	if !IsValid(ent) or tr.HitPos:DistToSqr(ply:EyePos()) > 130 * 130 then return end
	local name = ent:GetNW2String("GFR_BaseName", "")
	if name == "" then return end
	local action
	if ent:GetNW2Int("GFR_StorageSlots", 0) > 0 then action = "[E] Open"
	elseif ent:GetNW2Int("GFR_Bed", 0) > 0 then action = cvSkip:GetBool() and "[E] Sleep" or "[E] Rest" end
	local text = name .. (action and ("   " .. action) or "") .. "   [Crouch+E] Pick up"
	draw.SimpleTextOutlined(text, "GFR_Base_Small", ScrW() / 2, ScrH() / 2 + S(40), Color(225, 210, 170), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 180))
	-- Whose it is (cl_access.lua)
	local owner = GFR.OwnerPrompt && GFR.OwnerPrompt(ent)
	if owner then
		draw.SimpleTextOutlined(owner, "GFR_Base_Small", ScrW() / 2, ScrH() / 2 + S(60), colDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 180))
	end
end)
