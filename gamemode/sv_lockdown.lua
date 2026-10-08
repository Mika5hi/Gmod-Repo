--[[
	Custom Apocalypse - no Sandbox cheating

	The gamemode is built on Sandbox, and hiding the spawn menu only hid the menu: noclip, the C context menu's
	properties and the console spawn commands (gm_spawn, gm_giveswep, gm_spawnsent ...) still worked for everyone.
	All of it is off unless gfr_allow_spawnmenu is 1 (testing / creative), and then only for superadmins.
	The gamemode's own testing commands (gfr_give, gfr_spawn_*, gfr_settime...) also need sv_cheats 1 (shared.lua).
]]

GFR.CheatsNeedSvCheats = true

local function Allowed(ply)
	local cv = GetConVar("gfr_allow_spawnmenu")
	return cv && cv:GetBool() && IsValid(ply) && ply:IsSuperAdmin()
end

local function Deny(ply) if !Allowed(ply) then return false end end

hook.Add("PlayerNoClip", "GFR_Lockdown", function(ply, desired)
	if desired then return Deny(ply) end -- (turning it off is always fine)
end)

for _, name in ipairs({"PlayerSpawnProp", "PlayerSpawnRagdoll", "PlayerSpawnEffect", "PlayerSpawnVehicle", "PlayerSpawnNPC",
	"PlayerSpawnSENT", "PlayerSpawnSWEP", "PlayerGiveSWEP", "PlayerSpawnObject"}) do
	hook.Add(name, "GFR_Lockdown", Deny)
end

hook.Add("CanTool", "GFR_Lockdown", function(ply) return Deny(ply) end)
hook.Add("CanProperty", "GFR_Lockdown", function(ply) return Deny(ply) end)
hook.Add("CanDrive", "GFR_Lockdown", function(ply) return Deny(ply) end)
