--[[
	Custom Apocalypse - open world zombie survival, built on Sandbox (spawn menu/noclip stay available for testing)

	sh_stats.lua      stamina / hunger / thirst
	sh_ammo.lua       Crunchy ammo items -> EFT (ARC9) ammo pools
	sv_infection.lua  infection, bleeding, turning
	sv_inventory.lua  Tab inventory (server)
	sv_loot.lua       map stashes + body loot (Crunchy items, EFT weapons)
	sv_weapons.lua    fists-only start, press-E weapon pickup
	sh/sv/cl_containers.lua  press-E container search (fridges, lockers, cabinets, cars...)
	sv_spawner.lua, cl_factions.lua  spawn director: playermodel zombies, survivor/bandit/military groups
	sv/cl_surrender.lua  J to surrender, warnings, capture fates
	sv/cl_npc.lua     talk, trade (caps), quests
	sh/sv/cl_daynight.lua  day/night cycle
	sh_items.lua, sh_recipes.lua, sv/cl_crafting.lua  materials, recipes, workbench, barricades
	cl_hud.lua, cl_infection.lua, cl_inventory.lua
]]
DeriveGamemode("sandbox")

GM.Name = "Green Flu: Reimagined (Dev)"
GM.Author = "Green Flu: Reimagined"
GM.Email = ""
GM.Website = ""

GFR = GFR or {}

include("sh_rename.lua") -- (first: settings saved under the old cap_ names carry over)

-- Testing commands (gfr_give, gfr_spawn_*, gfr_settime...): superadmins - and with sv_cheats 1 when
-- GFR.CheatsNeedSvCheats is set (the public version: in single-player the host is always superadmin)
function GFR.CanCheat(ply)
	if GFR.CheatsNeedSvCheats then
		local cheats = GetConVar("sv_cheats")
		if !cheats or !cheats:GetBool() then return false end
	end
	return !IsValid(ply) or ply:IsSuperAdmin()
end

-- Q is the search/harvest key, so the spawn menu is off unless you turn this on for testing
CreateConVar("gfr_allow_spawnmenu", "0", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY), "Allow the Q spawn menu in Green Flu: Reimagined")

include("sh_sfw.lua")
include("sh_stats.lua")
include("sh_status.lua")
include("sh_ammo.lua")
include("sh_containers.lua")
include("sh_lootmodels.lua") -- (the container list edited in-game: after sh_containers.lua)
include("sh_daynight.lua")
include("sh_items.lua")
include("sh_recipes.lua")
include("sh_pickup.lua")
include("sh_junk.lua")
include("sh_equipment.lua")
include("sh_attachments.lua")
include("sh_drag.lua")
include("sh_zombieplayer.lua")
include("sh_claim.lua")
