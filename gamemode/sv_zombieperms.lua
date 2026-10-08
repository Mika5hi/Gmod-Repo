--[[
	Green Flu: Reimagined - who may play as their own zombie (server owners)
	A player who isn't allowed still turns: their body gets up as an ordinary AI zombie wearing them and carrying their
	gear (kill it to get the gear back), and they respawn as a survivor (sv_extract.lua GFR.BecomeZombie).

		gfr_zombieplay 0|1                 playing as your zombie at all (default 1)
		gfr_zombieplay_whitelist 0|1       only whitelisted players may (default 0: everyone not blacklisted)
		gfr_zombieplay_allow <name|SteamID>    whitelist someone (and take them off the blacklist)
		gfr_zombieplay_deny <name|SteamID>     blacklist someone (and take them off the whitelist); if they're a zombie
		                                       right now, they lose control of it
		gfr_zombieplay_clear <name|SteamID>    take someone off both lists
		gfr_zombieplay_list                    show both lists
	The commands are for staff (moderators and up, GFR.StaffLevel in sv_admin.lua) or the server console; the two
	settings for the owner (superadmin). The same is in the !gfr staff menu. Lists: data/greenflu/zombieplay.json.
]]
local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY)
local cvOn = CreateConVar("gfr_zombieplay", "1", flags, "Players who turn play as their own zombie (0 = their body gets up as an AI zombie and they respawn)")
local cvWhite = CreateConVar("gfr_zombieplay_whitelist", "0", flags, "Only players on the zombie whitelist (gfr_zombieplay_allow) may play as their zombie")

local FILE = "greenflu/zombieplay.json"
local lists = {white = {}, black = {}} -- [SteamID] = name

local function Load()
	local data = file.Exists(FILE, "DATA") && util.JSONToTable(file.Read(FILE, "DATA") or "") or nil
	lists.white = istable(data) && istable(data.white) && data.white or {}
	lists.black = istable(data) && istable(data.black) && data.black or {}
end
Load()

local function Save()
	file.CreateDir("greenflu")
	file.Write(FILE, util.TableToJSON(lists, true))
end

function GFR.CanPlayZombie(ply)
	if !cvOn:GetBool() then return false end
	local id = ply:SteamID()
	if lists.black[id] then return false end
	if cvWhite:GetBool() then return lists.white[id] != nil end
	return true
end

-- A connected player by (part of) their name, or a SteamID typed out. Returns id, name.
local function Find(arg)
	if !arg or arg == "" then return end
	if string.match(arg, "^STEAM_%d:%d:%d+$") then
		local p = player.GetBySteamID(arg)
		return arg, IsValid(p) and p:Nick() or arg
	end
	local q, found = string.lower(arg)
	for _, p in ipairs(player.GetAll()) do
		if string.find(string.lower(p:Nick()), q, 1, true) then
			if found then return nil, "more than one player matches '" .. arg .. "'" end
			found = p
		end
	end
	if found then return found:SteamID(), found:Nick() end
	return nil, "no player matches '" .. arg .. "' (or use their SteamID)"
end

local function Reply(ply, msg)
	msg = "[GFR] " .. msg
	if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) ply:ChatPrint(msg) else print(msg) end
end

local function Staff(ply) return !IsValid(ply) or (GFR.StaffLevel && GFR.StaffLevel(ply) >= 1) end

-- "white", "black" or nil (neither) for a SteamID; the staff menu uses these too (sv_admin.lua)
function GFR.ZombieListOf(id)
	return lists.black[id] and "black" or lists.white[id] and "white" or nil
end

function GFR.ZombieLists() return lists end

function GFR.ZombieListSet(id, name, which)
	lists.white[id] = which == "white" and name or nil
	lists.black[id] = which == "black" and name or nil
	Save()
	-- Blacklisted while they're a zombie: they let go of it (it carries on as an AI zombie with their gear)
	local p = player.GetBySteamID(id)
	if which == "black" && IsValid(p) && p.GFR_IsZombie && IsValid(p.GFR_ZombieController) && p.GFR_ZombieController.StopControlling then
		p.GFR_ZTakenAway = true -- (they keep watching it: sv_extract.lua HandleRelease)
		p.GFR_ZombieController:StopControlling()
	end
end

local function ListCommand(name, which, help)
	concommand.Add(name, function(ply, _, args)
		if !Staff(ply) then return end
		local id, who = Find(table.concat(args, " "))
		if !id then Reply(ply, "Usage: " .. name .. " <name|SteamID> - " .. (who or "nobody given")) return end
		GFR.ZombieListSet(id, who, which)
		local now = GFR.ZombieListOf(id)
		Reply(ply, string.format("%s (%s): %s", who, id, now == "black" and "blacklisted" or now == "white" and "whitelisted" or "on neither list"))
	end, nil, help)
end

ListCommand("gfr_zombieplay_allow", "white", "Let a player play as their zombie (whitelist): gfr_zombieplay_allow <name|SteamID>")
ListCommand("gfr_zombieplay_deny", "black", "Stop a player playing as their zombie (blacklist): gfr_zombieplay_deny <name|SteamID>")
ListCommand("gfr_zombieplay_clear", nil, "Take a player off the zombie whitelist and blacklist: gfr_zombieplay_clear <name|SteamID>")

concommand.Add("gfr_zombieplay_list", function(ply)
	if !Staff(ply) then return end
	local function Show(t)
		local out = {}
		for id, name in SortedPairs(t) do out[#out + 1] = name .. " (" .. id .. ")" end
		return #out > 0 and table.concat(out, ", ") or "nobody"
	end
	Reply(ply, string.format("Playing as a zombie: %s%s", cvOn:GetBool() and "on" or "OFF",
		cvWhite:GetBool() and " (whitelist only)" or ""))
	Reply(ply, "Whitelist: " .. Show(lists.white))
	Reply(ply, "Blacklist: " .. Show(lists.black))
end, nil, "Show the zombie whitelist and blacklist")
