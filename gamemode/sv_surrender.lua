--[[
	Custom Apocalypse - surrendering, warnings and capture

	J               hands up / change your mind (before you're tied)
	Hostile groups  sometimes shout a warning first and hold fire ~10s: surrender (J) or leave.
	                Too slow or shoot them and they open fire. They won't warn again until you've left the area.
	Captured        the nearest hostile walks up and ties you, then decides:
	                  Bandits   rob you / keep you for their games / leave you tied for the zombies / execute you
	                  Survivors (that you angered) rob you / zombies / execute
	                  Military  confiscate your weapons / inject you with a test vial (infection) / execute
	                Robbed gear is carried by the robber: kill them later to get it back.
	Tied for zombies: no escape - the captors back off and watch you get eaten and turn.
]]

local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY)
local cvEnabled  = CreateConVar("gfr_surrender_enabled", "0", flags, "Enable surrendering (J) and hostile warnings")
local cvWarn     = CreateConVar("gfr_warn_chance", "30", flags, "% chance a hostile group shouts a warning before opening fire")
local cvStruggle = CreateConVar("gfr_struggle_rate", "5", flags, "% gained per SPACE press when struggling free")

util.AddNetworkString("GFR_Say")

local factionNames = {survivor = "Survivor", bandit = "Bandit", military = "Soldier"}

function GFR.Say(npc, text)
	if !IsValid(npc) then return end
	local name = npc:GetNW2String("GFR_Name", "") -- companions have names (sv_companions.lua)
	if name == "" then name = factionNames[npc:GetNW2String("GFR_Faction", "")] or "Someone" end
	for _, ply in ipairs(player.GetAll()) do
		if ply:GetPos():DistToSqr(npc:GetPos()) < 2500 * 2500 then
			net.Start("GFR_Say")
			net.WriteString(name)
			net.WriteString(text)
			net.Send(ply)
		end
	end
end
local Say = GFR.Say

local lines = {
	warn = {
		bandit = {"Hey! Hands where I can see 'em!", "Drop it and get on your knees!", "This is our turf. Hands up or get lost!"},
		military = {"Halt! Hands up!", "Restricted area. Surrender or leave, now!"},
		survivor = {"Stop right there! Hands up!", "Don't come any closer. Hands up or walk away!"}
	},
	tooSlow = {"Too slow!", "Light 'em up!", "Your choice."},
	left = {"Yeah, keep walking.", "Smart choice.", "And stay away."},
	approach = {"Smart. Stay right there.", "Don't move a muscle.", "Keep those hands up."},
	tie = {"Hold still.", "On your knees.", "Don't try anything."},
	rob = {
		bandit = {"Let's see what you've got...", "Thanks for the donation."},
		military = {"We're confiscating your weapons.", "Weapons are property of the military now."},
		survivor = {"Sorry. We need this more than you do."}
	},
	release = {"Now get lost.", "Walk away. Don't look back.", "Go. Before I change my mind."},
	zombies = {"The dead look hungry today. Good luck.", "Let's see how long you last.", "Dinner time, boys."},
	execute = {"Nothing personal.", "End of the line.", "Sorry, friend."},
	inject = {"Hold still. Science needs volunteers.", "Subject acquired. Administer the sample.", "This won't hurt. Much."}
}
local function Line(list) return list[math.random(#list)] end

-- Letting someone walk away is rare: most know an armed survivor they robbed will come back for them
local fates = {
	bandit = {rob = 10, games = 40, zombies = 25, execute = 25}, -- games: kept around for their amusement (below)
	survivor = {rob = 25, zombies = 20, execute = 55},
	military = {rob = 15, inject = 50, execute = 35}
}

local function PickFate(faction)
	local weights = fates[faction] or fates.bandit
	local total = 0
	for _, w in pairs(weights) do total = total + w end
	local roll = math.Rand(0, total)
	for fate, w in pairs(weights) do
		roll = roll - w
		if roll <= 0 then return fate end
	end
	return "rob"
end

local function IsHostile(group, ply)
	return group.hostileTo[ply] or group.attitude == D_HT
end

local function NearestMember(group, pos)
	local best, bestD
	for _, m in ipairs(group.members) do
		if IsValid(m) && m:Health() > 0 then
			local d = m:GetPos():Distance(pos)
			if !best or d < bestD then best, bestD = m, d end
		end
	end
	return best, bestD
end

local function Refresh(group)
	if GFR.Spawner then GFR.Spawner.RefreshGroup(group) end
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Tying / untying
-- Tied up you can't move, shoot or use anything, but you can still look around (frozen, you couldn't even do that)
hook.Add("StartCommand", "GFR_Surrender_Tied", function(ply, cmd)
	if !ply.GFR_Tied then return end
	-- One of the bandits' choices put to you: E yes, SPACE no (read before the buttons are cleared; a key already held
	-- when it's asked has to be let go first)
	local c = ply.GFR_Choice
	if c then
		local yes, no = cmd:KeyDown(IN_USE), cmd:KeyDown(IN_JUMP)
		if !yes && !no then
			c.held = false
		elseif !c.held && !c.answered then
			c.answered = true
			timer.Simple(0, function() if IsValid(ply) && ply.GFR_Choice == c then GFR.SurrenderAnswer(ply, yes) end end)
		end
	end
	cmd:ClearMovement()
	cmd:ClearButtons()
end)

local function Untie(ply)
	ply:Freeze(false)
	ply.GFR_Tied = nil
	ply.GFR_Bait = nil
	ply.GFR_Captive = nil
	ply.GFR_Choice = nil
	ply:SetNW2String("GFR_ChoiceText", "")
	ply.GFR_Struggling = nil
	ply.GFR_Surrender = nil
	ply:SetNW2Bool("GFR_Struggling", false)
	ply:SetNW2Bool("GFR_Tied", false)
	ply:SetNW2Bool("GFR_HandsUp", false)
	ply:SetNW2Float("GFR_Struggle", 0)
end

-- Everyone who held fire while you surrendered lets you go, not just the captor's group
local function SpareFor(ply, group, seconds)
	for _, g in ipairs(ply.GFR_CaptureGroups or {}) do
		g.truce[ply] = CurTime() + seconds
		Refresh(g)
	end
	if group then
		group.truce[ply] = CurTime() + seconds
		Refresh(group)
	end
end

local function Release(ply, group, captor)
	if !IsValid(ply) then return end
	Untie(ply)
	SpareFor(ply, group, 180) -- let you walk away
	ply.GFR_CaptureGroups = nil
	if IsValid(captor) then Say(captor, Line(lines.release)) end
end

local noTake = {weapon_fists = true, arc9_cod2019_me_fist = true, weapon_physgun = true, gmod_tool = true, gmod_camera = true}

local function Rob(ply, captor, faction)
	local stolen = captor.GFR_StolenGear or {name = ply:Nick(), weapons = {}, ammo = {}, items = {}, caps = 0}
	-- Every faction takes your guns
	for _, wep in ipairs(ply:GetWeapons()) do
		if IsValid(wep) && !noTake[wep:GetClass()] then
			stolen.weapons[#stolen.weapons + 1] = {class = wep:GetClass(), clip1 = wep:Clip1(), clip2 = wep:Clip2()}
			ply:StripWeapon(wep:GetClass())
		end
	end
	for id, count in pairs(ply:GetAmmo()) do
		if count > 0 then stolen.ammo[id] = (stolen.ammo[id] or 0) + count end
	end
	ply:RemoveAllAmmo()

	-- Bandits and survivors go through your pockets too; the military only disarms you
	if faction != "military" then
		local caps = ply:GetNW2Int("GFR_Caps", 0)
		local take = faction == "bandit" and caps or math.floor(caps / 2)
		stolen.caps = stolen.caps + take
		GFR.AddCaps(ply, -take)
		local chance = faction == "bandit" and 0.6 or 0.4
		local inv = ply.GFR_Inv or {}
		for i = #inv, 1, -1 do
			if math.Rand(0, 1) < chance then
				local e = inv[i]
				stolen.items[#stolen.items + 1] = {class = e.class, count = e.count, contaminated = e.contaminated, model = e.model}
				table.remove(inv, i)
			end
		end
		if GFR.InvSync then GFR.InvSync(ply) end
	end

	captor.GFR_StolenGear = stolen
	local fists = GFR.Fists()
	if !ply:HasWeapon(fists) then ply:Give(fists) end
	ply:SelectWeapon(fists)
	GFR.Notify(ply, faction == "military" and "Your weapons were confiscated." or "You were robbed.")
end

-- The robber carries your stuff; kill them to get it back
hook.Add("OnNPCKilled", "GFR_Surrender_StolenGear", function(npc)
	if npc.GFR_StolenGear && GFR.DropGearBag then GFR.DropGearBag(npc:GetPos(), npc.GFR_StolenGear) end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Left tied up for the dead: the bandits back off to a safe distance and watch. The first infected to reach you grabs
-- you, and tied up you can't fight it: you give in (sv_extract.lua GFR.GiveIn) - it feeds on you, wanders off, and
-- you get up as one of them, while they look on.
lines.watchBait = {"Here they come!", "Hah! Look at it squirm.", "Ring the dinner bell!", "Shh... wouldn't want to spoil it.", "Bet it doesn't last a minute."}
lines.baitEaten = {"Bon appetit.", "Hah! There it goes.", "Messy."}
lines.baitTurned = {"Ha! One of them now.", "Look - it's getting up!", "Welcome to the family. Time to go, boys."}

-- The bandits and the zombies coming for you leave each other alone meanwhile (they're not there for each other)
local function Ignore(group, z, on)
	for _, m in ipairs(group.members) do
		if IsValid(m) && m:Health() > 0 then
			m:AddEntityRelationship(z, on and D_NU or D_HT, 99)
			z:AddEntityRelationship(m, on and D_NU or D_HT, 99)
			if on && m:GetEnemy() == z then m:SetEnemy(NULL) end
		end
	end
end

local function StartBaitWatch(ply, group)
	group.noWanderT = CurTime() + 600 -- (sv_groupwander.lua: they stay to watch)
	-- Back off: about 15 m away from you, on the side they're on
	local center, n = Vector(0, 0, 0), 0
	for _, m in ipairs(group.members) do if IsValid(m) && m:Health() > 0 then center = center + m:GetPos() n = n + 1 end end
	if n == 0 then return end
	center = center / n
	local away = center - ply:GetPos()
	away.z = 0
	if away:LengthSqr() < 1 then away = VectorRand() away.z = 0 end
	local spot = ply:GetPos() + away:GetNormalized() * 800
	for i, m in ipairs(group.members) do
		if IsValid(m) && m:Health() > 0 then
			m:SetLastPosition(spot + Vector(math.Rand(-120, 120), math.Rand(-120, 120), 0) * (i == 1 and 0 or 1))
			m:SetSchedule(SCHED_FORCED_GO_RUN)
		end
	end
end

local function EndBaitWatch(group, lured)
	if !group then return end
	group.noWanderT = CurTime() + 20
	for z in pairs(lured or {}) do
		if IsValid(z) then Ignore(group, z, false) end
	end
end

local function LureZombies(ply)
	local bait = ply.GFR_Bait
	for _, z in ipairs(ents.FindInSphere(ply:GetPos(), 3000)) do
		if z:IsNPC() && GFR.IsZombie(z) && !z.GFR_ControlPlayer then
			if z.ForceSetEnemy then z:ForceSetEnemy(ply, true) else z:SetEnemy(ply) end
			z:UpdateEnemyMemory(ply, ply:GetPos())
			if bait && !bait.lured[z] then
				bait.lured[z] = true
				Ignore(bait.group, z, true)
			end
		end
	end
	-- And a couple more drawn in by the noise
	if GFR.Spawner then
		for _ = 1, 2 do
			local pos = GFR.Spawner.FindSpawnSpot(700, 1400)
			local z = pos && GFR.Spawner.SpawnZombie(pos)
			if IsValid(z) then
				timer.Simple(1, function()
					if IsValid(z) && IsValid(ply) then
						if z.ForceSetEnemy then z:ForceSetEnemy(ply, true) else z:SetEnemy(ply) end
						z:UpdateEnemyMemory(ply, ply:GetPos())
						local b = ply.GFR_Bait
						if b && !b.lured[z] then b.lured[z] = true Ignore(b.group, z, true) end
					end
				end)
			end
		end
	end
end

-- Tied up as bait: the zombies can't kill you outright (you'd just die, not turn) - the first infected to reach you
-- grabs you, and you give in
hook.Add("EntityTakeDamage", "GFR_Surrender_BaitNoKill", function(target, dmg)
	if !target:IsPlayer() or !target.GFR_Bait then return end
	local att = dmg:GetAttacker()
	if IsValid(att) && att:IsNPC() && GFR.IsZombie(att) then return true end
end)

timer.Create("GFR_Surrender_Bait", 0.25, 0, function()
	for _, ply in ipairs(player.GetAll()) do
		local b = ply.GFR_Bait
		if !b then
			-- What the bandits do after: watch you turn, then move on
			local w = ply.GFR_BaitWatched
			if w then
				if ply.GFR_IsZombie && !w.turned then
					w.turned = true
					local m = NearestMember(w.group, ply:GetPos())
					if m then Say(m, Line(lines.baitTurned)) end
					timer.Simple(8, function() EndBaitWatch(w.group, w.lured) end)
					ply.GFR_BaitWatched = nil
				elseif CurTime() > w.untilT then
					EndBaitWatch(w.group, w.lured)
					ply.GFR_BaitWatched = nil
				end
			end
			continue
		end
		if !ply:Alive() then
			Untie(ply)
			continue
		end
		local now = CurTime()
		-- The first infected to reach you takes you
		local grabber
		for _, z in ipairs(ents.FindInSphere(ply:GetPos(), 85)) do
			if z:IsNPC() && z:Health() > 0 && GFR.IsZombie(z) && !z.GFR_ControlPlayer then grabber = z break end
		end
		if grabber then
			local group, lured = b.group, b.lured
			Untie(ply) -- (GFR_Tied off: giving in takes it from here)
			ply.GFR_BaitWatched = {group = group, lured = lured, untilT = now + 120}
			local m = NearestMember(group, ply:GetPos())
			if m then Say(m, Line(lines.baitEaten)) end
			if grabber.GFR_StartGrab && grabber.GFR_CanGrab && grabber:GFR_CanGrab(ply) then
				grabber:GFR_StartGrab(ply)
				GFR.Notify(ply, "It has you. Tied up, there's nothing you can do...")
				timer.Simple(1.2, function() if IsValid(ply) && ply.GOTDR_Grappled then GFR.GiveIn(ply) end end)
			elseif GFR.CollapseIntoZombie then
				-- (a zombie that can't grab: it just drags you down)
				GFR.Notify(ply, "They drag you down. Tied up, there's nothing you can do...")
				GFR.CollapseIntoZombie(ply, grabber.GFR_FeedOn and grabber or nil)
			end
			continue
		end
		-- Keep them coming (they lose interest), the bandits jeering from where they watch
		if now > b.nextLure then
			b.nextLure = now + 5
			LureZombies(ply)
			-- Nobody's come for a while: something hears you
			if now - b.start > 60 && GFR.Spawner && (b.nextSpawn or 0) < now then
				b.nextSpawn = now + 30
				local pos = GFR.Spawner.FindSpawnSpot(500, 900)
				if pos then GFR.Spawner.SpawnZombie(pos) end
			end
		end
		if now > b.nextJeer then
			b.nextJeer = now + math.Rand(10, 18)
			local m = NearestMember(b.group, ply:GetPos())
			if m then Say(m, Line(lines.watchBait)) end
		end
		-- They keep their eyes on the show
		if (b.nextFace or 0) < now then
			b.nextFace = now + 2
			for _, m in ipairs(b.group.members) do
				if IsValid(m) && m:Health() > 0 && !m:IsMoving() then
					m:SetTarget(ply)
					m:SetSchedule(SCHED_TARGET_FACE)
				end
			end
		end
	end
end)

local function StartBait(ply, group, captor)
	if IsValid(captor) then Say(captor, Line(lines.zombies)) end
	SpareFor(ply, group, 600)
	ply.GFR_Surrender = nil
	ply.GFR_Captive = nil
	ply.GFR_Bait = {group = group, start = CurTime(), nextLure = CurTime() + 5, nextJeer = CurTime() + 8, lured = {}}
	GFR.Notify(ply, "They leave you tied up for the dead. There's nothing you can do but watch them come.")
	StartBaitWatch(ply, group)
	LureZombies(ply)
end

local function Shoot(ply, captor, delay, line)
	if line && IsValid(captor) then Say(captor, line) end
	timer.Simple(delay or 2, function()
		if !IsValid(ply) or !ply:Alive() or !ply.GFR_Tied or !IsValid(captor) then return end
		captor:EmitSound("Weapon_Pistol.Single")
		ply.GFR_Executed = true
		ply:Freeze(false)
		local dmg = DamageInfo()
		dmg:SetDamage(ply:Health() + 200)
		dmg:SetDamageType(DMG_BULLET)
		dmg:SetAttacker(captor)
		dmg:SetInflictor(captor)
		ply:TakeDamageInfo(dmg)
	end)
end

local function Execute(ply, captor) Shoot(ply, captor, 2, Line(lines.execute)) end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Bandit games: some bandits keep you around for their amusement. Every so often one of them comes over with a twisted
-- choice (E yes / SPACE no, saying nothing is saying no):
--   Meat      raw dead flesh dropped at your feet - eat it off the floor like one of them, or get shot
--   Roulette  one round in the cylinder - pull the trigger on yourself, or they pull theirs
--   Beg       beg for your life - they might laugh, they might kick you anyway; refuse and they beat you
--   Run       "ten second head start" - run for it (they come hunting after), or stay and get beaten for spoiling it
-- After a few games they decide what to do with you: kill you, leave you tied for the dead, keep you for another round,
-- or (rarely, if you amused them) let you go. How you played changes the odds.
lines.captive = {"Oh, we're not done with you.", "Don't kill it yet. I'm bored.", "Let's have some fun first."}
lines.captiveIdle = {"Comfy down there?", "Don't go anywhere, now.", "Bet it's thinking about running.", "What should we do with it next?", "Quiet, meat."}
lines.laugh = {"Hahaha!", "Ha! It actually did it!", "Look at it!", "Good dog.", "Again! Again!"}
lines.spoil = {"Boring.", "Wrong answer.", "You're no fun."}
lines.keep = {"We'll keep this one around. For now.", "Nah, not yet. Tie it tighter.", "It's still fun. It stays."}
lines.letGo = {"Alright, you earned it. Get lost before I change my mind.", "Go on. Tell your friends how nice we were."}
lines.runOut = {"Time's up!", "Here we come, rabbit!", "Ready or not!"}

local GAMES = {
	meat = {weight = 30, ask = {"Hungry? There. Eat it off the floor like one of them.", "Dinner's served. On your knees - eat it, or eat a bullet."}, yes = "Eat it", no = "Refuse"},
	roulette = {weight = 25, ask = {"One round, six chambers. You pull it... or I pull mine.", "Let's play a game. Gun to your head - your finger, your call."}, yes = "Pull the trigger", no = "Refuse"},
	beg = {weight = 30, ask = {"Beg. Make it convincing.", "Go on, beg for your life. Louder."}, yes = "Beg", no = "Stay silent"},
	run = {weight = 15, ask = {"Tell you what. Ten second head start. Run.", "I'll let you go. Run, rabbit. Ten seconds."}, yes = "Run", no = "Stay put"}
}
local CHOICE_TIME = 12

local meatClasses = {"meat_chunk1", "meat_chunk2", "meat_arm1", "meat_leg1"}

local function Captor(c)
	if !IsValid(c.captor) or c.captor:Health() <= 0 then c.captor = NearestMember(c.group, c.ply:GetPos()) end
	return c.captor
end

-- A kick or the butt of a rifle: hurts, never kills
local function Beat(ply, captor, amount)
	if !IsValid(ply) or !ply:Alive() then return end
	ply:EmitSound("physics/body/body_medium_impact_hard" .. math.random(1, 6) .. ".wav")
	ply:ViewPunch(Angle(math.Rand(-12, -6), math.Rand(-10, 10), math.Rand(-8, 8)))
	ply:SetHealth(math.max(ply:Health() - amount, 5))
	ply:ScreenFade(SCREENFADE.IN, Color(120, 0, 0, 120), 0.4, 0)
end

local function Ask(ply, kind)
	local c = ply.GFR_Captive
	local game = GAMES[kind]
	local captor = Captor(c)
	ply.GFR_Choice = {kind = kind, endT = CurTime() + CHOICE_TIME, held = true}
	ply:SetNW2String("GFR_ChoiceText", game.yes .. "|" .. game.no)
	ply:SetNW2Float("GFR_ChoiceEnd", CurTime() + CHOICE_TIME)
	ply:SetNW2Float("GFR_ChoiceLen", CHOICE_TIME)
	Say(captor, Line(game.ask))

	if kind == "meat" then
		-- Dropped at your feet
		local class = meatClasses[math.random(#meatClasses)]
		local pos = ply:GetPos() + ply:GetForward() * 28 + Vector(0, 0, 8)
		local ent = scripted_ents.GetStored(class) && ents.Create(class) or ents.Create("prop_physics")
		if IsValid(ent) then
			if ent:GetClass() == "prop_physics" then ent:SetModel("models/crunchy/props/fallout_props/gorelegb03.mdl") end
			ent:SetPos(pos)
			ent:Spawn()
			ent.GFR_NoPickup = true
			ply.GFR_Choice.meat = ent
			ply.GFR_Choice.meatClass = class
		end
	end
end

local function NextGame(c)
	local pool, total = {}, 0
	for kind, g in pairs(GAMES) do
		if kind != c.last then pool[kind] = g.weight total = total + g.weight end
	end
	local roll = math.Rand(0, total)
	for kind, w in pairs(pool) do
		roll = roll - w
		if roll <= 0 then return kind end
	end
	return "beg"
end

local function Verdict(ply)
	local c = ply.GFR_Captive
	local captor, group = Captor(c), c.group
	local amuse = c.amuse
	local w = {
		kill = math.max(35 - amuse * 3, 10),
		bait = 35,
		keep = c.rounds < 2 && (20 + amuse * 4) or 0,
		letGo = math.Clamp(amuse * 2, 0, 15)
	}
	local total = 0
	for _, v in pairs(w) do total = total + v end
	local roll, pick = math.Rand(0, total), "kill"
	for k, v in pairs(w) do
		roll = roll - v
		if roll <= 0 then pick = k break end
	end

	if pick == "keep" then
		Say(captor, Line(lines.keep))
		c.rounds = c.rounds + 1
		c.games = 0
		c.target = math.random(2, 3)
		c.nextGame = CurTime() + math.Rand(30, 50)
	elseif pick == "letGo" then
		ply.GFR_Captive = nil
		Release(ply, group, nil)
		if IsValid(captor) then Say(captor, Line(lines.letGo)) end
		group.noWanderT = CurTime() + 10
	elseif pick == "bait" then
		StartBait(ply, group, captor)
	else
		ply.GFR_Captive = nil
		group.noWanderT = CurTime() + 10
		Execute(ply, captor)
	end
end

-- Your answer (E / SPACE), or none when time runs out
function GFR.SurrenderAnswer(ply, yes)
	local c, choice = ply.GFR_Captive, ply.GFR_Choice
	if !c or !choice then return end
	ply.GFR_Choice = nil
	ply:SetNW2String("GFR_ChoiceText", "")
	local captor = Captor(c)
	if !IsValid(captor) then return end
	local kind = choice.kind
	c.last = kind
	c.games = c.games + 1
	c.nextGame = CurTime() + math.Rand(35, 60)
	local function Done() if IsValid(choice.meat) then choice.meat:Remove() end end

	if kind == "meat" then
		if yes then
			-- Down on the floor, chewing raw dead flesh, while they watch
			GFR.Notify(ply, "You lean down and tear into it. They howl with laughter.")
			ply:ViewPunch(Angle(20, 0, 0))
			for i = 0, 3 do
				timer.Simple(i * 0.8, function() if IsValid(ply) then ply:EmitSound("npc/barnacle/barnacle_crunch" .. math.random(2, 3) .. ".wav", 65) end end)
			end
			timer.Simple(3.2, function()
				if !IsValid(ply) then return end
				local class = choice.meatClass or "meat_chunk1"
				hook.Run("GFR_ItemUsed", ply, class, choice.meat) -- filling - and the raw flesh may infect you (sv_infection.lua)
				Done()
				if IsValid(captor) then Say(captor, Line(lines.laugh)) end
			end)
			c.amuse = c.amuse + 2
		else
			Done()
			ply.GFR_Captive = nil
			c.group.noWanderT = CurTime() + 10
			Shoot(ply, captor, 1.5, Line(lines.spoil))
		end

	elseif kind == "roulette" then
		if yes then
			ply:EmitSound("weapons/357/357_spin1.wav")
			timer.Simple(1.2, function()
				if !IsValid(ply) or !ply:Alive() then return end
				if math.random(1, 6) == 1 then
					ply:EmitSound("weapons/357/357_fire2.wav", 90)
					ply.GFR_Executed = true
					ply.GFR_Captive = nil
					local dmg = DamageInfo()
					dmg:SetDamage(ply:Health() + 200)
					dmg:SetDamageType(DMG_BULLET)
					dmg:SetAttacker(ply)
					dmg:SetInflictor(ply)
					ply:TakeDamageInfo(dmg)
					if IsValid(captor) then Say(captor, "Ooh. Unlucky.") end
					c.group.noWanderT = CurTime() + 10
				else
					ply:EmitSound("weapons/pistol/pistol_empty.wav", 75)
					ply:ViewPunch(Angle(-4, 0, 0))
					GFR.Notify(ply, "*click*")
					if IsValid(captor) then Say(captor, Line(lines.laugh)) end
				end
			end)
			c.amuse = c.amuse + 3
		else
			ply.GFR_Captive = nil
			c.group.noWanderT = CurTime() + 10
			Shoot(ply, captor, 1.5, "Then I'll do it for you.")
		end

	elseif kind == "beg" then
		if yes then
			GFR.Notify(ply, "You beg. Your voice cracks.")
			if math.random(1, 2) == 1 then
				Say(captor, Line(lines.laugh))
				c.amuse = c.amuse + 1
			else
				Say(captor, "Pathetic.")
				timer.Simple(0.8, function() Beat(ply, captor, 15) end)
			end
		else
			Say(captor, "Proud one, huh? Let's fix that.")
			for i = 0, 2 do timer.Simple(0.8 + i * 0.7, function() Beat(ply, captor, 12) end) end
			c.amuse = c.amuse - 1
		end

	elseif kind == "run" then
		if yes then
			-- A real chance: ten seconds, then they hunt you down
			local group = c.group
			Untie(ply)
			SpareFor(ply, group, 10) -- (everyone who was holding fire, too)
			ply.GFR_CaptureGroups = nil
			group.noWanderT = CurTime() + 60
			Refresh(group)
			GFR.Notify(ply, "RUN.")
			Say(captor, "Go on then! Ten... nine...")
			timer.Simple(10, function()
				Refresh(group)
				local m = IsValid(ply) && NearestMember(group, ply:GetPos())
				if m then Say(m, Line(lines.runOut)) end
			end)
			return
		else
			Say(captor, Line(lines.spoil))
			timer.Simple(0.8, function() Beat(ply, captor, 20) end)
			c.amuse = c.amuse - 1
		end
	end

	-- Enough games: what now?
	if ply.GFR_Captive == c && c.games >= c.target then
		c.nextGame = math.huge
		timer.Simple(6, function()
			if IsValid(ply) && ply:Alive() && ply.GFR_Captive == c && ply.GFR_Tied then Verdict(ply) end
		end)
	end
end

local function StartCaptive(ply, group, captor)
	Say(captor, Line(lines.captive))
	timer.Simple(2, function()
		if !IsValid(ply) or !ply.GFR_Tied or !IsValid(captor) then return end
		Rob(ply, captor, group.faction) -- (they take your guns first, of course)
		SpareFor(ply, group, 900)
		ply.GFR_Surrender = nil
		local now = CurTime()
		ply.GFR_Captive = {ply = ply, group = group, captor = captor, games = 0, target = math.random(2, 3), rounds = 1, amuse = 0,
			nextGame = now + math.Rand(12, 20), nextJeer = now + math.Rand(15, 25)}
		GFR.Notify(ply, "They're keeping you around. Bandits get bored...")
	end)
end

timer.Create("GFR_Surrender_Captive", 0.25, 0, function()
	local now = CurTime()
	for _, ply in ipairs(player.GetAll()) do
		local c = ply.GFR_Captive
		if !c then continue end
		if !ply:Alive() or !ply.GFR_Tied then
			if IsValid(ply.GFR_Choice && ply.GFR_Choice.meat) then ply.GFR_Choice.meat:Remove() end
			Untie(ply)
			continue
		end
		c.group.noWanderT = now + 30 -- (sv_groupwander.lua: they stay with their prisoner)
		if (c.group.truce[ply] or 0) < now + 600 then SpareFor(ply, c.group, 900) end
		local captor = Captor(c)
		if !captor then
			-- Nobody left to hold you
			if IsValid(ply.GFR_Choice && ply.GFR_Choice.meat) then ply.GFR_Choice.meat:Remove() end
			Untie(ply)
			GFR.Notify(ply, "Your captors are dead. You work the ropes loose.")
			continue
		end

		local choice = ply.GFR_Choice
		if choice then
			if now > choice.endT && !choice.answered then
				choice.answered = true
				GFR.SurrenderAnswer(ply, false) -- (saying nothing is saying no)
			end
			continue
		end

		if now > c.nextGame then
			-- Come over first
			if captor:GetPos():Distance(ply:GetPos()) > 140 then
				if !captor:IsMoving() then
					captor:SetLastPosition(ply:GetPos() + (captor:GetPos() - ply:GetPos()):GetNormalized() * 70)
					captor:SetSchedule(SCHED_FORCED_GO)
				end
				if now - c.nextGame < 8 then continue end
			end
			captor:SetTarget(ply)
			captor:SetSchedule(SCHED_TARGET_FACE)
			Ask(ply, NextGame(c))
			continue
		end

		if now > c.nextJeer then
			c.nextJeer = now + math.Rand(18, 30)
			local m = NearestMember(c.group, ply:GetPos())
			if m then Say(m, Line(lines.captiveIdle)) end
		end
		if (c.nextFace or 0) < now then
			c.nextFace = now + 3
			for _, m in ipairs(c.group.members) do
				if IsValid(m) && m:Health() > 0 && !m:IsMoving() && m:GetPos():Distance(ply:GetPos()) < 1200 then
					m:SetTarget(ply)
					m:SetSchedule(SCHED_TARGET_FACE)
				end
			end
		end
	end
end)

local function DecideFate(ply)
	local s = ply.GFR_Surrender
	if !IsValid(ply) or !ply:Alive() or !s or !ply.GFR_Tied then return end
	local captor, group = s.captor, s.group
	if !IsValid(captor) then Release(ply, group) return end
	local faction = group.faction
	local fate = PickFate(faction)

	if fate == "rob" then
		Say(captor, Line(lines.rob[faction] or lines.rob.bandit))
		timer.Simple(2.5, function()
			if !IsValid(ply) or !ply.GFR_Tied or !IsValid(captor) then return end
			Rob(ply, captor, faction)
			timer.Simple(1.5, function() Release(ply, group, captor) end)
		end)

	elseif fate == "inject" then
		Say(captor, Line(lines.inject))
		timer.Simple(2.5, function()
			if !IsValid(ply) or !ply.GFR_Tied or !IsValid(captor) then return end
			ply:EmitSound("items/medshot4.wav")
			Rob(ply, captor, faction)
			-- Their experimental vial: you go down and get back up as a hunter, one they don't control and you don't either
			if GFR.HunterTurnPlayer && GFR.HunterClass && GFR.HunterClass() then
				GFR.Notify(ply, "They inject you with a blue vial. Your heart races... then everything locks up.")
				Untie(ply)
				SpareFor(ply, group, 60)
				ply.GFR_CaptureGroups = nil
				GFR.HunterTurnPlayer(ply)
			else
				GFR.Infect(ply, 15)
				GFR.Notify(ply, "They inject you with something... you feel cold.")
				timer.Simple(2, function() Release(ply, group, captor) end)
			end
		end)

	elseif fate == "games" then
		StartCaptive(ply, group, captor)

	elseif fate == "zombies" then
		StartBait(ply, group, captor)

	else -- execute
		Execute(ply, captor)
	end
end

local function Tie(ply)
	local s = ply.GFR_Surrender
	ply.GFR_CaptureGroups = s.groups
	ply.GFR_Tied = true -- (held in place by StartCommand above, free to look around)
	ply:SetNW2Bool("GFR_Tied", true)
	ply:SetNW2Bool("GFR_HandsUp", false)
	ply:EmitSound("physics/cardboard/cardboard_box_impact_soft" .. math.random(1, 7) .. ".wav")
	Say(s.captor, Line(lines.tie))
	GFR.Notify(ply, "You've been tied up.")
	timer.Simple(3, function() DecideFate(ply) end)
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Surrendering
local function CancelSurrender(ply, msg)
	local s = ply.GFR_Surrender
	if !s or ply.GFR_Tied then return end
	ply.GFR_Surrender = nil
	ply:SetNW2Bool("GFR_HandsUp", false)
	for _, g in ipairs(s.groups or {s.group}) do
		g.truce[ply] = nil
		Refresh(g)
	end
	if msg then GFR.Notify(ply, msg) end
end

-- Stop shooting NOW: a relationship change alone doesn't make an NPC drop the target it's already firing at
local function HoldFire(group, ply)
	for _, m in ipairs(group.members) do
		if IsValid(m) && m:Health() > 0 then
			if m:GetEnemy() == ply then m:SetEnemy(NULL) end
			if m.ClearEnemyMemory then m:ClearEnemyMemory(ply) end
			m:SetSchedule(SCHED_ALERT_FACE)
		end
	end
end

local function StartSurrender(ply)
	-- Every hostile group in earshot holds fire (bandits, angry survivors, soldiers); the closest one comes for you
	local best, bestD, bestG
	local near = {}
	for _, group in ipairs(GFR.Spawner && GFR.Spawner.Groups() or {}) do
		if IsHostile(group, ply) then
			local m, d = NearestMember(group, ply:GetPos())
			if m && d < 2500 then
				near[#near + 1] = group
				if !best or d < bestD then best, bestD, bestG = m, d, group end
			end
		end
	end
	if !best then
		GFR.Notify(ply, "There's no one here to surrender to.")
		return
	end
	ply.GFR_Surrender = {captor = best, group = bestG, groups = near, start = CurTime(), bestDist = bestD, closingT = CurTime()}
	ply:SetNW2Bool("GFR_HandsUp", true)
	if ply:HasWeapon(GFR.Fists()) then ply:SelectWeapon(GFR.Fists()) end
	for _, g in ipairs(near) do
		g.truce[ply] = CurTime() + 120
		if g.warning then g.warning[ply] = nil end
		Refresh(g)
		HoldFire(g, ply)
	end
	Say(best, Line(lines.approach))
	GFR.Notify(ply, "Hands up. They're coming to you - or walk over to them. J again to change your mind.")
end

hook.Add("PlayerButtonDown", "GFR_Surrender_Keys", function(ply, button)
	if !cvEnabled:GetBool() or !ply:Alive() then return end
	if button == KEY_J then
		-- In a zombie's grip or with a parasite on you, J means giving in (sv_extract.lua / sv_parasite.lua)
		if ply.GFR_Tied or ply.GOTDR_Grappled or ply.GFR_ParasiteLatch or ply.GFR_GivingIn or ply.GFR_IsZombie then return end
		if ply.GFR_Surrender then
			CancelSurrender(ply, "You lower your hands.")
		else
			StartSurrender(ply)
		end
	elseif button == KEY_SPACE && ply.GFR_Struggling then
		local v = ply:GetNW2Float("GFR_Struggle", 0) + cvStruggle:GetFloat()
		ply:SetNW2Float("GFR_Struggle", v)
		if v >= 100 then
			Untie(ply)
			GFR.Notify(ply, "You wriggle free!")
		elseif math.random(1, 3) == 1 then
			ply:EmitSound("physics/body/body_medium_impact_soft" .. math.random(1, 7) .. ".wav", 55)
		end
	end
end)

-- Hands up / tied: no shooting
hook.Add("StartCommand", "GFR_Surrender_NoAttack", function(ply, cmd)
	if ply:GetNW2Bool("GFR_HandsUp") or ply:GetNW2Bool("GFR_Tied") then
		cmd:RemoveKey(IN_ATTACK)
		cmd:RemoveKey(IN_ATTACK2)
		cmd:RemoveKey(IN_RELOAD)
	end
end)

hook.Add("GFR_GroupProvoked", "GFR_Surrender_Provoked", function(group, ply)
	if group.warning then group.warning[ply] = nil end
	local s = ply.GFR_Surrender
	if s && !ply.GFR_Tied then
		for _, g in ipairs(s.groups or {s.group}) do
			if g == group then CancelSurrender(ply) break end
		end
	end
end)

hook.Add("PlayerDeath", "GFR_Surrender_Death", function(ply)
	if ply.GFR_Tied or ply.GFR_Surrender then Untie(ply) end
end)

hook.Add("PlayerSpawn", "GFR_Surrender_Spawn", function(ply)
	Untie(ply)
	ply.GFR_Executed = nil
end)

---------------------------------------------------------------------------------------------------------------------------------------------
timer.Create("GFR_Surrender_Tick", 0.5, 0, function()
	if !cvEnabled:GetBool() or !GFR.Spawner then return end
	local now = CurTime()

	for _, ply in ipairs(player.GetAll()) do
		if !ply:Alive() then continue end

		-- Struggling slowly loses progress
		if ply.GFR_Struggling then
			ply:SetNW2Float("GFR_Struggle", math.max(ply:GetNW2Float("GFR_Struggle", 0) - 1, 0))
		end

		-- Captor walking over to tie you
		local s = ply.GFR_Surrender
		if s && !ply.GFR_Tied then
			if !IsValid(s.captor) or s.captor:Health() <= 0 then
				s.captor = NearestMember(s.group, ply:GetPos())
			end
			if !IsValid(s.captor) or now - s.start > 60 then
				CancelSurrender(ply, "Nobody came for you.")
			else
				for _, g in ipairs(s.groups or {s.group}) do g.truce[ply] = now + 60 end
				local d = s.captor:GetPos():Distance(ply:GetPos())
				if d <= 90 then
					Tie(ply)
				else
					-- They come to you; without AI nodes they can get stuck, so if they stop closing in,
					-- they wave you over instead (walking up to them with your hands up works too)
					if d < s.bestDist - 20 then s.bestDist, s.closingT = d, now end
					if now - s.closingT > 5 && !s.waved then
						s.waved = true
						Say(s.captor, Line({"Over here. Slowly.", "Walk to me. Hands where I can see them.", "Come here. Nice and easy."}))
						GFR.Notify(ply, "They want you to walk over to them. Keep your hands up.")
					end
					s.captor:SetLastPosition(ply:GetPos())
					s.captor:SetSchedule(SCHED_FORCED_GO_RUN)
				end
			end
		end
	end

	-- Warning shouts
	for _, group in ipairs(GFR.Spawner.Groups()) do
		group.encounter = group.encounter or {}
		group.warning = group.warning or {}
		for _, ply in ipairs(player.GetAll()) do
			if !ply:Alive() or ply.GFR_Surrender or ply.GFR_Tied or ply.GFR_Struggling then continue end
			local m, dist = NearestMember(group, ply:GetPos())
			if !m then continue end
			if dist > 3000 then group.encounter[ply] = nil end

			local warnUntil = group.warning[ply]
			if warnUntil then
				if dist > 2000 then
					group.warning[ply] = nil
					group.truce[ply] = now + 90
					Say(m, Line(lines.left))
					Refresh(group)
				elseif now > warnUntil then
					group.warning[ply] = nil
					group.truce[ply] = nil
					Say(m, Line(lines.tooSlow))
					Refresh(group)
				end
			elseif IsHostile(group, ply) && !group.encounter[ply] && dist < 1500 && (group.truce[ply] or 0) < now && m:Visible(ply) then
				group.encounter[ply] = true
				-- Bandits like to rob first; angry survivors/soldiers rarely bother
				local chance = cvWarn:GetFloat() * (group.attitude == D_HT and 1 or 0.5)
				if math.Rand(0, 100) < chance then
					group.warning[ply] = now + 10
					group.truce[ply] = now + 11
					Say(m, Line(lines.warn[group.faction] or lines.warn.bandit))
					GFR.Notify(ply, "[J] Surrender  -  or leave the area")
					Refresh(group)
				end
			end
		end
	end
end)
