--[[
	Custom Apocalypse Project - Inventory (server)
	Pressing E on a Crunchy pickup stores it instead of consuming it (see the Use wrapper in gfr_loot.lua).
	Items are used/dropped from the Tab menu (cl_gfr_inventory.lua).

	ply.GFR_Inv = { {class, count, contaminated, model}, ... }
	Using an item spawns a hidden copy and runs its normal Use with GFR_FromInventory set,
	so its own effect + our hooks (stats, infection, overheal clamp) apply exactly as before.
]]

GFR = GFR or {}

local cvEnabled = CreateConVar("gfr_inv_enabled", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY), "Store picked up items in the inventory instead of using them instantly")
local cvSlots = CreateConVar("gfr_inv_slots", "15", bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY), "Inventory slots without a bag (a satchel adds 5, a backpack 10)")
-- The default used to be 10 and the value is saved in your config: move it up to the new default once
if cookie.GetString("gfr_inv_slots_v2") != "1" then
	cookie.Set("gfr_inv_slots_v2", "1")
	if cvSlots:GetInt() == 10 then timer.Simple(0, function() RunConsoleCommand("gfr_inv_slots", "15") end) end
end

util.AddNetworkString("GFR_InvSync")
util.AddNetworkString("GFR_InvAction")

-- Not inventory items: big crates and dispensers
local function Storable(class)
	return !string.StartWith(class, "supply_") && class != "contagion_ammo_crate" && class != "weapon_ammo_spawn"
end

local drinks = {} -- (Crunchy drinks are gone; our own items carry their category in sh_items.lua)

function GFR.ItemCategory(class)
	if weapons.GetStored(class) then return "weapon" end -- a gun carried in the bag (GFR.WeaponEntry below)
	local custom = GFR.CustomItems && GFR.CustomItems[class]
	if custom then return custom.cat end
	if drinks[class] then return "drink" end
	if string.find(class, "ammo", 1, true) or string.StartWith(class, "pouch_") or string.StartWith(class, "smod_") then return "ammo" end
	if string.find(class, "armor", 1, true) or string.find(class, "kevlar", 1, true) or string.find(class, "helmet", 1, true) or string.find(class, "battery", 1, true) then return "armor" end
	if string.find(class, "food", 1, true) or string.StartWith(class, "meat_") then return "food" end
	if string.find(class, "med", 1, true) or string.find(class, "bandage", 1, true) or string.find(class, "pill", 1, true)
		or string.find(class, "painkill", 1, true) or string.find(class, "morphine", 1, true) or string.find(class, "splint", 1, true)
		or string.find(class, "blood", 1, true) or string.find(class, "inoculator", 1, true) or string.find(class, "injector", 1, true)
		or string.find(class, "herb", 1, true) or string.find(class, "spray", 1, true) or string.find(class, "stim", 1, true)
		or string.find(class, "health", 1, true) or string.find(class, "aid", 1, true) then return "medical" end
	return "misc"
end

-- How many of one item fit in a single slot
local catStack = {food = 4, drink = 4, medical = 5, ammo = 5, armor = 1, material = 10, deployable = 1, misc = 3, weapon = 1}

function GFR.StackMax(class)
	-- Loose rounds in storage ("ammo:<type>"): a slot holds what a bag slot does
	local rounds = string.match(class, "^ammo:(.+)$")
	local rule = rounds && GFR.AmmoRuleByType && GFR.AmmoRuleByType[rounds]
	if rule then return rule.perSlot end
	local custom = GFR.CustomItems && GFR.CustomItems[class]
	if custom && custom.stack then return custom.stack end
	if GFR.Medkits && GFR.Medkits[class] then return 2 end
	return catStack[GFR.ItemCategory(class)] or 3
end
local StackMax = GFR.StackMax

function GFR.InvCapacity(ply)
	return cvSlots:GetInt() + (ply.GFR_BagBonus or 0)
end

-- Short text describing what the item does, shown in the menu
local slotNames = {primary = "Primary weapon", secondary = "Secondary weapon (handgun)", melee = "Melee weapon", throwable = "Throwable"}
local function ItemDesc(class, contaminated, e)
	local lines = {}
	if e && e.wep then
		local slot = GFR.SlotOfClass && GFR.SlotOfClass(class)
		lines[#lines + 1] = slotNames[slot or ""] or "Weapon"
		if (e.wep.clip1 or -1) >= 0 then lines[#lines + 1] = "Magazine: " .. e.wep.clip1 .. " rounds" end
		lines[#lines + 1] = "Equip: swaps with the one in that slot"
		return table.concat(lines, "\n")
	end
	local ammo = GFR.AmmoItems && GFR.AmmoItems[class]
	if ammo then
		lines[#lines + 1] = string.format("%s  (+%d)", GFR.AmmoGroups[ammo.type] or ammo.type, ammo.amount)
	end
	local n = GFR.Nutrition && GFR.Nutrition[class]
	if n then
		if n.hunger then lines[#lines + 1] = string.format("Hunger %+d", n.hunger) end
		if n.thirst then lines[#lines + 1] = string.format("Thirst %+d", n.thirst) end
		if n.stamina then lines[#lines + 1] = string.format("Stamina %+d", n.stamina) end
	end
	if (GFR.Bandages && GFR.Bandages[class]) or (GFR.Medkits && GFR.Medkits[class]) then lines[#lines + 1] = "Stops bleeding" end
	local t = GFR.Treatments && GFR.Treatments[class]
	if t then
		if t.suppress then lines[#lines + 1] = string.format("Slows infection (%d min)", math.Round(t.suppress / 60)) end
		if t.pushback then lines[#lines + 1] = string.format("Pushes infection back %d%%", t.pushback) end
	end
	if contaminated or string.StartWith(class, "meat_") then lines[#lines + 1] = "Smells of blood - may be infected" end
	return table.concat(lines, "\n")
end

local function Sync(ply)
	local inv = ply.GFR_Inv or {}
	local out = {}
	for i, e in ipairs(inv) do
		out[i] = {
			class = e.class, count = e.count, contaminated = e.contaminated, model = e.model,
			cat = GFR.ItemCategory(e.class), stack = StackMax(e.class), desc = ItemDesc(e.class, e.contaminated, e)
		}
	end
	-- Your rounds, as the stacks they take up (below: GFR.RoundStacks)
	for _, st in ipairs(GFR.RoundStacks && GFR.RoundStacks(ply) or {}) do
		local r = st.rule
		out[#out + 1] = {
			class = "ammo:" .. st.ammo, count = st.count, contaminated = false, model = GFR.RoundModel(r), cat = "ammo", stack = r.perSlot,
			rounds = true, desc = string.format("Loose rounds - your guns load these.\n%d to a slot.", r.perSlot)
		}
	end
	net.Start("GFR_InvSync")
	net.WriteTable(out)
	net.WriteUInt(GFR.InvCapacity(ply), 8)
	net.Send(ply)
end
GFR.InvSync = Sync

---------------------------------------------------------------------------------------------------------------------------------------------
-- Rounds: ammo isn't boxes in the bag, it's loose rounds per caliber (what the guns load from) - but they take bag slots
-- (GFR.AmmoRules in sh_ammo.lua: perSlot rounds a slot; bag room is the only limit), and show in the bag as their own
-- stacks. Picked up, looted, bought or crafted, ammo goes straight in as rounds; what doesn't fit stays where it was.
local function RoundSlots(rule, n) return math.ceil(math.max(n, 0) / rule.perSlot) end

-- Bag slots your rounds take (leaving one caliber out)
function GFR.AmmoSlots(ply, except)
	local n = 0
	for _, r in ipairs(GFR.AmmoRules or {}) do
		if r.type != except then n = n + RoundSlots(r, ply:GetAmmoCount(r.type)) end
	end
	return n
end

-- How many rounds of a caliber you can hold right now: what fits in the room the bag has
function GFR.AmmoRoom(ply, ammoType)
	local r = GFR.AmmoRuleByType && GFR.AmmoRuleByType[ammoType]
	if !r or !cvEnabled:GetBool() then return math.huge end
	local free = GFR.InvCapacity(ply) - #(ply.GFR_Inv or {}) - GFR.AmmoSlots(ply, ammoType)
	return math.max(free * r.perSlot, 0)
end

-- Give rounds, as many as fit. Returns how many went in.
function GFR.GiveRounds(ply, amount, ammoType)
	local give = math.Clamp(math.min(amount, GFR.AmmoRoom(ply, ammoType) - ply:GetAmmoCount(ammoType)), 0, amount)
	if give > 0 then ply:GiveAmmo(give, ammoType, true) end
	return give
end

local function RoundsName(ammoType) return GFR.AmmoGroups && GFR.AmmoGroups[ammoType] or ammoType end

-- Rounds put down: an ammo pickup of that caliber holding exactly that many (GFR_AmmoAmount)
local function DropRounds(ply, ammoType, n, pos)
	if n <= 0 then return end
	local class
	for c, a in pairs(GFR.AmmoItems or {}) do
		if a.type == ammoType && scripted_ents.GetStored(c) then class = c break end
	end
	if !class then return end
	local ent = ents.Create(class)
	if !IsValid(ent) then return end
	if !pos then
		local tr = util.TraceLine({start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * 60, filter = ply})
		pos = tr.HitPos + tr.HitNormal * 8
	end
	ent:SetPos(pos)
	ent:Spawn()
	ent:Activate()
	ent.GFR_Loot = true
	ent.GFR_AmmoAmount = n
end

-- An ammo item as rounds; returns how many went in (0: no room)
local function AmmoStraightIn(ply, class, rounds)
	local a = GFR.AmmoItems && GFR.AmmoItems[class]
	if !a then return end
	local given = GFR.GiveRounds(ply, rounds, a.type)
	if given > 0 then
		GFR.Notify(ply, string.format("+%d %s", given, RoundsName(a.type)))
	else
		GFR.Notify(ply, "No room for more " .. RoundsName(a.type) .. ".")
	end
	return given
end

-- The model a caliber's stack shows: an installed ammo pickup of that caliber (a real ammo box), the HL2 one if none
local roundModels = {}
local preferRounds = {
	AR2 = {"nmrih_rifle_ammo", "stalker_sniper_ammo", "uh_ammo_sniper", "zps_ammo_sniper", "contagion_ammo_sniper", "nmrih_rifle_ammo_mag"},
	Buckshot = {"nmrih_shotgun_ammo", "zps_ammo_buckshot", "stalker_shotgun_ammo", "uh_ammo_shotgun", "pouch_shotgun_ammo", "contagion_ammo_shotgun"},
	["357"] = {"nmrih_magnum_ammo", "zps_ammo_357", "stalker_magnum_ammo", "uh_ammo_357", "pouch_magnum_ammo", "contagion_ammo_magnum"},
	XBowBolt = {"nmrih_crossbow_ammo", "contagion_ammo_arrows"},
	SMG1_Grenade = {"contagion_ammo_m79_pack", "contagion_ammo_m79", "loose_ammo_m79"},
	RPG_Round = {"stalker_rpg_ammo"}
}
local function RoundModel(rule)
	if roundModels[rule.type] then return roundModels[rule.type] end
	-- ARC9's own ammo box first (sh_ammo.lua)
	if rule.arc9Model && util.IsValidModel(rule.arc9Model) then
		roundModels[rule.type] = rule.arc9Model
		return rule.arc9Model
	end
	local function ModelOf(class)
		local st = scripted_ents.GetStored(class)
		local m = st && st.t.Model
		return isstring(m) && util.IsValidModel(m) && m or nil
	end
	local found
	for _, c in ipairs(preferRounds[rule.type] or {}) do
		found = ModelOf(c)
		if found then break end
	end
	if !found then
		local classes = {}
		for c, a in pairs(GFR.AmmoItems or {}) do if a.type == rule.type then classes[#classes + 1] = c end end
		table.sort(classes)
		for _, c in ipairs(classes) do
			found = ModelOf(c)
			if found then break end
		end
	end
	roundModels[rule.type] = found or rule.model
	return roundModels[rule.type]
end

-- Your rounds as bag stacks (after the real entries): one per slot they take
local function RoundStacks(ply)
	local out = {}
	for _, r in ipairs(GFR.AmmoRules or {}) do
		local n = ply:GetAmmoCount(r.type)
		while n > 0 do
			local put = math.min(r.perSlot, n)
			out[#out + 1] = {ammo = r.type, count = put, rule = r}
			n = n - put
		end
	end
	return out
end
GFR.RoundStacks = RoundStacks
GFR.RoundModel = RoundModel

-- Each entry is one slot. Fills partial stacks first, then empty slots. Returns how many were added.
function GFR.InvAdd(ply, class, count, contaminated, model)
	local a = GFR.AmmoItems && GFR.AmmoItems[class]
	if a then
		local given = AmmoStraightIn(ply, class, a.amount * count)
		return given > 0 and count or 0
	end
	ply.GFR_Inv = ply.GFR_Inv or {}
	local inv = ply.GFR_Inv
	local max = StackMax(class)
	contaminated = contaminated or false
	local left = count
	for _, e in ipairs(inv) do
		if left <= 0 then break end
		if e.class == class && e.contaminated == contaminated && e.count < max then
			local put = math.min(max - e.count, left)
			e.count = e.count + put
			left = left - put
		end
	end
	while left > 0 && #inv + GFR.AmmoSlots(ply) < GFR.InvCapacity(ply) do
		local put = math.min(max, left)
		inv[#inv + 1] = {class = class, count = put, contaminated = contaminated, model = model}
		left = left - put
	end
	if left < count then Sync(ply) end
	return count - left
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Guns in the bag: one slot each, remembering the magazine and the parts fitted to it.
-- e = {class, count = 1, model, wep = {clip1, clip2, atts}}
local function WorldModelOf(class)
	local w = weapons.Get(class)
	local mdl = w && w.WorldModel
	return (mdl && mdl != "" && util.IsValidModel(mdl)) and mdl or "models/weapons/w_pistol.mdl"
end

-- An entry for a weapon entity (held, or lying in the world)
function GFR.WeaponEntry(wep)
	return {class = wep:GetClass(), count = 1, contaminated = false, model = WorldModelOf(wep:GetClass()),
		wep = {clip1 = wep:Clip1(), clip2 = wep:Clip2(), atts = GFR.CaptureWeaponAtts && GFR.CaptureWeaponAtts(wep)}}
end

-- Add any entry as its own slot (weapons never stack). Returns true if it fit.
function GFR.InvAddEntry(ply, e)
	if e.wep or StackMax(e.class) <= 1 then
		ply.GFR_Inv = ply.GFR_Inv or {}
		if #ply.GFR_Inv + GFR.AmmoSlots(ply) >= GFR.InvCapacity(ply) then return false end
		ply.GFR_Inv[#ply.GFR_Inv + 1] = table.Copy(e)
		Sync(ply)
		return true
	end
	return GFR.InvAdd(ply, e.class, e.count, e.contaminated, e.model) >= e.count
end

-- Make a weapon from an entry: in your hands (give) or on the ground (pos)
function GFR.SpawnWeaponFromEntry(e, ply, pos)
	local w
	if IsValid(ply) then
		w = ply:Give(e.class, true)
	else
		w = ents.Create(e.class)
		if IsValid(w) then
			w:SetPos(pos)
			w:Spawn()
			w:Activate()
			w.GFR_Loot = true
		end
	end
	if !IsValid(w) then return end
	w.GaveDefaultAmmo = true -- ARC9: no free reserve ammo
	local data = e.wep or {}
	-- Its magazine as it was (ARC9 would otherwise top it up for free: sh_attachments.lua)
	GFR.ApplyWeaponState(w, data.clip1, data.clip2, data.atts)
	return w
end

-- Equip a gun from the bag; whatever is in that weapon slot goes into the bag in its place
function GFR.EquipFromInventory(ply, index)
	local e = ply.GFR_Inv && ply.GFR_Inv[index]
	if !e or !e.wep then return end
	if ply:HasWeapon(e.class) then GFR.Notify(ply, "You're already carrying one of those.") return end
	local slot = GFR.SlotOfClass && GFR.SlotOfClass(e.class)
	local current = slot && GFR.WeaponInSlot && GFR.WeaponInSlot(ply, slot)
	if IsValid(current) then
		ply.GFR_Inv[index] = GFR.WeaponEntry(current)
		ply:StripWeapon(current:GetClass())
	else
		table.remove(ply.GFR_Inv, index)
	end
	local w = GFR.SpawnWeaponFromEntry(e, ply)
	if IsValid(w) then ply:SelectWeapon(e.class) end
	ply:EmitSound("items/ammo_pickup.wav", 60)
	Sync(ply)
end

-- Put a held gun into the bag
function GFR.StashWeapon(ply, wep)
	if !IsValid(wep) or wep:GetOwner() != ply then return false end
	if GFR.SpentOneUse && GFR.SpentOneUse(ply, wep) then return true end -- (used up: nothing to put away, sv_weapons.lua)
	if !GFR.InvAddEntry(ply, GFR.WeaponEntry(wep)) then
		GFR.Notify(ply, "No room in your bag.")
		return false
	end
	if ply:GetActiveWeapon() == wep then ply:SelectWeapon(GFR.Fists()) end
	ply:StripWeapon(wep:GetClass())
	ply:EmitSound("items/ammo_pickup.wav", 60)
	return true
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Bags: using a satchel/backpack straps it on for extra slots. Only one at a time; the old one goes back in
-- your inventory (or on the floor). It stays on your body when you die.
local function EquipBag(ply, class, bonus, name)
	local old = ply.GFR_BagClass
	if old == class then GFR.Notify(ply, "You're already wearing one.") return false end
	if old && (GFR.CustomItems[old].bag or 0) > bonus then GFR.Notify(ply, "Your current bag is bigger.") return false end
	ply.GFR_BagClass = class
	ply.GFR_BagBonus = bonus
	ply:SetNW2String("GFR_Bag", name)
	if old then
		local oldDef = GFR.CustomItems[old]
		if GFR.InvAdd(ply, old, 1, false, oldDef.model) == 0 then
			local ent = ents.Create(old)
			ent:SetPos(ply:GetPos() + ply:GetForward() * 30 + Vector(0, 0, 30))
			ent:Spawn()
		end
	end
	ply:EmitSound("physics/cardboard/cardboard_box_impact_soft" .. math.random(1, 7) .. ".wav")
	GFR.Notify(ply, "You strap on the " .. string.lower(name) .. ". +" .. bonus .. " slots.")
	timer.Simple(0, function() if IsValid(ply) then Sync(ply) end end)
	return true
end

function GFR.EquipSatchel(ply) return EquipBag(ply, "gfr_item_satchel", 5, "Satchel") end
function GFR.EquipBackpack(ply) return EquipBag(ply, "gfr_item_backpack", 10, "Backpack") end

-- Called from the Crunchy Use wrapper. Return true = handled (don't consume it).
function GFR.InvPickup(ply, ent, class)
	if !cvEnabled:GetBool() or ent.GFR_FromInventory or !Storable(class) then return false end
	local a = GFR.AmmoItems && GFR.AmmoItems[class]
	if a then
		-- Ammo: straight into your rounds, as many as you have room for; the rest stays on the ground
		local total = ent.GFR_AmmoAmount or a.amount
		local given = AmmoStraightIn(ply, class, total)
		if given >= total then
			ent:EmitSound("items/ammo_pickup.wav", 60)
			ent:Remove()
		elseif given > 0 then
			ent.GFR_AmmoAmount = total - given
		end
		return true
	end
	if GFR.InvAdd(ply, class, 1, ent.GFR_Contaminated, ent:GetModel()) == 0 then
		GFR.Notify(ply, "You can't carry any more.")
		return true
	end
	ent:EmitSound("items/itempickup.wav", 60)
	ent:Remove()
	local stored = scripted_ents.GetStored(class)
	GFR.Notify(ply, "+ " .. GFR.CleanName(stored && stored.t.PrintName or class))
	return true
end

function GFR.CleanName(name)
	name = string.gsub(name, "%s*%(%+*%d+%a*P%)", "") -- "(++10HP)", "(50AP)"
	local after = string.match(name, "^.-%s%-%s(.+)$")      -- "CTGN Food - Can O' Beans" -> "Can O' Beans"
	return after or name
end

local function Take(ply, index, amount)
	local e = ply.GFR_Inv[index]
	e.count = e.count - amount
	if e.count <= 0 then table.remove(ply.GFR_Inv, index) end
end

-- Remove `amount` of entry `index` and resync (trading, quests, robbery)
function GFR.InvTake(ply, index, amount)
	if !ply.GFR_Inv or !ply.GFR_Inv[index] then return end
	Take(ply, index, amount)
	Sync(ply)
end

-- Caps: the currency. Kept as a number, not an inventory item (takes no slot)
function GFR.GetCaps(ply)
	return ply:GetNW2Int("GFR_Caps", 0)
end

function GFR.AddCaps(ply, amount)
	ply:SetNW2Int("GFR_Caps", math.max(GFR.GetCaps(ply) + amount, 0))
end

local function DropItem(ply, e)
	local tr = util.TraceLine({start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * 60, filter = ply})
	if e.wep then
		-- A gun from the bag: on the ground with its magazine and parts, E to pick it back up
		GFR.SpawnWeaponFromEntry(e, nil, tr.HitPos + tr.HitNormal * 10)
		return
	end
	local ent = ents.Create(e.class)
	if !IsValid(ent) then return end
	ent:SetPos(tr.HitPos + tr.HitNormal * 8)
	ent:SetAngles(Angle(0, ply:EyeAngles().y, 0))
	ent:Spawn()
	ent:Activate()
	ent.GFR_Loot = true
	if e.contaminated then
		ent.GFR_Contaminated = true
		ent:SetColor(Color(190, 120, 115))
	end
	local phys = ent:GetPhysicsObject()
	if IsValid(phys) then phys:SetVelocity(ply:GetAimVector() * 80) end
end

local function UseItem(ply, index)
	local e = ply.GFR_Inv[index]
	if e.wep then GFR.EquipFromInventory(ply, index) return end
	local ent = ents.Create(e.class)
	if !IsValid(ent) then Take(ply, index, 1) return end
	ent:SetPos(ply:GetPos() + Vector(0, 0, 40))
	ent:Spawn()
	ent:SetNoDraw(true)
	ent:SetNotSolid(true)
	ent.GFR_FromInventory = true
	ent.GFR_Contaminated = e.contaminated or nil
	ent:Use(ply, ply, USE_ON, 1)
	if !IsValid(ent) or ent:IsMarkedForDeletion() then
		Take(ply, index, 1)
	else
		ent:Remove()
		-- Kits explain themselves (where to place it); materials are for crafting
		local cat = GFR.ItemCategory(e.class)
		if cat == "material" then
			GFR.Notify(ply, "That's a crafting material.")
		elseif cat != "deployable" && !(GFR.CustomItems[e.class] && (GFR.CustomItems[e.class].use or GFR.CustomItems[e.class].swep)) then
			GFR.Notify(ply, "You don't need that right now.")
		end
	end
end

net.Receive("GFR_InvAction", function(_, ply)
	if !IsValid(ply) or !ply:Alive() or ply.GFR_IsZombie then return end
	local action = net.ReadString()
	local index = net.ReadUInt(8)
	local inv = ply.GFR_Inv
	if (ply.GFR_NextInvAction or 0) > CurTime() then return end
	-- Past the real entries: one of your round stacks (Sync). Only putting them down.
	if index > #(inv or {}) then
		local st = RoundStacks(ply)[index - #(inv or {})]
		if !st or (action != "drop" && action != "dropall") then return end
		ply.GFR_NextInvAction = CurTime() + 0.25
		local n = action == "dropall" and ply:GetAmmoCount(st.ammo) or st.count
		ply:RemoveAmmo(n, st.ammo)
		DropRounds(ply, st.ammo, n)
		Sync(ply)
		return
	end
	local e = inv && inv[index]
	if !e then return end
	ply.GFR_NextInvAction = CurTime() + 0.25

	if action == "use" then
		UseItem(ply, index)
	elseif action == "drop" then
		DropItem(ply, e)
		Take(ply, index, 1)
	elseif action == "dropall" then
		for _ = 1, math.min(e.count, 20) do DropItem(ply, e) end
		table.remove(inv, index)
	elseif action == "scrap" then
		-- A gun from the bag broken down into parts, right from the inventory (sv_crafting.lua)
		if GFR.DismantleFromInventory then GFR.DismantleFromInventory(ply, index) end
		return
	end
	Sync(ply)
end)

-- Rounds that came in some other way (unloading a gun, a pickup that isn't ours) or a smaller bag: whatever's past
-- what the bag has room for drops at your feet. And the bag's round stacks follow
-- what you fire.
timer.Create("GFR_Inv_Rounds", 0.5, 0, function()
	if !cvEnabled:GetBool() then return end
	for _, ply in ipairs(player.GetAll()) do
		if !ply:Alive() or ply.GFR_IsZombie or !ply.GFR_Inv then continue end
		local sig = {}
		for _, r in ipairs(GFR.AmmoRules or {}) do
			local have = ply:GetAmmoCount(r.type)
			if have > 0 then
				local room = GFR.AmmoRoom(ply, r.type)
				if have > room then
					local extra = have - room
					ply:SetAmmo(room, r.type)
					DropRounds(ply, r.type, extra, ply:GetPos() + Vector(0, 0, 20) + ply:GetForward() * 20)
					GFR.Notify(ply, "Too much to carry: dropped " .. extra .. " " .. RoundsName(r.type) .. ".")
					have = room
				end
			end
			sig[#sig + 1] = have
		end
		sig = table.concat(sig, ",")
		if ply.GFR_RoundSig != sig then
			ply.GFR_RoundSig = sig
			Sync(ply)
		end
	end
end)

hook.Add("PlayerSpawn", "GFR_Inv_Spawn", function(ply)
	ply.GFR_Inv = {}
	ply.GFR_BagClass = nil
	ply.GFR_BagBonus = 0
	ply:SetNW2String("GFR_Bag", "")
	ply:SetNW2Int("GFR_Caps", 0)
	Sync(ply)
end)

concommand.Add("gfr_inv_clear", function(ply)
	if !IsValid(ply) then return end
	ply.GFR_Inv = {}
	Sync(ply)
end)

-- Testing (admins): gfr_give <item class> [count] puts it straight in your inventory, e.g. gfr_give gfr_item_hvial
concommand.Add("gfr_give", function(ply, _, args)
	if !IsValid(ply) or !GFR.CanCheat(ply) then return end
	local class = args[1]
	local count = math.Clamp(math.floor(tonumber(args[2] or "") or 1), 1, 100)
	if !class or class == "" then ply:PrintMessage(HUD_PRINTCONSOLE, "Usage: gfr_give <item class> [count]") return end
	local def = GFR.CustomItems && GFR.CustomItems[class]
	if !def && !scripted_ents.GetStored(class) then ply:PrintMessage(HUD_PRINTCONSOLE, "[GFR] No item called " .. class) return end
	local added = GFR.InvAdd(ply, class, count, false, def && def.model or nil)
	ply:PrintMessage(HUD_PRINTCONSOLE, string.format("[GFR] Gave %d / %d %s%s", added or 0, count, class,
		(added or 0) < count and " (no room for the rest)" or ""))
end, function(cmd, argStr)
	-- (tab-completes our own item classes)
	local out, q = {}, string.lower(string.Trim(argStr or ""))
	for class in pairs(GFR.CustomItems or {}) do
		if q == "" or string.find(class, q, 1, true) then out[#out + 1] = cmd .. " " .. class end
	end
	table.sort(out)
	return out
end, "Put an item in your inventory (admin): gfr_give <item class> [count]")
