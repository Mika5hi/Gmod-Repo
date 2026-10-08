--[[
	Custom Apocalypse - crafting window (opened from the inventory, Tab closes it)
	Laid out in panels:
		far left   category strip (icons; hover for the name)
		left       recipe list, grouped under collapsible sub-headers; pinned (starred) recipes on top;
		           sort / search / "can craft now" at the bottom. Shift+click a row crafts one, right click for more.
		middle     ITEM TO CRAFT (badge, name, what it does) beside CRAFTING MATERIALS (have / need),
		           quantity slider, the [E] CRAFT bar, and your materials as tiles underneath
		right      ITEM PREVIEW: the model, drag to rotate, scroll to zoom
	Header: which station you're at (hands / workbench / fire) and whether nearby storage is counted.
	Pins are kept between sessions (data/greenflu/craft_pins.txt).
	"Hand-loading" (sh_attachments.lua) is grouped by part type; "Dismantle" strips guns you carry.
	Also: barricade/workbench labels when you look at them.
	Server side: sv_crafting.lua
]]
-- Kept on GFR so a Lua refresh doesn't forget it; the window also asks the server again whenever it opens
GFR.CraftKnown = GFR.CraftKnown or {}
local known = GFR.CraftKnown
local frame
local selected      -- recipe id
local selectedWep   -- weapon class (Dismantle tab)
local catFilter = "All"
local search = ""
local onlyCraftable = false
local sortMode = 1 -- 1 craftable first, 2 name
local qty = 1
local collapsed = {} -- [cat .. "/" .. sub] = true
local previewYaw, previewZoom = 30, 1

local cats = {"All", "Pinned", "Medical", "Survival", "Ammo", "Hand-loading", "Weapons", "Armor", "Building", "Materials", "Salvage", "Dismantle"}
local catColors = {
	All = Color(200, 200, 200), Pinned = Color(240, 200, 70),
	Medical = Color(205, 75, 70), Survival = Color(120, 170, 90), Ammo = Color(205, 180, 90), ["Hand-loading"] = Color(220, 140, 60),
	Weapons = Color(150, 160, 180), Armor = Color(80, 135, 210), Building = Color(150, 115, 185), Materials = Color(170, 145, 105),
	Salvage = Color(140, 120, 95), Dismantle = Color(180, 90, 70)
}
local catIcons = {
	All = "icon16/application_view_tile.png", Pinned = "icon16/star.png", Medical = "icon16/heart.png", Survival = "icon16/cup.png",
	Ammo = "icon16/box.png", ["Hand-loading"] = "icon16/cog.png", Weapons = "icon16/bomb.png", Armor = "icon16/shield.png",
	Building = "icon16/house.png", Materials = "icon16/brick.png", Salvage = "icon16/arrow_refresh.png", Dismantle = "icon16/cut.png"
}
local iconMats = {}
local function IconMat(path)
	iconMats[path] = iconMats[path] or Material(path, "smooth mips")
	return iconMats[path]
end

-- Sub-headers inside a category (by recipe id); anything not listed goes under the category's last group
local subGroups = {
	Medical = {
		{"Bandages & splints", {bandage = true, tourniquet = true, alusplint = true}},
		{"Medkits", {medkit = true, carkit = true, afak = true, surgical = true}},
		{"Drugs & injectors", nil}
	},
	Ammo = {
		{"Bulk & explosive", {ammo_pistol_bulk = true, ammo_40mm = true}},
		{"Rounds", nil}
	},
	Weapons = {
		{"Melee", {crowbar = true, machete = true, kukri = true, knife = true, shovel = true, shield = true}},
		{"Throwables", {grenade = true, molotov = true, pipebomb = true, thermite = true}},
		{"Firearms", nil}
	},
	Armor = {
		{"Head", {helmet = true}},
		{"Body", nil}
	},
	Building = {
		{"Turrets", {turret_light = true, turret_heavy = true}},
		{"Defenses", {claim = true, barricade_wood = true, wall_wood = true, barricade_metal = true, fence = true, barricade_planks = true,
			fence_planks = true, barbed = true, bars = true, fence_tall = true, dumpster = true, steelwall = true}},
		{"Stations", {workbench = true, gunbench = true, burnbarrel = true}},
		{"Storage", {crate = true, locker = true}},
		{"Camp", nil}
	},
	Survival = {
		{"Bags", {satchel = true, backpack = true}},
		{"Cooking", {cook_zmeat = true, cook_zmeat3 = true}},
		{"Tools & tricks", nil}
	}
}

-- A line or two on what each thing is for
local blurbs = {
	bandage = "Strips of clean cloth. Stops bleeding.",
	medkit = "Bandages, alcohol and chemicals in a kit. Heals and stops bleeding.",
	tourniquet = "Clamps a bleeding limb. Stops bleeding fast.",
	alusplint = "Sets a broken limb.",
	antibiotics = "Slows the infection for about 10 minutes.",
	carkit = "A full first aid kit. Heals well and stops bleeding.",
	afak = "Military first aid kit. Several uses.",
	surgical = "Fixes the worst wounds.",
	antidote = "Pushes the infection back.",
	adrenaline = "A burst of stamina.",
	pills = "Takes the edge off pain.",
	inoculator = "Slows the infection.",
	tape = "Holds everything together.",
	gunpowder = "Mixed from chemicals. Goes into ammo and bombs.",
	molotov = "Sets an area on fire. Zombies burn.",
	pipebomb = "Loud and deadly. Draws every zombie nearby.",
	thermite = "Burns through anything it sticks to.",
	shield = "Blocks hits from the front.",
	crossbow = "Silent. Bolts can be picked back up.",
	vest = "Scrap plates sewn into cloth. Some protection.",
	helmet = "Better than nothing.",
	heavyarmor = "Heavy plates. Real protection, slows you down.",
	satchel = "Wear it for +5 inventory slots.",
	backpack = "Wear it for +10 inventory slots.",
	flare = "Lights the night. Fired straight up at open sky, it calls a supply drop.",
	cook_zmeat = "Cooked, it won't make you sick... probably.",
	cook_zmeat3 = "Three at once over the fire.",
	camo = "Smear yourself in gore: zombies take longer to notice you.",
	zextract = "Inject someone and they turn. Inject yourself and you become one.",
	workbench = "Unlocks bench recipes.",
	gunbench = "Customize your guns here: stand next to it and press C. Every attachment is available.",
	burnbarrel = "A fire to cook over and keep warm.",
	crate = "12 slots of storage. Crafting pulls from storage nearby.",
	locker = "24 slots of storage. Crafting pulls from storage nearby.",
	sleepbag = "Rest here to shake off tiredness. You respawn here.",
	bed = "A proper bed: rest here to shake off tiredness (heals more than a mat when sleeping skips time). You respawn here.",
	lamp = "Light for your camp.",
	barricade_planks = "A cheap plank barricade on trestles. Repair with wood.",
	fence_planks = "A long run of wooden fence: closes a gap in one piece.",
	barbed = "Low wire: zombies pushing into it get cut up (and wear it down). Doesn't hurt you.",
	bars = "Heavy steel bars, about as tall as a doorway.",
	fence_tall = "Tall chain-link panel. Hard to get over, harder to get through.",
	dumpster = "A dumpster dragged into place. Blocks a lane on its own.",
	steelwall = "A slab of steel door. The toughest wall you can build.",
	claim = "Claims the area around it as your base: no zombies, groups or loot spawn within its radius (about 30 m). You see the edge as a green ring. Things can still walk in from outside, so build walls. Up to 2.",
	turret_light = "Shoots zombies and hostiles in a 120 degree arc in front of it (aim it when placing). Holds 250 pistol / SMG rounds: E loads it from your ammo. Loud: draws the dead.",
	turret_heavy = "Sentinel minigun: covers all the way round (the gun swings wide, the tripod turns for anything behind it) and shreds it at long range. Holds 400 rifle rounds (5.45 / 5.56 / 7.62) and goes through them fast. Very loud."
}
local catBlurbs = {
	Building = "You choose where it goes after crafting.",
	Salvage = "Breaks things down into materials.",
	Ammo = "Goes into your inventory as ammo.",
	["Hand-loading"] = "Cartridge part: goes in your attachment stash. Fit it to a gun at a Gun Table (C)."
}

net.Receive("GFR_RecipesKnown", function()
	local new, changed = {}, false
	for _, id in ipairs(net.ReadTable()) do
		new[id] = true
		if !known[id] then changed = true end
	end
	for id in pairs(known) do if !new[id] then changed = true end end
	known = new
	GFR.CraftKnown = known
	if changed && IsValid(frame) then frame:Rebuild() end -- only redraw if something was learned
end)

local function S(x) return math.Round(x * ScrH() / 1080) end
local function Fonts()
	surface.CreateFont("GFR_Craft_Title", {font = "Roboto", size = S(30), weight = 900, extended = true})
	surface.CreateFont("GFR_Craft_Big", {font = "Roboto", size = S(26), weight = 800, extended = true})
	surface.CreateFont("GFR_Craft_Name", {font = "Roboto", size = S(20), weight = 700, extended = true})
	surface.CreateFont("GFR_Craft_Card", {font = "Roboto", size = S(16), weight = 700, extended = true})
	surface.CreateFont("GFR_Craft_Text", {font = "Roboto", size = S(16), weight = 500, extended = true})
	surface.CreateFont("GFR_Craft_Small", {font = "Roboto", size = S(14), weight = 700, extended = true})
	surface.CreateFont("GFR_Craft_Chip", {font = "Roboto", size = S(13), weight = 600, extended = true})
	surface.CreateFont("GFR_Craft_Head", {font = "Roboto", size = S(13), weight = 900, extended = true})
	surface.CreateFont("GFR_Craft_Star", {font = "Roboto", size = S(18), weight = 700, extended = true})
end
Fonts()

local colBg = Color(16, 16, 18, 248)
local colPanel = Color(255, 255, 255, 8)
local colPanel2 = Color(0, 0, 0, 90)
local colStripe = Color(255, 255, 255, 14)
local colCard = Color(255, 255, 255, 10)
local colHover = Color(255, 255, 255, 26)
local colText = Color(232, 232, 232)
local colDim = Color(145, 145, 145)
local colFaint = Color(255, 255, 255, 45)
local colGood = Color(120, 205, 120)
local colBad = Color(220, 95, 85)
local colWarn = Color(220, 175, 80)
local colAccent = Color(175, 150, 110)
local colStar = Color(240, 200, 70)

local function Alpha(c, a) return Color(c.r, c.g, c.b, a) end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Pins (favorites), kept on disk
local PIN_FILE = "greenflu/craft_pins.txt"
local pins = {}
do
	local raw = file.Read(PIN_FILE, "DATA")
	local t = raw && util.JSONToTable(raw)
	if istable(t) then for _, id in ipairs(t) do pins[id] = true end end
end
local function SavePins()
	local list = {}
	for id in pairs(pins) do list[#list + 1] = id end
	file.CreateDir("greenflu")
	file.Write(PIN_FILE, util.TableToJSON(list))
end
local function TogglePin(id)
	pins[id] = !pins[id] or nil
	SavePins()
	if IsValid(frame) then frame:Rebuild() end
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- What you have / can make
-- Materials in your storage crates/lockers close by count too (sv_crafting.lua sends them)
local nearby, nearbyCount = {}, 0
local nearbyKey = ""
net.Receive("GFR_CraftNearby", function()
	local count = net.ReadUInt(8)
	local tbl = net.ReadTable()
	local key = count .. util.TableToJSON(tbl)
	if key == nearbyKey then return end -- nothing changed: don't redraw (keeps your scroll position)
	nearbyKey, nearbyCount, nearby = key, count, tbl
	if IsValid(frame) then frame:Rebuild() end
end)

local function Have(class)
	local n = 0
	for _, e in ipairs(GFR.InvData or {}) do
		if GFR.InGroup(class, e.class) && !e.contaminated && e.cat != "weapon" then n = n + e.count end
	end
	for c, count in pairs(nearby) do
		if GFR.InGroup(class, c) then n = n + count end
	end
	return n
end

local function IsKnown(r) return known[r.id] or r.always or r.known end

local function PlaceOK(r)
	if r.fire && !GFR.NearFire(LocalPlayer()) then return false end
	return !r.bench or GFR.NearWorkbench(LocalPlayer())
end

local function HasInputs(r)
	for class, need in pairs(r.inputs) do
		if Have(class) < need then return false end
	end
	return true
end

local function CanCraft(r) return IsKnown(r) && HasInputs(r) && PlaceOK(r) end

-- How many you could make in one go
local function MaxCraft(r)
	if !CanCraft(r) then return 0 end
	local m = 25
	for class, need in pairs(r.inputs) do m = math.min(m, math.floor(Have(class) / need)) end
	if r.weapon then
		local w = weapons.Get(r.weapon)
		local consumable = w && (w.Disposable or w.BottomlessClip or (w.Primary && (w.Primary.ClipSize or 0) <= 0 && (w.ClipSize or 0) <= 0))
		if !consumable then m = math.min(m, 1) end
	end
	return math.max(m, 0)
end

-- 3 = craftable, 2 = known but short (or wrong place), 1 = unknown
local function State(r)
	if !IsKnown(r) then return 1 end
	return CanCraft(r) and 3 or 2
end

local function ItemModel(class)
	local custom = GFR.CustomItems[class]
	if custom then return custom.model end
	local stored = class && scripted_ents.GetStored(class)
	if stored then return stored.t.WorldModel or stored.t.Model end
	local w = class && weapons.Get(class)
	return w && w.WorldModel
end

local function RecipeModel(r)
	if r.weapon then
		local w = weapons.Get(r.weapon)
		return w && w.WorldModel
	end
	if r.att then
		local t = ARC9 && ARC9.GetAttTable(r.att)
		return t && t.Model or "models/items/arc9/att_plastic_box.mdl"
	end
	return ItemModel(r.out or (r.outs && next(r.outs)))
end

-- A material's model: the item itself, or the first member of a group ("@bandage")
local function InputModel(class)
	local g = GFR.ItemGroups && GFR.ItemGroups[class]
	if g && g.classes then
		for c in pairs(g.classes) do
			local m = ItemModel(c)
			if m then return m end
		end
	end
	return ItemModel(class)
end

local function ShortItem(class)
	local name = GFR.ItemDisplayName(class)
	name = string.gsub(name, "%s*%(any%)", "")
	name = string.gsub(name, "%s*%b()", "")
	return name
end

local function Send(action, arg)
	net.Start("GFR_Craft")
	net.WriteString(action)
	net.WriteString(arg)
	net.SendToServer()
end

local function CraftN(r, n)
	if !r then return end
	if n <= 1 then Send("craft", r.id) else Send("craftn", r.id .. "|" .. n) end
	surface.PlaySound("ui/buttonclick.wav")
end

local function StationText()
	local ply = LocalPlayer()
	local bench, fire = GFR.NearWorkbench(ply), GFR.NearFire(ply)
	if bench && fire then return "Workbench + Fire" end
	if bench then return "Workbench" end
	if fire then return "Burn Barrel" end
	return "Hands"
end

-- Hand-loading parts grouped by what they are
local handGroups = {
	{"Cartridges", function(s) return !string.find(s, "_case_", 1, true) && !string.find(s, "_projectile_", 1, true) && !string.find(s, "_load_", 1, true) end},
	{"Cases", function(s) return string.find(s, "_case_", 1, true) end},
	{"Bullet cores", function(s) return string.find(s, "_projectile_main_", 1, true) end},
	{"Fillings (tracer / incendiary / HE)", function(s) return string.find(s, "_projectile_intern_", 1, true) end},
	{"Powder loads", function(s) return string.find(s, "_load_", 1, true) end},
	{"Tips, jackets & shot", function(s) return string.find(s, "_projectile_", 1, true) end}
}

-- Which sub-header a recipe goes under: index (for ordering) and name
local function SubGroup(r)
	if r.att then
		for i, g in ipairs(handGroups) do
			if g[2](r.att) then return i, g[1] end
		end
		return #handGroups + 1, "Other parts"
	end
	local groups = subGroups[r.cat]
	if !groups then return 1, nil end
	for i, g in ipairs(groups) do
		if !g[2] or g[2][r.id] then return i, g[1] end
	end
	return #groups, groups[#groups][1]
end

---------------------------------------------------------------------------------------------------------------------------------------------
local function WrapLines(text, font, maxW, maxLines)
	surface.SetFont(font)
	local lines = {}
	for para in string.gmatch(text .. "\n", "(.-)\n") do
		local line = ""
		for word in string.gmatch(para, "%S+") do
			local try = line == "" and word or (line .. " " .. word)
			if surface.GetTextSize(try) <= maxW then
				line = try
			else
				if line != "" then lines[#lines + 1] = line end
				line = word
			end
		end
		lines[#lines + 1] = line
	end
	if maxLines && #lines > maxLines then
		lines = {unpack(lines, 1, maxLines)}
		local last = lines[maxLines]
		while #last > 3 && surface.GetTextSize(last .. "...") > maxW do last = string.sub(last, 1, -2) end
		lines[maxLines] = last .. "..."
	end
	return lines
end

-- A titled box like the reference: a darker strip with the title, then the body
local function PanelBox(parent, title, x, y, w, h, icon)
	local p = parent:Add("DPanel")
	p:SetPos(x, y)
	p:SetSize(w, h)
	p.Title = title
	p.Paint = function(self, pw, ph)
		draw.RoundedBox(S(6), 0, 0, pw, ph, colPanel2)
		surface.SetDrawColor(255, 255, 255, 18)
		surface.DrawOutlinedRect(0, 0, pw, ph, 1)
		if self.Title then
			draw.RoundedBoxEx(S(6), 0, 0, pw, S(28), colStripe, true, true, false, false)
			draw.SimpleText(string.upper(self.Title), "GFR_Craft_Head", S(10), S(14), colDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end
	p:DockPadding(S(6), title and S(32) or S(6), S(6), S(6))
	return p
end

-- The picture the spawn menu shows for a weapon / entity (its IconOverride, entities/<class>.png or
-- vgui/entities/<class>), cached; false when it has none
local spawnIcons = {}
local function SpawnMenuIcon(class)
	if !class then return end
	if spawnIcons[class] != nil then return spawnIcons[class] or nil end
	local wl, el, w = list.Get("Weapon")[class], list.Get("SpawnableEntities")[class], weapons.Get(class)
	local paths = {wl && wl.IconOverride, el && el.IconOverride, w && w.IconOverride, "entities/" .. class .. ".png", "vgui/entities/" .. class}
	local found = false
	for i = 1, 5 do
		local p = paths[i]
		if p && p != "" then
			local onDisk = string.EndsWith(p, ".png") and file.Exists("materials/" .. p, "GAME") or (!string.EndsWith(p, ".png") && file.Exists("materials/" .. p .. ".vmt", "GAME"))
			if onDisk then
				local m = Material(p, "smooth mips")
				if m && !m:IsError() then found = m break end
			end
		end
	end
	spawnIcons[class] = found
	return found or nil
end
GFR.SpawnMenuIcon = SpawnMenuIcon -- (the inventory uses the same pictures: cl_inventory.lua)

local function RecipeIcon(r)
	if r.att then
		local t = ARC9 && ARC9.GetAttTable(r.att)
		local m = t && t.Icon
		if type(m) == "IMaterial" && !m:IsError() then return m end
		return
	end
	return SpawnMenuIcon(r.weapon or r.out or (r.outs && next(r.outs)))
end

local function InputIcon(class)
	local g = GFR.ItemGroups && GFR.ItemGroups[class]
	if g && g.classes then
		for c in pairs(g.classes) do
			local m = SpawnMenuIcon(c)
			if m then return m end
		end
	end
	return SpawnMenuIcon(class)
end

-- The spawn menu's picture when there is one; otherwise the model itself, rendered live and framed to fit (a cached
-- spawnicon was often missing for these, leaving an empty square)
local function Icon(parent, mdl, size, x, y, dim, mat)
	if mat then
		local img = parent:Add("DImage")
		img:SetMaterial(mat)
		img:SetSize(size, size)
		img:SetPos(x, y)
		img:SetMouseInputEnabled(false)
		if dim then img:SetImageColor(Color(255, 255, 255, 90)) end
		return img
	end
	if !mdl or !util.IsValidModel(mdl) then return end
	local p = parent:Add("DModelPanel")
	p:SetSize(size, size)
	p:SetPos(x, y)
	p:SetMouseInputEnabled(false)
	p:SetModel(mdl)
	local ent = p.Entity
	if IsValid(ent) then
		local mn, mx = ent:GetRenderBounds()
		local c, r = (mn + mx) / 2, (mx - mn):Length() / 2
		p:SetFOV(30)
		p:SetLookAt(c)
		p:SetCamPos(c + Vector(1, 0.8, 0.55):GetNormalized() * r * 3.6)
	end
	p.LayoutEntity = function() end -- (still, not spinning)
	if dim then p:SetColor(Color(255, 255, 255, 90)) p:SetAlpha(90) end
	return p
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Panels built in OpenCrafting
local ui = {}
local BuildList, BuildMiddle, SetPreview

local function RecipeMenu(r)
	local m = DermaMenu()
	m:AddOption(pins[r.id] and "Unpin" or "Pin to top", function() TogglePin(r.id) end):SetIcon(pins[r.id] and "icon16/star.png" or "icon16/award_star_gold_1.png")
	if CanCraft(r) then
		m:AddOption("Craft 1", function() CraftN(r, 1) end):SetIcon("icon16/wrench.png")
		local max = MaxCraft(r)
		if max >= 5 then m:AddOption("Craft 5", function() CraftN(r, 5) end):SetIcon("icon16/wrench.png") end
		if max > 1 then m:AddOption("Craft max (" .. max .. ")", function() CraftN(r, max) end):SetIcon("icon16/wrench_orange.png") end
	end
	m:Open()
end

local function Select(id)
	selected = id
	qty = 1
	previewYaw, previewZoom = 30, 1
	BuildMiddle()
end

-- One recipe in the list
local function Row(parent, r)
	local row = parent:Add("DButton")
	row:Dock(TOP)
	row:DockMargin(0, 0, 0, S(3))
	row:SetTall(S(54))
	row:SetText("")
	local state = State(r)
	local catCol = catColors[r.cat] or colAccent
	Icon(row, RecipeModel(r), S(44), S(8), S(5), state == 1, RecipeIcon(r))
	local title = r.name .. ((r.n or 1) > 1 and (" x" .. r.n) or "")
	local where = r.fire and "Fire" or (r.bench and "Bench" or "Hands")

	row.Paint = function(self, pw, ph)
		local sel = selected == r.id
		draw.RoundedBox(S(4), 0, 0, pw, ph, sel and Alpha(catCol, 45) or (self:IsHovered() and colHover or colCard))
		-- Left edge: green ready, amber short, grey unknown
		local edge = state == 3 and colGood or (state == 2 and colWarn or Color(80, 80, 80))
		draw.RoundedBoxEx(S(4), 0, 0, S(3), ph, edge, true, false, true, false)
		if sel then
			surface.SetDrawColor(catCol)
			surface.DrawOutlinedRect(0, 0, pw, ph, 1)
		end
	end
	row.PaintOver = function(self, pw, ph)
		local tx = S(60)
		local line = WrapLines(title, "GFR_Craft_Card", pw - tx - S(36), 1)[1] or title
		draw.SimpleText(line, "GFR_Craft_Card", tx, S(9), state == 1 and colDim or colText)
		local sub = (r.cat or "") .. "  ·  " .. where
		if state == 1 then sub = "Unknown recipe" end
		draw.SimpleText(sub, "GFR_Craft_Chip", tx, S(30), (state != 1 && (r.bench or r.fire) && !PlaceOK(r)) and colBad or colDim)
		if state == 1 then
			draw.SimpleText("LOCKED", "GFR_Craft_Head", pw - S(10), ph / 2, colDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		else
			local pinned = pins[r.id]
			local mx, my = self:CursorPos()
			local hoverStar = self:IsHovered() && mx > pw - S(32)
			draw.SimpleText(pinned and "★" or "☆", "GFR_Craft_Star", pw - S(18), ph / 2, pinned and colStar or (hoverStar and colText or colFaint), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end
	row.DoClick = function(self)
		local mx = self:CursorPos()
		if state != 1 && mx > self:GetWide() - S(32) then TogglePin(r.id) return end
		if input.IsShiftDown() then
			if CanCraft(r) then CraftN(r, 1)
			else surface.PlaySound("buttons/button10.wav") end
			return
		end
		Select(r.id)
	end
	row.DoRightClick = function() RecipeMenu(r) end
	if state == 3 then row:SetTooltip("Click: select   Shift+click: craft 1   Right click: more") end
	return row
end

local function SubHeader(parent, text, col, key, count)
	local hp = parent:Add("DButton")
	hp:Dock(TOP)
	hp:DockMargin(0, S(4), 0, S(3))
	hp:SetTall(S(26))
	hp:SetText("")
	hp.Paint = function(self, pw, ph)
		draw.RoundedBox(S(3), 0, 0, pw, ph, self:IsHovered() && key and colHover or Color(255, 255, 255, 14))
		draw.SimpleText(text .. (count and ("  (" .. count .. ")") or ""), "GFR_Craft_Small", S(8), ph / 2, col or colText, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		if key then
			draw.SimpleText(collapsed[key] and "▸" or "▾", "GFR_Craft_Small", pw - S(10), ph / 2, colDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
	end
	hp.DoClick = function()
		if !key then return end
		collapsed[key] = !collapsed[key] or nil
		BuildList()
	end
	return hp
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Middle: the selected recipe
local function Badge(r)
	if !IsKnown(r) then return "UNKNOWN RECIPE", Color(110, 110, 110) end
	if r.bench && !GFR.NearWorkbench(LocalPlayer()) then return "REQUIRES WORKBENCH", colBad end
	if r.fire && !GFR.NearFire(LocalPlayer()) then return "REQUIRES A FIRE", colBad end
	if !HasInputs(r) then return "MISSING MATERIALS", colWarn end
	return "READY TO CRAFT", colGood
end

local function Effects(r)
	local lines = {}
	local b = blurbs[r.id] or catBlurbs[r.cat]
	if b then lines[#lines + 1] = b end
	local out = r.out
	local n = out && GFR.Nutrition && GFR.Nutrition[out]
	if n then
		local parts = {}
		if n.hunger then parts[#parts + 1] = string.format("Hunger %+d", n.hunger) end
		if n.thirst then parts[#parts + 1] = string.format("Thirst %+d", n.thirst) end
		if n.stamina then parts[#parts + 1] = string.format("Stamina %+d", n.stamina) end
		if #parts > 0 then lines[#lines + 1] = table.concat(parts, "   ") end
	end
	if r.weapon && GFR.WeaponSlot then
		local slot = GFR.WeaponSlot(r.weapon)
		local names = {primary = "Primary weapon slot", secondary = "Secondary weapon slot", melee = "Melee weapon slot", throwable = "Throwable slot"}
		if names[slot or ""] then lines[#lines + 1] = "Takes the " .. string.lower(names[slot]) end
	end
	if r.outs then
		local parts = {}
		for class, count in SortedPairs(r.outs) do parts[#parts + 1] = count .. " " .. ShortItem(class) end
		lines[#lines + 1] = "Gives: " .. table.concat(parts, ", ")
	end
	return table.concat(lines, "\n")
end

local function BuildDismantle(mid)
	local info = PanelBox(mid, "Dismantle", 0, 0, mid:GetWide(), mid:GetTall() - S(70))
	local l = info:Add("DLabel")
	l:Dock(TOP)
	l:DockMargin(S(8), S(4), S(8), 0)
	l:SetFont("GFR_Craft_Text")
	l:SetTextColor(colText)
	l:SetWrap(true)
	l:SetAutoStretchVertical(true)
	local w = selectedWep && weapons.Get(selectedWep)
	l:SetText((w and ("Selected: " .. (w.PrintName or selectedWep) .. "\n\n") or "Pick a weapon on the left.\n\n")
		.. "Strip a weapon down for materials. Works anywhere.\n\n"
		.. "Melee / grenades: 1-2 Scrap\nHandguns: 1 Gun Part, 1-2 Scrap\nSMGs / shotguns: 1-2 Parts, 2-3 Scrap\n"
		.. "Rifles: 2-3 Parts, 2-3 Scrap\nHeavy / snipers / MGs: 3-4 Parts, 3-5 Scrap\nGunpowder sometimes, more often from bigger guns.\n\n"
		.. "At a workbench: +1 Part, +1 Scrap, better gunpowder odds.\nWorkbench nearby: " .. (GFR.NearWorkbench(LocalPlayer()) and "yes" or "no"))
	local btn = mid:Add("DButton")
	btn:SetPos(0, mid:GetTall() - S(60))
	btn:SetSize(mid:GetWide(), S(60))
	btn:SetText("")
	btn.Paint = function(self, pw, ph)
		local ok = w != nil
		local c = ok and catColors.Dismantle or Color(90, 90, 90)
		draw.RoundedBox(S(6), 0, 0, pw, ph, Alpha(c, self:IsHovered() && ok and 170 or 90))
		draw.SimpleText(ok and "DISMANTLE" or "SELECT A WEAPON", "GFR_Craft_Big", pw / 2, ph / 2, ok and colText or colDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	btn.DoClick = function()
		if !w then return end
		local c = selectedWep
		Derma_Query("Dismantle " .. (w.PrintName or c) .. "? You lose the gun.", "Dismantle", "Yes", function() Send("dismantle", c) selectedWep = nil end, "No")
	end
	SetPreview(w && w.WorldModel)
end

BuildMiddle = function()
	local mid = ui.mid
	if !IsValid(mid) then return end
	mid:Clear()
	ui.craftNow = nil
	if catFilter == "Dismantle" then BuildDismantle(mid) return end

	local r = selected && GFR.RecipeById[selected]
	local W, H = mid:GetWide(), mid:GetTall()
	local gap = S(10)
	local matsW = math.Clamp(math.floor(W * 0.38), S(210), S(280))
	local tilesH = S(150)
	local craftH = S(118)
	local topH = H - tilesH - craftH - gap * 2

	-- Your materials as tiles, along the bottom (what the selected recipe needs is lit)
	local tiles = PanelBox(mid, "Your materials" .. (nearbyCount > 0 and ("  (incl. " .. nearbyCount .. " storage nearby)") or ""), 0, H - tilesH, W, tilesH)
	local tileGrid = tiles:Add("DIconLayout")
	tileGrid:Dock(FILL)
	tileGrid:SetSpaceX(S(6))
	tileGrid:SetSpaceY(S(6))
	local needs = r && r.inputs or {}
	for _, class in ipairs(ui.MATS) do
		local def = GFR.CustomItems[class]
		if def then
			local t = tileGrid:Add("DPanel")
			local ts = S(76)
			t:SetSize(ts, tilesH - S(44))
			Icon(t, def.model, S(48), (ts - S(48)) / 2, S(4), false, SpawnMenuIcon(class))
			local needed = needs[class]
			t.Paint = function(self, pw, ph)
				local n = Have(class)
				local col = needed and (n >= needed and colGood or colBad) or nil
				draw.RoundedBox(S(4), 0, 0, pw, ph, col and Alpha(col, 40) or (n > 0 and colCard or Color(255, 255, 255, 4)))
				if col then surface.SetDrawColor(col) surface.DrawOutlinedRect(0, 0, pw, ph, 1) end
			end
			t.PaintOver = function(self, pw, ph)
				local n = Have(class)
				draw.SimpleText(n, "GFR_Craft_Card", pw - S(5), S(4), n > 0 and colText or colDim, TEXT_ALIGN_RIGHT)
				local name = WrapLines(def.name, "GFR_Craft_Chip", pw - S(4), 1)[1] or ""
				draw.SimpleText(name, "GFR_Craft_Chip", pw / 2, ph - S(10), colDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
			t:SetTooltip(def.name)
		end
	end

	if !r then
		local info = PanelBox(mid, "Item to craft", 0, 0, W, topH + craftH + gap)
		local l = info:Add("DLabel")
		l:Dock(FILL)
		l:SetContentAlignment(5)
		l:SetFont("GFR_Craft_Text")
		l:SetTextColor(colDim)
		l:SetText("Pick a recipe on the left")
		SetPreview(nil)
		return
	end
	local catCol = catColors[r.cat] or colAccent
	SetPreview(RecipeModel(r))

	-- ITEM TO CRAFT
	local info = PanelBox(mid, "Item to craft", 0, 0, W - matsW - gap, topH)
	local badgeText, badgeCol = Badge(r)
	local effects = Effects(r)
	local title = r.name .. ((r.n or 1) > 1 and ("  x" .. r.n) or "")
	local mdl = RecipeModel(r)
	Icon(info, mdl, S(64), info:GetWide() - S(76), S(40), !IsKnown(r), RecipeIcon(r))
	local pin = info:Add("DButton")
	pin:SetSize(S(28), S(28))
	pin:SetPos(info:GetWide() - S(34), 0)
	pin:SetText("")
	pin:SetTooltip(pins[r.id] and "Unpin" or "Pin to the top of the list")
	pin.Paint = function(self, w, h)
		draw.SimpleText(pins[r.id] and "★" or "☆", "GFR_Craft_Star", w / 2, h / 2, pins[r.id] and colStar or (self:IsHovered() and colText or colDim), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	pin.DoClick = function() TogglePin(r.id) end
	info.PaintOver = function(self, pw, ph)
		local x, y = S(12), S(40)
		-- Badge
		surface.SetFont("GFR_Craft_Head")
		local bw = surface.GetTextSize(badgeText) + S(20)
		draw.RoundedBox(S(3), x, y, bw, S(22), Alpha(badgeCol, 60))
		draw.RoundedBoxEx(S(3), x, y, S(4), S(22), badgeCol, true, false, true, false)
		draw.SimpleText(badgeText, "GFR_Craft_Head", x + S(11), y + S(11), badgeCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		y = y + S(32)
		draw.SimpleText(string.upper(r.cat or ""), "GFR_Craft_Small", x, y, catCol)
		y = y + S(20)
		local textW = pw - x * 2 - S(76)
		for _, l in ipairs(WrapLines(title, "GFR_Craft_Big", textW, 2)) do
			draw.SimpleText(l, "GFR_Craft_Big", x, y, IsKnown(r) and colText or colDim)
			y = y + S(30)
		end
		local where = r.fire and "Made over a fire" or (r.bench and "Made at a workbench" or "Made by hand")
		draw.SimpleText(where, "GFR_Craft_Small", x, y, (r.bench or r.fire) && !PlaceOK(r) and colBad or colDim)
		y = y + S(28)
		surface.SetDrawColor(255, 255, 255, 18)
		surface.DrawRect(x, y - S(6), pw - x * 2, 1)
		local text = IsKnown(r) and effects
			or "You don't know this recipe yet.\nFind recipe notes in desks and lockers, buy it from traders, or earn it doing jobs."
		local maxLines = math.max(math.floor((ph - y - S(8)) / S(20)), 1)
		for _, l in ipairs(WrapLines(text, "GFR_Craft_Text", pw - x * 2, maxLines)) do
			draw.SimpleText(l, "GFR_Craft_Text", x, y, colText)
			y = y + S(20)
		end
	end

	-- CRAFTING MATERIALS
	local mats = PanelBox(mid, "Crafting materials", W - matsW, 0, matsW, topH)
	local rows = {}
	for class, need in SortedPairs(r.inputs) do rows[#rows + 1] = {class, need} end
	if r.bench then rows[#rows + 1] = {"#bench"} end
	if r.fire then rows[#rows + 1] = {"#fire"} end
	for _, it in ipairs(rows) do
		local row = mats:Add("DPanel")
		row:Dock(TOP)
		row:DockMargin(0, 0, 0, S(4))
		row:SetTall(S(46))
		local class, need = it[1], it[2]
		if need then Icon(row, InputModel(class), S(38), S(4), S(4), false, InputIcon(class)) end
		row.Paint = function(self, pw, ph)
			local ok
			if class == "#bench" then ok = GFR.NearWorkbench(LocalPlayer())
			elseif class == "#fire" then ok = GFR.NearFire(LocalPlayer())
			else ok = Have(class) >= need end
			draw.RoundedBox(S(4), 0, 0, pw, ph, colCard)
			draw.RoundedBoxEx(S(4), pw - S(3), 0, S(3), ph, ok and colGood or colBad, false, true, false, true)
		end
		row.PaintOver = function(self, pw, ph)
			if class == "#bench" or class == "#fire" then
				local ok = class == "#bench" and GFR.NearWorkbench(LocalPlayer()) or class == "#fire" and GFR.NearFire(LocalPlayer())
				draw.SimpleText(class == "#bench" and "Workbench" or "Fire (burn barrel)", "GFR_Craft_Card", S(10), S(8), colText)
				draw.SimpleText(ok and "✔ nearby" or "✖ not nearby", "GFR_Craft_Chip", S(10), S(27), ok and colGood or colBad)
				return
			end
			local have = Have(class)
			local ok = have >= need
			local name = WrapLines(ShortItem(class), "GFR_Craft_Card", pw - S(56), 1)[1] or ""
			draw.SimpleText(name, "GFR_Craft_Card", S(48), S(7), colText)
			draw.SimpleText(math.min(have, 999) .. " / " .. need, "GFR_Craft_Chip", S(48), S(27), ok and colGood or colBad)
		end
	end

	-- Quantity + craft
	local craft = PanelBox(mid, nil, 0, topH + gap, W, craftH)
	local max = MaxCraft(r)
	if qty > math.max(max, 1) then qty = math.max(max, 1) end
	local ok = CanCraft(r)

	local bar = craft:Add("DPanel")
	bar:SetPos(S(12), S(10))
	bar:SetSize(W - S(24), S(36))
	local function SetFromX(x)
		local sx, sw = S(60), bar:GetWide() - S(120)
		local t = math.Clamp((x - sx) / sw, 0, 1)
		qty = math.max(1, math.Round(1 + t * (math.max(max, 1) - 1)))
	end
	bar.Paint = function(self, pw, ph)
		local mx1 = math.max(max, 1)
		local sx, sw = S(60), pw - S(120)
		local cy = ph / 2
		-- [-] and [+]
		draw.RoundedBox(S(4), 0, S(4), S(40), ph - S(8), colCard)
		draw.SimpleText("−", "GFR_Craft_Name", S(20), cy, colText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		draw.RoundedBox(S(4), pw - S(40), S(4), S(40), ph - S(8), colCard)
		draw.SimpleText("+", "GFR_Craft_Name", pw - S(20), cy, colText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		-- Track
		draw.RoundedBox(S(2), sx, cy - S(2), sw, S(4), Color(255, 255, 255, 25))
		local t = mx1 > 1 and (qty - 1) / (mx1 - 1) or 0
		draw.RoundedBox(S(2), sx, cy - S(2), sw * t, S(4), ok and catCol or colDim)
		local kx = sx + sw * t
		draw.NoTexture()
		surface.SetDrawColor(ok and colText or colDim)
		surface.DrawPoly({{x = kx, y = cy - S(8)}, {x = kx + S(8), y = cy}, {x = kx, y = cy + S(8)}, {x = kx - S(8), y = cy}})
		draw.SimpleText("1", "GFR_Craft_Chip", sx, cy + S(10), colDim, TEXT_ALIGN_CENTER)
		draw.SimpleText(mx1, "GFR_Craft_Chip", sx + sw, cy + S(10), colDim, TEXT_ALIGN_CENTER)
		draw.RoundedBox(S(3), kx - S(18), cy - S(26), S(36), S(16), Color(0, 0, 0, 200))
		draw.SimpleText(qty, "GFR_Craft_Chip", kx, cy - S(18), colText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	bar.OnMousePressed = function(self, code)
		if code != MOUSE_LEFT then return end
		local mx = self:CursorPos()
		local mx1 = math.max(max, 1)
		if mx < S(44) then qty = math.max(qty - 1, 1) return end
		if mx > self:GetWide() - S(44) then qty = math.min(qty + 1, mx1) return end
		self.Dragging = true
		self:MouseCapture(true)
		SetFromX(mx)
	end
	bar.OnMouseReleased = function(self)
		self.Dragging = nil
		self:MouseCapture(false)
	end
	bar.Think = function(self)
		if self.Dragging then SetFromX((self:CursorPos())) end
	end
	bar.OnMouseWheeled = function(self, d)
		qty = math.Clamp(qty + (d > 0 and 1 or -1), 1, math.max(max, 1))
		return true
	end
	bar:SetCursor("hand")

	local btn = craft:Add("DButton")
	btn:SetPos(S(12), S(54))
	btn:SetSize(W - S(24), craftH - S(66))
	btn:SetText("")
	btn.Paint = function(self, pw, ph)
		local c = ok and colGood or Color(90, 90, 90)
		draw.RoundedBox(S(5), 0, 0, pw, ph, Alpha(c, self:IsHovered() && ok and 150 or 70))
		-- Output on the left, the key + label on the right, like the reference
		local outText = (r.n or 1) * qty > 1 and ("Makes " .. (r.n or 1) * qty) or "Makes 1"
		if r.outs then outText = "Salvage x" .. qty end
		draw.SimpleText(outText, "GFR_Craft_Small", S(16), ph / 2, ok and colText or colDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		local label = !ok and (!IsKnown(r) and "UNKNOWN" or (PlaceOK(r) and "MISSING MATERIALS" or (r.fire and "NEEDS A FIRE" or "NEEDS A WORKBENCH"))) or ("CRAFT" .. (qty > 1 and (" x" .. qty) or ""))
		surface.SetFont("GFR_Craft_Big")
		local lw = surface.GetTextSize(label)
		draw.SimpleText(label, "GFR_Craft_Big", pw - S(16), ph / 2, ok and colText or colDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		if ok then
			local kx = pw - S(16) - lw - S(40)
			draw.RoundedBox(S(4), kx, ph / 2 - S(14), S(28), S(28), Color(235, 235, 235))
			draw.SimpleText("E", "GFR_Craft_Name", kx + S(14), ph / 2, Color(20, 20, 20), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end
	btn.DoClick = function() if ok then CraftN(r, qty) end end
	ui.craftNow = function() if ok then CraftN(r, qty) else surface.PlaySound("buttons/button10.wav") end end
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Left: the recipe list
local function Matches(r)
	if search == "" then return true end
	local s = string.lower(search)
	if string.find(string.lower(r.name), s, 1, true) then return true end
	for class in pairs(r.inputs) do
		if string.find(string.lower(ShortItem(class)), s, 1, true) then return true end
	end
	return false
end

local function SortRecipes(list)
	table.sort(list, function(a, b)
		if sortMode == 1 then
			local sa, sb = State(a), State(b)
			if sa != sb then return sa > sb end
		end
		return a.name < b.name
	end)
end

local function BuildDismantleList(canvas)
	SubHeader(canvas, "WEAPONS YOU CARRY", catColors.Dismantle)
	local any = false
	for _, w in ipairs(LocalPlayer():GetWeapons()) do
		local c = w:GetClass()
		if !GFR.IsFists(c) && weapons.Get(c) && !string.StartWith(c, "weapon_phys") && !string.StartWith(c, "weapon_eft_")
			&& !string.StartWith(c, "weapon_stalker2_") && !string.StartWith(c, "weapon_scpsl_") && c != "gmod_tool" && c != "gmod_camera" then
			any = true
			local row = canvas:Add("DButton")
			row:Dock(TOP)
			row:DockMargin(0, 0, 0, S(3))
			row:SetTall(S(54))
			row:SetText("")
			local mdl = w.GetWeaponWorldModel && w:GetWeaponWorldModel() or w.WorldModel
			Icon(row, mdl ~= "" and mdl or nil, S(44), S(8), S(5), false, SpawnMenuIcon(c))
			row.Paint = function(self, pw, ph)
				local sel = selectedWep == c
				draw.RoundedBox(S(4), 0, 0, pw, ph, sel and Alpha(catColors.Dismantle, 45) or (self:IsHovered() and colHover or colCard))
				if sel then surface.SetDrawColor(catColors.Dismantle) surface.DrawOutlinedRect(0, 0, pw, ph, 1) end
			end
			row.PaintOver = function(self, pw, ph)
				draw.SimpleText(w:GetPrintName(), "GFR_Craft_Card", S(60), S(9), colText)
				draw.SimpleText("Click to select", "GFR_Craft_Chip", S(60), S(30), colDim)
			end
			row.DoClick = function()
				selectedWep = c
				BuildMiddle()
			end
		end
	end
	if !any then SubHeader(canvas, "Nothing to dismantle", colDim) end
end

BuildList = function()
	local list = ui.list
	if !IsValid(list) then return end
	local scroll = list:GetVBar():GetScroll()
	list:Clear()
	local canvas = list

	if catFilter == "Dismantle" then
		BuildDismantleList(canvas)
		BuildMiddle()
		return
	end

	-- Gather what this tab shows
	local pinned, shown, unknownList = {}, {}, {}
	for _, r in ipairs(GFR.Recipes) do
		if !GFR.RecipeAvailable(r) then continue end
		if catFilter == "Pinned" && !pins[r.id] then continue end
		if catFilter != "All" && catFilter != "Pinned" && r.cat != catFilter then continue end
		if catFilter == "All" && r.att && !pins[r.id] then continue end -- 100+ cartridge parts live in their own tab
		if !Matches(r) then continue end
		if onlyCraftable && !CanCraft(r) then continue end
		if pins[r.id] then pinned[#pinned + 1] = r
		elseif !IsKnown(r) then unknownList[#unknownList + 1] = r
		else shown[#shown + 1] = r end
	end
	SortRecipes(pinned)
	SortRecipes(unknownList)

	local firstPick, visible = nil, false
	local function Add(r)
		Row(canvas, r)
		if !firstPick or State(r) > State(firstPick) then firstPick = r end
		if r.id == selected then visible = true end
	end

	if #pinned > 0 then
		local key = "pinned"
		SubHeader(canvas, "★  PINNED", colStar, key, #pinned)
		if !collapsed[key] then for _, r in ipairs(pinned) do Add(r) end end
	end

	if catFilter == "All" then
		-- One collapsible section per category
		for _, c in ipairs(cats) do
			local group = {}
			for _, r in ipairs(shown) do if r.cat == c then group[#group + 1] = r end end
			if #group > 0 then
				SortRecipes(group)
				local key = "All/" .. c
				SubHeader(canvas, string.upper(c), catColors[c], key, #group)
				if !collapsed[key] then for _, r in ipairs(group) do Add(r) end end
			end
		end
	elseif catFilter != "Pinned" then
		-- Sub-headers within the category
		local groups, order = {}, {}
		for _, r in ipairs(shown) do
			local i, name = SubGroup(r)
			if !groups[i] then groups[i] = {name = name, list = {}} order[#order + 1] = i end
			table.insert(groups[i].list, r)
		end
		table.sort(order)
		for _, i in ipairs(order) do
			local g = groups[i]
			SortRecipes(g.list)
			if g.name then
				local key = catFilter .. "/" .. g.name
				SubHeader(canvas, g.name, catColors[catFilter], key, #g.list)
				if !collapsed[key] then for _, r in ipairs(g.list) do Add(r) end end
			else
				for _, r in ipairs(g.list) do Add(r) end
			end
		end
	end

	if #unknownList > 0 then
		local key = "unknown/" .. catFilter
		if collapsed[key] == nil then collapsed[key] = true end -- folded away to start with
		SubHeader(canvas, "UNKNOWN RECIPES", colDim, key, #unknownList)
		if !collapsed[key] then for _, r in ipairs(unknownList) do Add(r) end end
	end

	if #pinned + #shown + #unknownList == 0 then
		SubHeader(canvas, search != "" and ("Nothing matches \"" .. search .. "\"")
			or (catFilter == "Pinned" and "Nothing pinned yet: click ☆ on a recipe" or "Nothing you can make right now"), colDim)
	end

	-- Keep the selection if it's still listed, else pick the best one
	if !visible then
		local r = selected && GFR.RecipeById[selected]
		if !(r && (catFilter == "All" or r.cat == catFilter or (catFilter == "Pinned" && pins[r.id]))) then
			selected = firstPick && firstPick.id or nil
		end
	end
	BuildMiddle()
	timer.Simple(0, function() if IsValid(list) then list:GetVBar():SetScroll(scroll) end end)
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Right: item preview
local lastPreview
SetPreview = function(mdl)
	local mp = ui.preview
	if !IsValid(mp) then return end
	if mdl == lastPreview && IsValid(mp.Entity) then return end
	lastPreview = mdl
	if !mdl or !util.IsValidModel(mdl) then
		if IsValid(mp.Entity) then mp.Entity:Remove() end
		mp.Entity = nil
		mp.HasModel = false
		return
	end
	mp:SetModel(mdl)
	mp.HasModel = IsValid(mp.Entity)
	if !mp.HasModel then return end
	local mn, mx = mp.Entity:GetRenderBounds()
	mp.Center = (mn + mx) / 2
	mp.Radius = math.max((mx - mn):Length() / 2, 4)
end

---------------------------------------------------------------------------------------------------------------------------------------------
function GFR.CraftingOpen() return IsValid(frame) end
function GFR.CloseCrafting() if IsValid(frame) then frame:Remove() end end

local MATS = {"gfr_mat_scrap", "gfr_mat_cloth", "gfr_mat_wood", "gfr_mat_tape", "gfr_mat_chem", "gfr_mat_gunpowder", "gfr_mat_parts", "gfr_mat_zblood"}

function GFR.OpenCrafting()
	if IsValid(frame) then return end
	Fonts()
	net.Start("GFR_RecipesRequest")
	net.SendToServer()
	lastPreview = nil
	ui = {MATS = MATS}

	local w, h = math.min(S(1640), ScrW() - S(40)), math.min(S(900), ScrH() - S(40))
	local pad = S(16)
	local headH, footH = S(70), S(30)
	local stripW = S(52)
	local listW = math.Clamp(math.floor(w * 0.25), S(320), S(420))
	local previewW = math.Clamp(math.floor(w * 0.24), S(280), S(420))
	local gap = S(10)
	local bodyY, bodyH = headH, h - headH - footH - pad
	local midX = pad + stripW + gap + listW + gap
	local midW = w - midX - gap - previewW - pad

	frame = vgui.Create("DFrame")
	frame:SetSize(w, h)
	frame:Center()
	frame:SetTitle("")
	frame:ShowCloseButton(false)
	frame:SetDraggable(false)
	frame:MakePopup()
	frame:SetKeyboardInputEnabled(false)
	frame.Paint = function(self, pw, ph)
		draw.RoundedBox(S(10), 0, 0, pw, ph, colBg)
		-- Header: title + station
		surface.SetMaterial(IconMat("icon16/wrench.png"))
		surface.SetDrawColor(255, 255, 255, 220)
		surface.DrawTexturedRect(pad, S(16), S(36), S(36))
		draw.SimpleText("CRAFTING", "GFR_Craft_Title", pad + S(46), S(10), colText)
		local station = StationText()
		draw.SimpleText("Station: " .. station, "GFR_Craft_Small", pad + S(48), S(44), station == "Hands" and colDim or colGood)
		-- Storage nearby, on the right
		local st = nearbyCount > 0 and ("● Using " .. nearbyCount .. " storage nearby") or "○ No storage nearby"
		draw.SimpleText(st, "GFR_Craft_Small", pw - S(250), S(34), nearbyCount > 0 and colGood or colDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		-- Footer: controls
		local fy = ph - footH / 2 - S(4)
		local hints = {{"Drag", "Rotate preview"}, {"Scroll", "Zoom preview"}, {"E", "Craft"}, {"Shift+Click", "Craft 1"}, {"Right click", "Pin / craft"}, {"Tab", "Close"}}
		local x = pw - pad
		surface.SetFont("GFR_Craft_Chip")
		for i = #hints, 1, -1 do
			local key, label = hints[i][1], hints[i][2]
			local lw = surface.GetTextSize(label)
			draw.SimpleText(label, "GFR_Craft_Chip", x, fy, colDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
			x = x - lw - S(6)
			local kw = surface.GetTextSize(key) + S(10)
			draw.RoundedBox(S(3), x - kw, fy - S(9), kw, S(18), Color(235, 235, 235, 220))
			draw.SimpleText(key, "GFR_Craft_Chip", x - kw / 2, fy, Color(20, 20, 20), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			x = x - kw - S(18)
		end
	end

	local back = frame:Add("DButton")
	back:SetSize(S(140), S(32))
	back:SetPos(w - S(140) - S(56), S(18))
	back:SetText("<  INVENTORY")
	back:SetFont("GFR_Craft_Small")
	back:SetTextColor(colText)
	back.Paint = function(self, pw, ph) draw.RoundedBox(S(5), 0, 0, pw, ph, self:IsHovered() and colHover or colPanel) end
	back.DoClick = function()
		frame:Remove()
		if GFR.OpenInventory then GFR.OpenInventory() end
	end

	local close = frame:Add("DButton")
	close:SetSize(S(32), S(32))
	close:SetPos(w - S(44), S(18))
	close:SetText("✕")
	close:SetFont("GFR_Craft_Name")
	close:SetTextColor(colDim)
	close.Paint = nil
	close.DoClick = function() frame:Remove() end

	-- Category strip
	local strip = frame:Add("DPanel")
	strip:SetPos(pad, bodyY)
	strip:SetSize(stripW, bodyH)
	strip.Paint = function(self, pw, ph) draw.RoundedBox(S(6), 0, 0, pw, ph, colPanel2) end
	for i, c in ipairs(cats) do
		local b = strip:Add("DButton")
		b:SetPos(S(4), S(4) + (i - 1) * (stripW - S(4)))
		b:SetSize(stripW - S(8), stripW - S(8))
		b:SetText("")
		b:SetTooltip(c)
		b.Paint = function(self, pw, ph)
			local col = catColors[c] or colText
			local active = catFilter == c
			draw.RoundedBox(S(5), 0, 0, pw, ph, active and Alpha(col, 110) or (self:IsHovered() and colHover or Color(0, 0, 0, 0)))
			if active then draw.RoundedBox(0, 0, S(6), S(3), ph - S(12), col) end
			surface.SetMaterial(IconMat(catIcons[c]))
			surface.SetDrawColor(255, 255, 255, (active or self:IsHovered()) and 255 or 150)
			local is = S(22)
			surface.DrawTexturedRect((pw - is) / 2, (ph - is) / 2, is, is)
		end
		b.DoClick = function()
			if catFilter == c then return end
			catFilter = c
			selectedWep = nil
			surface.PlaySound("ui/buttonrollover.wav")
			BuildList()
		end
	end

	-- Recipe list box: category title on top, list, sort/search at the bottom
	local listBox = frame:Add("DPanel")
	listBox:SetPos(pad + stripW + gap, bodyY)
	listBox:SetSize(listW, bodyH)
	listBox.Paint = function(self, pw, ph)
		draw.RoundedBox(S(6), 0, 0, pw, ph, colPanel2)
		draw.RoundedBoxEx(S(6), 0, 0, pw, S(34), colStripe, true, true, false, false)
		local col = catColors[catFilter] or colText
		surface.SetMaterial(IconMat(catIcons[catFilter]))
		surface.SetDrawColor(255, 255, 255, 230)
		surface.DrawTexturedRect(S(10), S(9), S(16), S(16))
		draw.SimpleText(string.upper(catFilter), "GFR_Craft_Small", pw - S(10), S(17), col, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end

	local list = listBox:Add("DScrollPanel")
	list:SetPos(S(6), S(40))
	list:SetSize(listW - S(12), bodyH - S(40) - S(82))
	list:GetCanvas():DockPadding(0, 0, S(4), 0)
	local vbar = list:GetVBar()
	vbar:SetWide(S(6))
	vbar:SetHideButtons(true)
	vbar.Paint = function(self, pw, ph) draw.RoundedBox(S(3), 0, 0, pw, ph, Color(255, 255, 255, 8)) end
	vbar.btnGrip.Paint = function(self, pw, ph) draw.RoundedBox(S(3), 0, 0, pw, ph, Color(255, 255, 255, 60)) end
	ui.list = list

	local tools = listBox:Add("DPanel")
	tools:SetPos(S(6), bodyH - S(76))
	tools:SetSize(listW - S(12), S(70))
	tools.Paint = nil

	local entry = tools:Add("DTextEntry")
	entry:SetPos(0, 0)
	entry:SetSize(listW - S(12), S(32))
	entry:SetFont("GFR_Craft_Text")
	entry:SetValue(search)
	entry:SetUpdateOnType(true)
	entry.Paint = function(self, pw, ph)
		draw.RoundedBox(S(4), 0, 0, pw, ph, self:HasFocus() and Color(255, 255, 255, 30) or colCard)
		self:DrawTextEntryText(colText, colAccent, colText)
		if self:GetValue() == "" && !self:HasFocus() then
			draw.SimpleText("Search recipes or materials...", "GFR_Craft_Text", S(8), ph / 2, colDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end
	-- Typing needs the keyboard; give it back to the game (Tab closes) once you click away
	entry.OnGetFocus = function() frame:SetKeyboardInputEnabled(true) end
	entry.OnLoseFocus = function() if IsValid(frame) then frame:SetKeyboardInputEnabled(false) end end
	entry.OnValueChange = function(self, v)
		search = v or ""
		BuildList()
	end
	ui.entry = entry

	local half = (listW - S(12) - S(6)) / 2
	local sortBtn = tools:Add("DButton")
	sortBtn:SetPos(0, S(38))
	sortBtn:SetSize(half, S(30))
	sortBtn:SetText("")
	sortBtn.Paint = function(self, pw, ph)
		draw.RoundedBox(S(4), 0, 0, pw, ph, self:IsHovered() and colHover or colCard)
		draw.SimpleText("Sort: " .. (sortMode == 1 and "Craftable first" or "Name"), "GFR_Craft_Small", S(10), ph / 2, colText, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText("▾", "GFR_Craft_Small", pw - S(10), ph / 2, colDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end
	sortBtn.DoClick = function()
		local m = DermaMenu()
		m:AddOption("Craftable first", function() sortMode = 1 BuildList() end)
		m:AddOption("Name", function() sortMode = 2 BuildList() end)
		m:Open()
	end

	local toggle = tools:Add("DButton")
	toggle:SetPos(half + S(6), S(38))
	toggle:SetSize(half, S(30))
	toggle:SetText("")
	toggle.Paint = function(self, pw, ph)
		draw.RoundedBox(S(4), 0, 0, pw, ph, onlyCraftable and Alpha(colGood, 80) or (self:IsHovered() and colHover or colCard))
		draw.SimpleText((onlyCraftable and "☑" or "☐") .. "  Can craft now", "GFR_Craft_Small", S(10), ph / 2, colText, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	toggle.DoClick = function()
		onlyCraftable = !onlyCraftable
		BuildList()
	end

	-- Middle
	local mid = frame:Add("DPanel")
	mid:SetPos(midX, bodyY)
	mid:SetSize(midW, bodyH)
	mid.Paint = nil
	ui.mid = mid

	-- Item preview
	local pbox = PanelBox(frame, "Item preview", w - pad - previewW, bodyY, previewW, bodyH)
	local mp = pbox:Add("DModelPanel")
	mp:Dock(FILL)
	mp:SetFOV(35)
	mp:SetAmbientLight(Color(90, 90, 90))
	mp:SetDirectionalLight(BOX_TOP, Color(255, 245, 230))
	mp:SetDirectionalLight(BOX_FRONT, Color(140, 140, 150))
	mp.LayoutEntity = function(self, ent)
		if self.Dragging then
			local x = gui.MouseX()
			previewYaw = previewYaw + (x - (self.LastX or x)) * 0.6
			self.LastX = x
		else
			previewYaw = previewYaw + FrameTime() * 12 -- a slow turn while idle
		end
		ent:SetAngles(Angle(0, previewYaw, 0))
		local center = self.Center or vector_origin
		local dist = (self.Radius or 20) * 2.6 / previewZoom
		self:SetLookAt(center)
		self:SetCamPos(center - Angle(18, 0, 0):Forward() * dist)
	end
	mp.OnMousePressed = function(self, code)
		if code != MOUSE_LEFT then return end
		self.Dragging = true
		self.LastX = gui.MouseX()
		self:MouseCapture(true)
	end
	mp.OnMouseReleased = function(self)
		self.Dragging = nil
		self:MouseCapture(false)
	end
	mp.OnMouseWheeled = function(self, d)
		previewZoom = math.Clamp(previewZoom * (d > 0 and 1.15 or 1 / 1.15), 0.5, 4)
		return true
	end
	mp:SetCursor("sizewe")
	local basePaint = mp.Paint
	mp.Paint = function(self, pw, ph)
		-- A soft floor glow behind the item
		draw.RoundedBox(S(6), 0, 0, pw, ph, Color(255, 255, 255, 4))
		if self.HasModel then
			basePaint(self, pw, ph)
		else
			draw.SimpleText("No preview", "GFR_Craft_Text", pw / 2, ph / 2, colDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end
	ui.preview = mp

	frame.Rebuild = function() BuildList() end
	-- Walking up to / away from a bench or fire changes what you can make
	local lastPlace
	local nextNearby = 0
	strip.Think = function()
		local ply = LocalPlayer()
		-- Keep the crates' contents fresh while the window is open (you may walk around, or someone may take things)
		if CurTime() > nextNearby then
			nextNearby = CurTime() + 3
			net.Start("GFR_RecipesRequest")
			net.SendToServer()
		end
		local place = tostring(GFR.NearWorkbench(ply)) .. tostring(GFR.NearFire(ply))
		if lastPlace && place != lastPlace then BuildList() end
		lastPlace = place
	end
	-- Lay out once the panels have their sizes
	timer.Simple(0, function() if IsValid(frame) then BuildList() end end)
end

-- E crafts while the window is open (instead of using whatever's in front of you)
hook.Add("PlayerBindPress", "GFR_Crafting_EKey", function(ply, bind, pressed)
	if !IsValid(frame) or !pressed or !string.find(bind, "+use", 1, true) then return end
	if IsValid(ui.entry) && ui.entry:HasFocus() then return end
	if catFilter != "Dismantle" && ui.craftNow then ui.craftNow() end
	return true
end)

hook.Add("GFR_InventoryChanged", "GFR_Crafting_Refresh", function()
	if IsValid(frame) then frame:Rebuild() end
end)

hook.Add("Think", "GFR_Crafting_CloseOnDeath", function()
	if IsValid(frame) && (!IsValid(LocalPlayer()) or !LocalPlayer():Alive()) then frame:Remove() end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Looking at a barricade / workbench
hook.Add("HUDPaint", "GFR_Barricade_Label", function()
	local ply = LocalPlayer()
	if !IsValid(ply) or !ply:Alive() or ply:GetNW2Bool("GFR_IsZombie") then return end
	local tr = ply:GetEyeTrace()
	local ent = tr.Entity
	if !IsValid(ent) or tr.HitPos:DistToSqr(ply:EyePos()) > 110 * 110 then return end
	local cx, cy = ScrW() / 2, ScrH() / 2 + S(40)
	-- Whose it is, under the rest (cl_access.lua)
	local owner = GFR.OwnerPrompt && GFR.OwnerPrompt(ent)
	local function Owner(y)
		if owner then draw.SimpleTextOutlined(owner, "GFR_Craft_Small", cx, y, colDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 180)) end
	end
	if ent:GetNW2Bool("GFR_Workbench") or ent:GetNW2Bool("GFR_Fire") or ent:GetNW2Bool("GFR_GunBench") then
		local name = ent:GetNW2Bool("GFR_Fire") and "Burn Barrel (cook here)" or (ent:GetNW2Bool("GFR_GunBench") and "Gun Table   [C] Customize gun" or "Workbench")
		draw.SimpleTextOutlined(name .. "   [Crouch+E] Pick up", "GFR_Craft_Small", cx, cy, Color(225, 210, 170), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 180))
		Owner(cy + S(20))
		return
	end
	local max = ent:GetNW2Int("GFR_BarMax", 0)
	if max <= 0 then return end
	local hp = ent:GetNW2Int("GFR_BarHP", 0)
	local w, h = S(160), S(6)
	-- Turret: health, ammo, controls
	local tmax = ent:GetNW2Int("GFR_TurretMax", 0)
	if tmax > 0 then
		local ammo = ent:GetNW2Int("GFR_TurretAmmo", 0)
		draw.SimpleTextOutlined(ent:GetNW2String("GFR_TurretName", "Turret") .. "  " .. hp .. "/" .. max, "GFR_Craft_Small", cx, cy, colText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 180))
		draw.RoundedBox(h / 2, cx - w / 2, cy + S(12), w, h, Color(0, 0, 0, 160))
		draw.RoundedBox(h / 2, cx - w / 2, cy + S(12), math.max(w * hp / max, h), h, hp / max > 0.35 and colGood or colBad)
		draw.SimpleTextOutlined("Ammo  " .. ammo .. " / " .. tmax .. "   (" .. ent:GetNW2String("GFR_TurretAmmoName", "") .. ")", "GFR_Craft_Small", cx, cy + S(30),
			ammo > 0 and colWarn or colBad, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 180))
		draw.SimpleTextOutlined("[E] Load ammo / repair when full   [Crouch+E] " .. (hp < max and "Tear down (repair to move)" or "Pick up"), "GFR_Craft_Small", cx, cy + S(50), colDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 180))
		Owner(cy + S(70))
		return
	end
	draw.SimpleTextOutlined(ent:GetNW2String("GFR_BuildName", "Barricade") .. "  " .. hp .. "/" .. max, "GFR_Craft_Small", cx, cy, colText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 180))
	draw.RoundedBox(h / 2, cx - w / 2, cy + S(12), w, h, Color(0, 0, 0, 160))
	draw.RoundedBox(h / 2, cx - w / 2, cy + S(12), math.max(w * hp / max, h), h, hp / max > 0.35 and colGood or colBad)
	draw.SimpleTextOutlined(hp < max and "[E] Repair   [Crouch+E] Tear down (repair to move)" or "[Crouch+E] Pick up", "GFR_Craft_Small", cx, cy + S(30), colDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 180))
	Owner(cy + S(50))
end)
