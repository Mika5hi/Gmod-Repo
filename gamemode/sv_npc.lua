--[[
	Custom Apocalypse - talking, trading and quests with friendly/neutral survivors and military

	E on a person         opens the dialog (hostile ones just tell you to back off)
	Trade                 buy/sell for caps. Survivors: food, water, basic meds, loose ammo, the odd pistol.
	                      Military: medkits, ammo boxes, armor, grenades, rifles. Nobody buys blood-soaked items.
	Work (quests)         fetch items / kill zombies / clear a bandit group / rescue a lost survivor.
	                      Up to 3 at a time, tracked top-right with markers. Return to the giver to get paid.
]]

util.AddNetworkString("GFR_Dialog")
util.AddNetworkString("GFR_DialogAction")
util.AddNetworkString("GFR_Trade")
util.AddNetworkString("GFR_Quests")

local TALK_RANGE = 200
local MAX_QUESTS = 3

---------------------------------------------------------------------------------------------------------------------------------------------
-- Item values (caps)
local perRound = {pistol = 0.6, smg1 = 0.9, ar2 = 1.1, ["357"] = 2, buckshot = 1.2, smg1_grenade = 15, rpg_round = 40}

-- Recipes sold by traders are stock entries named "recipe:<id>"
local function RecipeOf(class)
	return string.StartWith(class, "recipe:") && GFR.RecipeById[string.sub(class, 8)]
end

function GFR.ItemValue(class)
	local recipe = RecipeOf(class)
	if recipe then return (recipe.cat == "Weapons" or recipe.cat == "Ammo") and 110 or 60 end
	if class == "gfr_item_hvial" then return 260 end -- classified research (sv_hunter.lua)
	local ammo = GFR.AmmoItems[class]
	if ammo then return math.max(2, math.Round(ammo.amount * (perRound[string.lower(ammo.type)] or 1))) end

	-- EFT Medical Items are weapons but priced as meds
	local eftMed = {weapon_eft_cat = 15, weapon_eft_alusplint = 12, weapon_eft_anaglin = 14, weapon_eft_augmentin = 35,
		weapon_eft_automedkit = 30, weapon_eft_salewa = 35, weapon_eft_afak = 45, weapon_eft_grizzly = 60, weapon_eft_surgicalkit = 50,
		weapon_eft_injectormorphine = 25, weapon_eft_injectortg12 = 90, weapon_eft_injectoradrenaline = 30, weapon_eft_injectorl1 = 30,
		weapon_eft_injectorpropital = 40, weapon_eft_injectoretg = 40}
	if eftMed[class] then return eftMed[class] end

	local wep = weapons.Get(class)
	if wep then
		if string.find(class, "melee", 1, true) then return 20 end
		local a = string.lower(GFR.WeaponAmmo(class) or "")
		local ht = string.lower(wep.HoldType or "")
		local handgun = ht == "pistol" or ht == "revolver"
		if a == "grenade" then return 25 end
		if a == "pistol" then return handgun and 60 or 120 end
		if a == "smg1" then return 180 end
		if a == "ar2" then return 200 end
		if a == "357" then return handgun and 100 or 350 end
		if a == "buckshot" then return 110 end
		if a == "smg1_grenade" or a == "rpg_round" then return 300 end
		return 100
	end

	local t = GFR.Treatments && GFR.Treatments[class]
	if t && t.pushback then return class == "zps_inoculator" and 90 or 50 end
	if GFR.Medkits && GFR.Medkits[class] then return 30 end
	if GFR.Bandages && GFR.Bandages[class] then return 8 end
	if t then return 14 end
	local n = GFR.Nutrition && GFR.Nutrition[class]
	if n then return math.max(3, math.Round(((n.hunger or 0) + (n.thirst or 0) + (n.stamina or 0) * 0.5) / 4)) end
	local cat = GFR.ItemCategory(class)
	if cat == "armor" then return (class == "contagion_armor_heavy" or class == "stalker_armor_medium") and 120 or 45 end
	if cat == "medical" then return 12 end
	return 5
end

local function ItemName(class)
	local recipe = RecipeOf(class)
	if recipe then return "Recipe: " .. recipe.name end
	local stored = scripted_ents.GetStored(class)
	if stored then return GFR.CleanName(stored.t.PrintName or class) end
	local wep = weapons.Get(class)
	if wep && wep.PrintName && wep.PrintName != "" then return wep.PrintName end
	return string.upper(string.gsub(class, "^arc9_eft_", ""))
end

local function ItemModel(class)
	if RecipeOf(class) then return "models/props_lab/clipboard.mdl" end
	local wep = weapons.GetStored(class)
	if wep then return wep.WorldModel end
	return GFR.ModelOf && GFR.ModelOf(class)
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Trader stock (per group)
local stockPlan = {
	survivor = {{"packaged", 3}, {"drink", 3}, {"meds_basic", 2}, {"ammo_loose", 3}, {"melee", 1}, {"gun_pistol", 0.5}, {"fresh", 1}, {"materials", 4}},
	military = {{"meds_good", 2}, {"ammo_box", 4}, {"armor", 1}, {"grenade", 1}, {"packaged", 2}, {"gun_military", 1}, {"gun_rifle", 0.5}, {"gun_smg", 0.5},
		{"gun_rare", 0.2}, {"meds_rare", 0.4}, {"materials", 2}}
}
local markup = {
	survivor = {sell = 1.3, buy = 0.5, caps = {60, 160}},
	military = {sell = 1.1, buy = 0.6, caps = {150, 400}}
}

local function GetTrade(group)
	if group.trade then return group.trade end
	local plan = stockPlan[group.faction] or stockPlan.survivor
	local m = markup[group.faction] or markup.survivor
	local stock = {}
	local function Add(class)
		for _, s in ipairs(stock) do
			if s.class == class then s.count = s.count + 1 return end
		end
		stock[#stock + 1] = {class = class, count = 1}
	end
	for _, p in ipairs(plan) do
		local n = p[2] >= 1 and p[2] or (math.Rand(0, 1) < p[2] and 1 or 0)
		for _ = 1, n do
			local class = GFR.Loot.PickItem(p[1])
			if class && class != "gfr_currency" && !string.StartWith(class, "supply_") then Add(class) end
		end
	end
	-- Soldiers sometimes part with one of their experimental vials (the only way to get one: sv_hunter.lua)
	if group.faction == "military" && math.Rand(0, 1) < 0.6 then Add("gfr_item_hvial") end
	-- A couple of recipes: survivors know medicine/building, the military weapons/ammo
	local recipeCats = group.faction == "military" and {Weapons = true, Ammo = true, Armor = true, Materials = true}
		or {Medical = true, Building = true, Survival = true, Materials = true}
	local candidates = {}
	for _, r in ipairs(GFR.Recipes) do
		if !r.known && recipeCats[r.cat] && GFR.RecipeAvailable(r) then candidates[#candidates + 1] = r end
	end
	for _ = 1, math.min(2, #candidates) do
		local r = table.remove(candidates, math.random(#candidates))
		stock[#stock + 1] = {class = "recipe:" .. r.id, count = 1}
	end

	group.trade = {stock = stock, caps = math.random(m.caps[1], m.caps[2]), m = m, faction = group.faction}
	return group.trade
end

local function SellPrice(trade, class) return math.max(1, math.Round(GFR.ItemValue(class) * trade.m.sell)) end
-- Zombie samples: the military pays well for research, survivors won't touch them
local samples = {gfr_mat_zblood = 30, meat_head = 40, meat_torso = 25}

local function BuyPrice(trade, class, contaminated)
	if samples[class] or string.StartWith(class, "meat_") then
		return trade.faction == "military" and (samples[class] or 15) or 0
	end
	if contaminated then return 0 end
	return math.max(1, math.Round(GFR.ItemValue(class) * trade.m.buy))
end

local function SendTrade(ply, npc)
	local trade = GetTrade(npc.GFR_Group)
	local stock, sell, weps = {}, {}, {}
	for i, s in ipairs(trade.stock) do
		stock[i] = {class = s.class, count = s.count, price = SellPrice(trade, s.class), name = ItemName(s.class), model = ItemModel(s.class)}
	end
	for i, e in ipairs(ply.GFR_Inv or {}) do
		sell[i] = {class = e.class, count = e.count, price = BuyPrice(trade, e.class, e.contaminated), name = GFR.CleanName(ItemName(e.class)), model = e.model, contaminated = e.contaminated}
	end
	for _, w in ipairs(ply:GetWeapons()) do
		local c = w:GetClass()
		if !GFR.IsFists(c) && weapons.Get(c) && !string.StartWith(c, "weapon_phys") && c != "gmod_tool" && c != "gmod_camera" then
			weps[#weps + 1] = {class = c, price = BuyPrice(trade, c), name = w.GetPrintName && w:GetPrintName() or ItemName(c), model = w:GetModel()}
		end
	end
	net.Start("GFR_Trade")
	net.WriteEntity(npc)
	net.WriteUInt(trade.caps, 16)
	net.WriteTable(stock)
	net.WriteTable(sell)
	net.WriteTable(weps)
	net.Send(ply)
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Quests
local function IsCleanFood(e) return GFR.ItemCategory(e.class) == "food" && !e.contaminated && !string.StartWith(e.class, "meat_") end

local fetchDefs = {
	{text = "Bring me %d drinks. Water, juice, anything.", n = {2, 3}, each = 12,
		match = function(e) return GFR.ItemCategory(e.class) == "drink" && !e.contaminated end},
	{text = "We're starving. Bring %d food. Nothing off the dead.", n = {3, 4}, each = 10, match = IsCleanFood},
	{text = "Find me %d bandages or painkillers.", n = {2, 3}, each = 14,
		match = function(e) return GFR.Bandages[e.class] or (GFR.Treatments[e.class] && GFR.Treatments[e.class].suppress == 180) end},
	{text = "Someone's hurt bad. Bring me %d medkit.", n = {1, 1}, each = 45, match = function(e) return GFR.Medkits[e.class] end},
	{ammo = true, n = {2, 3}, each = 18}
}
local ammoNames = {Pistol = "pistol rounds", Buckshot = "shotgun shells", SMG1 = "5.45/5.56 rounds", AR2 = "7.62 rounds"}

local function Compass(from, to)
	local dirs = {"east", "northeast", "north", "northwest", "west", "southwest", "south", "southeast"}
	local ang = math.deg(math.atan2(to.y - from.y, to.x - from.x)) % 360
	return dirs[math.floor((ang + 22.5) / 45) % 8 + 1]
end

local function NewQuest(group, npc, ply)
	local types = group.faction == "military" and {kill = 35, bandits = 40, fetch = 15, rescue = 10} or {fetch = 40, rescue = 25, kill = 25, bandits = 10}
	for _ = 1, 4 do
		local total, roll, qtype = 0, 0
		for _, w in pairs(types) do total = total + w end
		roll = math.Rand(0, total)
		for t, w in pairs(types) do
			roll = roll - w
			if roll <= 0 then qtype = t break end
		end
		local q = {type = qtype, giver = npc, group = group, progress = 0}

		if qtype == "fetch" then
			local def = fetchDefs[math.random(#fetchDefs)]
			q.need = math.random(def.n[1], def.n[2])
			q.reward = def.each * q.need + 10
			if def.ammo then
				-- Rounds from your ammo (found ammo goes straight in, it's never an item in the bag: sv_inventory.lua)
				local types2 = {"Pistol", "Buckshot", "SMG1", "AR2"}
				local at = types2[math.random(#types2)]
				q.ammoType = at
				q.need = q.need * (at == "Buckshot" and 8 or 15)
				q.match = function() return false end
				q.text = string.format("We're low on %s. Bring me %d.", ammoNames[at], q.need)
			else
				q.match = def.match
				q.text = string.format(def.text, q.need)
			end
			return q

		elseif qtype == "kill" then
			q.need = math.random(8, 15)
			q.text = string.format("Thin out the dead around here. Kill %d zombies.", q.need)
			q.reward = q.need * 3 + 10
			return q

		elseif qtype == "bandits" then
			local target = GFR.Spawner.SpawnGroup("bandit", nil, {keep = true, minDist = 1500, maxDist = 3500})
			if target && #target.members > 0 then
				q.target = target
				q.text = "Bandits have been raiding us. Wipe out the group to the " .. Compass(npc:GetPos(), target.members[1]:GetPos()) .. "."
				q.reward = 90
				q.rewardPool = group.faction == "military" and "ammo_box" or "meds_good"
				return q
			end

		elseif qtype == "rescue" then
			local lost = GFR.Spawner.SpawnGroup("survivor", nil, {keep = true, size = 1, attitude = D_LI, noWeapon = true, minDist = 1500, maxDist = 3500})
			local person = lost && lost.members[1]
			if IsValid(person) then
				q.lostGroup = lost
				q.person = person
				person.GFR_LostQuest = true
				q.text = "One of ours went missing out to the " .. Compass(npc:GetPos(), person:GetPos()) .. ". Find them and bring them back."
				q.reward = 70
				return q
			end
		end
		types[qtype] = nil
		if table.IsEmpty(types) then break end
	end
end

local function CountMatching(ply, q)
	if q.ammoType then return ply:GetAmmoCount(q.ammoType) end
	local n = 0
	for _, e in ipairs(ply.GFR_Inv or {}) do
		if q.match(e) then n = n + e.count end
	end
	return n
end

local function ReleaseQuestGroups(q)
	if q.target then q.target.keep = nil end
	if q.lostGroup then q.lostGroup.keep = nil end
end

local function GiverStillNeeded(group)
	for _, ply in ipairs(player.GetAll()) do
		for _, q in ipairs(ply.GFR_Quests or {}) do
			if q.group == group then return true end
		end
	end
	return false
end

local function RemoveQuest(ply, q)
	table.RemoveByValue(ply.GFR_Quests, q)
	ReleaseQuestGroups(q)
	if !GiverStillNeeded(q.group) then q.group.keep = nil end
end

local function QuestStatus(ply, q)
	if q.type == "fetch" then
		local have = math.min(CountMatching(ply, q), q.need)
		return have .. "/" .. q.need, have >= q.need
	elseif q.type == "kill" then
		return q.progress .. "/" .. q.need, q.progress >= q.need
	elseif q.type == "bandits" then
		local alive = 0
		for _, m in ipairs(q.target.members) do if IsValid(m) && m:Health() > 0 then alive = alive + 1 end end
		return alive > 0 and (alive .. " left") or "done", alive == 0
	elseif q.type == "rescue" then
		if q.home then return "brought home", true end
		return q.following and "follow you" or "missing", false
	end
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Dialog
local greetings = {
	survivor = {"Easy there. We don't want trouble.", "You look like you've been through hell.", "Another living face. Rare these days."},
	military = {"State your business, civilian.", "Keep your weapon lowered and we'll get along.", "Area's under military control. What do you need?"}
}
local smallTalk = {
	survivor = {
		"The dead eat each other if there's nothing else. Saw it with my own eyes.",
		"Don't eat anything you take off a body. Trust me.",
		"If you get bitten, find painkillers. Won't save you, but it buys time.",
		"Bandits are worse than the dead. At least the dead are honest."
	},
	military = {
		"Command says the infection spreads through blood. Keep your face covered.",
		"We've got orders to collect samples. Don't ask what kind.",
		"Bites are a death sentence. The meds just slow it down.",
		"Stay out of our way and we'll stay out of yours."
	}
}

local function CanTalk(ply, npc)
	return IsValid(npc) && npc.GFR_Group && npc:Health() > 0 && ply:Alive()
		&& npc:GetPos():DistToSqr(ply:GetPos()) < TALK_RANGE * TALK_RANGE
		&& GFR.Spawner.PlayerDisposition(npc.GFR_Group, ply) != D_HT
		&& npc.GFR_Group.faction != "bandit"
end

local function SendDialog(ply, npc, text)
	local group = npc.GFR_Group
	if !group.offer && CurTime() > (group.nextOffer or 0) && !npc.GFR_LostQuest then
		group.offer = NewQuest(group, npc, ply)
	end
	local myQuests = {}
	for i, q in ipairs(ply.GFR_Quests or {}) do
		if q.group == group then
			local status, ready = QuestStatus(ply, q)
			myQuests[#myQuests + 1] = {index = i, text = q.text, status = status, ready = ready}
		end
	end
	net.Start("GFR_Dialog")
	net.WriteEntity(npc)
	net.WriteString(group.faction)
	net.WriteString(text or "")
	net.WriteBool(!npc.GFR_LostQuest)
	net.WriteTable(group.offer && {text = group.offer.text, reward = group.offer.reward} or {})
	net.WriteTable(myQuests)
	net.WriteTable(GFR.RecruitOffer && GFR.RecruitOffer(ply, npc) or {}) -- "Come with me" (sv_companions.lua)
	net.Send(ply)
end

-- E on a person
hook.Add("KeyPress", "GFR_NPC_Talk", function(ply, key)
	if key != IN_USE or !ply:Alive() or ply.GFR_IsZombie or ply.GFR_Tied or ply:GetNW2Bool("GFR_HandsUp") then return end
	local tr = util.TraceLine({start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * TALK_RANGE * 0.7, filter = ply, mask = MASK_SHOT})
	local npc = tr.Entity
	if !IsValid(npc) or !npc.GFR_Group or npc:Health() <= 0 then return end

	-- Your own companion: their window (Crouch+E is the quick follow/hold order, sv_companions.lua)
	if npc.GFR_CompanionOf == ply then
		if !ply:Crouching() && GFR.OpenCompanion then GFR.OpenCompanion(ply, npc) end
		return
	end

	-- Lost survivor from a rescue quest
	for _, q in ipairs(ply.GFR_Quests or {}) do
		if q.person == npc && !q.following then
			q.following = true
			GFR.Say(npc, "Thank god! Get me out of here, I'll follow you.")
			return
		end
	end

	if !CanTalk(ply, npc) then
		if CurTime() > (npc.GFR_NextBark or 0) then
			GFR.Say(npc, npc.GFR_Group.faction == "bandit" and "You've got some nerve. Back off." or "Back off. Now.")
			npc.GFR_NextBark = CurTime() + 4
		end
		return
	end

	npc:SetSchedule(SCHED_IDLE_STAND)
	npc:SetIdealYawAndUpdate((ply:GetPos() - npc:GetPos()):Angle().y)
	local g = greetings[npc.GFR_Group.faction] or greetings.survivor
	SendDialog(ply, npc, npc.GFR_LostQuest and "I'm right behind you." or g[math.random(#g)])
end)

local function GiveReward(ply, q)
	GFR.AddCaps(ply, q.reward)
	-- They owe you now: one of them will come along for free (sv_companions.lua)
	q.group.helped = q.group.helped or {}
	q.group.helped[ply] = true
	local msg = "+ " .. q.reward .. " caps"
	if q.rewardPool then
		local class = GFR.Loot.PickItem(q.rewardPool)
		if class then
			if GFR.InvAdd(ply, class, 1, false, ItemModel(class)) == 0 then GFR.Loot.SpawnItem(class, ply:GetPos() + Vector(0, 0, 40)) end
			msg = msg .. ", " .. ItemName(class)
		end
	end
	GFR.Notify(ply, "Quest complete! " .. msg)
	-- Sometimes they teach you something too
	if math.random(1, 100) <= 40 && GFR.LearnRandomRecipe && #GFR.UnknownRecipes(ply) > 0 then
		timer.Simple(1, function() if IsValid(ply) then GFR.LearnRandomRecipe(ply) end end)
	end
end

net.Receive("GFR_DialogAction", function(_, ply)
	local npc = net.ReadEntity()
	local action = net.ReadString()
	local arg = net.ReadUInt(16)
	local argStr = net.ReadString()
	if !CanTalk(ply, npc) then return end
	local group = npc.GFR_Group
	ply.GFR_Quests = ply.GFR_Quests or {}

	if action == "talk" then
		local lines = smallTalk[group.faction] or smallTalk.survivor
		SendDialog(ply, npc, lines[math.random(#lines)])

	-- Actions (sv_actions.lua)
	elseif action == "push" then
		net.Start("GFR_Comp") net.WriteEntity(NULL) net.WriteTable({}) net.Send(ply) -- (closes the dialog)
		GFR.PushPerson(ply, npc)

	elseif action == "givefood" then
		local ok, reply, caps = GFR.GiveFoodTo(ply, npc)
		if caps then GFR.Notify(ply, "+ " .. caps .. " caps") end
		SendDialog(ply, npc, reply)

	elseif action == "trade" then
		SendTrade(ply, npc)

	elseif action == "recruit" then
		if !GFR.Recruit then return end
		local reply = GFR.Recruit(ply, npc)
		if npc.GFR_CompanionOf == ply then
			GFR.Say(npc, reply)
			net.Start("GFR_Comp") net.WriteEntity(NULL) net.WriteTable({}) net.Send(ply) -- closes the dialog
		else
			SendDialog(ply, npc, reply)
		end

	elseif action == "accept" then
		local q = group.offer
		if !q then return end
		if #ply.GFR_Quests >= MAX_QUESTS then
			SendDialog(ply, npc, "You've got your hands full already. Come back when you've done some of it.")
			return
		end
		group.offer = nil
		group.nextOffer = CurTime() + 90
		group.keep = true
		ply.GFR_Quests[#ply.GFR_Quests + 1] = q
		SendDialog(ply, npc, "Good. Don't get yourself killed.")

	elseif action == "turnin" then
		local q = ply.GFR_Quests[arg]
		if !q or q.group != group then return end
		local _, ready = QuestStatus(ply, q)
		if !ready then
			SendDialog(ply, npc, "That's not done yet.")
			return
		end
		if q.type == "fetch" && q.ammoType then
			ply:RemoveAmmo(q.need, q.ammoType)
		elseif q.type == "fetch" then
			local left = q.need
			for i = #ply.GFR_Inv, 1, -1 do
				local e = ply.GFR_Inv[i]
				if left > 0 && q.match(e) then
					local take = math.min(e.count, left)
					left = left - take
					GFR.InvTake(ply, i, take)
				end
			end
		end
		RemoveQuest(ply, q)
		GiveReward(ply, q)
		SendDialog(ply, npc, "Thank you. Truly.")

	elseif action == "buy" then
		local trade = GetTrade(group)
		local s = trade.stock[arg]
		if !s then return end
		local price = SellPrice(trade, s.class)
		if GFR.GetCaps(ply) < price then GFR.Notify(ply, "You can't afford that.") return end
		local recipe = RecipeOf(s.class)
		if recipe then
			if ply.GFR_Recipes && ply.GFR_Recipes[recipe.id] then GFR.Notify(ply, "You already know that.") return end
			GFR.LearnRecipe(ply, recipe.id)
		elseif weapons.GetStored(s.class) then
			if ply:HasWeapon(s.class) then GFR.Notify(ply, "You already have one.") return end
			local w = ply:Give(s.class, true)
			if IsValid(w) && w:GetMaxClip1() > 0 then w:SetClip1(math.random(0, w:GetMaxClip1())) end
		elseif GFR.InvAdd(ply, s.class, 1, false, ItemModel(s.class)) == 0 then
			GFR.Notify(ply, "You can't carry any more.")
			return
		end
		GFR.AddCaps(ply, -price)
		trade.caps = trade.caps + price
		s.count = s.count - 1
		if s.count <= 0 then table.remove(trade.stock, arg) end
		SendTrade(ply, npc)

	elseif action == "sell" or action == "sellwep" then
		local trade = GetTrade(group)
		local class, contaminated
		if action == "sell" then
			local e = ply.GFR_Inv and ply.GFR_Inv[arg]
			if !e then return end
			class, contaminated = e.class, e.contaminated
		else
			if GFR.IsFists(argStr) or !ply:HasWeapon(argStr) or !weapons.Get(argStr) then return end
			class = argStr
		end
		local price = BuyPrice(trade, class, contaminated)
		if price <= 0 then GFR.Notify(ply, "\"That's covered in blood. Get it away from me.\"") return end
		if trade.caps < price then GFR.Notify(ply, "They can't afford that.") return end
		if action == "sell" then GFR.InvTake(ply, arg, 1) else ply:StripWeapon(class) end
		GFR.AddCaps(ply, price)
		trade.caps = trade.caps - price
		-- Samples go to the lab, not back on the shelf
		local isSample = samples[class] or string.StartWith(class, "meat_")
		local found = isSample
		for _, s in ipairs(trade.stock) do if !found && s.class == class then s.count = s.count + 1 found = true break end end
		if !found then trade.stock[#trade.stock + 1] = {class = class, count = 1} end
		SendTrade(ply, npc)
	end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Quest progress
hook.Add("OnNPCKilled", "GFR_Quests_Kills", function(npc, attacker)
	if !IsValid(attacker) or !attacker:IsPlayer() or !GFR.IsZombie(npc) then return end
	for _, q in ipairs(attacker.GFR_Quests or {}) do
		if q.type == "kill" && q.progress < q.need then
			q.progress = q.progress + 1
			if q.progress == q.need then GFR.Notify(attacker, "Objective done. Return to the " .. q.group.faction .. " who asked.") end
		end
	end
end)

local function GiverPos(q) return IsValid(q.giver) && q.giver:GetPos() + Vector(0, 0, 80) end

timer.Create("GFR_Quests_Tick", 1, 0, function()
	for _, ply in ipairs(player.GetAll()) do
		local list = ply.GFR_Quests
		if !list then continue end
		local out = {}
		for i = #list, 1, -1 do
			local q = list[i]
			if !IsValid(q.giver) or q.giver:Health() <= 0 then
				GFR.Notify(ply, "Quest failed: the one who asked is dead.")
				RemoveQuest(ply, q)
				continue
			end
			if q.type == "rescue" then
				local p = q.person
				if !IsValid(p) or p:Health() <= 0 then
					GFR.Notify(ply, "Quest failed: the missing survivor is dead.")
					RemoveQuest(ply, q)
					continue
				end
				if q.following && !q.home then
					if p:GetPos():DistToSqr(q.giver:GetPos()) < 350 * 350 then
						-- Back with their people
						q.home = true
						q.following = false
						p.GFR_LostQuest = nil
						GFR.Spawner.JoinGroup(p, q.group)
						GFR.Say(p, "I'm home... thank you.")
					elseif p:GetPos():DistToSqr(ply:GetPos()) > 140 * 140 then
						p:SetLastPosition(ply:GetPos())
						p:SetSchedule(SCHED_FORCED_GO_RUN)
					end
				end
			end
		end
		for _, q in ipairs(list) do
			local status, ready = QuestStatus(ply, q)
			local marker
			if ready then
				marker = GiverPos(q)
			elseif q.type == "bandits" then
				for _, m in ipairs(q.target.members) do
					if IsValid(m) && m:Health() > 0 then marker = m:GetPos() + Vector(0, 0, 80) break end
				end
			elseif q.type == "rescue" then
				marker = q.following and GiverPos(q) or (IsValid(q.person) && q.person:GetPos() + Vector(0, 0, 80))
			end
			out[#out + 1] = {text = q.text, status = status, ready = ready, marker = marker or false, faction = q.group.faction}
		end
		net.Start("GFR_Quests")
		net.WriteTable(out)
		net.Send(ply)
	end
end)

hook.Add("PlayerSpawn", "GFR_Quests_Spawn", function(ply)
	-- Quests are kept through death: the people who asked are still out there
	ply.GFR_Quests = ply.GFR_Quests or {}
end)
