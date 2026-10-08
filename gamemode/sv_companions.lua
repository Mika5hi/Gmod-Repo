--[[
	Custom Apocalypse - companions
	Talk to a survivor (E) and ask them to join you. They come along for caps, or for free if you've done a job for
	their group. Up to gfr_companion_max at once.
	E on a companion opens their window (cl_companions.lua):
		Orders     Follow me / Hold this position / Part ways
		Weapon     see what they carry, take it, hand them one of yours (carried or from your bag), give them ammo
		Pockets    6 slots: hand them items or take them back. Medical items get used on themselves when they're hurt.
	Crouch + E on a companion: quick toggle between follow and hold.
	They fight for you (bandits and zombies are their enemies too), don't turn on you over a stray shot, keep their gun
	slung when they run dry (sv_spawner.lua) and leave what's in their pockets on their body when they die.
	Server: this file. Spawner groups: sv_spawner.lua. Dialog option: sv_npc.lua / cl_npc.lua.
]]
util.AddNetworkString("GFR_Comp")
util.AddNetworkString("GFR_CompAction")

local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY)
local cvMax  = CreateConVar("gfr_companion_max", "3", flags, "Most companions you can have at once")
local cvCost = CreateConVar("gfr_companion_cost", "40", flags, "Caps a survivor wants to join you (free if you've done a job for their group)")

local POCKETS = 6
local RANGE = 200

local names = {
	"Alex", "Sam", "Jordan", "Casey", "Riley", "Morgan", "Taylor", "Jamie", "Quinn", "Avery", "Drew", "Robin", "Kai", "Sasha",
	"Nico", "Dana", "Lee", "Max", "Charlie", "Frankie", "Jesse", "Rowan", "Sky", "Toni", "Ellis", "Reese", "Marlo", "Shay"
}

local comps = {} -- [npc] = owner

function GFR.Companions(ply)
	local list = {}
	for npc, owner in pairs(comps) do
		if IsValid(npc) && owner == ply then list[#list + 1] = npc end
	end
	return list
end

local function Say(npc, text) if GFR.Say then GFR.Say(npc, text) end end
local function Name(npc) return npc:GetNW2String("GFR_Name", "Your companion") end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Recruiting
-- What the dialog offers: nil (they won't), or {cost = caps}
function GFR.RecruitOffer(ply, npc)
	local g = npc.GFR_Group
	if !g or g.faction != "survivor" or g.companion or npc.GFR_LostQuest then return end
	if #GFR.Companions(ply) >= cvMax:GetInt() then return end
	return {cost = (g.helped && g.helped[ply]) and 0 or cvCost:GetInt()}
end

local function SetOrder(npc, order)
	npc.GFR_Order = order
	npc:SetNW2String("GFR_Order", order)
	if order == "stay" then
		npc.GFR_HoldPos = npc:GetPos()
		npc:SetSchedule(SCHED_IDLE_STAND)
	end
end

function GFR.Recruit(ply, npc)
	local offer = GFR.RecruitOffer(ply, npc)
	if !offer then return "Sorry. I'm staying with my people." end
	if offer.cost > 0 then
		if GFR.GetCaps(ply) < offer.cost then return "Out here nobody works for free. " .. offer.cost .. " caps and I'm yours." end
		GFR.AddCaps(ply, -offer.cost)
	end
	-- A group of their own, attached to you: friendly to you, enemies with bandits and the dead
	local group = {faction = "survivor", squad = "gfr_comp_" .. ply:EntIndex(), members = {}, attitude = D_LI, hostileTo = {}, truce = {}, keep = true, companion = ply}
	for _, other in ipairs(GFR.Companions(ply)) do
		if other.GFR_Group then group = other.GFR_Group break end -- all your people in one squad
	end
	GFR.Spawner.JoinGroup(npc, group)
	comps[npc] = ply
	npc.GFR_CompanionOf = ply
	npc.GFR_CompItems = npc.GFR_CompItems or {}
	npc.GFR_LootProfile = nil
	npc:SetNW2Entity("GFR_CompOwner", ply)
	npc:SetNW2String("GFR_Name", names[math.random(#names)])
	npc:SetNW2Int("GFR_HP", npc:Health())
	npc:SetNW2Int("GFR_MaxHP", npc:GetMaxHealth())
	SetOrder(npc, "follow")
	GFR.Notify(ply, Name(npc) .. " joins you. (E on them: orders and gear, Crouch+E: follow / hold)")
	return "Alright. Lead the way, I've got your back."
end

-- Leaving: back to being a neutral survivor on their own
local function Dismiss(npc)
	local owner = comps[npc]
	comps[npc] = nil
	npc.GFR_CompanionOf = nil
	npc:SetNW2Entity("GFR_CompOwner", NULL)
	npc:SetNW2String("GFR_Order", "")
	local groups = GFR.Spawner.Groups()
	local group = {faction = "survivor", squad = "gfr_left_" .. npc:EntIndex(), members = {}, attitude = D_NU, hostileTo = {}, truce = {}}
	groups[#groups + 1] = group
	GFR.Spawner.JoinGroup(npc, group)
	npc.GFR_LootProfile = "survivor"
	Say(npc, "Take care of yourself out there.")
	if IsValid(owner) then GFR.Notify(owner, Name(npc) .. " goes their own way.") end
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Inventory helpers
local function NPCWeapon(npc)
	local w = npc.GFR_Weapon
	if IsValid(w) && w:GetOwner() == npc && w:GetClass() != "weapon_crowbar" then return w end -- (the crowbar is their fallback)
	w = npc:GetActiveWeapon()
	if IsValid(w) && w:GetClass() != "weapon_crowbar" then return w end
end

local function CanNPCUse(class)
	local t = weapons.GetStored(class)
	if !t then return false end
	if t.NotForNPCs or GFR.IsFists(class) then return false end
	if string.StartWith(class, "weapon_eft_") or string.StartWith(class, "weapon_stalker2_") or string.StartWith(class, "weapon_scpsl_") then return false end
	local slot = GFR.WeaponSlot && GFR.WeaponSlot(class)
	return slot == "primary" or slot == "secondary"
end

local function ClipSize(w)
	local c = IsValid(w) && w:GetMaxClip1() or 0
	if c <= 0 then
		local t = weapons.Get(w:GetClass())
		c = t && (t.ClipSize or (t.Primary && t.Primary.ClipSize)) or 0
	end
	return math.max(c, 1)
end

-- Their gun goes into your bag (with what's left of their spare mags as your ammo)
local function TakeWeapon(ply, npc)
	local w = NPCWeapon(npc)
	if !w then return false, "They're not carrying a gun." end
	if !GFR.InvAddEntry(ply, GFR.WeaponEntry(w)) then return false, "No room in your bag." end
	local mags = npc.GFR_Mags or 0
	local ammoType = w:GetPrimaryAmmoType()
	if mags > 0 && ammoType >= 0 then ply:GiveAmmo(mags * ClipSize(w), ammoType) end
	npc.GFR_Weapon = nil
	npc.GFR_Mags = nil
	npc.GFR_LastClip = nil
	npc.GFR_OutOfAmmo = nil
	w:Remove()
	if npc:HasWeapon("weapon_crowbar") then npc:SelectWeapon("weapon_crowbar") end
	return true
end

local function GiveWeapon(ply, npc, source)
	local entry, removeFn
	local kind, ref = string.match(source, "^(%a+):(.+)$")
	if kind == "inv" then
		local i = tonumber(ref)
		local e = i && ply.GFR_Inv && ply.GFR_Inv[i]
		if !e or !e.wep then return false end
		entry = table.Copy(e)
		removeFn = function() GFR.InvTake(ply, i, 1) end
	elseif kind == "held" then
		local w = ply:GetWeapon(ref)
		if !IsValid(w) then return false end
		entry = GFR.WeaponEntry(w)
		removeFn = function()
			if ply:GetActiveWeapon() == w then ply:SelectWeapon(GFR.Fists()) end
			ply:StripWeapon(ref)
		end
	else
		return false
	end
	if !CanNPCUse(entry.class) then return false, "They can't use that. Give them a gun." end
	-- Swapping: what they had goes into your bag first
	if NPCWeapon(npc) then
		local ok, why = TakeWeapon(ply, npc)
		if !ok then return false, why end
	end
	removeFn()
	local w = npc:Give(entry.class)
	if !IsValid(w) then return false, "They couldn't take it." end
	local data = entry.wep or {}
	GFR.ApplyWeaponState(w, data.clip1, nil, data.atts)
	npc:SelectWeapon(entry.class)
	npc.GFR_Weapon = w
	npc.GFR_Mags = 0
	npc.GFR_LastClip = nil
	npc.GFR_OutOfAmmo = nil
	Say(npc, "Nice. I'll put it to good use.")
	return true
end

-- One magazine's worth, from your reserve ammo or an ammo item in your bag
local function GiveAmmo(ply, npc)
	local w = NPCWeapon(npc)
	if !w then return false, "They don't have a gun to load." end
	local ammoType = w:GetPrimaryAmmoType()
	if ammoType < 0 then return false, "That gun doesn't take ammo." end
	local clip = ClipSize(w)
	local have = ply:GetAmmoCount(ammoType)
	local given = 0
	if have > 0 then
		given = math.min(clip, have)
		ply:RemoveAmmo(given, ammoType)
	else
		-- An ammo box in the bag that fits
		local typeName = string.lower(game.GetAmmoName(ammoType) or "")
		for i, e in ipairs(ply.GFR_Inv or {}) do
			local a = GFR.AmmoItems && GFR.AmmoItems[e.class]
			if a && string.lower(a.type) == typeName then
				given = a.amount
				GFR.InvTake(ply, i, 1)
				break
			end
		end
	end
	if given <= 0 then return false, "You don't have any " .. (game.GetAmmoName(ammoType) or "ammo") .. " for their gun." end
	npc.GFR_Mags = (npc.GFR_Mags or 0) + math.max(math.floor(given / clip + 0.5), 1)
	if npc.GFR_OutOfAmmo then
		npc.GFR_OutOfAmmo = nil
		npc.GFR_LastClip = nil
		npc:SelectWeapon(w:GetClass())
	end
	Say(npc, "Thanks, I was running low.")
	return true
end

local function StackMax(class) return GFR.StackMax and GFR.StackMax(class) or 5 end

local function PocketAdd(npc, e)
	local items = npc.GFR_CompItems
	local max = StackMax(e.class)
	for _, it in ipairs(items) do
		if it.class == e.class && (it.contaminated or false) == (e.contaminated or false) && it.count < max then
			it.count = it.count + 1
			return true
		end
	end
	if #items >= POCKETS then return false end
	items[#items + 1] = {class = e.class, count = 1, contaminated = e.contaminated, model = e.model}
	return true
end

-- How much a medical item heals them (they don't have our status effects, just health)
local function HealAmount(class)
	if GFR.Medkits && GFR.Medkits[class] then return 60 end
	if string.find(class, "medkit", 1, true) or string.find(class, "afak", 1, true) or string.find(class, "surgical", 1, true) or string.find(class, "aid", 1, true) then return 60 end
	if GFR.ItemCategory(class) == "medical" then return 25 end
end

local function UseMed(npc, index)
	local it = npc.GFR_CompItems[index]
	local heal = it && HealAmount(it.class)
	if !heal then return false end
	npc:SetHealth(math.min(npc:Health() + heal, npc:GetMaxHealth()))
	it.count = it.count - 1
	if it.count <= 0 then table.remove(npc.GFR_CompItems, index) end
	npc:EmitSound("items/medshot4.wav", 65)
	return true
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- The window
local function SendComp(ply, npc)
	local w = NPCWeapon(npc)
	local wep = false
	if w then
		local ammoType = w:GetPrimaryAmmoType()
		wep = {
			class = w:GetClass(), clip = w:Clip1(), mags = npc.GFR_Mags or 0, out = npc.GFR_OutOfAmmo or false,
			ammo = ammoType >= 0 and (game.GetAmmoName(ammoType) or "") or "", have = ammoType >= 0 and ply:GetAmmoCount(ammoType) or 0
		}
	end
	local myWeps = {}
	for _, pw in ipairs(ply:GetWeapons()) do
		local c = pw:GetClass()
		if CanNPCUse(c) then myWeps[#myWeps + 1] = {src = "held:" .. c, class = c, clip = pw:Clip1(), where = "carried"} end
	end
	local myItems = {}
	for i, e in ipairs(ply.GFR_Inv or {}) do
		if e.wep then
			if CanNPCUse(e.class) then myWeps[#myWeps + 1] = {src = "inv:" .. i, class = e.class, clip = e.wep.clip1 or 0, where = "in bag"} end
		else
			myItems[#myItems + 1] = {index = i, class = e.class, count = e.count, model = e.model, contaminated = e.contaminated, heal = HealAmount(e.class) or 0}
		end
	end
	net.Start("GFR_Comp")
	net.WriteEntity(npc)
	net.WriteTable({
		name = Name(npc), hp = npc:Health(), maxhp = npc:GetMaxHealth(), order = npc.GFR_Order or "follow",
		wep = wep, pockets = npc.GFR_CompItems or {}, slots = POCKETS, myWeps = myWeps, myItems = myItems
	})
	net.Send(ply)
end

function GFR.OpenCompanion(ply, npc)
	if comps[npc] != ply then return end
	npc:SetIdealYawAndUpdate((ply:GetPos() - npc:GetPos()):Angle().y)
	SendComp(ply, npc)
end

net.Receive("GFR_CompAction", function(_, ply)
	local npc = net.ReadEntity()
	local action = net.ReadString()
	local arg = net.ReadString()
	if !IsValid(npc) or comps[npc] != ply or !ply:Alive() or npc:Health() <= 0 then return end
	if npc:GetPos():DistToSqr(ply:GetPos()) > (RANGE + 100) ^ 2 then return end
	if (ply.GFR_NextCompAction or 0) > CurTime() then return end
	ply.GFR_NextCompAction = CurTime() + 0.2

	local ok, why = true, nil
	if action == "follow" then
		SetOrder(npc, "follow")
		Say(npc, "Right behind you.")
	elseif action == "stay" then
		SetOrder(npc, "stay")
		Say(npc, "I'll hold here.")
	elseif action == "dismiss" then
		Dismiss(npc)
		net.Start("GFR_Comp") net.WriteEntity(NULL) net.WriteTable({}) net.Send(ply) -- closes the window
		return
	elseif action == "takewep" then
		ok, why = TakeWeapon(ply, npc)
	elseif action == "givewep" then
		ok, why = GiveWeapon(ply, npc, arg)
	elseif action == "giveammo" then
		ok, why = GiveAmmo(ply, npc)
	elseif action == "giveitem" then
		local i = tonumber(arg)
		local e = i && ply.GFR_Inv && ply.GFR_Inv[i]
		if !e or e.wep then return end
		-- Hurt and it's medicine: they use it straight away
		local heal = HealAmount(e.class)
		if heal && npc:Health() < npc:GetMaxHealth() then
			npc:SetHealth(math.min(npc:Health() + heal, npc:GetMaxHealth()))
			npc:EmitSound("items/medshot4.wav", 65)
			Say(npc, "That's better. Thank you.")
			GFR.InvTake(ply, i, 1)
		elseif PocketAdd(npc, e) then
			GFR.InvTake(ply, i, 1)
		else
			ok, why = false, "Their pockets are full."
		end
	elseif action == "takeitem" then
		local i = tonumber(arg)
		local it = i && npc.GFR_CompItems[i]
		if !it then return end
		if GFR.InvAdd(ply, it.class, 1, it.contaminated, it.model) == 0 then
			ok, why = false, "No room in your bag."
		else
			it.count = it.count - 1
			if it.count <= 0 then table.remove(npc.GFR_CompItems, i) end
		end
	else
		return
	end
	if !ok && why then GFR.Notify(ply, why) end
	if ok then ply:EmitSound("items/ammo_pickup.wav", 55) end
	SendComp(ply, npc)
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- E on a companion opens their window (sv_npc.lua calls this); Crouch+E flips follow / hold
hook.Add("KeyPress", "GFR_Comp_QuickOrder", function(ply, key)
	if key != IN_USE or !ply:Crouching() or !ply:Alive() then return end
	local tr = util.TraceLine({start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * RANGE, filter = ply, mask = MASK_SHOT})
	local npc = tr.Entity
	if !IsValid(npc) or comps[npc] != ply then return end
	if npc.GFR_Order == "stay" then
		SetOrder(npc, "follow")
		Say(npc, "Coming.")
	else
		SetOrder(npc, "stay")
		Say(npc, "Holding here.")
	end
	ply.GFR_CompQuickT = CurTime()
end)

-- Being shot by your own people still hurts, a lot less
hook.Add("EntityTakeDamage", "GFR_Comp_FriendlyFire", function(target, dmg)
	local att = dmg:GetAttacker()
	if target.GFR_CompanionOf && IsValid(att) && att:IsPlayer() && att == target.GFR_CompanionOf then dmg:ScaleDamage(0.25) end
	-- ...and they don't shoot you
	if target:IsPlayer() && IsValid(att) && att.GFR_CompanionOf == target then return true end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Following, holding, patching themselves up
local function FreeSpotBehind(ply)
	for _ = 1, 10 do
		local ang = ply:EyeAngles().y + 180 + math.Rand(-70, 70)
		local p = ply:GetPos() + Angle(0, ang, 0):Forward() * math.Rand(80, 160)
		local down = util.TraceLine({start = p + Vector(0, 0, 40), endpos = p - Vector(0, 0, 100), mask = MASK_NPCSOLID_BRUSHONLY})
		if down.Hit then
			local hull = util.TraceHull({start = down.HitPos + Vector(0, 0, 4), endpos = down.HitPos + Vector(0, 0, 8), mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 72), mask = MASK_NPCSOLID})
			if !hull.Hit then return down.HitPos end
		end
	end
end

local function Seen(ply, pos)
	return !util.TraceLine({start = ply:EyePos(), endpos = pos + Vector(0, 0, 40), mask = MASK_VISIBLE}).Hit
		&& ply:GetAimVector():Dot((pos - ply:EyePos()):GetNormalized()) > 0.5
end

timer.Create("GFR_Companions_Think", 0.5, 0, function()
	local now = CurTime()
	for npc, ply in pairs(comps) do
		if !IsValid(npc) or npc:Health() <= 0 then comps[npc] = nil continue end
		if npc:GetNW2Int("GFR_HP") != npc:Health() then npc:SetNW2Int("GFR_HP", npc:Health()) end
		if !IsValid(ply) then continue end

		-- Hurt: use something from their pockets
		if npc:Health() < npc:GetMaxHealth() * 0.5 && (npc.GFR_NextHeal or 0) < now then
			for i, it in ipairs(npc.GFR_CompItems or {}) do
				if HealAmount(it.class) && UseMed(npc, i) then
					Say(npc, "Patching myself up!")
					npc.GFR_NextHeal = now + 8
					break
				end
			end
		end

		if !ply:Alive() then continue end -- you're down: they stay put
		local enemy = npc:GetEnemy()
		local fighting = IsValid(enemy) && enemy:Health() > 0
		if npc.GFR_Order == "follow" then
			local d = npc:GetPos():Distance(ply:GetPos())
			if d > 2500 && !Seen(ply, npc:GetPos()) then
				-- Lost them: catch up out of sight
				local spot = FreeSpotBehind(ply)
				if spot && !Seen(ply, spot) then npc:SetPos(spot) end
			elseif d > 170 && (!fighting or d > 700) && (npc.GFR_NextMove or 0) < now then
				npc:SetLastPosition(ply:GetPos() - ply:GetAimVector() * Vector(1, 1, 0) * 70)
				npc:SetSchedule(d > 420 and SCHED_FORCED_GO_RUN or SCHED_FORCED_GO)
				npc.GFR_NextMove = now + (d > 420 and 0.8 or 1.5)
			end
		elseif npc.GFR_Order == "stay" && npc.GFR_HoldPos then
			if !fighting && npc:GetPos():DistToSqr(npc.GFR_HoldPos) > 120 * 120 && (npc.GFR_NextMove or 0) < now then
				npc:SetLastPosition(npc.GFR_HoldPos)
				npc:SetSchedule(SCHED_FORCED_GO_RUN)
				npc.GFR_NextMove = now + 2
			end
		end
	end
end)

-- Dead: you're told, a gun they had slung (out of ammo) drops too; their pockets stay on the body (sv_loot.lua)
hook.Add("OnNPCKilled", "GFR_Comp_Death", function(npc)
	local ply = comps[npc]
	if !ply then return end
	comps[npc] = nil
	local w = npc.GFR_Weapon
	if npc.GFR_OutOfAmmo && IsValid(w) && w:GetOwner() == npc then
		GFR.SpawnWeaponFromEntry(GFR.WeaponEntry(w), nil, npc:GetPos() + Vector(0, 0, 30))
	end
	if IsValid(ply) then GFR.Notify(ply, Name(npc) .. " is dead.") end
end)

hook.Add("PostCleanupMap", "GFR_Comp_Cleanup", function() comps = {} end)
