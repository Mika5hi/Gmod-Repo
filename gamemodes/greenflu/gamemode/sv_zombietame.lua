--[[
	Custom Apocalypse - living with the living, as a zombie (your own zombie: sv_extract.lua)
	People don't just open fire on you: they read what you do.
		threat   rises when you rush at them, run around close by, run with other zombies, feed on a body in view;
		         falls when you keep your distance, stand still, walk slowly, sit or lie down (crouch)
		low      they hold fire and watch you ("Don't shoot, it's not attacking")
		lower    one of them edges closer, gun on you, and tosses you meat: E to go down and eat it
		high     they shoot
	Each meat you eat calmly builds trust; enough and the group takes you in: they never shoot you, and give you jobs:
		fetch    bring them food (E on food picks it up in your teeth, E next to one of them hands it over)
		guard    stay by them and keep the dead off them for a while
		hunt     kill a marked rival (bandits for survivors and soldiers; anyone for bandits)
	Done: trust and a meat reward. Ignored or failed: trust drops, and too low they stop trusting you.
	Hurt any of them and that group never trusts you again. Being someone's pet makes rival factions warier of you.
	Survivors are curious, bandits see a weapon, soldiers see a specimen (quickest to shoot, slowest to tame).
	Your own companions (sv_companions.lua) just hold fire. There's no way back from being a zombie.
	HUD: cl_zombietame.lua
]]
local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY)
local cvEnabled = CreateConVar("gfr_ztame_enabled", "0", flags, "People react to how your zombie behaves (0 = they just shoot it, same as gfr_ztame_mode 0)")
local cvMode = CreateConVar("gfr_ztame_mode", "0", flags,
	"How people treat your zombie: 0 = they just shoot it, 1 = they read you and hold fire while you're calm, nothing more, 2 = full: testing you with commands, meat, being taken in, jobs")

local function Mode()
	if !cvEnabled:GetBool() then return 0 end
	return math.Clamp(cvMode:GetInt(), 0, 2)
end
local function Taming() return Mode() >= 2 end

local TICK = 0.5
-- base: how wary they start; fire: threat at which they shoot; approach: threat under which one comes over with meat;
-- meat: trust per meat eaten (100 = taken in)
local F = {
	survivor = {base = 20, fire = 75, approach = 35, meat = 25, name = "The survivors"},
	bandit   = {base = 35, fire = 60, approach = 28, meat = 20, name = "The bandits"},
	military = {base = 45, fire = 55, approach = 22, meat = 15, name = "The soldiers"}
}
local MEAT = {"meat_chunk1", "meat_chunk2", "gfr_food_zmeat_cooked"}

local lines = {
	watch = {
		survivor = {"Hold your fire! It's not coming at us.", "Easy... it's just standing there.", "Don't shoot. Watch it."},
		bandit = {"Huh. That one's not charging.", "Hold up. Look at this one."},
		military = {"Weapons on it. Do not engage yet.", "Anomalous behaviour. Hold."}},
	fire = {
		survivor = {"It's coming at us!", "Shoot it!"},
		bandit = {"Light it up!", "Kill that thing!"},
		military = {"Contact! Engage!", "Hostile, open fire!"}},
	approach = {
		survivor = {"Stay back... I'm going to try something.", "Cover me. I'll get closer."},
		bandit = {"Watch this. Here, boy...", "Cover me, I wanna see something."},
		military = {"Moving to inspect the specimen.", "Cover me. Approaching."}},
	toss = {
		survivor = {"Here. Eat. Just... eat that.", "Go on, take it."},
		bandit = {"Fetch, freak.", "Here, chew on this."},
		military = {"Offering bait. Observe.", "Feeding it. Log the response."}},
	ate = {
		survivor = {"It ate it! It actually ate it.", "Good... good."},
		bandit = {"Ha! It likes us.", "Good doggy."},
		military = {"Subject accepted the bait.", "Response logged."}},
	ignored = {
		survivor = {"It won't take it."}, bandit = {"Ungrateful thing."}, military = {"Bait refused."}},
	tamed = {
		survivor = {"I think... it's on our side now.", "It knows us. It won't hurt us."},
		bandit = {"Heh. Got ourselves a pet.", "It's ours now."},
		military = {"Subject is compliant. Keep it close.", "Specimen is docile. Use it."}},
	betrayed = {
		survivor = {"It turned on us! Kill it!"}, bandit = {"Stupid mutt bit me! Kill it!"}, military = {"Subject hostile! Terminate!"}},
	order = {
		survivor = {"Hey... you. Can you help us?"}, bandit = {"Got a job for you, mutt."}, military = {"Specimen. New task."}},
	thanks = {
		survivor = {"Good job. Here, you earned it."}, bandit = {"Good boy. Here."}, military = {"Task complete. Reward issued."}},
	letdown = {
		survivor = {"Where did it go...?"}, bandit = {"Useless."}, military = {"Subject failed the task."}}
}

-- Calling out to you: the first time they get a good look at you, and checking whether you understand them
lines.notice = {
	survivor = {"Hey! You! ...Can you hear me?", "Wait - that one's not like the others.", "Hello? Is anyone still in there?"},
	bandit = {"Oi! Freak! You understand me?", "Look at this one. Something's different."},
	military = {"Contact. It's... not engaging.", "You! Can you understand English?"}}
lines.understood = {
	survivor = {"It understood! It actually listened!", "Did you see that? It's still in there!"},
	bandit = {"Ha! It listens! Smart mutt.", "Well, look at that. It's trainable."},
	military = {"Subject responded to the command.", "Comprehension confirmed. Note it."}}
lines.mindless = {
	survivor = {"Nothing. It's just... one of them.", "No one's home."},
	bandit = {"Dumb as rocks.", "Brain-dead. Figures."},
	military = {"No response. Mindless.", "Negative comprehension."}}
-- Between tests they just keep an eye on you
lines.eyeing = {
	survivor = {"Keep an eye on it.", "It's still watching us...", "Don't turn your back on it.", "Anyone else see it just... standing there?"},
	bandit = {"Watch that thing.", "If it twitches, shoot it.", "Creepy little freak."},
	military = {"Maintain visual on the subject.", "Subject still passive.", "Eyes on it. Weapons ready."}}
-- Mode 1 (gfr_ztame_mode): they don't call out to you, they keep it down among themselves so they don't draw you over
lines.notice_quiet = {
	survivor = {"Shh... there's one. Don't make a sound.", "Easy... it hasn't come at us yet. Nobody move.", "Quiet. Don't give it a reason."},
	bandit = {"Shut up, there's one. Don't draw it over.", "Nobody shoot unless it moves on us."},
	military = {"Contact, passive. Hold fire, hold noise.", "Stay quiet. Let it be."}}
lines.eyeing_quiet = {
	survivor = {"Keep your voice down...", "Just let it wander off.", "Don't look at it. Don't make noise.", "If it comes closer, we go. Quietly."},
	bandit = {"Keep it down, idiot.", "Let the freak pass.", "Nobody poke it."},
	military = {"Hold position. Minimal noise.", "Let it pass.", "Weapons ready. No shots unless it closes."}}
lines.spooked = {
	survivor = {"Whoa, slow down! SLOW!"}, bandit = {"Easy! I said slow!"}, military = {"Too fast! Stop!"}}

-- Tests: one of them shouts a command; doing it shows you understand them.
-- check(test, ctx) -> true: done; fail(test, ctx) -> true: you did the opposite (spooks them)
local TESTS = {
	sit = {
		say = {survivor = {"If you can understand me... sit down!", "Sit! Sit down!"}, bandit = {"Sit! Sit, mutt!"}, military = {"Subject: sit down. Now."}},
		hint = "They want you to SIT DOWN  [Crouch]", time = 9,
		check = function(t, c) return c.resting end},
	stay = {
		say = {survivor = {"Don't move! Stay right there!"}, bandit = {"Freeze, freak!"}, military = {"Halt! Do not move!"}},
		hint = "They want you to STAY STILL", time = 7, hold = 5,
		check = function(t, c) return t.held >= t.def.hold end,
		fail = function(t, c) return c.speed > 80 end},
	back = {
		say = {survivor = {"Back off! Go on, get back!"}, bandit = {"Back up! Get away from us!"}, military = {"Move back! Now!"}},
		hint = "They want you to BACK AWAY from them", time = 8,
		check = function(t, c) return c.nd > t.startD + 180 end,
		fail = function(t, c) return c.nd < t.startD - 150 end},
	come = {
		say = {survivor = {"Okay... come here. Slowly."}, bandit = {"C'mere. Nice and slow."}, military = {"Approach. Slowly."}},
		hint = "They want you to COME CLOSER - SLOWLY (walk)", time = 14,
		check = function(t, c) return c.nd < 350 end,
		fail = function(t, c) return c.speed > 200 end}
}
local testKinds = {"sit", "stay", "back", "come"}

local function Groups() return GFR.Spawner && GFR.Spawner.Groups() or {} end

local function Alive(m) return IsValid(m) && m:Health() > 0 end

local function Say(g, kind, npc, force)
	if !force && (g.GFR_ZSayT or 0) > CurTime() then return end
	local t = lines[kind] && lines[kind][g.faction]
	if !t then return end
	if !Alive(npc) then
		for _, m in ipairs(g.members) do if Alive(m) then npc = m break end end
	end
	if !Alive(npc) or !GFR.Say then return end
	g.GFR_ZSayT = CurTime() + 6
	GFR.Say(npc, t[math.random(#t)])
end

local function State(g, ply)
	g.ztame = g.ztame or {}
	local st = g.ztame[ply]
	if !st then
		st = {threat = (F[g.faction] or F.survivor).base, trust = 0}
		g.ztame[ply] = st
	end
	return st
end

local function Center(g)
	local sum, n = Vector(0, 0, 0), 0
	for _, m in ipairs(g.members) do
		if Alive(m) then sum = sum + m:GetPos() n = n + 1 end
	end
	return n > 0 and sum / n or nil
end

local function MoveTo(npc, pos)
	npc:SetLastPosition(pos)
	npc:SetSchedule(SCHED_FORCED_GO)
end

-- Fire or hold fire on your zombie
local function SetFire(g, z, fire)
	for _, m in ipairs(g.members) do
		if Alive(m) then
			m:AddEntityRelationship(z, fire and D_HT or D_NU, 99)
			if fire then
				m:UpdateEnemyMemory(z, z:GetPos())
			elseif m:GetEnemy() == z then
				m:SetEnemy(NULL)
				m:ClearEnemyMemory(z)
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Meat
local MeatEaten -- below

local function Toss(npc, z, ply, g, reward)
	local class
	for _, c in ipairs(MEAT) do if scripted_ents.GetStored(c) then class = c break end end
	if !class or !GFR.Loot or !Alive(npc) then return end
	local src = npc:EyePos() + npc:GetForward() * 16
	local meat = GFR.Loot.SpawnItem(class, src)
	if !IsValid(meat) then return end
	meat.GFR_Bait = true -- (your zombie can eat it: sv_extract.lua FindFood)
	meat.GFR_TameFor, meat.GFR_TameGroup, meat.GFR_Reward = ply, g, reward
	local to = z:GetPos() + (npc:GetPos() - z:GetPos()):GetNormalized() * 45
	local phys = meat:GetPhysicsObject()
	if IsValid(phys) then
		local d = to - src
		phys:Wake()
		phys:SetVelocity(Vector(d.x, d.y, 0) * 1.3 + Vector(0, 0, 160))
	end
	meat:CallOnRemove("GFR_ZTame", function(m) if (m.GFR_Bites or 0) >= 3 then MeatEaten(m) end end)
	return meat
end

MeatEaten = function(meat)
	local ply, g = meat.GFR_TameFor, meat.GFR_TameGroup
	if !IsValid(ply) or !g or meat.GFR_Reward then return end
	local st = State(g, ply)
	if st.hostile or st.tamed then return end
	local f = F[g.faction] or F.survivor
	st.trust = math.min(st.trust + f.meat, 100)
	st.threat = math.max(st.threat - 30, 0)
	st.meat = nil
	if st.trust >= 100 then
		st.tamed = true
		st.nextOrder = CurTime() + 20
		ply.GFR_ZTamedBy = g
		Say(g, "tamed", nil, true)
		GFR.Notify(ply, f.name .. " have taken you in. They won't shoot you, and they'll have jobs for you. Stay close.")
	else
		Say(g, "ate", nil, true)
		GFR.Notify(ply, f.name .. " watch you eat. (trust " .. st.trust .. "%)")
	end
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Jobs for a tamed zombie
local function Rival(a, b)
	if a == "bandit" then return b != "bandit" end
	return b == "bandit"
end

local function HuntTarget(g, from)
	local best, bestD
	for _, og in ipairs(Groups()) do
		if og != g && !og.companion && Rival(g.faction, og.faction) then
			for _, m in ipairs(og.members) do
				if Alive(m) then
					local d = m:GetPos():Distance(from)
					if d < 5000 && (!bestD or d < bestD) then best, bestD = m, d end
				end
			end
		end
	end
	return best
end

local function SetOrderNW(ply, text, ent)
	ply:SetNW2String("GFR_ZOrder", text or "")
	ply:SetNW2Entity("GFR_ZOrderEnt", IsValid(ent) and ent or NULL)
end

local function DropCarry(ply, pos)
	if !ply.GFR_ZCarry then return end
	if pos && GFR.Loot then GFR.Loot.SpawnItem(ply.GFR_ZCarry, pos) end
	ply.GFR_ZCarry = nil
	ply:SetNW2String("GFR_ZCarry", "")
end

local function EndOrder(ply, ok, silent)
	local o = ply.GFR_ZOrder
	if !o then return end
	ply.GFR_ZOrder = nil
	SetOrderNW(ply)
	local z = ply.GFR_ZombieNPC
	if ply.GFR_ZCarry then DropCarry(ply, IsValid(z) and z:GetPos() + Vector(0, 0, 20)) end
	local g = o.group
	local st = State(g, ply)
	st.nextOrder = CurTime() + math.Rand(90, 150)
	if silent then return end
	if ok then
		st.trust = math.min(st.trust + 10, 100)
		local giver
		for _, m in ipairs(g.members) do if Alive(m) && IsValid(z) && (!giver or m:GetPos():DistToSqr(z:GetPos()) < giver:GetPos():DistToSqr(z:GetPos())) then giver = m end end
		Say(g, "thanks", giver, true)
		if IsValid(z) && giver && giver:GetPos():DistToSqr(z:GetPos()) < 900 * 900 then Toss(giver, z, ply, g, true) end
		GFR.Notify(ply, "Job done. They toss you some meat. (trust " .. st.trust .. "%)")
	else
		st.trust = math.max(st.trust - 15, 0)
		Say(g, "letdown", nil, true)
		if st.trust < 60 then
			st.tamed = false
			if ply.GFR_ZTamedBy == g then ply.GFR_ZTamedBy = nil end
			GFR.Notify(ply, "You let them down. They don't trust you any more. (trust " .. st.trust .. "%)")
		else
			GFR.Notify(ply, "You let them down. (trust " .. st.trust .. "%)")
		end
	end
end

local function GiveOrder(ply, z, g, leader)
	local f = F[g.faction] or F.survivor
	local kinds = {"fetch", "guard"}
	local target = HuntTarget(g, leader:GetPos())
	if IsValid(target) then kinds[#kinds + 1] = "hunt" end
	local kind = kinds[math.random(#kinds)]
	local o = {kind = kind, group = g, leader = leader, started = CurTime()}
	local who = string.lower(f.name)
	if kind == "fetch" then
		o.ends = CurTime() + 240
		SetOrderNW(ply, "FETCH: bring " .. who .. " some food  (E on food: pick it up  -  E next to them: hand it over)", leader)
	elseif kind == "guard" then
		o.ends = CurTime() + 90
		o.away = 0
		SetOrderNW(ply, "GUARD: stay near " .. who .. " and keep the dead off them", leader)
	else
		o.ends = CurTime() + 300
		o.target = target
		local tf = target.GFR_Group && target.GFR_Group.faction or "rival"
		SetOrderNW(ply, "HUNT: kill the marked " .. (tf == "military" and "soldier" or tf), target)
	end
	ply.GFR_ZOrder = o
	Say(g, "order", leader, true)
	GFR.Notify(ply, f.name .. " have a job for you.")
end

local function CheckOrder(ply, z)
	local o = ply.GFR_ZOrder
	if !o then return end
	local center = Center(o.group)
	if !center then EndOrder(ply, false, true) return end -- they're all dead
	if o.kind == "guard" then
		if z:GetPos():DistToSqr(center) > 900 * 900 then o.away = o.away + TICK else o.away = 0 end
		if o.away > 15 then EndOrder(ply, false) return end
		if CurTime() > o.ends then EndOrder(ply, true) end
		return
	end
	if o.kind == "hunt" && !Alive(o.target) then EndOrder(ply, true) return end
	if CurTime() > o.ends then EndOrder(ply, false) end
end

-- E as your zombie (sv_extract.lua asks first): pick food up in your teeth / hand it over. true = handled.
function GFR.ZombieUse(ply, z)
	local o = ply.GFR_ZOrder
	if !o or o.kind != "fetch" then return false end
	if ply.GFR_ZCarry then
		for _, m in ipairs(o.group.members) do
			if Alive(m) && m:GetPos():DistToSqr(z:GetPos()) < 170 * 170 then
				ply.GFR_ZCarry = nil
				ply:SetNW2String("GFR_ZCarry", "")
				EndOrder(ply, true)
				return true
			end
		end
		GFR.Notify(ply, "Bring it to them.")
		return false
	end
	for _, ent in ipairs(ents.FindInSphere(z:GetPos(), 90)) do
		local class = ent:GetClass()
		local n = GFR.Nutrition && GFR.Nutrition[class]
		if n && (n.hunger or 0) > 0 && !ent.GFR_Bait && !IsValid(ent:GetOwner()) then
			ply.GFR_ZCarry = class
			ply:SetNW2String("GFR_ZCarry", GFR.ItemDisplayName and GFR.ItemDisplayName(class) or class)
			ent:Remove()
			z:EmitSound("physics/flesh/flesh_squishy_impact_hard" .. math.random(1, 4) .. ".wav", 60)
			GFR.Notify(ply, "You pick it up in your teeth. Bring it to them.")
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Testing you: a shouted command, a prompt on your screen (cl_zombietame.lua), a few seconds to show you understood
local function SetTestNW(ply, hint, len)
	ply:SetNW2String("GFR_ZTest", hint or "")
	ply:SetNW2Float("GFR_ZTestEnd", hint and (CurTime() + len) or 0)
	ply:SetNW2Float("GFR_ZTestLen", len or 0)
end

local function EndTest(ply, ok, spooked, silent)
	local test = ply.GFR_ZTest
	if !test then return end
	ply.GFR_ZTest = nil
	SetTestNW(ply)
	local g = test.group
	local st = State(g, ply)
	-- Once in a while, not back to back: they watch you a good while between tests
	st.nextTest = CurTime() + math.Rand(60, 120)
	if silent then return end
	local f = F[g.faction] or F.survivor
	if ok then
		st.threat = math.max(st.threat - 12, 0)
		Say(g, "understood", test.asker, true)
		if Taming() then
			st.trust = math.min(st.trust + 5, math.max(st.trust, 40)) -- (listening gets you so far; the rest is eating their meat)
			GFR.Notify(ply, f.name .. " saw that. They know you understand them now. (trust " .. math.floor(st.trust) .. "%)")
		else
			GFR.Notify(ply, f.name .. " saw that. They know you understand them.")
		end
	elseif spooked then
		st.threat = math.min(st.threat + 20, 100)
		Say(g, "spooked", test.asker, true)
	else
		st.threat = math.min(st.threat + 8, 100)
		Say(g, "mindless", test.asker, true)
	end
end

local function StartTest(ply, g, asker, nd)
	local kind = testKinds[math.random(#testKinds)]
	if kind == "come" && nd < 450 then kind = "stay" end -- (already close)
	if kind == "back" && nd > 900 then kind = "sit" end  -- (already far)
	local def = TESTS[kind]
	ply.GFR_ZTest = {group = g, def = def, kind = kind, ends = CurTime() + def.time, startD = nd, held = 0, asker = asker}
	local t = def.say[g.faction] or def.say.survivor
	g.GFR_ZSayT = CurTime() + 6
	if GFR.Say then GFR.Say(asker, t[math.random(#t)]) end
	SetTestNW(ply, def.hint, def.time)
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Reading what you do
local function Clear(ply)
	if ply.GFR_ZTest then EndTest(ply, false, false, true) end
	if ply.GFR_ZOrder then EndOrder(ply, false, true) end
	DropCarry(ply)
	if ply:GetNW2String("GFR_ZStatus", "") != "" then ply:SetNW2String("GFR_ZStatus", "") end
end

local function Seen(g, z)
	local zc = z:WorldSpaceCenter()
	for _, m in ipairs(g.members) do
		if Alive(m) && m:GetPos():DistToSqr(zc) < 1800 * 1800
			&& !util.TraceLine({start = m:EyePos(), endpos = zc, filter = {m, z}, mask = MASK_SOLID_BRUSHONLY}).Hit then
			return true
		end
	end
	return false
end

local function Update(ply, z)
	local now = CurTime()
	local zpos = z:GetPos()
	local speed = ply.GFR_ZLastPos and zpos:Distance(ply.GFR_ZLastPos) / TICK or 0
	ply.GFR_ZLastPos = zpos
	local resting = (z.Zombie_IdleState or 0) != 0
	local eatingMeat = IsValid(z.GFR_EatFood) && z.GFR_EatFood.GFR_Bait
	local eatingBody = IsValid(z.GFR_EatFood) && !z.GFR_EatFood.GFR_Bait
	local pack = 0
	for _, e in ipairs(ents.FindInSphere(zpos, 400)) do
		if e != z && e:IsNPC() && e:Health() > 0 && GFR.IsZombie && GFR.IsZombie(e) then pack = pack + 1 end
	end
	local tamedBy = ply.GFR_ZTamedBy
	local statusText, statusD

	for _, g in ipairs(Groups()) do
		local f = F[g.faction]
		if !f or (z.GFR_Hunter && g.faction == "military" && !z.GFR_HunterBetrayed) then continue end -- (hunters: sv_hunter.lua)
		local near, nd
		for _, m in ipairs(g.members) do
			if Alive(m) then
				local d = m:GetPos():Distance(zpos)
				if !nd or d < nd then near, nd = m, d end
			end
		end
		if !near then continue end
		local st = State(g, ply)
		local newZ = st.z != z
		if newZ then st.z, st.fire, st.lastD = z, nil, nd end

		-- Your own people: they just hold fire (unless you went for them)
		if g.companion then
			if st.fire != (st.hostile or false) or newZ then st.fire = st.hostile or false SetFire(g, z, st.fire) end
			continue
		end

		local approach = st.lastD and (st.lastD - nd) / TICK or 0
		st.lastD = nd
		-- Someone else's pet: other factions are warier of you
		local base = f.base + ((tamedBy && tamedBy != g && tamedBy.faction != g.faction) and 20 or 0)
		local seen = nd < 2500 && Seen(g, z)

		if st.hostile then
			st.threat = 100
		elseif st.tamed then
			st.threat = math.min(st.threat, 15)
		elseif seen then
			local d = 0
			if resting or eatingMeat then d = d - 12
			elseif speed < 20 then d = d - 6
			elseif speed < 120 && approach < 60 then d = d - 2 end
			if approach > 120 && nd < 1000 then d = d + 25 end
			if speed > 200 && nd < 700 then d = d + 8 end
			if pack > 0 then d = d + 6 + pack end
			if eatingBody && nd < 1200 then d = d + 10 end
			if nd < 120 && st.trust < 50 && !eatingMeat then d = d + 5 end
			-- How hungry you look (sv_zombiehunger.lua)
			local hunger = GFR.ZombieHungerStage && GFR.ZombieHungerStage(ply)
			if hunger == "sated" then d = d - 1
			elseif hunger == "starving" then d = d + 3
			elseif hunger == "feral" then d = d + 6 end
			st.threat = math.Clamp(st.threat + d * TICK, 0, 100)
		else
			st.threat = math.Approach(st.threat, base, 3 * TICK) -- out of sight: back to how wary they start
		end

		local fire = st.hostile or st.threat >= f.fire
		if fire != st.fire or newZ then
			if fire && st.fire == false then Say(g, "fire", near) end
			if !fire && st.fire then Say(g, "watch", near) end
			if !fire && st.fire == nil && seen && nd < 1500 then Say(g, "watch", near) end
			st.fire = fire
			SetFire(g, z, fire)
		elseif (st.nextRel or 0) < now then
			SetFire(g, z, fire) -- (new members, relationships reset by something else)
		end
		if (st.nextRel or 0) < now then st.nextRel = now + 3 end

		-- Holding fire: they keep their eyes (and guns) on you
		if !fire && !st.tamed && seen && nd < 1500 && (st.nextFace or 0) < now then
			st.nextFace = now + 2
			for _, m in ipairs(g.members) do
				if Alive(m) && m != st.scout && !m:IsMoving() && !IsValid(m:GetEnemy()) then
					m:SetTarget(z)
					m:SetSchedule(SCHED_TARGET_FACE)
				end
			end
		end

		-- Calling out to you, and every so often testing whether you still understand them (or are just one of them)
		local free = !fire && !st.tamed && !st.hostile && seen && nd < 1300
		if free && !st.noticed then
			st.noticed = true
			Say(g, Taming() and "notice" or "notice_quiet", near, true)
			st.nextTest = now + math.Rand(15, 25)
			st.nextEye = now + math.Rand(20, 35)
			-- (nobody walks up to you with meat until they've watched you a while)
			st.nextScout = math.max(st.nextScout or 0, now + math.Rand(45, 70))
		end
		-- Watching you between tests: a remark now and then, so you know they still are
		if free && st.noticed && !ply.GFR_ZTest && now > (st.nextEye or 0) then
			st.nextEye = now + math.Rand(25, 45)
			Say(g, Taming() and "eyeing" or "eyeing_quiet", near)
		end
		local test = ply.GFR_ZTest
		if test && test.group == g then
			if !free or !Taming() then -- (mode 1: no testing you either)
				EndTest(ply, false, false, true) -- (they started shooting, took you in, lost sight of you...)
			else
				local ctx = {resting = resting, speed = speed, nd = nd}
				if test.def.hold && speed < 15 then test.held = test.held + TICK end
				if test.def.check(test, ctx) then
					EndTest(ply, true)
				elseif test.def.fail && test.def.fail(test, ctx) then
					EndTest(ply, false, true)
				elseif now > test.ends then
					EndTest(ply, false)
				end
			end
		elseif Taming() && free && !test && !IsValid(st.meat) && !Alive(st.scout) && now > (st.nextTest or math.huge) then
			StartTest(ply, g, near, nd)
		end

		-- One of them comes over with meat
		if IsValid(st.meat) then
			if !st.meat.GFR_Bites && now > (st.meatT or 0) + 45 then
				st.meat:Remove()
				st.meat = nil
				st.trust = math.max(st.trust - 5, 0)
				Say(g, "ignored", near)
			end
		elseif Alive(st.scout) then
			local sd = st.scout:GetPos():Distance(zpos)
			if fire or now > (st.scoutUntil or 0) then
				local c = Center(g)
				if c then MoveTo(st.scout, c) end
				st.scout = nil
				st.nextScout = now + math.Rand(60, 100)
			elseif sd > 220 then
				if (st.nextScoutMove or 0) < now then
					st.nextScoutMove = now + 1
					MoveTo(st.scout, zpos + (st.scout:GetPos() - zpos):GetNormalized() * 170)
				end
			else
				st.meat = Toss(st.scout, z, ply, g, false)
				st.meatT = now
				Say(g, "toss", st.scout, true)
				if IsValid(st.meat) then GFR.Notify(ply, "They tossed you meat. Go to it and press E to eat it.") end
				local c = Center(g)
				if c then MoveTo(st.scout, c) end
				st.scout = nil
				st.nextScout = now + math.Rand(60, 100)
			end
		elseif Taming() && !fire && !st.tamed && seen && st.threat < f.approach && nd < 1600 && speed < 150 && now > (st.nextScout or 0) && !ply.GFR_ZTest then
			st.scout = near
			st.scoutUntil = now + 25
			Say(g, "approach", near, true)
		end

		-- Jobs
		if Taming() && st.tamed && !ply.GFR_ZOrder && now > (st.nextOrder or 0) && nd < 1500 then GiveOrder(ply, z, g, near) end

		-- What the closest group thinks of you (HUD; trust only matters when they can take you in)
		if nd < 2000 && (!statusD or nd < statusD) then
			statusD = nd
			local mood = st.hostile and "want you dead" or (st.tamed && Taming() and "trust you") or (fire and "are shooting at you")
				or (st.threat < f.approach and "are curious about you") or "are watching you, guns up"
			statusText = f.name .. " " .. mood .. ((st.hostile or fire or !Taming()) and "" or ("  (trust " .. math.floor(st.trust) .. "%)"))
		end
	end
	CheckOrder(ply, z)
	-- (the group that asked is gone: all dead, or recycled far away)
	if ply.GFR_ZTest && CurTime() > ply.GFR_ZTest.ends + 2 then EndTest(ply, false, false, true) end
	ply:SetNW2String("GFR_ZStatus", statusText or "")
end

timer.Create("GFR_ZTame_Tick", TICK, 0, function()
	local on = Mode() > 0
	for _, ply in ipairs(player.GetAll()) do
		local z = ply.GFR_ZombieNPC
		local alive = ply.GFR_IsZombie && IsValid(z) && z:Health() > 0
		if on && alive then
			-- (taming switched off mid-way: a pending job ends quietly)
			if !Taming() && ply.GFR_ZOrder then EndOrder(ply, false, true) end
			Update(ply, z)
		else
			Clear(ply)
			-- Switched off (mode 0): anyone still holding fire on your zombie treats it like any other again
			if !on && alive then
				for _, g in ipairs(Groups()) do
					local st = g.ztame && g.ztame[ply]
					if st && st.fire == false then
						st.fire = true
						SetFire(g, z, true)
					end
				end
			end
		end
	end
end)

-- Hurt one of them: that group never trusts you again
hook.Add("EntityTakeDamage", "GFR_ZTame_Attacked", function(target, dmg)
	local g = target.GFR_Group
	local att = dmg:GetAttacker()
	local ply = g && IsValid(att) && att.GFR_ControlPlayer
	if !IsValid(ply) or !F[g.faction] then return end
	local st = State(g, ply)
	if !st.hostile then
		st.hostile = true
		st.trust = 0
		if st.tamed then Say(g, "betrayed", target, true) else Say(g, "fire", target, true) end
		st.tamed = false
		if ply.GFR_ZTamedBy == g then ply.GFR_ZTamedBy = nil end
		if ply.GFR_ZOrder && ply.GFR_ZOrder.group == g then EndOrder(ply, false, true) end
	end
	st.threat = 100
	st.fire = true
	SetFire(g, att, true)
end)

-- Guarding: every zombie you put down near them counts
hook.Add("OnNPCKilled", "GFR_ZTame_GuardKill", function(npc, attacker)
	local ply = IsValid(attacker) && attacker.GFR_ControlPlayer
	if !IsValid(ply) or !GFR.IsZombie or !GFR.IsZombie(npc) then return end
	local o = ply.GFR_ZOrder
	if !o or o.kind != "guard" then return end
	local c = Center(o.group)
	if c && npc:GetPos():DistToSqr(c) < 1000 * 1000 then
		local st = State(o.group, ply)
		st.trust = math.min(st.trust + 3, 100)
	end
end)

-- A new life (you respawned as a survivor): what they knew about your zombie is gone
-- (not when your zombie just gets back up after going down: that's still you, and they remember)
hook.Add("PlayerSpawn", "GFR_ZTame_Forget", function(ply)
	timer.Simple(0.5, function()
		if !IsValid(ply) or ply.GFR_IsZombie or ply:GetNW2Bool("GFR_ZombieSpectate") then return end
		ply.GFR_ZTamedBy = nil
		ply.GFR_ZLastPos = nil
		for _, g in ipairs(Groups()) do
			if g.ztame then g.ztame[ply] = nil end
		end
	end)
end)
