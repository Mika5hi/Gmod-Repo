--[[
	Green Flu: Reimagined - staff menu (!gfr or /gfr in chat; the window is cl_admin.lua)

	Who's who (GMod's user groups; ULX / SAM / ServerGuard groups work the same way):
		3  owner       superadmin, or the host of a listen / single-player game
		2  admin       admin
		1  moderator   moderator / mod / operator
	Players tab (moderators and up): zombie whitelist / blacklist (sv_zombieperms.lua), take a zombie away from someone,
	and character models per player: "any model" (also outside the SFW list) or "stock only" (the SFW list, even with
	SFW off) - saved in data/greenflu/models.json, read through the GFR_ModelPerm networked int (sh_sfw.lua).
	Server tab (admins and up): the gamemode's settings; a few big switches are for the owner only (need = 3), and so is
	"Restore defaults" (every setting here back to the defaults this copy of the gamemode ships with).
	Settings are saved by GMod on whoever hosts (garrysmod/cfg/server.vdf on their PC or the dedicated server).
	Every change is printed in the server console with who made it.
]]
util.AddNetworkString("GFR_Admin")
util.AddNetworkString("GFR_AdminReq")

local modGroups = {moderator = true, mod = true, operator = true}

function GFR.StaffLevel(ply)
	if !IsValid(ply) then return 3 end -- (the server console)
	if ply:IsSuperAdmin() or ply:IsListenServerHost() then return 3 end
	if ply:IsAdmin() then return 2 end
	if modGroups[string.lower(ply:GetUserGroup())] then return 1 end
	return 0
end

-- The settings in the Server tab: kind bool / int / float, min / max for sliders, need = who may change it
local settings = {
	{group = "Playing as a zombie", name = "gfr_zombieplay", label = "Players can play as their zombie", kind = "bool", need = 3},
	{group = "Playing as a zombie", name = "gfr_zombieplay_whitelist", label = "Whitelisted players only", kind = "bool", need = 3},
	{group = "Playing as a zombie", name = "gfr_ztame_enabled", label = "People react to your zombie (taming)", kind = "bool"},

	{group = "Zombies", name = "gfr_zombie_count", label = "Zombies around each player", kind = "int", min = 0, max = 60},
	{group = "Zombies", name = "gfr_night_zombie_mult", label = "Zombie count at night (x)", kind = "float", min = 1, max = 4},
	{group = "Zombies", name = "gfr_day_runner_chance", label = "Runners by day (%)", kind = "int", min = 0, max = 100},
	{group = "Zombies", name = "gfr_night_runner_chance", label = "Runners at night (%)", kind = "int", min = 0, max = 100},
	{group = "Zombies", name = "gfr_zombie_rise_chance", label = "Get back up if the head isn't destroyed (%)", kind = "int", min = 0, max = 100},
	{group = "Zombies", name = "gfr_infected_gore", label = "Gore", kind = "bool"},

	{group = "Survival", name = "gfr_infection_enabled", label = "Infection", kind = "bool"},
	{group = "Survival", name = "gfr_stats_enabled", label = "Hunger, thirst and stamina", kind = "bool"},
	{group = "Survival", name = "gfr_surrender_enabled", label = "Surrendering (J) and hostile warnings", kind = "bool"},
	{group = "Survival", name = "gfr_human_groups", label = "Human groups at once", kind = "int", min = 0, max = 10},
	{group = "Survival", name = "gfr_arc9_bench", label = "Guns can only be customized at a Gun Table", kind = "bool"},
	{group = "Survival", name = "gfr_arc9_found", label = "Attachments must be found in loot (off: all at the Gun Table; after map restart)", kind = "bool"},
	{group = "Survival", name = "gfr_turret_players", label = "Owners may set turrets to shoot players", kind = "bool"},
	{group = "Survival", name = "gfr_container_loot_mult", label = "Loot in each container (x)", kind = "float", min = 0.25, max = 5},
	{group = "Survival", name = "gfr_loot_refresh_hours", label = "Loot refills after (in-game hours; sleeping speeds it up)", kind = "int", min = 1, max = 72},
	{group = "Survival", name = "gfr_keep_inventory", label = "Players keep their inventory when they leave (off: it drops)", kind = "bool"},
	{group = "Survival", name = "gfr_inv_slots", label = "Inventory slots (without a bag)", kind = "int", min = 5, max = 40},
	{group = "Survival", name = "gfr_walk_speed", label = "Walk speed (on respawn)", kind = "int", min = 100, max = 250},
	{group = "Survival", name = "gfr_run_speed", label = "Sprint speed (on respawn)", kind = "int", min = 150, max = 450},
	{group = "Survival", name = "gfr_airdrop_enabled", label = "Flares call in supply drops", kind = "bool"},

	{group = "Time", name = "gfr_daynight_enabled", label = "Day / night cycle", kind = "bool"},
	{group = "Time", name = "gfr_day_length", label = "Real minutes per in-game day", kind = "int", min = 6, max = 120},
	{group = "Time", name = "gfr_timeskip", label = "Sleeping can skip time (vote)", kind = "bool", need = 3},
	{group = "Time", name = "gfr_timeskip_pct", label = "Players needed to skip (%)", kind = "int", min = 1, max = 100},

	{group = "Server", name = "gfr_sfw", label = "SFW mode (stock models for the world)", kind = "bool", need = 3},
	{group = "Server", name = "gfr_sfw_character", label = "Character models: -1 follow SFW, 0 any, 1 stock", kind = "int", min = -1, max = 1, need = 3},
	{group = "Server", name = "gfr_allow_spawnmenu", label = "Spawn menu / noclip for superadmins (testing)", kind = "bool", need = 3}
}
local settingByName = {}
for _, s in ipairs(settings) do settingByName[s.name] = s end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Character models per player: white = any installed model, black = stock (SFW) models only
local MODEL_FILE = "greenflu/models.json"
local modelLists = {white = {}, black = {}} -- [SteamID] = name
do
	local d = file.Exists(MODEL_FILE, "DATA") && util.JSONToTable(file.Read(MODEL_FILE, "DATA") or "") or nil
	modelLists.white = istable(d) && istable(d.white) && d.white or {}
	modelLists.black = istable(d) && istable(d.black) && d.black or {}
end

function GFR.ModelListOf(id)
	return modelLists.black[id] and "black" or modelLists.white[id] and "white" or nil
end

local function ApplyModelPerm(ply)
	local which = GFR.ModelListOf(ply:SteamID())
	ply:SetNW2Int("GFR_ModelPerm", which == "white" and 1 or which == "black" and -1 or 0)
end

function GFR.ModelListSet(id, name, which)
	modelLists.white[id] = which == "white" and name or nil
	modelLists.black[id] = which == "black" and name or nil
	file.CreateDir("greenflu")
	file.Write(MODEL_FILE, util.TableToJSON(modelLists, true))
	local p = player.GetBySteamID(id)
	if IsValid(p) then
		ApplyModelPerm(p)
		-- Stock only now and wearing something else: back to a stock citizen at once
		if which == "black" && p:Alive() && !p.GFR_IsZombie && !GFR.ModelAllowed(p:GetInfo("cl_playermodel"), p) then
			p:SetModel(player_manager.TranslatePlayerModel("male07"))
			timer.Simple(0.5, function() if IsValid(p) then p:SetupHands() end end)
		end
	end
end

hook.Add("PlayerInitialSpawn", "GFR_Admin_ModelPerm", ApplyModelPerm)

local function Send(ply)
	local level = GFR.StaffLevel(ply)
	local out = {level = level, settings = {}, players = {}, listed = {}}
	if level >= 2 then
		for _, s in ipairs(settings) do
			local cv = GetConVar(s.name)
			if cv then
				out.settings[#out.settings + 1] = {group = s.group, name = s.name, label = s.label, kind = s.kind, min = s.min,
					max = s.max, need = s.need or 2, value = cv:GetString()}
			end
		end
	end
	local online = {}
	for _, p in ipairs(player.GetAll()) do
		local id = p:SteamID()
		online[id] = true
		out.players[#out.players + 1] = {name = p:Nick(), id = id, zombie = p.GFR_IsZombie == true, list = GFR.ZombieListOf && GFR.ZombieListOf(id),
			allowed = !GFR.CanPlayZombie or GFR.CanPlayZombie(p), models = GFR.ModelListOf(id)}
	end
	-- People on any list who aren't here right now
	local offline = {}
	local function Offline(id, name)
		if online[id] then return end
		if !offline[id] then
			offline[id] = {name = name, id = id, list = GFR.ZombieListOf && GFR.ZombieListOf(id), models = GFR.ModelListOf(id)}
			out.listed[#out.listed + 1] = offline[id]
		end
	end
	for _, t in pairs(GFR.ZombieLists && GFR.ZombieLists() or {}) do
		for id, name in pairs(t) do Offline(id, name) end
	end
	for _, t in pairs(modelLists) do
		for id, name in pairs(t) do Offline(id, name) end
	end
	net.Start("GFR_Admin")
	net.WriteTable(out)
	net.Send(ply)
end

function GFR.OpenStaffMenu(ply)
	if GFR.StaffLevel(ply) < 1 then GFR.Notify(ply, "That's for staff only.") return end
	Send(ply)
end

local function Log(ply, what)
	print(string.format("[GFR] %s (%s) %s", ply:Nick(), ply:SteamID(), what))
end

net.Receive("GFR_AdminReq", function(_, ply)
	local level = GFR.StaffLevel(ply)
	if level < 1 then return end
	if (ply.GFR_NextAdminReq or 0) > CurTime() then return end
	ply.GFR_NextAdminReq = CurTime() + 0.15
	local action = net.ReadString()

	if action == "list" then
		-- Whitelist / blacklist / clear a player (white, black, or "" for neither)
		local id, name, which = net.ReadString(), net.ReadString(), net.ReadString()
		if !string.match(id, "^STEAM_%d:%d:%d+$") or !GFR.ZombieListSet then return end
		if which != "white" && which != "black" then which = nil end
		GFR.ZombieListSet(id, name, which)
		Log(ply, (which and ("put " .. name .. " on the zombie " .. which .. "list") or ("cleared " .. name .. " from the zombie lists")))
	elseif action == "models" then
		-- Character models: white (any), black (stock only), or "" (the server's setting)
		local id, name, which = net.ReadString(), net.ReadString(), net.ReadString()
		if !string.match(id, "^STEAM_%d:%d:%d+$") then return end
		if which != "white" && which != "black" then which = nil end
		GFR.ModelListSet(id, name, which)
		Log(ply, which == "white" and ("let " .. name .. " use any model") or which == "black" and ("limited " .. name .. " to stock models")
			or ("put " .. name .. "'s models back to the server setting"))
	elseif action == "release" then
		-- Take their zombie away from them this once (no list)
		local p = player.GetBySteamID(net.ReadString())
		if IsValid(p) && p.GFR_IsZombie && IsValid(p.GFR_ZombieController) && p.GFR_ZombieController.StopControlling then
			p.GFR_ZTakenAway = true -- (they keep watching it: sv_extract.lua HandleRelease)
			p.GFR_ZombieController:StopControlling()
			Log(ply, "took " .. p:Nick() .. "'s zombie away")
		end
	elseif action == "reset" then
		-- Owner: every setting in the Server tab back to this copy's defaults (saved, like any change)
		if level < 3 then return end
		for _, s in ipairs(settings) do
			local cv = GetConVar(s.name)
			if cv && cv:GetString() != cv:GetDefault() then RunConsoleCommand(s.name, cv:GetDefault()) end
		end
		Log(ply, "restored the server settings to their defaults")
	elseif action == "cvar" then
		local name, value = net.ReadString(), net.ReadString()
		local s = settingByName[name]
		if !s or level < (s.need or 2) or !GetConVar(name) then return end
		local n = tonumber(value)
		if s.kind == "bool" then value = (n && n != 0) and "1" or "0"
		elseif !n then return
		else
			n = math.Clamp(n, s.min or n, s.max or n)
			value = s.kind == "int" and tostring(math.Round(n)) or tostring(math.Round(n, 2))
		end
		RunConsoleCommand(name, value)
		Log(ply, "set " .. name .. " to " .. value)
	end
	-- Fresh state back to the menu (a moment later, so a changed setting has taken)
	timer.Simple(0.2, function() if IsValid(ply) then Send(ply) end end)
end)
