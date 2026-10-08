--[[
	Custom Apocalypse - Inventory screen (replaces the scoreboard; Tab toggles it)
	Left:   your condition (health, armor, hunger, thirst, stamina, infection), your character holding what you have
	        out (drag to turn it), and what you wear (bag, armor).
	Middle: weapon slots - primary, secondary, melee, throwable (sh_equipment.lua; click = draw, right click = drop),
	        the belt (medical tools and other slotless gear), and the item grid (15 slots + bag).
	        Left click selects an item, double click uses it, right click opens Use/Eat/Drink/Drop options.
	        Category filters dim the other items instead of hiding them, so slots never move around.
	Right:  details of the selected item.
	Server side: sv_inventory.lua, sv_weapons.lua
]]
local inventory = {}
local capacity = 15
local frame
function GFR.InventoryOpen() return IsValid(frame) end -- (the clock only shows while it's open: cl_daynight.lua)
local selectedKey
local filter = "all"

local catInfo = {
	food       = {name = "Food",      action = "Eat",   color = Color(215, 135, 55)},
	drink      = {name = "Drink",     action = "Drink", color = Color(70, 170, 225)},
	medical    = {name = "Medical",   action = "Use",   color = Color(205, 70, 70)},
	ammo       = {name = "Ammo",      action = "Load",  color = Color(200, 185, 110)},
	armor      = {name = "Armor",     action = "Equip", color = Color(70, 130, 210)},
	misc       = {name = "Misc",      action = "Use",   color = Color(150, 150, 150)},
	material   = {name = "Materials",                   color = Color(160, 140, 110)},
	junk       = {name = "Junk",      action = "Scrap", color = Color(125, 115, 95)},
	weapon     = {name = "Weapons",   action = "Equip", color = Color(185, 95, 75)},
	deployable = {name = "Kits",      action = "Place", color = Color(130, 110, 170)}
}
local filters = {"all", "weapon", "food", "drink", "medical", "ammo", "armor", "material", "junk", "deployable", "misc"}

local colBg = Color(16, 16, 19, 248)
local colPanel = Color(255, 255, 255, 10)
local colSlot = Color(255, 255, 255, 22)
local colSlotEmpty = Color(255, 255, 255, 7)
local colSlotHover = Color(255, 255, 255, 42)
local colText = Color(232, 232, 232)
local colDim = Color(150, 150, 150)
local colCaps = Color(225, 190, 90)
local colBlood = Color(160, 20, 20, 90)
local colActive = Color(235, 200, 70)

local function S(x) return math.Round(x * ScrH() / 1080) end

local function MakeFonts()
	surface.CreateFont("GFR_Inv_Title", {font = "Roboto", size = S(28), weight = 800, extended = true})
	surface.CreateFont("GFR_Inv_Name", {font = "Roboto", size = S(22), weight = 700, extended = true})
	surface.CreateFont("GFR_Inv_Text", {font = "Roboto", size = S(17), weight = 500, extended = true})
	surface.CreateFont("GFR_Inv_Small", {font = "Roboto", size = S(15), weight = 700, extended = true})
	surface.CreateFont("GFR_Inv_Tiny", {font = "Roboto", size = S(13), weight = 600, extended = true})
	surface.CreateFont("GFR_Inv_Head", {font = "Roboto", size = S(14), weight = 800, extended = true})
end
MakeFonts()

local function CleanName(class)
	if GFR.CustomItems && GFR.CustomItems[class] then return GFR.CustomItems[class].name end
	-- Your loose rounds of one caliber ("ammo:<type>", sv_inventory.lua)
	local rounds = string.match(class, "^ammo:(.+)$")
	if rounds then return GFR.AmmoGroups && GFR.AmmoGroups[rounds] or rounds end
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

local function HealText(class)
	local stored = scripted_ents.GetStored(class)
	local hp = stored && string.match(stored.t.PrintName or "", "(%d+)HP")
	return hp and ("Heals " .. hp .. " HP") or nil
end

-- Slots are entries; the index is the identity (two stacks of the same item are different slots)
local function SendAction(action, index)
	net.Start("GFR_InvAction")
	net.WriteString(action)
	net.WriteUInt(index, 8)
	net.SendToServer()
end

local function SendWeaponAction(action, wep)
	net.Start("GFR_WepAction")
	net.WriteString(action)
	net.WriteEntity(wep)
	net.SendToServer()
end

local function OpenOptions(index)
	local e = inventory[index]
	if !e then return end
	local info = catInfo[e.cat] or catInfo.misc
	local menu = DermaMenu()
	if info.action then
		menu:AddOption(info.action, function() SendAction("use", index) end):SetIcon("icon16/arrow_right.png")
	end
	menu:AddOption("Drop one", function() SendAction("drop", index) end):SetIcon("icon16/arrow_down.png")
	if e.count > 1 then
		menu:AddOption("Drop stack (" .. e.count .. ")", function() SendAction("dropall", index) end):SetIcon("icon16/basket_remove.png")
	end
	menu:Open()
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Weapons
local function WeaponSlotOf(wep)
	local s = wep:GetNW2String("GFR_WSlot", "")
	if s != "" then return s end
	return GFR.WeaponSlot && GFR.WeaponSlot(wep:GetClass())
end

local function IsFists(wep)
	return GFR.IsFists && GFR.IsFists(wep:GetClass()) or wep:GetClass() == "weapon_fists"
end

local function WorldModelOf(wep)
	local mdl = wep.GetWeaponWorldModel && wep:GetWeaponWorldModel() or wep.WorldModel
	if !mdl or mdl == "" or !util.IsValidModel(mdl) then return end
	return mdl
end

local function WeaponName(wep)
	return wep.GetPrintName && wep:GetPrintName() or wep:GetClass()
end

local function AmmoText(wep)
	local ply = LocalPlayer()
	local ammoType = wep:GetPrimaryAmmoType()
	local clip = wep:Clip1()
	local reserve = ammoType >= 0 and ply:GetAmmoCount(ammoType) or 0
	if clip >= 0 && wep:GetMaxClip1() > 0 then return clip .. " / " .. reserve end
	if ammoType >= 0 then return "x" .. reserve end
end

local function WeaponMenu(wep)
	local menu = DermaMenu()
	menu:AddOption("Draw", function() SendWeaponAction("select", wep) end):SetIcon("icon16/arrow_right.png")
	if !IsFists(wep) && WeaponSlotOf(wep) then
		menu:AddOption("Put in bag", function() SendWeaponAction("stash", wep) end):SetIcon("icon16/basket_put.png")
	end
	if !IsFists(wep) then
		menu:AddOption("Drop", function() SendWeaponAction("drop", wep) end):SetIcon("icon16/arrow_down.png")
	end
	menu:Open()
end

-- The spawn menu's picture for a weapon / item class (cl_crafting.lua), or nil. Your loose rounds ("ammo:<type>")
-- show ARC9's ammo box pictures (sh_ammo.lua)
local function MenuIcon(class)
	if !class or !GFR.SpawnMenuIcon then return end
	local rounds = string.match(class, "^ammo:(.+)$")
	if rounds then
		local r = GFR.AmmoRuleByType && GFR.AmmoRuleByType[rounds]
		if !r then return end
		if r.arc9Icon then return GFR.SpawnMenuIcon(r.arc9Icon) end
		for _, c in ipairs(r.pickupIcons or {}) do
			local m = GFR.SpawnMenuIcon(c)
			if m then return m end
		end
		return
	end
	return GFR.SpawnMenuIcon(class)
end

-- An item's picture: the spawn menu's when it has one, otherwise its model
local function ItemIcon(parent, class, mdl, size, x, y)
	local mat = MenuIcon(class)
	local icon
	if mat then
		icon = parent:Add("DImage")
		icon:SetMaterial(mat)
	else
		icon = parent:Add("SpawnIcon")
		icon:SetModel(mdl or "models/props_junk/cardboard_box004a.mdl")
	end
	icon:SetSize(size, size)
	if x then icon:SetPos(x, y) end
	icon:SetMouseInputEnabled(false)
	return icon
end

-- One big slot per weapon slot; follows what you carry live (no resync needed)
local function WeaponSlotPanel(parent, def)
	local p = parent:Add("DButton")
	p:SetText("")
	local icon = p:Add("SpawnIcon")
	icon:SetMouseInputEnabled(false)
	icon:SetVisible(false)
	local img = p:Add("DImage") -- (the spawn menu's picture, when the gun has one)
	img:SetMouseInputEnabled(false)
	img:SetVisible(false)
	p.PerformLayout = function(self, w, h)
		local size = math.min(h - S(48), w - S(20))
		icon:SetSize(size, size)
		icon:SetPos((w - size) / 2, S(22))
		img:SetSize(size, size)
		img:SetPos((w - size) / 2, S(22))
	end
	p.Think = function(self)
		local wep
		for _, w in ipairs(LocalPlayer():GetWeapons()) do
			if WeaponSlotOf(w) == def.id then wep = w break end
		end
		self.Wep = wep
		local class = IsValid(wep) and wep:GetClass() or nil
		local mdl = IsValid(wep) and WorldModelOf(wep) or nil
		if class != self.Class or mdl != self.Mdl then
			self.Class = class
			local mat = MenuIcon(class)
			img:SetVisible(mat != nil)
			if mat then img:SetMaterial(mat) end
			self.Mdl = mdl or (mat and "" or nil) -- (a picture counts: no name in the middle)
			icon:SetVisible(!mat && mdl != nil)
			if !mat && mdl then icon:SetModel(mdl) end
		end
		if IsValid(wep) then self:SetTooltip(WeaponName(wep)) else self:SetTooltip(false) end
	end
	p.Paint = function(self, w, h)
		local wep = self.Wep
		local active = IsValid(wep) && LocalPlayer():GetActiveWeapon() == wep
		draw.RoundedBox(S(8), 0, 0, w, h, IsValid(wep) and (self:IsHovered() and colSlotHover or colSlot) or colSlotEmpty)
		if active then
			surface.SetDrawColor(colActive)
			surface.DrawOutlinedRect(0, 0, w, h, 2)
		else
			surface.SetDrawColor(255, 255, 255, 16)
			surface.DrawOutlinedRect(0, 0, w, h, 1)
		end
		draw.SimpleText(string.upper(def.name), "GFR_Inv_Head", S(10), S(6), active and colActive or colDim)
	end
	p.PaintOver = function(self, w, h)
		local wep = self.Wep
		if !IsValid(wep) then
			draw.SimpleText("empty", "GFR_Inv_Small", w / 2, h / 2, Color(255, 255, 255, 40), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			return
		end
		if !self.Mdl then
			draw.SimpleText(WeaponName(wep), "GFR_Inv_Small", w / 2, h / 2, colText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		local ammo = AmmoText(wep)
		if ammo then draw.SimpleTextOutlined(ammo, "GFR_Inv_Small", w - S(8), S(6), colCaps, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 200)) end
		surface.SetFont("GFR_Inv_Tiny")
		local name = WeaponName(wep)
		while #name > 3 && surface.GetTextSize(name) > w - S(12) do name = string.sub(name, 1, -2) end
		draw.SimpleTextOutlined(name, "GFR_Inv_Tiny", w / 2, h - S(6), colText, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, 220))
	end
	p.DoClick = function(self) if IsValid(self.Wep) then SendWeaponAction("select", self.Wep) end end
	p.DoRightClick = function(self) if IsValid(self.Wep) then WeaponMenu(self.Wep) end end
	return p
end

-- The belt: weapons that don't take a slot (EFT medical tools, Sandbox tools...), fists first
local function BeltWeapons()
	local list = {}
	for _, w in ipairs(LocalPlayer():GetWeapons()) do
		if !WeaponSlotOf(w) then list[#list + 1] = w end
	end
	table.sort(list, function(a, b)
		if IsFists(a) != IsFists(b) then return IsFists(a) end
		return a:GetClass() < b:GetClass()
	end)
	return list
end

local function BuildBelt(belt)
	belt:Clear()
	local size = belt:GetTall() - S(12)
	for _, wep in ipairs(BeltWeapons()) do
		local b = belt:Add("DButton")
		b:SetSize(size * 1.3, size)
		b:SetText("")
		b:SetTooltip(WeaponName(wep))
		local mdl = WorldModelOf(wep) or (MenuIcon(wep:GetClass()) and "")
		if mdl then
			ItemIcon(b, wep:GetClass(), mdl != "" and mdl or nil, size - S(14), (size * 1.3 - (size - S(14))) / 2, S(2))
		end
		b.Paint = function(self, w, h)
			local active = IsValid(wep) && LocalPlayer():GetActiveWeapon() == wep
			draw.RoundedBox(S(6), 0, 0, w, h, self:IsHovered() and colSlotHover or colSlot)
			if active then
				surface.SetDrawColor(colActive)
				surface.DrawOutlinedRect(0, 0, w, h, 2)
			end
		end
		b.PaintOver = function(self, w, h)
			if !IsValid(wep) then return end
			local ammo = AmmoText(wep)
			if ammo then draw.SimpleTextOutlined(ammo, "GFR_Inv_Tiny", w - S(4), S(3), colCaps, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 200)) end
			if !mdl then
				surface.SetFont("GFR_Inv_Tiny")
				local name = WeaponName(wep)
				while #name > 3 && surface.GetTextSize(name) > w - S(6) do name = string.sub(name, 1, -2) end
				draw.SimpleText(name, "GFR_Inv_Tiny", w / 2, h / 2, colText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
		end
		b.DoClick = function() if IsValid(wep) then SendWeaponAction("select", wep) end end
		b.DoRightClick = function() if IsValid(wep) then WeaponMenu(wep) end end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Your character, holding whatever you have out
local holdSeq = {
	pistol = "idle_pistol", revolver = "idle_revolver", smg = "idle_smg1", ar2 = "idle_ar2", rpg = "idle_rpg", shotgun = "idle_shotgun",
	crossbow = "idle_crossbow", melee = "idle_melee", melee2 = "idle_melee2", knife = "idle_knife", grenade = "idle_grenade",
	fist = "idle_fist", physgun = "idle_physgun", camera = "idle_camera", slam = "idle_slam", duel = "idle_dual", passive = "idle_passive"
}

local function CharacterPanel(parent)
	local ply = LocalPlayer()
	local mp = parent:Add("DModelPanel")
	mp:SetModel(ply:GetModel())
	mp:SetFOV(28)
	mp:SetCamPos(Vector(125, 0, 44))
	mp:SetLookAt(Vector(0, 0, 37))
	mp.Yaw = 25
	mp.Seq = nil

	local function Dress(self)
		local ent = self.Entity
		if !IsValid(ent) then return end
		ent:SetSkin(ply:GetSkin())
		for i = 0, ply:GetNumBodyGroups() - 1 do ent:SetBodygroup(i, ply:GetBodygroup(i)) end
		ent.GetPlayerColor = function() return IsValid(ply) && ply:GetPlayerColor() or Vector(1, 1, 1) end
		self.Model = ply:GetModel()
		self.Seq = nil
	end
	Dress(mp)

	mp.OnMousePressed = function(self) self.Dragging, self.LastX = true, gui.MouseX() end
	mp.OnMouseReleased = function(self) self.Dragging = false end
	mp.LayoutEntity = function(self, ent)
		if !IsValid(ply) then return end
		if self.Model != ply:GetModel() then
			self:SetModel(ply:GetModel())
			Dress(self)
			ent = self.Entity
		end
		if self.Dragging then
			if !input.IsMouseDown(MOUSE_LEFT) then self.Dragging = false end
			self.Yaw = self.Yaw + (gui.MouseX() - self.LastX) * 0.6
			self.LastX = gui.MouseX()
		end
		ent:SetAngles(Angle(0, self.Yaw, 0))

		-- Stance and the weapon in hand follow what you have out
		local wep = ply:GetActiveWeapon()
		local hold = IsValid(wep) && wep.GetHoldType && wep:GetHoldType() or "normal"
		local seqName = holdSeq[hold] or "idle_all_01"
		if self.Seq != seqName then
			local seq = ent:LookupSequence(seqName)
			if seq < 0 then seq = ent:LookupSequence("idle_all_01") end
			if seq >= 0 then ent:ResetSequence(seq) end
			self.Seq = seqName
		end
		self:RunAnimation()

		local mdl = IsValid(wep) && !IsFists(wep) and WorldModelOf(wep) or nil
		if mdl != self.WepMdl then
			if IsValid(self.WepEnt) then self.WepEnt:Remove() end
			self.WepMdl = mdl
			if mdl then
				local w = ClientsideModel(mdl, RENDERGROUP_OPAQUE)
				if IsValid(w) then
					w:SetNoDraw(true)
					w:SetParent(ent)
					w:AddEffects(EF_BONEMERGE)
					self.WepEnt = w
				end
			end
		end
		if IsValid(self.WepEnt) && self.WepEnt:GetParent() != ent then self.WepEnt:SetParent(ent) end
	end
	mp.PostDrawModel = function(self) if IsValid(self.WepEnt) then self.WepEnt:DrawModel() end end
	mp.OnRemove = function(self) if IsValid(self.WepEnt) then self.WepEnt:Remove() end end
	return mp
end

-- Condition bars
local function StatBars(ply)
	local inf = ply:GetNW2Float("GFR_Infection", 0)
	local bars = {
		{"HEALTH", ply:Health(), ply:GetMaxHealth(), Color(200, 55, 50)},
		{"ARMOR", ply:Armor(), ply:GetMaxArmor(), Color(70, 130, 210)},
		{"HUNGER", ply:GetNW2Float("GFR_Hunger", 100), 100, Color(215, 135, 55)},
		{"THIRST", ply:GetNW2Float("GFR_Thirst", 100), 100, Color(70, 170, 225)},
		{"STAMINA", ply:GetNW2Float("GFR_Stamina", 100), 100, Color(110, 190, 90)}
	}
	if inf > 0 then bars[#bars + 1] = {"INFECTION", inf * 100, 100, Color(150, 60, 160)} end
	return bars
end

---------------------------------------------------------------------------------------------------------------------------------------------
local Rebuild

local function BuildDetails(parent)
	parent:Clear()
	local e = selectedKey && inventory[selectedKey]
	if !e then
		local lbl = parent:Add("DLabel")
		lbl:Dock(FILL)
		lbl:SetContentAlignment(5)
		lbl:SetFont("GFR_Inv_Text")
		lbl:SetTextColor(colDim)
		lbl:SetText("Select an item")
		return
	end
	local info = catInfo[e.cat] or catInfo.misc

	local iconSize = S(140)
	local icon = ItemIcon(parent, e.class, e.model, iconSize)
	icon:Dock(TOP)
	local side = math.max((parent:GetWide() - iconSize) / 2, 0)
	icon:DockMargin(side, S(16), side, S(10))
	icon:SetMouseInputEnabled(false)

	local name = parent:Add("DLabel")
	name:Dock(TOP)
	name:SetFont("GFR_Inv_Name")
	name:SetTextColor(colText)
	name:SetText(CleanName(e.class))
	name:SetContentAlignment(5)
	name:SetTall(S(30))

	local cat = parent:Add("DLabel")
	cat:Dock(TOP)
	cat:SetFont("GFR_Inv_Small")
	cat:SetTextColor(info.color)
	cat:SetText(string.upper(info.name) .. "     " .. e.count .. " / " .. (e.stack or 1) .. " in this slot")
	cat:SetContentAlignment(5)
	cat:SetTall(S(22))

	local lines = {}
	local heal = HealText(e.class)
	if heal then lines[#lines + 1] = heal end
	if e.desc && e.desc != "" then lines[#lines + 1] = e.desc end
	-- Which of your guns these rounds / this ammo fits
	local roundsType = e.rounds && string.match(e.class, "^ammo:(.+)$")
	if roundsType then
		local fits = {}
		for _, wep in ipairs(LocalPlayer():GetWeapons()) do
			local am = GFR.WeaponAmmo(wep:GetClass())
			if am && string.lower(am) == string.lower(roundsType) then fits[#fits + 1] = wep:GetPrintName() end
		end
		lines[#lines + 1] = #fits > 0 and ("Fits your: " .. table.concat(fits, ", ")) or "None of your guns use these"
	elseif GFR.AmmoItems && GFR.AmmoItems[e.class] then
		local fits = {}
		for _, wep in ipairs(LocalPlayer():GetWeapons()) do
			if GFR.AmmoFits(e.class, wep:GetClass()) then fits[#fits + 1] = wep:GetPrintName() end
		end
		lines[#lines + 1] = #fits > 0 and ("Fits your: " .. table.concat(fits, ", ")) or "None of your guns use this"
	end
	local desc = parent:Add("DLabel")
	desc:Dock(TOP)
	desc:DockMargin(S(20), S(14), S(20), 0)
	desc:SetFont("GFR_Inv_Text")
	desc:SetTextColor(e.contaminated and Color(235, 125, 115) or colText)
	desc:SetText(table.concat(lines, "\n"))
	desc:SetWrap(true)
	desc:SetAutoStretchVertical(true)

	local buttons = parent:Add("DPanel")
	buttons:Dock(BOTTOM)
	buttons:SetTall(S(46))
	buttons:DockMargin(S(16), 0, S(16), S(16))
	buttons.Paint = nil
	local index = selectedKey
	-- Guns in the bag can be scrapped here too (no trip to the crafting menu); junk's own action is scrapping
	local scrapGun = e.cat == "weapon" && weapons.Get(e.class) != nil && !string.StartWith(e.class, "weapon_eft_") && !(GFR.IsFists && GFR.IsFists(e.class))
	local action = !e.rounds and info.action or nil -- (loose rounds: nothing to do but drop them - guns load them themselves)
	local count = (action and 1 or 0) + 1 + (scrapGun and 1 or 0)
	local bw = (parent:GetWide() - S(32) - S(10) * (count - 1)) / count
	local function Btn(text, col, fn)
		local b = buttons:Add("DButton")
		b:Dock(LEFT)
		b:SetWide(bw)
		b:DockMargin(0, 0, S(10), 0)
		b:SetText(text)
		b:SetFont("GFR_Inv_Small")
		b:SetTextColor(colText)
		b.Paint = function(self, w, h)
			draw.RoundedBox(S(6), 0, 0, w, h, self:IsHovered() and Color(col.r, col.g, col.b, 170) or Color(col.r, col.g, col.b, 95))
		end
		b.DoClick = fn
		return b
	end
	-- Scrapping can't be undone: hold the button for a second (it fills up) - a stray click does nothing
	local HOLD = 1
	local function HoldBtn(text, col, fn)
		local b = Btn(text, col, function() end)
		b:SetText("")
		b.OnMousePressed = function(self, code) if code == MOUSE_LEFT then self.holdFrom = RealTime() self:MouseCapture(true) end end
		b.OnMouseReleased = function(self) self.holdFrom = nil self:MouseCapture(false) end
		b.Think = function(self)
			if self.holdFrom && !input.IsMouseDown(MOUSE_LEFT) then self.holdFrom = nil end
			if self.holdFrom && RealTime() - self.holdFrom >= HOLD then
				self.holdFrom = nil
				self:MouseCapture(false)
				surface.PlaySound("physics/metal/metal_box_impact_soft2.wav")
				fn()
			end
		end
		b.Paint = function(self, w, h)
			draw.RoundedBox(S(6), 0, 0, w, h, self:IsHovered() and Color(col.r, col.g, col.b, 140) or Color(col.r, col.g, col.b, 80))
			local f = self.holdFrom && math.Clamp((RealTime() - self.holdFrom) / HOLD, 0, 1) or 0
			if f > 0 then draw.RoundedBox(S(6), 0, 0, w * f, h, Color(col.r, col.g, col.b, 230)) end
			draw.SimpleText(text, "GFR_Inv_Small", w / 2, h / 2, colText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		return b
	end
	if action == "Scrap" then
		HoldBtn("Scrap", info.color, function() SendAction("use", index) end)
	elseif action then
		Btn(action, info.color, function() SendAction("use", index) end)
	end
	if scrapGun then HoldBtn("Scrap", Color(125, 115, 95), function() SendAction("scrap", index) end) end
	Btn("Drop", Color(120, 120, 120), function() SendAction("drop", index) end)
end

local function ShortName(name, font, maxW)
	surface.SetFont(font)
	if surface.GetTextSize(name) <= maxW then return name end
	while #name > 3 && surface.GetTextSize(name .. "...") > maxW do name = string.sub(name, 1, -2) end
	return name .. "..."
end

Rebuild = function()
	if !IsValid(frame) then return end
	local grid, details = frame.Grid, frame.Details
	grid:Clear()
	if selectedKey && !inventory[selectedKey] then selectedKey = nil end

	local size = frame.SlotSize
	for i = 1, math.max(capacity, #inventory) do
		local e = inventory[i]
		local slot = grid:Add("DButton")
		slot:SetSize(size, size)
		slot:SetText("")

		if !e then
			-- Empty slot
			slot:SetMouseInputEnabled(false)
			slot.Paint = function(self, w, h)
				draw.RoundedBox(S(8), 0, 0, w, h, colSlotEmpty)
				surface.SetDrawColor(255, 255, 255, 14)
				surface.DrawOutlinedRect(0, 0, w, h, 1)
			end
			continue
		end

		local info = catInfo[e.cat] or catInfo.misc
		local match = filter == "all" or e.cat == filter
		local name = CleanName(e.class)
		slot:SetTooltip(name)
		slot.Paint = function(self, w, h)
			local sel = selectedKey == i
			draw.RoundedBox(S(8), 0, 0, w, h, (sel or self:IsHovered()) and colSlotHover or colSlot)
			draw.RoundedBox(0, S(8), 0, w - S(16), S(4), info.color)
			if sel then
				surface.SetDrawColor(info.color)
				surface.DrawOutlinedRect(0, 0, w, h, 2)
			end
		end
		slot.PaintOver = function(self, w, h)
			if e.contaminated then draw.RoundedBox(S(8), 0, 0, w, h, colBlood) end
			draw.SimpleTextOutlined(ShortName(name, "GFR_Inv_Tiny", w - S(10)), "GFR_Inv_Tiny", w / 2, h - S(5), colText, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, 220))
			if (e.stack or 1) > 1 then
				draw.SimpleTextOutlined(e.count .. "/" .. e.stack, "GFR_Inv_Small", w - S(6), S(7), e.count >= e.stack and colCaps or colText, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 220))
			end
			if !match then draw.RoundedBox(S(8), 0, 0, w, h, Color(10, 10, 12, 200)) end
		end
		ItemIcon(slot, e.class, e.model, size - S(30), S(15), S(8))

		slot.DoClick = function()
			if selectedKey == i && slot.LastClick && SysTime() - slot.LastClick < 0.35 then
				SendAction("use", i)
			end
			slot.LastClick = SysTime()
			selectedKey = i
			BuildDetails(details)
		end
		slot.DoRightClick = function()
			selectedKey = i
			BuildDetails(details)
			OpenOptions(i)
		end
	end

	BuildDetails(details)
end

local function CloseInventory()
	if IsValid(frame) then frame:Remove() end
end

local function OpenInventory()
	if IsValid(frame) then return end
	MakeFonts()
	local ply = LocalPlayer()
	local w, h = math.min(S(1560), ScrW() - S(40)), math.min(S(840), ScrH() - S(40))
	local pad = S(24)
	local leftW = math.min(S(380), math.floor(w * 0.25))
	local detailsW = math.min(S(320), math.floor(w * 0.21))
	local centerX = pad + leftW + pad
	local centerW = w - leftW - detailsW - pad * 4
	local top = S(68)

	frame = vgui.Create("DFrame")
	frame:SetSize(w, h)
	frame:Center()
	frame:SetTitle("")
	frame:ShowCloseButton(false)
	frame:SetDraggable(false)
	frame:MakePopup()
	frame:SetKeyboardInputEnabled(false) -- Tab still reaches the game to close it

	local weaponsY = top
	local weaponsH = S(132)
	local beltY = weaponsY + S(22) + weaponsH + S(14)
	local beltH = S(66)
	local tabsY = beltY + S(22) + beltH + S(14)
	local gridY = tabsY + S(42)

	frame.Paint = function(self, pw, ph)
		draw.RoundedBox(S(12), 0, 0, pw, ph, colBg)
		draw.SimpleText("INVENTORY", "GFR_Inv_Title", pad, S(18), colText)
		draw.SimpleText(LocalPlayer():GetNW2Int("GFR_Caps", 0) .. " caps", "GFR_Inv_Small", pad + S(176), S(28), colCaps)

		draw.SimpleText("WEAPONS", "GFR_Inv_Head", centerX, weaponsY, colDim)
		draw.SimpleText("BELT", "GFR_Inv_Head", centerX, beltY, colDim)
		draw.SimpleText("click to draw  -  right click: put in bag / drop", "GFR_Inv_Tiny", centerX + centerW, weaponsY + S(1), Color(255, 255, 255, 60), TEXT_ALIGN_RIGHT)

		-- Slots used
		local used = #inventory
		local bag = LocalPlayer():GetNW2String("GFR_Bag", "")
		local full = used >= capacity
		local bw = S(240)
		local bx, by = pw - S(56) - bw, S(18)
		draw.SimpleText(used .. " / " .. capacity .. " slots" .. (bag != "" and ("   " .. bag) or "   no bag"), "GFR_Inv_Small", bx + bw, by, full and Color(215, 80, 70) or colDim, TEXT_ALIGN_RIGHT)
		draw.RoundedBox(S(3), bx, by + S(24), bw, S(6), Color(255, 255, 255, 18))
		draw.RoundedBox(S(3), bx, by + S(24), bw * math.Clamp(used / math.max(capacity, 1), 0, 1), S(6), full and Color(215, 80, 70) or Color(190, 190, 190))
	end

	local close = frame:Add("DButton")
	close:SetSize(S(34), S(34))
	close:SetPos(w - S(46), S(16))
	close:SetText("✕")
	close:SetFont("GFR_Inv_Name")
	close:SetTextColor(colDim)
	close.Paint = nil
	close.DoClick = CloseInventory

	-- Switch to the crafting window (cl_crafting.lua)
	local craft = frame:Add("DButton")
	craft:SetSize(S(140), S(34))
	craft:SetPos(w - S(56) - S(240) - S(160), S(16))
	craft:SetText("CRAFTING  >")
	craft:SetFont("GFR_Inv_Small")
	craft:SetTextColor(colText)
	craft.Paint = function(self, pw, ph)
		draw.RoundedBox(S(6), 0, 0, pw, ph, self:IsHovered() and Color(160, 140, 110, 170) or Color(160, 140, 110, 80))
	end
	craft.DoClick = function()
		CloseInventory()
		if GFR.OpenCrafting then GFR.OpenCrafting() end
	end

	-------------------------------------------------------------------------------------------------------------------------------------
	-- Left: condition, character, what you wear
	local left = frame:Add("DPanel")
	left:SetPos(pad, top)
	left:SetSize(leftW, h - top - pad)
	local barH, barGap = S(10), S(30)
	local barsTop = S(14)
	left.Paint = function(self, pw, ph)
		draw.RoundedBox(S(8), 0, 0, pw, ph, colPanel)
		local y = barsTop
		for _, b in ipairs(StatBars(LocalPlayer())) do
			local frac = math.Clamp(b[2] / math.max(b[3], 1), 0, 1)
			draw.SimpleText(b[1], "GFR_Inv_Head", S(16), y, colDim)
			draw.SimpleText(math.Round(b[2]) .. (b[1] == "INFECTION" and "%" or ""), "GFR_Inv_Small", pw - S(16), y - S(1), colText, TEXT_ALIGN_RIGHT)
			draw.RoundedBox(S(4), S(16), y + S(16), pw - S(32), barH, Color(255, 255, 255, 16))
			draw.RoundedBox(S(4), S(16), y + S(16), math.max((pw - S(32)) * frac, frac > 0 and S(6) or 0), barH, b[4])
			y = y + barGap + S(4)
		end
	end
	local barsH = barsTop + 6 * (barGap + S(4))

	local equipH = S(92)
	local char = CharacterPanel(left)
	char:SetPos(0, barsH)
	char:SetSize(leftW, left:GetTall() - barsH - equipH - S(8))

	-- Worn gear: bag and armor
	local equip = left:Add("DPanel")
	equip:SetPos(S(12), left:GetTall() - equipH - S(8))
	equip:SetSize(leftW - S(24), equipH)
	equip.Paint = nil
	local function WornSlot(label, getText, getModel)
		local p = equip:Add("DPanel")
		p:Dock(LEFT)
		p:SetWide((leftW - S(24) - S(10)) / 2)
		p:DockMargin(0, 0, S(10), 0)
		local icon = p:Add("SpawnIcon")
		icon:SetSize(equipH - S(26), equipH - S(26))
		icon:SetPos(S(6), S(20))
		icon:SetMouseInputEnabled(false)
		icon:SetVisible(false) -- (shown once there's something worn: an empty one drew a broken-picture box)
		p.Think = function(self)
			local mdl = getModel()
			if mdl != self.Mdl then
				self.Mdl = mdl
				icon:SetVisible(mdl != nil)
				if mdl then icon:SetModel(mdl) end
			end
		end
		p.Paint = function(self, pw, ph)
			draw.RoundedBox(S(8), 0, 0, pw, ph, self.Mdl and colSlot or colSlotEmpty)
			draw.SimpleText(label, "GFR_Inv_Head", S(8), S(4), colDim)
			draw.SimpleText(getText(), "GFR_Inv_Small", self.Mdl and (equipH - S(12)) or S(8), ph / 2 + S(8), self.Mdl and colText or Color(255, 255, 255, 50), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end
	WornSlot("BACKPACK", function()
		local bag = LocalPlayer():GetNW2String("GFR_Bag", "")
		return bag != "" and bag or "none"
	end, function()
		local bag = LocalPlayer():GetNW2String("GFR_Bag", "")
		if bag == "" then return end
		local def = GFR.CustomItems && GFR.CustomItems[string.find(string.lower(bag), "backpack", 1, true) and "gfr_item_backpack" or "gfr_item_satchel"]
		return def && def.model
	end)
	WornSlot("ARMOR", function()
		local a = LocalPlayer():Armor()
		return a > 0 and (a .. " armor") or "none"
	end, function()
		return LocalPlayer():Armor() > 0 and "models/items/battery.mdl" or nil
	end)

	-------------------------------------------------------------------------------------------------------------------------------------
	-- Middle: weapon slots, belt, items
	local weapons = frame:Add("DPanel")
	weapons:SetPos(centerX, weaponsY + S(22))
	weapons:SetSize(centerW, weaponsH)
	weapons.Paint = nil
	local slotW = (centerW - S(10) * (#GFR.WeaponSlots - 1)) / #GFR.WeaponSlots
	for i, def in ipairs(GFR.WeaponSlots) do
		local p = WeaponSlotPanel(weapons, def)
		p:SetPos((i - 1) * (slotW + S(10)), 0)
		p:SetSize(slotW, weaponsH)
	end

	local belt = frame:Add("DIconLayout")
	belt:SetPos(centerX, beltY + S(22))
	belt:SetSize(centerW, beltH)
	belt:SetSpaceX(S(8))
	belt.Think = function(self)
		local key = ""
		for _, wep in ipairs(BeltWeapons()) do key = key .. wep:EntIndex() .. "," end
		if key != self.Key then
			self.Key = key
			BuildBelt(self)
		end
	end

	-- Category filter
	local tabs = frame:Add("DPanel")
	tabs:SetPos(centerX, tabsY)
	tabs:SetSize(centerW, S(30))
	tabs.Paint = nil
	for _, f in ipairs(filters) do
		local b = tabs:Add("DButton")
		b:Dock(LEFT)
		b:DockMargin(0, 0, S(5), 0)
		b:SetText(f == "all" and "All" or catInfo[f].name)
		b:SetFont("GFR_Inv_Tiny")
		b:SizeToContentsX(S(16))
		b:SetTextColor(colText)
		b.Paint = function(self, pw, ph)
			local active = filter == f
			local col = f == "all" and Color(200, 200, 200) or catInfo[f].color
			draw.RoundedBox(S(5), 0, 0, pw, ph, active and Color(col.r, col.g, col.b, 120) or (self:IsHovered() and colSlotHover or colSlot))
		end
		b.DoClick = function()
			filter = f
			Rebuild()
		end
	end

	-- Slot grid
	local scroll = frame:Add("DScrollPanel")
	scroll:SetPos(centerX, gridY)
	scroll:SetSize(centerW, h - gridY - pad)
	scroll.Paint = function(self, pw, ph) draw.RoundedBox(S(8), 0, 0, pw, ph, colPanel) end
	local grid = scroll:Add("DIconLayout")
	grid:Dock(FILL)
	grid:DockMargin(S(10), S(10), S(10), S(10))
	grid:SetSpaceX(S(8))
	grid:SetSpaceY(S(8))
	frame.Grid = grid
	-- As many columns as fit, slots sized to fill the row
	local inner = centerW - S(20) - S(14)
	local cols = math.max(math.floor((inner + S(8)) / (S(96) + S(8))), 1)
	frame.SlotSize = math.floor((inner - S(8) * (cols - 1)) / cols)

	-------------------------------------------------------------------------------------------------------------------------------------
	-- Right: details
	local details = frame:Add("DPanel")
	details:SetPos(w - detailsW - pad, top)
	details:SetSize(detailsW, h - top - pad)
	details.Paint = function(self, pw, ph) draw.RoundedBox(S(8), 0, 0, pw, ph, colPanel) end
	frame.Details = details

	Rebuild()
end

net.Receive("GFR_InvSync", function()
	inventory = net.ReadTable()
	capacity = net.ReadUInt(8)
	GFR.InvData = inventory
	GFR.InvCap = capacity
	Rebuild()
	hook.Run("GFR_InventoryChanged")
end)

GFR.OpenInventory = OpenInventory
GFR.CloseInventory = CloseInventory

-- Using a consumable you hold (sv_consumables.lua): out of the menu so you can watch it
net.Receive("GFR_InvClose", CloseInventory)

-- Tab = inventory instead of the scoreboard (closes the crafting window too)
-- The dead don't rummage through pockets: no inventory while you control your zombie (sv_extract.lua)
local function IsZombified()
	local ply = LocalPlayer()
	return IsValid(ply) && ply:GetNW2Bool("GFR_IsZombie")
end

hook.Add("Think", "GFR_Inventory_ZombieClose", function()
	if !IsZombified() then return end
	if IsValid(frame) then CloseInventory() end
	if GFR.CraftingOpen && GFR.CraftingOpen() then GFR.CloseCrafting() end
end)

hook.Add("ScoreboardShow", "GFR_Inventory", function()
	if IsZombified() then return true end
	if GFR.CraftingOpen && GFR.CraftingOpen() then
		GFR.CloseCrafting()
	elseif IsValid(frame) then
		CloseInventory()
	else
		OpenInventory()
	end
	return true
end)
hook.Add("ScoreboardHide", "GFR_Inventory", function()
	return true
end)

hook.Add("Think", "GFR_Inventory_CloseOnDeath", function()
	if IsValid(frame) && (!IsValid(LocalPlayer()) or !LocalPlayer():Alive()) then CloseInventory() end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Quick melee on the noclip key (V): a gun that can bash (ARC9) bashes with ARC9's own melee; anything else, your
-- melee weapon (fists if there's none) comes out, swings once, and you're back on what you held.
-- Shift + V is still noclip (testing), as is "noclip" in the console. gfr_quickmelee 0: V is noclip again.
local cvQuickMelee = CreateClientConVar("gfr_quickmelee", "1", true, false, "V does a quick melee instead of noclip (Shift+V still noclips)")
local qm -- {prev, melee, stage, t}

local function MeleeWeapon(ply)
	local fists
	for _, w in ipairs(ply:GetWeapons()) do
		if WeaponSlotOf(w) == "melee" then return w end
		if IsFists(w) then fists = w end
	end
	return fists
end

local function QuickMelee(ply)
	if qm then return end
	local wep = ply:GetActiveWeapon()
	-- ARC9's own bash (predicted, its animation): a short press of its melee key
	-- (not while aiming down sights: ARC9 won't bash then, so the melee weapon comes out instead)
	if IsValid(wep) && wep.ARC9 && wep.GetProcessedValue && wep:GetProcessedValue("Bash", true) && ARC9
		&& !(wep.GetInSights && wep:GetInSights()) then
		ARC9.KeyPressed_Melee = true
		timer.Simple(0.1, function() if ARC9 then ARC9.KeyPressed_Melee = false end end)
		return
	end
	local melee = MeleeWeapon(ply)
	if !IsValid(melee) then return end
	if melee == wep then
		qm = {melee = melee, stage = "swing", t = CurTime(), swingAt = CurTime()}
		return
	end
	qm = {prev = IsValid(wep) and wep or nil, melee = melee, stage = "draw", t = CurTime()}
	input.SelectWeapon(melee)
end

hook.Add("PlayerBindPress", "GFR_QuickMelee", function(ply, bind, pressed)
	if !pressed or !cvQuickMelee:GetBool() or !string.find(bind, "noclip", 1, true) then return end
	if input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT) then return end -- (Shift+V: noclip)
	if !ply:Alive() or ply:GetNW2Bool("GFR_IsZombie") or ply:InVehicle() then return end
	QuickMelee(ply)
	return true
end)

-- The swing itself: once the melee weapon is out, attack for a moment, then switch back
hook.Add("CreateMove", "GFR_QuickMelee", function(cmd)
	if !qm then return end
	local ply = LocalPlayer()
	local now = CurTime()
	if !IsValid(qm.melee) or !ply:Alive() or now - qm.t > 4 then qm = nil return end
	if qm.stage == "draw" then
		if ply:GetActiveWeapon() == qm.melee then
			qm.outAt = qm.outAt or now
			if now - qm.outAt >= 0.3 then qm.stage, qm.swingAt = "swing", now end -- (done drawing)
		end
	elseif qm.stage == "swing" then
		cmd:AddKey(IN_ATTACK)
		if now - qm.swingAt >= 0.1 then qm.stage, qm.backAt = "back", now + 0.7 end
	elseif qm.stage == "back" && now >= qm.backAt then
		if IsValid(qm.prev) then input.SelectWeapon(qm.prev) end
		qm = nil
	end
end)
