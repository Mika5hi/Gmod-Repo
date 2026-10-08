--[[
	Custom Apocalypse - per-map decoration and ground spots

	gamemode/maps/<map>.lua (generated from the map's BSP street layout) returns:
		decor = { {kind, model, x, y, yaw}, ... }   optional (none shipped); placed on the ground at x,y
			along  - the model's long side follows yaw (cars parked along a road)
			across - the long side goes across yaw (barriers blocking a road)
			free   - yaw as given          rag - a dead body (ragdoll) with blood
			fire   - like along, plus a fire burning on top
		spots = { x, y, z, ... }   walkable ground for loot stashes and spawns (maps without navmesh/AI nodes)

	Editing in game (superadmin):
		gfr_decor_edit 1      props you spawn become decor; move existing decor with the physgun
		gfr_decor_save        saves every decor prop exactly where it is now (data/greenflu/decor_<map>.txt),
		                      used instead of the generated layout from then on
		gfr_decor_reset       forget your saved edits, back to the generated layout
		gfr_decor_reload      respawn the decor
]]
local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY)
local cvEnabled = CreateConVar("gfr_decor_enabled", "1", flags, "Spawn map decoration")
local cvEdit = CreateConVar("gfr_decor_edit", "0", flags, "Props you spawn become map decor (then gfr_decor_save)")

GFR.MapSpots = GFR.MapSpots or {}
local decorEnts = {}

local function SavePath() return "greenflu/decor_" .. game.GetMap() .. ".txt" end

local folder = GM.FolderName -- GM only exists while the gamemode loads

local function LoadGenerated()
	local path = folder .. "/gamemode/maps/" .. game.GetMap() .. ".lua"
	if !file.Exists(path, "LUA") then return end
	local ok, data = pcall(include, path)
	if ok && istable(data) then return data end
	if !ok then print("[GFR] Couldn't load " .. path .. ": " .. tostring(data)) end
end

-- Ground under x,y near the expected height
local function Ground(x, y, zHint)
	local top = Vector(x, y, (zHint or -200) + 200)
	local tr = util.TraceLine({start = top, endpos = top - Vector(0, 0, 900), mask = MASK_SOLID_BRUSHONLY})
	if tr.Hit && !tr.StartSolid && !tr.HitSky then return tr.HitPos end
end

local function AddFire(ent)
	local fire = ents.Create("env_fire")
	fire:SetPos(ent:WorldSpaceCenter() + Vector(0, 0, ent:OBBMaxs().z * 0.4))
	fire:SetKeyValue("firesize", "70")
	fire:SetKeyValue("damagescale", "0")
	fire:SetKeyValue("spawnflags", tostring(1 + 4 + 16))
	fire:SetParent(ent)
	fire:Spawn()
	fire:Fire("StartFire")
	ent:DeleteOnRemove(fire)
end

local function Blocked(ent)
	local tr = util.TraceHull({start = ent:GetPos() + Vector(0, 0, 2), endpos = ent:GetPos() + Vector(0, 0, 3),
		mins = ent:OBBMins() * 0.8, maxs = ent:OBBMaxs() * 0.8, filter = ent, mask = MASK_SOLID_BRUSHONLY})
	return tr.Hit
end

local function SpawnDecor(d)
	local kind, mdl = d[1], d[2]
	if !util.IsValidModel(mdl) then return end
	local ent

	if kind == "rag" then
		local pos = d.exact and Vector(d[3], d[4], d[6]) or Ground(d[3], d[4])
		if !pos then return end
		ent = ents.Create("prop_ragdoll")
		ent:SetModel(mdl)
		ent:SetPos(pos + Vector(0, 0, 16))
		ent:SetAngles(Angle(0, d[5], 0))
		ent:Spawn()
		ent:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
		util.Decal("Blood", pos + Vector(0, 0, 8), pos - Vector(0, 0, 16))
		-- Let it fall into a pose, then pin it
		timer.Simple(3, function()
			if !IsValid(ent) then return end
			for i = 0, ent:GetPhysicsObjectCount() - 1 do
				local phys = ent:GetPhysicsObjectNum(i)
				if IsValid(phys) then phys:EnableMotion(false) end
			end
		end)
	else
		ent = ents.Create("prop_physics")
		ent:SetModel(mdl)
		ent:Spawn()
		if d.exact then
			ent:SetPos(Vector(d[3], d[4], d[6]))
			ent:SetAngles(Angle(d[7] or 0, d[5], d[8] or 0))
		else
			local pos = Ground(d[3], d[4])
			if !pos then ent:Remove() return end
			local yaw = d[5]
			if kind != "free" then
				-- Line the model up: its longest side along (or across) the given direction
				local ext = ent:OBBMaxs() - ent:OBBMins()
				local longX = ext.x >= ext.y
				if kind == "across" then yaw = yaw + (longX and 90 or 0) else yaw = yaw + (longX and 0 or 90) end
			end
			ent:SetAngles(Angle(0, yaw, 0))
			ent:SetPos(pos - Vector(0, 0, ent:OBBMins().z) + Vector(0, 0, 1))
			if Blocked(ent) then ent:Remove() return end
		end
		local phys = ent:GetPhysicsObject()
		if IsValid(phys) then phys:EnableMotion(false) end
		if kind == "fire" then AddFire(ent) end
	end

	ent.GFR_Decor = true
	ent.GFR_DecorKind = kind
	decorEnts[#decorEnts + 1] = ent
	return ent
end

local function ClearDecor()
	for _, ent in ipairs(decorEnts) do
		if IsValid(ent) then ent:Remove() end
	end
	decorEnts = {}
end

local function LoadSpots(data)
	GFR.MapSpots = {}
	local s = data && data.spots
	if !s then return end
	for i = 1, #s - 2, 3 do
		GFR.MapSpots[#GFR.MapSpots + 1] = Vector(s[i], s[i + 1], s[i + 2])
	end
end

local function SpawnAll()
	ClearDecor()
	local generated = LoadGenerated()
	LoadSpots(generated)
	if !cvEnabled:GetBool() then return end

	-- Your saved edits win over the generated layout
	local saved = file.Read(SavePath(), "DATA")
	local list = saved && util.JSONToTable(saved) or (generated && generated.decor)
	if !list then return end
	local made = 0
	for _, d in ipairs(list) do
		if SpawnDecor(d) then made = made + 1 end
	end
	print("[GFR] Map decor: " .. made .. "/" .. #list .. " props" .. (saved and " (your saved layout)" or "") .. ", " .. #GFR.MapSpots .. " ground spots")
end

hook.Add("InitPostEntity", "GFR_MapDecor", function() timer.Simple(1, SpawnAll) end)
hook.Add("PostCleanupMap", "GFR_MapDecor", function() timer.Simple(0.5, SpawnAll) end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Editing
hook.Add("PlayerSpawnedProp", "GFR_MapDecor_Edit", function(ply, mdl, ent)
	if cvEdit:GetBool() && ply:IsSuperAdmin() then
		ent.GFR_Decor = true
		ent.GFR_DecorKind = "free"
		decorEnts[#decorEnts + 1] = ent
	end
end)
hook.Add("PlayerSpawnedRagdoll", "GFR_MapDecor_EditRag", function(ply, mdl, ent)
	if cvEdit:GetBool() && ply:IsSuperAdmin() then
		ent.GFR_Decor = true
		ent.GFR_DecorKind = "rag"
		decorEnts[#decorEnts + 1] = ent
	end
end)

local function Admin(ply) return !IsValid(ply) or ply:IsSuperAdmin() end

concommand.Add("gfr_decor_save", function(ply)
	if !Admin(ply) then return end
	local out = {}
	for _, ent in ipairs(decorEnts) do
		if IsValid(ent) then
			local p, a = ent:GetPos(), ent:GetAngles()
			local kind = ent.GFR_DecorKind == "fire" and "fire" or (ent.GFR_DecorKind == "rag" and "rag" or "free")
			out[#out + 1] = {kind, ent:GetModel(), math.Round(p.x), math.Round(p.y), math.Round(a.y), math.Round(p.z), math.Round(a.p), math.Round(a.r), exact = true}
		end
	end
	file.CreateDir("greenflu")
	file.Write(SavePath(), util.TableToJSON(out))
	local msg = "[GFR] Saved " .. #out .. " decor props for " .. game.GetMap()
	print(msg)
	if IsValid(ply) then ply:ChatPrint(msg) end
end)

concommand.Add("gfr_decor_reset", function(ply)
	if !Admin(ply) then return end
	file.Delete(SavePath())
	SpawnAll()
end)

concommand.Add("gfr_decor_reload", function(ply)
	if !Admin(ply) then return end
	SpawnAll()
end)
