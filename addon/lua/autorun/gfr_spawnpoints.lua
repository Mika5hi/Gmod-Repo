--[[
	Custom Apocalypse - placed spawn points (any gamemode, so maps can be set up in Sandbox)
	Placed with the Spawn Points toolgun (weapons/gmod_tool/stools/gfr_spawnpoints.lua), saved per map in
	data/greenflu/spawns_<map>.txt. The gamemode uses them on top of its own random spots (sv_spawner.lua, sv_loot.lua):
		loot      a searchable stash turns up here
		zombie    the infected
		survivor / bandit / military   a group of that faction
	Markers show only while you hold the tool.
]]
GFR_SP = GFR_SP or {}
GFR_SP.Kinds = {
	{id = "loot",     name = "Loot stash", color = Color(235, 190, 70)},
	{id = "zombie",   name = "Zombies",    color = Color(130, 200, 60)},
	{id = "survivor", name = "Survivors",  color = Color(80, 160, 235)},
	{id = "bandit",   name = "Bandits",    color = Color(225, 70, 60)},
	{id = "military", name = "Military",   color = Color(170, 165, 110)}
}
GFR_SP.KindById = {}
for _, k in ipairs(GFR_SP.Kinds) do GFR_SP.KindById[k.id] = k end

GFR_SP.Points = GFR_SP.Points or {} -- {kind = id, pos = Vector}

-- Server owners: a map set up with points can use ONLY them. Per kind: with gfr_spawnpoints_only 1, a kind this map has
-- points for (loot / zombies / groups) never turns up at random spots; kinds with no points stay random.
local cvOnly = CreateConVar("gfr_spawnpoints_only", "0", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY),
	"1 = on a map with placed spawn points, loot / zombies / groups that have points only appear at them (kinds without points stay random)")

if SERVER then
	util.AddNetworkString("GFR_SP_Sync")

	local loaded = false
	local function Path() return "greenflu/spawns_" .. game.GetMap() .. ".txt" end

	local function Sync(ply)
		local out = {}
		for _, p in ipairs(GFR_SP.Points) do out[#out + 1] = {p.kind, math.Round(p.pos.x), math.Round(p.pos.y), math.Round(p.pos.z)} end
		local data = util.Compress(util.TableToJSON(out))
		net.Start("GFR_SP_Sync")
		net.WriteUInt(#data, 32)
		net.WriteData(data, #data)
		if IsValid(ply) then net.Send(ply) else net.Broadcast() end
	end

	function GFR_SP.Load()
		loaded = true
		GFR_SP.Points = {}
		local raw = file.Read(Path(), "DATA")
		local list = raw && util.JSONToTable(raw)
		for _, p in ipairs(list or {}) do
			if GFR_SP.KindById[p[1]] then GFR_SP.Points[#GFR_SP.Points + 1] = {kind = p[1], pos = Vector(p[2], p[3], p[4])} end
		end
		Sync()
	end

	local function Save()
		local out = {}
		for _, p in ipairs(GFR_SP.Points) do out[#out + 1] = {p.kind, math.Round(p.pos.x), math.Round(p.pos.y), math.Round(p.pos.z)} end
		file.CreateDir("greenflu")
		file.Write(Path(), util.TableToJSON(out))
		Sync()
	end

	-- Every placed point of a kind: a list of Vectors
	function GFR_SP.Get(kind)
		if !loaded then GFR_SP.Load() end
		local out = {}
		for _, p in ipairs(GFR_SP.Points) do
			if p.kind == kind then out[#out + 1] = p.pos end
		end
		return out
	end

	-- Only placed points for any of these kinds? (gfr_spawnpoints_only, and the map has at least one of them)
	function GFR_SP.Only(kinds)
		if !cvOnly:GetBool() then return false end
		if isstring(kinds) then kinds = {kinds} end
		for _, k in ipairs(kinds) do
			if #GFR_SP.Get(k) > 0 then return true end
		end
		return false
	end

	function GFR_SP.Add(kind, pos)
		if !loaded then GFR_SP.Load() end
		if !GFR_SP.KindById[kind] then return false end
		GFR_SP.Points[#GFR_SP.Points + 1] = {kind = kind, pos = pos}
		Save()
		return true
	end

	-- The nearest point within radius (any kind)
	function GFR_SP.RemoveNear(pos, radius)
		if !loaded then GFR_SP.Load() end
		local best, bestD
		for i, p in ipairs(GFR_SP.Points) do
			local d = p.pos:DistToSqr(pos)
			if d <= radius * radius && (!bestD or d < bestD) then best, bestD = i, d end
		end
		if !best then return false end
		local kind = GFR_SP.Points[best].kind
		table.remove(GFR_SP.Points, best)
		Save()
		return kind
	end

	function GFR_SP.ClearKind(kind)
		if !loaded then GFR_SP.Load() end
		local n = 0
		for i = #GFR_SP.Points, 1, -1 do
			if GFR_SP.Points[i].kind == kind then table.remove(GFR_SP.Points, i) n = n + 1 end
		end
		if n > 0 then Save() end
		return n
	end

	hook.Add("InitPostEntity", "GFR_SP_Load", GFR_SP.Load)
	hook.Add("PlayerInitialSpawn", "GFR_SP_Sync", function(ply) timer.Simple(2, function() if IsValid(ply) then Sync(ply) end end) end)
	if game.GetMap() != "" && CurTime() > 5 then GFR_SP.Load() end -- (reloaded mid-game)
else
	net.Receive("GFR_SP_Sync", function()
		local len = net.ReadUInt(32)
		local list = util.JSONToTable(util.Decompress(net.ReadData(len)) or "") or {}
		GFR_SP.Points = {}
		for _, p in ipairs(list) do GFR_SP.Points[#GFR_SP.Points + 1] = {kind = p[1], pos = Vector(p[2], p[3], p[4])} end
	end)

	local function HoldingTool()
		local ply = LocalPlayer()
		local wep = IsValid(ply) && ply:GetActiveWeapon()
		return IsValid(wep) && wep:GetClass() == "gmod_tool" && wep:GetMode() == "gfr_spawnpoints"
	end

	surface.CreateFont("GFR_SP_Label", {font = "Roboto", size = 40, weight = 800, extended = true})

	-- Markers: a box the size of what spawns there (smaller for loot), a label above, while you hold the tool
	hook.Add("PostDrawTranslucentRenderables", "GFR_SP_Markers", function(depth, sky)
		if sky or !HoldingTool() then return end
		local eye = EyePos()
		for _, p in ipairs(GFR_SP.Points) do
			local k = GFR_SP.KindById[p.kind]
			if k && p.pos:DistToSqr(eye) < 4000 * 4000 then
				local loot = p.kind == "loot"
				local mins, maxs = loot and Vector(-12, -12, 0) or Vector(-16, -16, 0), loot and Vector(12, 12, 20) or Vector(16, 16, 72)
				render.DrawWireframeBox(p.pos, angle_zero, mins, maxs, k.color, false)
				render.SetColorMaterial()
				render.DrawBox(p.pos, angle_zero, mins, maxs, ColorAlpha(k.color, 30))
				local top = p.pos + Vector(0, 0, maxs.z + 10)
				local ang = (eye - top):Angle()
				ang = Angle(0, ang.y + 90, 90)
				cam.Start3D2D(top, ang, 0.15)
					draw.SimpleTextOutlined(string.upper(k.name), "GFR_SP_Label", 0, 0, k.color, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, Color(0, 0, 0, 220))
				cam.End3D2D()
			end
		end
	end)
end
