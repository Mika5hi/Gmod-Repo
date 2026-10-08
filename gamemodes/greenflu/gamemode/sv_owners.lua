--[[
	Green Flu: Reimagined - who owns what you build, and who else may touch it (the window: cl_access.lua)

	Everything you place (sv_crafting.lua GFR.PlaceDeployable) is yours, by SteamID - it stays yours if you leave and
	come back. Shift+E on something of yours opens its access window:
		- your access list: players allowed at your things (pick someone on the server, or type a SteamID). One list for
		  everything you've built, saved in data/greenflu/friends.json
		- on a turret, who it shoots at besides the dead and hostile NPCs:
		      0  no players (default)      1  every player but you      2  every player but you and your list
		  (gfr_turret_players 0: turrets never shoot players, whatever they're set to)
	Only you, your list, and admins (sv_admin.lua) can pick up / tear down your things, open your storage or use your
	beds. Anyone can still repair your barricades and load your turrets.
]]
util.AddNetworkString("GFR_Access")
util.AddNetworkString("GFR_AccessReq")

local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY)
local cvPlayers = CreateConVar("gfr_turret_players", "1", flags, "Owners may set their turrets to shoot players (0 = turrets never shoot players)")

local FILE = "greenflu/friends.json"
local friends = {} -- [owner SteamID] = {[friend SteamID] = name}
do
	local d = file.Exists(FILE, "DATA") && util.JSONToTable(file.Read(FILE, "DATA") or "") or nil
	friends = istable(d) && d or {}
end
local function Save()
	file.CreateDir("greenflu")
	file.Write(FILE, util.TableToJSON(friends, true))
end

-- Mark a placed thing as ply's
function GFR.SetOwner(ent, ply)
	ent.GFR_Builder = ply
	ent.GFR_OwnerID = ply:SteamID()
	ent:SetNW2String("GFR_OwnerID", ent.GFR_OwnerID)
	ent:SetNW2String("GFR_OwnerName", ply:Nick())
end

function GFR.IsFriendOf(ownerID, ply)
	return IsValid(ply) && friends[ownerID] != nil && friends[ownerID][ply:SteamID()] != nil
end

-- May ply pick up / open / sleep in ent?
function GFR.CanUseOwned(ply, ent)
	local id = IsValid(ent) && ent.GFR_OwnerID
	if !id or ply:SteamID() == id or GFR.IsFriendOf(id, ply) then return true end
	return GFR.StaffLevel && GFR.StaffLevel(ply) >= 2 or false
end

-- A turret shooting at a player? (gfr_turret.lua / gfr_sentinel.lua through GFR.TurretHostile)
function GFR.TurretShootsPlayer(turret, ply)
	if !cvPlayers:GetBool() then return false end
	local mode = turret:GetNW2Int("GFR_TurretPlayers", 0)
	if mode == 0 then return false end
	if !ply:Alive() or ply.GFR_IsZombie or ply.GFR_Customizing or ply:GetObserverMode() != OBS_MODE_NONE
		or ply:GetMoveType() == MOVETYPE_NOCLIP then return false end
	local id = ply:SteamID()
	if id == turret.GFR_OwnerID then return false end
	if mode == 2 && GFR.IsFriendOf(turret.GFR_OwnerID, ply) then return false end
	return true
end

-- Back on the server: your things know you again (turrets read hostility off their builder)
hook.Add("PlayerInitialSpawn", "GFR_Owners_Relink", function(ply)
	local id = ply:SteamID()
	for _, ent in ipairs(ents.GetAll()) do
		if ent.GFR_OwnerID == id then
			ent.GFR_Builder = ply
			ent:SetNW2String("GFR_OwnerName", ply:Nick())
		end
	end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- The access window
local function Send(ply, ent)
	local id = ent.GFR_OwnerID
	local out = {
		ent = ent, owner = ent:GetNW2String("GFR_OwnerName", "?"), isOwner = ply:SteamID() == id,
		turret = ent.GFR_Turret == true, mode = ent:GetNW2Int("GFR_TurretPlayers", 0), pvp = cvPlayers:GetBool(),
		list = {}, online = {}
	}
	for fid, name in SortedPairsByValue(friends[id] or {}) do out.list[#out.list + 1] = {id = fid, name = name} end
	for _, p in ipairs(player.GetAll()) do
		local pid = p:SteamID()
		if pid != id && !(friends[id] && friends[id][pid]) then out.online[#out.online + 1] = {id = pid, name = p:Nick()} end
	end
	net.Start("GFR_Access")
	net.WriteTable(out)
	net.Send(ply)
end

-- Shift+E on something you placed
hook.Add("KeyPress", "GFR_Owners_Menu", function(ply, key)
	if key != IN_USE or !ply:KeyDown(IN_SPEED) or !ply:Alive() or ply.GFR_IsZombie then return end
	local tr = util.TraceLine({start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * 130, filter = ply})
	local ent = tr.Entity
	if !IsValid(ent) or !ent.GFR_Place or !ent.GFR_OwnerID then return end
	if ply:SteamID() != ent.GFR_OwnerID && !(GFR.StaffLevel && GFR.StaffLevel(ply) >= 2) then
		GFR.Notify(ply, "That belongs to " .. ent:GetNW2String("GFR_OwnerName", "someone else") .. ".")
		return
	end
	Send(ply, ent)
end)

net.Receive("GFR_AccessReq", function(_, ply)
	local ent = net.ReadEntity()
	local action = net.ReadString()
	if !IsValid(ent) or !ent.GFR_OwnerID or (ply.GFR_NextAccessReq or 0) > CurTime() then return end
	ply.GFR_NextAccessReq = CurTime() + 0.15
	-- The owner, or an admin sorting it out
	if ply:SteamID() != ent.GFR_OwnerID && !(GFR.StaffLevel && GFR.StaffLevel(ply) >= 2) then return end
	if ply:EyePos():DistToSqr(ent:WorldSpaceCenter()) > 400 * 400 then return end
	local owner = ent.GFR_OwnerID

	if action == "add" then
		local id, name = string.Trim(net.ReadString()), string.Trim(net.ReadString())
		if !string.match(id, "^STEAM_%d:%d:%d+$") or id == owner then
			GFR.Notify(ply, "That isn't a SteamID (it looks like STEAM_0:1:12345678).")
		else
			local p = player.GetBySteamID(id)
			friends[owner] = friends[owner] or {}
			friends[owner][id] = IsValid(p) and p:Nick() or (name != "" and name or id)
			Save()
		end
	elseif action == "remove" then
		local id = net.ReadString()
		if friends[owner] then friends[owner][id] = nil Save() end
	elseif action == "mode" && ent.GFR_Turret then
		ent:SetNW2Int("GFR_TurretPlayers", math.Clamp(net.ReadUInt(2), 0, 2))
	end
	Send(ply, ent)
end)
