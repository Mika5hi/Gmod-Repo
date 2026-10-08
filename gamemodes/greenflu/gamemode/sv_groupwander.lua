--[[
	Custom Apocalypse - human groups get on with their lives
	Survivor / bandit / military groups (sv_spawner.lua) don't just stand where they spawned: they move around together,
	scavenging. The leader picks a nearby container nobody has searched (or, with none around, somewhere to look),
	the group walks there, one of them goes through it (you hear the rummaging), then they rest a while and move on.
	What they find is theirs: the container counts as searched (it refills like any other: gfr_loot_refresh_hours), and
	it's in their pockets if they die (sv_loot.lua GFR_Scavenged).
	They stay put while busy: fighting, holding you up / tying you, warning you off, giving quests (they wait for you),
	being your companions, heading for a supply drop, or when you're right there with them (talking, trading).
	Not inside a claimed base (sh_claim.lua), and not to a container you're standing at.
]]
local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY)
local cvEnabled = CreateConVar("gfr_groups_wander", "1", flags, "Human groups move around and scavenge containers")
local cvRest    = CreateConVar("gfr_groups_rest", "40", flags, "Average seconds a group rests between moves")

local TICK = 1
local NEAR_PLAYER = 300     -- you're with them (talking, trading): they stay
local ACTIVE_RANGE = 4500   -- groups further from every player than this aren't worth moving

local lines = {
	go = {
		survivor = {"Let's keep moving.", "Come on, there might be something over there.", "We can't stay here."},
		bandit = {"Move it. Plenty more to take.", "Let's go shopping.", "Come on, boys."},
		military = {"Move out.", "Next sector. Let's go.", "On me. Moving."}},
	search = {
		survivor = {"Check this one.", "Anything in there?", "Let me look..."},
		bandit = {"Grab everything.", "Mine.", "Let's see what we got."},
		military = {"Searching.", "Checking supplies.", "Inventory this."}},
	found = {
		survivor = {"Found something.", "Got it."}, bandit = {"Score.", "Nice."}, military = {"Supplies recovered."}},
	empty = {
		survivor = {"Nothing.", "Picked clean."}, bandit = {"Empty. Figures."}, military = {"Negative. Empty."}}
}

local function Say(g, kind, npc)
	local t = lines[kind] && lines[kind][g.faction]
	if !t or !GFR.Say or !IsValid(npc) or math.random(3) == 1 then return end -- (not every time)
	GFR.Say(npc, t[math.random(#t)])
end

local function Alive(m) return IsValid(m) && m:Health() > 0 end

local function Members(g)
	local list = {}
	for _, m in ipairs(g.members) do if Alive(m) then list[#list + 1] = m end end
	return list
end

local function Center(list)
	local sum = Vector(0, 0, 0)
	for _, m in ipairs(list) do sum = sum + m:GetPos() end
	return sum / #list
end

-- Anything keeping this group where it is right now?
local function Busy(g, list, center)
	if g.companion or g.keep then return true end -- (your companions follow you; quest givers wait for you)
	if (g.noWanderT or 0) > CurTime() then return true end
	for _, m in ipairs(list) do
		-- Fighting (an enemy close by: NPCs can remember one from across the map)
		local e = m:GetEnemy()
		if IsValid(e) && (e:IsPlayer() and e:Alive() or e:Health() > 0) && e:GetPos():DistToSqr(m:GetPos()) < 2500 * 2500 then return true end
	end
	for _, ply in ipairs(player.GetAll()) do
		local d = ply:GetPos():DistToSqr(center)
		if ply.GFR_Surrender or ply.GFR_Tied or ply.GFR_Struggling then
			if d < 2000 * 2000 then return true end
		end
		if g.warning && (g.warning[ply] or 0) > CurTime() then return true end
		-- Your zombie: sv_zombietame.lua is reading what you do and they're watching you
		if ply.GFR_IsZombie && IsValid(ply.GFR_ZombieNPC) && ply.GFR_ZombieNPC:GetPos():DistToSqr(center) < 2000 * 2000 then return true end
		for _, m in ipairs(list) do
			if ply:Alive() && !ply.GFR_IsZombie && ply:GetPos():DistToSqr(m:GetPos()) < NEAR_PLAYER * NEAR_PLAYER then return true end
		end
	end
	return false
end

local function NearAnyPlayer(pos, dist)
	for _, ply in ipairs(player.GetAll()) do
		if ply:GetPos():DistToSqr(pos) < dist * dist then return true end
	end
	return false
end

-- Where to next: an unsearched container close by, or else somewhere to look around
local function PickDestination(center)
	if GFR.ContainerType then
		local best, bestD
		for _, ent in ipairs(ents.FindInSphere(center, 1800)) do
			local ctype = (ent.GFR_SearchedUntil or 0) < CurTime() && !ent.GFR_GroupClaimed && GFR.ContainerType(ent)
			-- (not your flare drop: bandits raid that their own way, sv_airdrop.lua; not the Supply Units, which open
			-- up for whoever searches them, sv_containers.lua)
			if ctype && ctype != "airdrop" && !ent.GFR_Airdrop && !(GFR.ContainerOpensTo && GFR.ContainerOpensTo(ent))
				&& !(GFR.InClaim && GFR.InClaim(ent:GetPos())) && !NearAnyPlayer(ent:GetPos(), 500) then
				local d = ent:GetPos():DistToSqr(center) * math.Rand(0.6, 1.4) -- (not always the very closest)
				if !best or d < bestD then best, bestD = ent, d end
			end
		end
		if best then return best:GetPos(), best end
	end
	local cands = GFR.Loot && GFR.Loot.GetCandidates && GFR.Loot.GetCandidates() or {}
	for _ = 1, 30 do
		local c = cands[math.random(math.max(#cands, 1))]
		if c then
			local d = c:Distance(center)
			if d > 400 && d < 1600 && !(GFR.InClaim && GFR.InClaim(c)) then return c end
		end
	end
	for _ = 1, 8 do
		local ang = math.Rand(0, math.pi * 2)
		local p = center + Vector(math.cos(ang), math.sin(ang), 0) * math.Rand(400, 1000) + Vector(0, 0, 60)
		local tr = util.TraceLine({start = p, endpos = p - Vector(0, 0, 300), mask = MASK_SOLID_BRUSHONLY})
		if tr.Hit && !tr.StartSolid && tr.HitNormal.z > 0.7 && !(GFR.InClaim && GFR.InClaim(tr.HitPos)) then return tr.HitPos end
	end
end

local function Walk(npc, pos)
	npc:SetLastPosition(pos)
	npc:SetSchedule(SCHED_FORCED_GO)
end

-- Search a container: it's theirs now
local function Scavenge(g, npc, container)
	container.GFR_GroupClaimed = nil
	if !IsValid(container) or (container.GFR_SearchedUntil or 0) > CurTime() then return end
	GFR.MarkSearched(container) -- (refills like any searched container: sv_containers.lua)
	local found = GFR.RollContainerLoot && GFR.RollContainerLoot(GFR.ContainerType(container)) or {}
	local kept = 0
	if Alive(npc) then
		npc.GFR_Scavenged = npc.GFR_Scavenged or {}
		for _, class in ipairs(found) do
			-- (attachments go to players' stashes, not NPC pockets; a few items each at most)
			if !string.StartWith(class, "att:") && #npc.GFR_Scavenged < 6 then
				npc.GFR_Scavenged[#npc.GFR_Scavenged + 1] = class
				kept = kept + 1
			end
		end
	end
	Say(g, kept > 0 and "found" or "empty", npc)
end

local function Tick(g)
	local list = Members(g)
	if #list == 0 then return end
	local center = Center(list)
	if !NearAnyPlayer(center, ACTIVE_RANGE) then return end
	local w = g.wander
	if !w then
		w = {state = "rest", untilT = CurTime() + math.Rand(5, cvRest:GetFloat())}
		g.wander = w
	end
	local now = CurTime()
	if Busy(g, list, center) then
		-- Paused: when free again, a short breather first
		if w.state != "rest" then
			if IsValid(w.container) then w.container.GFR_GroupClaimed = nil end
			w.state, w.untilT, w.container = "rest", now + math.Rand(4, 10), nil
		end
		return
	end
	local leader = list[1]

	if w.state == "rest" then
		if now < w.untilT then return end
		local dest, container = PickDestination(center)
		if !dest then w.untilT = now + 15 return end
		w.state, w.dest, w.container, w.untilT, w.nextOrder = "move", dest, container, now + 45, 0
		if IsValid(container) then container.GFR_GroupClaimed = true end
		Say(g, "go", leader)
	end

	if w.state == "move" then
		local arrived = leader:GetPos():DistToSqr(w.dest) < 110 * 110
		local containerGone = w.container != nil && !IsValid(w.container)
		if arrived or now > w.untilT or containerGone then
			if arrived && IsValid(w.container) then
				w.state, w.untilT = "search", now + math.Rand(4, 6.5)
				leader:SetTarget(w.container)
				leader:SetSchedule(SCHED_TARGET_FACE)
				Say(g, "search", leader)
			else
				if IsValid(w.container) then w.container.GFR_GroupClaimed = nil end
				w.state, w.untilT, w.container = "rest", now + math.Rand(cvRest:GetFloat() * 0.5, cvRest:GetFloat() * 1.5), nil
			end
			return
		end
		-- Keep walking; the others follow loosely around the leader's destination
		if now >= w.nextOrder then
			w.nextOrder = now + 3
			for i, m in ipairs(list) do
				if !m:IsCurrentSchedule(SCHED_FORCED_GO) or i == 1 then
					local off = i == 1 and Vector(0, 0, 0) or Vector(math.Rand(-110, 110), math.Rand(-110, 110), 0)
					Walk(m, w.dest + off)
				end
			end
		end
		return
	end

	if w.state == "search" then
		if !IsValid(w.container) or now >= w.untilT then
			if IsValid(w.container) then Scavenge(g, leader, w.container) end
			w.state, w.untilT, w.container = "rest", now + math.Rand(cvRest:GetFloat() * 0.5, cvRest:GetFloat() * 1.5), nil
			return
		end
		if math.random(3) == 1 then
			w.container:EmitSound("physics/cardboard/cardboard_box_impact_soft" .. math.random(1, 7) .. ".wav", 60, math.random(90, 110))
		end
	end
end

timer.Create("GFR_GroupWander", TICK, 0, function()
	if !cvEnabled:GetBool() or !GFR.Spawner then return end
	for _, g in ipairs(GFR.Spawner.Groups()) do Tick(g) end
end)
