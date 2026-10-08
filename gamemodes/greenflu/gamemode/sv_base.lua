--[[
	Custom Apocalypse - base building: storage, beds, lamps
	Placed from kits like the other deployables (sv_crafting.lua: GFR.PlaceDeployable calls GFR.SetupBaseProp).

	Storage (crate 12 slots, locker 24): E opens it next to your inventory, click to move whole stacks.
	                                     Must be empty before you can take it down (crouch+E).
	Bed (mat or bed): E rests (no longer tired) and makes it your respawn point. With gfr_timeskip 1 it opens
	                  "sleep until 08:00 / 18:00" instead: a vote of the living players (see Sleeping below). When
	                  time skips you get hungry/thirsty (slower than awake) and heal (a bed heals more).
	                  You can't sleep with enemies nearby, while bleeding, or while tied up.
	Lamp: a warm light that stays on.
	Base props can't be shot apart (barricades still can).
]]
util.AddNetworkString("GFR_Storage")
util.AddNetworkString("GFR_StorageAction")
util.AddNetworkString("GFR_SleepMenu")
util.AddNetworkString("GFR_Sleep")

local REACH = 130
local bedHeal = {[1] = 4, [2] = 9}       -- HP per hour slept
local bedDrain = {[1] = 0.6, [2] = 0.45}  -- hunger/thirst drain while asleep, vs. awake

function GFR.SetupBaseProp(ent, place)
	ent:SetNW2String("GFR_BaseName", place.name or "")
	if place.storage then
		ent.GFR_Storage = {}
		ent:SetNW2Int("GFR_StorageSlots", place.storage)
	elseif place.bed then
		ent:SetNW2Int("GFR_Bed", place.bed)
	elseif place.lamp then
		ent:SetNW2Bool("GFR_Lamp", true)
		local light = ents.Create("light_dynamic")
		light:SetPos(ent:GetPos() + Vector(0, 0, ent:OBBMaxs().z - 6))
		light:SetKeyValue("_light", "255 190 110 255")
		light:SetKeyValue("brightness", "3")
		light:SetKeyValue("distance", "420")
		light:SetKeyValue("style", "6") -- gentle flicker
		light:SetParent(ent)
		light:Spawn()
		light:Fire("TurnOn")
		ent:DeleteOnRemove(light)
	end
end

hook.Add("EntityTakeDamage", "GFR_Base_NoBreak", function(ent)
	if ent.GFR_Place && (ent.GFR_Storage or ent:GetNW2Int("GFR_Bed") > 0 or ent:GetNW2Bool("GFR_Lamp")) then return true end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Storage
local function Entry(e)
	return {class = e.class, count = e.count, contaminated = e.contaminated, model = e.model,
		cat = GFR.ItemCategory(e.class), stack = GFR.StackMax(e.class)}
end

local function SendStorage(ply, ent, open)
	local out = {}
	for i, e in ipairs(ent.GFR_Storage) do out[i] = Entry(e) end
	net.Start("GFR_Storage")
	net.WriteEntity(ent)
	net.WriteBool(open)
	net.WriteTable(out)
	net.Send(ply)
end

-- Same rules as the inventory: fill partial stacks, then new slots. Returns how many fit.
local function StorageAdd(ent, class, count, contaminated, model)
	local list, max = ent.GFR_Storage, GFR.StackMax(class)
	contaminated = contaminated or false
	local left = count
	for _, e in ipairs(list) do
		if left <= 0 then break end
		if e.class == class && e.contaminated == contaminated && e.count < max then
			local put = math.min(max - e.count, left)
			e.count = e.count + put
			left = left - put
		end
	end
	while left > 0 && #list < ent:GetNW2Int("GFR_StorageSlots", 0) do
		local put = math.min(max, left)
		list[#list + 1] = {class = class, count = put, contaminated = contaminated, model = model}
		left = left - put
	end
	return count - left
end

-- (and it's yours, or you're on its owner's access list: sv_owners.lua)
local function Allowed(ply, ent) return !GFR.CanUseOwned or GFR.CanUseOwned(ply, ent) end

local function InReach(ply, ent)
	return IsValid(ent) && ent.GFR_Storage && ply:Alive() && !ply.GFR_Tied && ply:EyePos():DistToSqr(ent:NearestPoint(ply:EyePos())) < (REACH + 20) ^ 2
		&& Allowed(ply, ent)
end

net.Receive("GFR_StorageAction", function(_, ply)
	local ent = net.ReadEntity()
	local action = net.ReadString()
	local index = net.ReadUInt(8)
	if !InReach(ply, ent) then return end
	if (ply.GFR_NextStorage or 0) > CurTime() then return end
	ply.GFR_NextStorage = CurTime() + 0.1

	local inv = ply.GFR_Inv or {}
	local takeRounds = action == "take" && ent.GFR_Storage[index] && string.match(ent.GFR_Storage[index].class, "^ammo:(.+)$")
	if action == "put" && index > #inv then
		-- One of your loose round stacks (listed after the real entries: sv_inventory.lua Sync)
		local st = GFR.RoundStacks(ply)[index - #inv]
		if !st then return end
		local moved = StorageAdd(ent, "ammo:" .. st.ammo, st.count, false, GFR.RoundModel(st.rule))
		if moved == 0 then GFR.Notify(ply, "It's full.") return end
		ply:RemoveAmmo(moved, st.ammo)
		GFR.InvSync(ply)
	elseif takeRounds then
		local e = ent.GFR_Storage[index]
		local moved = GFR.GiveRounds(ply, e.count, takeRounds)
		if moved == 0 then GFR.Notify(ply, "You can't carry any more.") return end
		e.count = e.count - moved
		if e.count <= 0 then table.remove(ent.GFR_Storage, index) end
		GFR.InvSync(ply)
	elseif action == "put" && inv[index] && inv[index].wep then
		-- A gun keeps its magazine and parts in storage
		if #ent.GFR_Storage >= ent:GetNW2Int("GFR_StorageSlots", 0) then GFR.Notify(ply, "It's full.") return end
		ent.GFR_Storage[#ent.GFR_Storage + 1] = table.Copy(ply.GFR_Inv[index])
		GFR.InvTake(ply, index, 1)
	elseif action == "take" && ent.GFR_Storage[index] && ent.GFR_Storage[index].wep then
		if !GFR.InvAddEntry(ply, ent.GFR_Storage[index]) then GFR.Notify(ply, "You can't carry any more.") return end
		table.remove(ent.GFR_Storage, index)
	elseif action == "put" then
		local e = ply.GFR_Inv && ply.GFR_Inv[index]
		if !e then return end
		local moved = StorageAdd(ent, e.class, e.count, e.contaminated, e.model)
		if moved == 0 then GFR.Notify(ply, "It's full.") return end
		GFR.InvTake(ply, index, moved)
	elseif action == "take" then
		local e = ent.GFR_Storage[index]
		if !e then return end
		local moved = GFR.InvAdd(ply, e.class, e.count, e.contaminated, e.model)
		if moved == 0 then GFR.Notify(ply, "You can't carry any more.") return end
		e.count = e.count - moved
		if e.count <= 0 then table.remove(ent.GFR_Storage, index) end
		GFR.InvSync(ply)
	end
	ent:EmitSound(ent.GFR_Place.material == "metal" and "physics/metal/metal_box_impact_soft" .. math.random(1, 3) .. ".wav" or "physics/wood/wood_box_impact_soft" .. math.random(1, 3) .. ".wav", 55)
	SendStorage(ply, ent, false)
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Sleeping
local function EnemyNearby(ply)
	for _, npc in ipairs(ents.FindInSphere(ply:GetPos(), 900)) do
		if npc:IsNPC() && npc:Health() > 0 && (GFR.IsZombie(npc) or npc:Disposition(ply) == D_HT) then return true end
	end
	return false
end

local function CanSleep(ply, bed)
	if !IsValid(bed) or bed:GetNW2Int("GFR_Bed") <= 0 or !ply:Alive() or ply.GFR_IsZombie or ply.GFR_Tied or ply.GFR_Sleeping then return false end
	if ply:EyePos():DistToSqr(bed:NearestPoint(ply:EyePos())) > (REACH + 20) ^ 2 then return false end
	if !Allowed(ply, bed) then GFR.Notify(ply, "That's " .. bed:GetNW2String("GFR_OwnerName", "someone else") .. "'s bed.") return false end
	if ply.GFR_Bleeding then GFR.Notify(ply, "You're bleeding. Patch yourself up first.") return false end
	if EnemyNearby(ply) then GFR.Notify(ply, "You can't sleep with enemies nearby.") return false end
	return true
end

-- Skipping time is off by default: a bed is somewhere to rest (no longer tired) and to wake up after dying.
-- With gfr_timeskip 1 the bed offers "sleep until 08:00 / 18:00": you lie down and wait, and once enough of the living
-- players (gfr_timeskip_pct %, players' zombies don't count) want the same hour, the clock jumps there for everyone.
-- Alone, that's just you.
local cvSkip = CreateConVar("gfr_timeskip", "0", bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED), "Sleeping in a bed can skip time (to 08:00 or 18:00, by vote)")
local cvSkipPct = CreateConVar("gfr_timeskip_pct", "75", bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED), "% of living players who must choose the same hour to skip to it")
GFR.SkipChoices = {8, 18} -- (cl_base.lua shows the same two)

-- What happened to you while you were out
local function WakeUp(ply, hours)
	local bed = ply.GFR_SleepBed
	local quality = IsValid(bed) and bed:GetNW2Int("GFR_Bed") or 1
	ply.GFR_Sleeping = nil
	ply.GFR_SleepBed = nil
	ply:SetNW2Int("GFR_SleepVote", 0)
	ply:Freeze(false)
	ply:ScreenFade(SCREENFADE.IN, color_black, 2, 0)
	if GFR.SleptWell then GFR.SleptWell(ply) end -- (rested, not tired any more: sh_status.lua)
	if hours <= 0 then GFR.Notify(ply, "You rest a while. You'll wake up here if you die.") return end

	local realSecs = hours * GFR.RealSecondsPerHour()
	local drain = bedDrain[quality] or 0.6
	local hungerMins = GetConVar("gfr_hunger_minutes"):GetFloat()
	local thirstMins = GetConVar("gfr_thirst_minutes"):GetFloat()
	ply:SetNW2Float("GFR_Hunger", math.max(ply:GetNW2Float("GFR_Hunger", 100) - 100 / math.max(hungerMins * 60, 1) * realSecs * drain, 0))
	ply:SetNW2Float("GFR_Thirst", math.max(ply:GetNW2Float("GFR_Thirst", 100) - 100 / math.max(thirstMins * 60, 1) * realSecs * drain, 0))
	ply:SetNW2Float("GFR_Stamina", 100)
	ply:SetNW2Bool("GFR_Exhausted", false)
	local starving = ply:GetNW2Float("GFR_Hunger") <= 0 or ply:GetNW2Float("GFR_Thirst") <= 0
	if !starving then
		ply:SetHealth(math.min(ply:Health() + math.Round((bedHeal[quality] or 4) * hours), ply:GetMaxHealth()))
	end

	-- The infection doesn't sleep
	local worse = false
	if ply.GFR_Inf && ply.GFR_Inf > 0 then
		local rate = 100 / math.max(GetConVar("gfr_infection_minutes"):GetFloat() * 60, 1)
		local suppressed = CurTime() < (ply.GFR_SuppressUntil or 0)
		ply.GFR_Inf = math.min(ply.GFR_Inf + rate * realSecs * (suppressed and 0.2 or 1), 99)
		worse = true
	end

	local whole = math.max(math.Round(hours), 1)
	local msg = string.format("You slept %d hour%s.", whole, whole == 1 and "" or "s")
	if starving then msg = msg .. " You woke up starving."
	elseif worse then msg = msg .. " You wake up feverish..."
	else msg = msg .. " You feel rested." end
	GFR.Notify(ply, msg)
end

local function LieDown(ply, bed)
	ply.GFR_Sleeping = true
	ply.GFR_SleepBed = bed
	ply.GFR_SpawnBed = bed
	ply:Freeze(true)
	ply:EmitSound("player/breathe1.wav", 50, 80)
end

-- Gfr_timeskip off: a short rest, no time passes
local function Rest(ply, bed)
	LieDown(ply, bed)
	ply:ScreenFade(SCREENFADE.OUT, color_black, 1.5, 2.5)
	timer.Simple(3, function()
		if !IsValid(ply) or !ply.GFR_Sleeping then return end
		if !ply:Alive() then ply.GFR_Sleeping = nil ply:Freeze(false) return end
		WakeUp(ply, 0)
	end)
end

-- Who gets a say: living players who aren't zombies
local function Voters()
	local n = 0
	for _, p in ipairs(player.GetAll()) do
		if p:Alive() && !p.GFR_IsZombie then n = n + 1 end
	end
	return n
end

local function Tally()
	local counts = {}
	for i = 1, #GFR.SkipChoices do counts[i] = 0 end
	for _, p in ipairs(player.GetAll()) do
		local v = p:GetNW2Int("GFR_SleepVote", 0)
		if v > 0 then
			-- Died, turned or got off the bed: their vote is gone
			if !p:Alive() or p.GFR_IsZombie or !p.GFR_Sleeping then
				p:SetNW2Int("GFR_SleepVote", 0)
				p.GFR_Sleeping = nil
				p.GFR_SleepBed = nil
				p:Freeze(false)
			else
				counts[v] = counts[v] + 1
			end
		end
	end
	local voters = math.max(Voters(), 1)
	for i, c in ipairs(counts) do
		SetGlobal2Int("GFR_SleepVotes" .. i, c)
	end
	SetGlobal2Int("GFR_SleepVoters", voters)
	for i, c in ipairs(counts) do
		if c > 0 && c / voters * 100 >= cvSkipPct:GetFloat() - 0.01 then
			local hours = (GFR.SkipChoices[i] - GFR.Hour()) % 24
			if hours < 0.1 then hours = hours + 24 end
			GFR.SkipHours(hours)
			-- Everyone in bed wakes up to it, whichever hour they wanted
			for _, p in ipairs(player.GetAll()) do
				if p:GetNW2Int("GFR_SleepVote", 0) > 0 then WakeUp(p, hours) end
			end
			for j = 1, #GFR.SkipChoices do SetGlobal2Int("GFR_SleepVotes" .. j, 0) end
			return
		end
	end
end
timer.Create("GFR_SleepVote", 1, 0, Tally)

net.Receive("GFR_Sleep", function(_, ply)
	local bed = net.ReadEntity()
	local choice = net.ReadUInt(2)
	if !CanSleep(ply, bed) then return end
	if !cvSkip:GetBool() or !GFR.SkipChoices[choice] then Rest(ply, bed) return end
	LieDown(ply, bed)
	ply:SetNW2Int("GFR_SleepVote", choice) -- (cl_base.lua darkens the screen and shows the count while you wait)
	Tally()
end)

-- Waiting in bed: jump to get up again
hook.Add("KeyPress", "GFR_Base_GetUp", function(ply, key)
	if key == IN_JUMP && ply:GetNW2Int("GFR_SleepVote", 0) > 0 then
		ply:SetNW2Int("GFR_SleepVote", 0)
		ply.GFR_Sleeping = nil
		ply.GFR_SleepBed = nil
		ply:Freeze(false)
		Tally()
	end
end)

-- Wake up at your bed after dying
hook.Add("PlayerSpawn", "GFR_Base_BedSpawn", function(ply)
	local bed = ply.GFR_SpawnBed
	if !IsValid(bed) then return end
	timer.Simple(0, function()
		if !IsValid(ply) or !IsValid(bed) or !ply:Alive() then return end
		local center = bed:WorldSpaceCenter()
		local mins, maxs = ply:OBBMins(), ply:OBBMaxs()
		for _, dir in ipairs({bed:GetRight(), -bed:GetRight(), bed:GetForward(), -bed:GetForward()}) do
			local pos = center + dir * 50
			local tr = util.TraceLine({start = pos + Vector(0, 0, 40), endpos = pos - Vector(0, 0, 100), filter = bed, mask = MASK_PLAYERSOLID})
			if tr.Hit then
				local hull = util.TraceHull({start = tr.HitPos + Vector(0, 0, 2), endpos = tr.HitPos + Vector(0, 0, 2), mins = mins, maxs = maxs, filter = ply, mask = MASK_PLAYERSOLID})
				if !hull.Hit then
					ply:SetPos(tr.HitPos + Vector(0, 0, 2))
					return
				end
			end
		end
	end)
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- E on a storage box or bed
hook.Add("KeyPress", "GFR_Base_Use", function(ply, key)
	if key != IN_USE or !ply:Alive() or ply.GFR_IsZombie or ply.GFR_Tied or ply:Crouching() or ply:KeyDown(IN_SPEED) then return end
	local tr = util.TraceLine({start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * REACH, filter = ply})
	local ent = tr.Entity
	if !IsValid(ent) or !ent.GFR_Place then return end
	if ent.GFR_Storage then
		if !Allowed(ply, ent) then
			GFR.Notify(ply, "It's locked. It belongs to " .. ent:GetNW2String("GFR_OwnerName", "someone else") .. ".")
			return
		end
		ent:EmitSound(ent.GFR_Place.material == "metal" and "doors/door_metal_medium_open1.wav" or "physics/wood/wood_crate_impact_soft2.wav", 60)
		SendStorage(ply, ent, true)
	elseif ent:GetNW2Int("GFR_Bed") > 0 then
		if !cvSkip:GetBool() then
			if CanSleep(ply, ent) then Rest(ply, ent) end
			return
		end
		net.Start("GFR_SleepMenu")
		net.WriteEntity(ent)
		net.Send(ply)
	end
end)
