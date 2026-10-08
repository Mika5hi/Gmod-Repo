--[[
	Custom Apocalypse - the container model list, edited in-game (the Lootbox Models tool:
	addon lua/weapons/gmod_tool/stools/gfr_lootmodels.lua)
	The built-in list is GFR.ContainerModels in sh_containers.lua. Once anything is changed with the tool, the whole
	list is saved to data/greenflu/containers.json (every map) and used instead; "Restore defaults" deletes the file.
	Each entry: model, skin (or any), type (sh_containers.lua GFR.ContainerTypes, or "none": never a container, even if
	its name looks like one), indoor / outdoor (how often map loot spawns it; 0 = never, still searchable where it is).
	Admins and up (sv_admin.lua staff level 2), superadmins, or anyone in single-player.
]]
AddCSLuaFile()
GFR = GFR or {}
GFR.LootModels = GFR.LootModels or {}
local LM = GFR.LootModels

local FILE = "greenflu/containers.json"
local MAX_WEIGHT = 20

function LM.CanEdit(ply)
	if game.SinglePlayer() or !IsValid(ply) then return true end
	if ply:IsSuperAdmin() then return true end
	if SERVER && GFR.StaffLevel then return GFR.StaffLevel(ply) >= 2 end
	return ply:IsAdmin()
end

-- What the tool can set: every container type, plus "none"
function LM.ValidType(t)
	return t == "none" or (GFR.ContainerTypes && GFR.ContainerTypes[t] != nil)
end

function LM.TypeName(t)
	if t == "none" then return "Not a container" end
	local def = GFR.ContainerTypes && GFR.ContainerTypes[t]
	return def && def.name or tostring(t)
end

-- Entries <-> plain tables for JSON (keeps [1] out of the JSON as a "1" key)
local function Pack(list)
	local out = {}
	for _, e in ipairs(list) do
		out[#out + 1] = {model = e[1], skin = e.skin, type = e.type, indoor = e.indoor, outdoor = e.outdoor, opens = e.opens}
	end
	return out
end

local function Unpack(list)
	local out = {}
	for _, p in ipairs(list or {}) do
		if isstring(p.model) && isstring(p.type) then
			out[#out + 1] = {p.model, skin = tonumber(p.skin), type = p.type, indoor = tonumber(p.indoor), outdoor = tonumber(p.outdoor),
				opens = isstring(p.opens) && p.opens or nil}
		end
	end
	return out
end

local function Apply(list)
	GFR.ContainerModelsSaved = list
	GFR.ContainerModels = list or table.Copy(GFR.DefaultContainerModels or GFR.ContainerModels)
	if GFR.RebuildContainerIndex then GFR.RebuildContainerIndex() end
	if CLIENT then hook.Run("GFR_LootModelsChanged") end
end

if SERVER then
	util.AddNetworkString("GFR_LootModels")
	util.AddNetworkString("GFR_LootModelsEdit")

	local function Sync(ply)
		local data = util.Compress(util.TableToJSON({saved = GFR.ContainerModelsSaved != nil, models = Pack(GFR.ContainerModels)}))
		net.Start("GFR_LootModels")
		net.WriteUInt(#data, 32)
		net.WriteData(data, #data)
		if IsValid(ply) then net.Send(ply) else net.Broadcast() end
	end

	local function Save()
		file.CreateDir("greenflu")
		file.Write(FILE, util.TableToJSON({version = 1, models = Pack(GFR.ContainerModels)}, true))
		Apply(GFR.ContainerModels)
		Sync()
	end

	local function Load()
		local raw = file.Exists(FILE, "DATA") && file.Read(FILE, "DATA")
		local t = raw && util.JSONToTable(raw)
		Apply(istable(t) && istable(t.models) && Unpack(t.models) or nil)
	end
	Load()

	hook.Add("PlayerInitialSpawn", "GFR_LootModels_Sync", function(ply)
		timer.Simple(2, function() if IsValid(ply) then Sync(ply) end end)
	end)

	local function CleanModel(mdl)
		mdl = string.lower(string.Trim(tostring(mdl or "")))
		mdl = string.gsub(mdl, "\\", "/")
		if #mdl > 200 or !string.StartWith(mdl, "models/") or !string.EndsWith(mdl, ".mdl") then return end
		return mdl
	end

	local function SameEntry(e, mdl, skin)
		return string.lower(e[1]) == mdl && e.skin == skin
	end

	-- Add a model to a type, or move / re-weight it if it's already listed (same model and skin).
	-- skin nil = every skin of the model. Returns the entry, or nil + why not.
	function LM.Set(mdl, skin, ctype, indoor, outdoor)
		mdl = CleanModel(mdl)
		if !mdl then return nil, "That isn't a model path (models/....mdl)." end
		if !LM.ValidType(ctype) then return nil, "No container type '" .. tostring(ctype) .. "'." end
		skin = skin && math.Clamp(math.floor(tonumber(skin) or 0), 0, 63) or nil
		indoor = math.Clamp(tonumber(indoor) or 0, 0, MAX_WEIGHT)
		outdoor = math.Clamp(tonumber(outdoor) or 0, 0, MAX_WEIGHT)
		local entry
		for _, e in ipairs(GFR.ContainerModels) do
			if SameEntry(e, mdl, skin) then entry = e break end
		end
		if !entry then
			entry = {mdl, skin = skin}
			GFR.ContainerModels[#GFR.ContainerModels + 1] = entry
		end
		entry.type = ctype
		-- (a "none" entry is never spawned)
		entry.indoor = ctype != "none" && indoor > 0 && indoor or nil
		entry.outdoor = ctype != "none" && outdoor > 0 && outdoor or nil
		Save()
		return entry
	end

	-- Take a model off the list (skin nil: every entry of that model). Returns how many were removed.
	function LM.Remove(mdl, skin)
		mdl = CleanModel(mdl)
		if !mdl then return 0 end
		local n = 0
		for i = #GFR.ContainerModels, 1, -1 do
			local e = GFR.ContainerModels[i]
			if string.lower(e[1]) == mdl && (skin == nil or e.skin == skin) then
				table.remove(GFR.ContainerModels, i)
				n = n + 1
			end
		end
		if n > 0 then Save() end
		return n
	end

	function LM.Reset()
		if file.Exists(FILE, "DATA") then file.Delete(FILE) end
		Apply(nil)
		Sync()
	end

	-- From the tool's panel: set / remove / reset
	net.Receive("GFR_LootModelsEdit", function(_, ply)
		if !LM.CanEdit(ply) or (ply.GFR_NextLootEdit or 0) > CurTime() then return end
		ply.GFR_NextLootEdit = CurTime() + 0.1
		local action = net.ReadString()
		local mdl = net.ReadString()
		local skin = net.ReadInt(8)
		local ctype = net.ReadString()
		local indoor, outdoor = net.ReadFloat(), net.ReadFloat()
		skin = skin >= 0 and skin or nil
		if action == "set" then
			local e, why = LM.Set(mdl, skin, ctype, indoor, outdoor)
			ply:ChatPrint("[Lootbox Models] " .. (e and ("Saved: " .. e[1] .. " as " .. LM.TypeName(e.type)) or why))
		elseif action == "remove" then
			local n = LM.Remove(mdl, skin)
			ply:ChatPrint("[Lootbox Models] " .. (n > 0 and ("Removed " .. mdl .. " from the list.") or "That model isn't on the list."))
		elseif action == "reset" then
			LM.Reset()
			ply:ChatPrint("[Lootbox Models] Back to the built-in list.")
		end
	end)
else
	net.Receive("GFR_LootModels", function()
		local len = net.ReadUInt(32)
		local t = util.JSONToTable(util.Decompress(net.ReadData(len)) or "")
		if !istable(t) or !istable(t.models) then return end
		Apply(t.saved && Unpack(t.models) or nil)
	end)

	-- Panel -> server
	function LM.Request(action, mdl, skin, ctype, indoor, outdoor)
		net.Start("GFR_LootModelsEdit")
		net.WriteString(action)
		net.WriteString(mdl or "")
		net.WriteInt(skin or -1, 8)
		net.WriteString(ctype or "")
		net.WriteFloat(indoor or 0)
		net.WriteFloat(outdoor or 0)
		net.SendToServer()
	end
end
