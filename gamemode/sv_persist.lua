--[[
	Green Flu: Reimagined - leaving and coming back
	gfr_keep_inventory 1 (default): what you carry when you leave (guns with their magazines and parts, bag and its
	    contents, rounds, caps, weapon attachments, the bag on your back) is saved, and you get it back when you rejoin -
	    after a map change or a server restart too. Saved in data/greenflu/players/<SteamID64>.json until then.
	gfr_keep_inventory 0: it drops in a belongings bag where you were standing, for anyone to take.
	Leaving as a zombie or while dead: nothing to save (your gear is on your zombie / in your belongings already).
	The server shutting down counts as everyone leaving (single-player: quitting and loading again keeps your gear).
]]
local cvKeep = CreateConVar("gfr_keep_inventory", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY), "Players get their inventory back when they rejoin (0 = it drops where they left)")

local DIR = "greenflu/players"
local function FileOf(sid64) return DIR .. "/" .. sid64 .. ".json" end

local worn = {gfr_item_satchel = "EquipSatchel", gfr_item_backpack = "EquipBackpack"}

local function Leave(ply, shuttingDown)
	if ply.GFR_PersistDone or !ply:Alive() or ply.GFR_IsZombie or ply.GFR_GivingIn or ply.GFR_Collapsing or !GFR.CollectGear then return end
	ply.GFR_PersistDone = true
	local gear = GFR.CollectGear(ply)
	if !cvKeep:GetBool() then
		if !shuttingDown && GFR.DropGearBag then GFR.DropGearBag(ply:GetPos(), gear) end
		return
	end
	-- Ammo by name: ammo numbers can change between sessions (other addons adding types)
	local ammo = {}
	for id, count in pairs(gear.ammo or {}) do
		local name = game.GetAmmoName(id)
		if name then ammo[name] = count end
	end
	gear.ammo = ammo
	gear.wornBag = ply.GFR_BagClass -- (CollectGear put it first in the items: worn again on the way back)
	file.CreateDir(DIR)
	file.Write(FileOf(ply:SteamID64() or "0"), util.TableToJSON(gear))
end

hook.Add("PlayerDisconnected", "GFR_Persist_Leave", function(ply) Leave(ply) end)
-- The server closing (or the host quitting a single-player / listen game): everyone still here counts as leaving
hook.Add("ShutDown", "GFR_Persist_Shutdown", function()
	for _, ply in ipairs(player.GetAll()) do Leave(ply, true) end
end)

-- Back again: once you're in (after your first spawn), your things come back through a belongings bag at your feet -
-- the same way as picking one up, so whatever doesn't fit stays in it
local function Restore(ply)
	local path = FileOf(ply:SteamID64() or "0")
	if !file.Exists(path, "DATA") then return end
	local gear = util.JSONToTable(file.Read(path, "DATA") or "")
	file.Delete(path)
	if !istable(gear) then return end
	local ammo = {}
	for name, count in pairs(gear.ammo or {}) do
		local id = game.GetAmmoID(name)
		if id && id >= 0 then ammo[id] = tonumber(count) or 0 end
	end
	gear.ammo = ammo
	gear.weapons = gear.weapons or {}
	gear.items = gear.items or {}
	-- The bag you had on: straight on your back, so its slots are there for the rest
	local bag = gear.wornBag
	gear.wornBag = nil
	if bag && worn[bag] && gear.items[1] && gear.items[1].class == bag && GFR[worn[bag]] then
		table.remove(gear.items, 1)
		GFR[worn[bag]](ply)
	end
	local ent = ents.Create("gfr_gear_bag")
	if !IsValid(ent) then return end
	ent:SetPos(ply:GetPos() + Vector(0, 0, 20))
	ent.Gear = gear
	ent:Spawn()
	ent:SetOwnerName(ply:Nick())
	ent:Use(ply)
	if IsValid(ent) then GFR.Notify(ply, "Welcome back. You couldn't carry all of it - the rest is in the bag at your feet.") return end
	GFR.Notify(ply, "Welcome back. You have everything you left with.")
end

hook.Add("PlayerInitialSpawn", "GFR_Persist_Join", function(ply) ply.GFR_RestorePending = true end)

hook.Add("PlayerSpawn", "GFR_Persist_Spawn", function(ply)
	if !ply.GFR_RestorePending then return end
	ply.GFR_RestorePending = nil
	-- (after the spawn's own reset of the inventory and loadout)
	timer.Simple(1.5, function()
		if IsValid(ply) && ply:Alive() && !ply.GFR_IsZombie then Restore(ply) end
	end)
end)
