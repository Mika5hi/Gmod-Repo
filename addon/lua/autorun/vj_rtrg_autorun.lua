--[[
	Custom Apocalypse Project - Ravenholm Grabber Zombies
	Requires: VJ Base, [VJ] Return to Ravenholm, [VJ] GMod of the Dead Reanimated

	- npc_vj_rtrg_zombie: Return to Ravenholm zombie models/voices driven by
	  GMod of the Dead's AI (grab + bite attack), eats corpses, walkers only.
	- Stops the original Return to Ravenholm zombies from spawning as runners.
	- Optionally lets VJ zombies eat any server-side ragdoll, not just VJ corpses.
]]
AddCSLuaFile()

if !file.Exists("autorun/vj_base_autorun.lua", "LUA") then return end

local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY)
CreateConVar("vj_rtrg_runners", "0", flags, "Allow Ravenholm Grabber zombies to become runners/sprinters (uses GOTDR runner settings)")
CreateConVar("vj_rtrg_female_chance", "3", flags, "1 in X Ravenholm Grabber zombies use a female model")
-- These two change other people's addons, so outside Green Flu: Reimagined they're off unless you turn them on
local ours = engine.ActiveGamemode() == "greenflu" and "1" or "0"
CreateConVar("vj_rtrg_fix_rtr_runners", ours, flags, "Stop original Return to Ravenholm zombies from spawning as runners")
CreateConVar("vj_rtrg_eat_all_ragdolls", ours, flags, "Let VJ zombies eat any server-side flesh ragdoll, not just VJ corpses")

local hasGOTDR = file.Exists("entities/npc_vj_gotdr_zombie_base/init.lua", "LUA")
local hasRTR = file.Exists("autorun/vj_cncr_autorun.lua", "LUA")

if hasGOTDR && hasRTR then
	VJ.AddNPC("Ravenholm Grabber", "npc_vj_rtrg_zombie", "Green Flu: Reimagined")
	VJ.AddNPC("Playermodel Zombie", "npc_vj_rtrg_zombie_pm", "Green Flu: Reimagined")
end
-- Left 4 Dead common infected with grab/eat/crawl (needs [Left 4 Dead Common Infected SNPCs])
if file.Exists("vj_base/extensions/l4d_com_infected.lua", "LUA") then
	VJ.AddNPC("Infected", "npc_gfr_infected", "Green Flu: Reimagined")
end

if CLIENT then return end

-- Original Return to Ravenholm zombies roll a 50% runner chance in Zombie_CustomOnPreInitialize
local rtrClasses = {"npc_vj_cncr_zmale", "npc_vj_cncr_zfemale", "npc_vj_cncr_zmale_rotter"}

hook.Add("InitPostEntity", "VJ_RTRG_FixRunners", function()
	for _, class in ipairs(rtrClasses) do
		local stored = scripted_ents.GetStored(class)
		local tbl = stored && stored.t
		if tbl && rawget(tbl, "Zombie_CustomOnPreInitialize") && !tbl.RTRG_Patched then
			local orig = tbl.Zombie_CustomOnPreInitialize
			tbl.Zombie_CustomOnPreInitialize = function(self, ...)
				orig(self, ...)
				if GetConVar("vj_rtrg_fix_rtr_runners"):GetBool() then
					self.CNCR_Run = false
				end
			end
			tbl.RTRG_Patched = true
		end
	end
end)

-- VJ only marks its own NPC corpses as food; mark other flesh ragdolls too
hook.Add("OnEntityCreated", "VJ_RTRG_EdibleRagdolls", function(ent)
	if ent:GetClass() != "prop_ragdoll" then return end
	timer.Simple(0.5, function()
		-- Map decoration bodies (Custom Apocalypse) are old remains, not food: zombies would all crowd onto them
		if !IsValid(ent) or ent.IsVJBaseCorpse or ent.RTRG_Edible or ent.GFR_Decor then return end
		if !GetConVar("vj_rtrg_eat_all_ragdolls"):GetBool() or !VJ.Corpse_AddStinky then return end
		if ent:Health() <= 0 then
			local hp = ent:OBBMaxs():Distance(ent:OBBMins())
			ent:SetMaxHealth(hp)
			ent:SetHealth(hp)
		end
		ent.BloodData = ent.BloodData or {Color = VJ.BLOOD_COLOR_RED, Particle = "blood_impact_red_01", Decal = "Blood"}
		ent.RTRG_Edible = VJ.Corpse_AddStinky(ent, true)
	end)
end)
