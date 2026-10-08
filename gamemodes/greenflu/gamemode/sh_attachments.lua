--[[
	Custom Apocalypse - ARC9 weapon attachments
	Customizing a gun only works at a Gun Table (crafted at a workbench, gfr_deploy_gunbench; gfr_arc9_bench).
	There, every attachment is available (arc9_free_atts 1) - nothing to loot.
	gfr_arc9_found 1 is the old way (arc9_free_atts 0):
		- You can only fit what you own. Owned attachments sit in ARC9's attachment stash (shown in its customize menu).
		  Taking a part off puts it in your stash.
		- Found in loot: weapon crates, lockers, military crates, ammo crates, cargo... mostly for guns you carry
		  (sh_containers.lua "atts", sv_containers.lua). Lying around they're small boxes (gfr_att_box), E to take.
		- When you die, the stash and the parts on your guns go into your belongings with everything else.
	ARC9's own settings are put back when the gamemode shuts down.
]]
AddCSLuaFile()
GFR = GFR or {}

local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED)
local cvOwned = CreateConVar("gfr_arc9_found", "0", flags, "ARC9 attachments must be found in loot (0: every attachment is available at a Gun Table)")
local cvBench = CreateConVar("gfr_arc9_bench", "1", flags, "ARC9 guns can only be customized at a Gun Table")

function GFR.AttName(att)
	local t = ARC9 && ARC9.GetAttTable(att)
	if !t then return att end
	local name = t.PrintName or att
	if ARC9.GetPhrase && isstring(name) then name = ARC9:GetPhrase(name) or name end
	return name
end

local function BenchOK(ply)
	return !cvBench:GetBool() or !IsValid(ply) or !ply:IsPlayer() or !GFR.NearGunBench or GFR.NearGunBench(ply)
end

-- The customize menu only opens at a Gun Table
local function PatchBase()
	local base = weapons.GetStored("arc9_base")
	if !base or base.GFR_BenchPatched then return end
	local orig = base.ToggleCustomize
	base.ToggleCustomize = function(self, on)
		if on then
			local owner = self:GetOwner()
			if !BenchOK(owner) then
				if CLIENT && owner == LocalPlayer() && (self.GFR_NextBenchMsg or 0) < CurTime() then
					self.GFR_NextBenchMsg = CurTime() + 2
					notification.AddLegacy("You need a Gun Table to work on your gun.", NOTIFY_HINT, 3)
					surface.PlaySound("buttons/button10.wav")
				end
				return
			end
		end
		return orig(self, on)
	end
	base.GFR_BenchPatched = true
end
hook.Add("InitPostEntity", "GFR_Attachments_Patch", PatchBase)
hook.Add("OnReloaded", "GFR_Attachments_Patch", PatchBase)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Hand-loading: [ARC9] EFT Modular Cartridges (Workshop 3443227960) parts are made at a workbench from our materials,
-- never found as loot. Each recipe puts one part in your attachment stash (Crafting window, "Hand-loading" tab).
GFR.HANDLOAD_PREFIX = "eft_ammo_mb_"

local function HandloadCost(att)
	local s = string.sub(att, #GFR.HANDLOAD_PREFIX + 1)
	local function has(w) return string.find(s, w, 1, true) != nil end
	if string.StartWith(s, "case_") then
		if has("steel") then return {gfr_mat_scrap = 2} end
		return {gfr_mat_scrap = 1}
	elseif string.StartWith(s, "projectile_intern_") then
		if has("_he") then return {gfr_mat_gunpowder = 3, gfr_mat_chem = 1, gfr_mat_parts = 1} end
		if has("incendiary") then return {gfr_mat_chem = 2, gfr_mat_gunpowder = 1} end
		return {gfr_mat_chem = 1} -- tracers
	elseif string.StartWith(s, "projectile_main_") then
		if has("lead") or has("copper") then return {gfr_mat_scrap = 1} end
		if has("softsteel") or s == "projectile_main_steel" then return {gfr_mat_scrap = 2} end
		return {gfr_mat_scrap = 2, gfr_mat_parts = 1} -- hardened steel, tungsten and other penetrators
	elseif has("flare") then
		return {gfr_mat_chem = 1, gfr_mat_gunpowder = 1}
	elseif string.StartWith(s, "projectile_") then
		return {gfr_mat_scrap = 1} -- tips, jackets, shot
	elseif string.StartWith(s, "load_") then
		if has("magnum") then return {gfr_mat_gunpowder = 2} end
		return {gfr_mat_gunpowder = 1}
	end
	return {gfr_mat_gunpowder = 1, gfr_mat_scrap = 1} -- the cartridge itself (one per caliber) and anything else
end

local function BuildHandloadRecipes()
	if !ARC9 or !ARC9.Attachments or GFR.HandloadBuilt or !cvOwned:GetBool() then return end -- (free attachments: nothing to make)
	local list = {}
	for att, t in pairs(ARC9.Attachments) do
		if string.StartWith(att, GFR.HANDLOAD_PREFIX) && !t.Free then list[#list + 1] = att end
	end
	if #list == 0 then return end
	GFR.HandloadBuilt = true
	table.sort(list, function(a, b) return GFR.AttName(a) < GFR.AttName(b) end)
	for _, att in ipairs(list) do
		local r = {id = "hl_" .. att, name = GFR.AttName(att), cat = "Hand-loading", att = att, n = 1,
			inputs = HandloadCost(att), bench = true, always = true}
		GFR.Recipes[#GFR.Recipes + 1] = r
		GFR.RecipeById[r.id] = r
	end
end
hook.Add("InitPostEntity", "GFR_Attachments_Handload", BuildHandloadRecipes)

if CLIENT then return end

---------------------------------------------------------------------------------------------------------------------------------------------
-- ARC9 settings while playing (restored on shutdown). Your own values are also kept in a cookie: if the game closes
-- without a clean shutdown (a crash), they're put back the next time anything loads (lua/autorun/gfr_restore_settings.lua)
local COOKIE = "gfr_arc9_saved"

hook.Add("InitPostEntity", "GFR_Attachments_Convars", function()
	if !ARC9 then return end
	local wanted = {arc9_free_atts = cvOwned:GetBool() and "0" or "1", arc9_atts_lock = "0", arc9_atts_loseondie = "0", arc9_atts_nocustomize = "0"}
	-- (still saved from a session that crashed: those are your real values, not what's set now)
	local saved = util.JSONToTable(cookie.GetString(COOKIE, "") or "") or {}
	for name, value in pairs(wanted) do
		local cv = GetConVar(name)
		if cv && cv:GetString() != value then
			if saved[name] == nil then saved[name] = cv:GetString() end
			RunConsoleCommand(name, value)
		end
	end
	if !table.IsEmpty(saved) then cookie.Set(COOKIE, util.TableToJSON(saved)) end
end)
hook.Add("ShutDown", "GFR_Attachments_Convars", function()
	local saved = util.JSONToTable(cookie.GetString(COOKIE, "") or "") or {}
	for name, value in pairs(saved) do RunConsoleCommand(name, value) end
	cookie.Delete(COOKIE)
end)

-- Changes to a gun are refused away from a Gun Table (the menu is blocked client-side, this stops anything sneaking past)
hook.Add("InitPostEntity", "GFR_Attachments_NetGuard", function()
	local nocustomize = GetConVar("arc9_atts_nocustomize")
	net.Receive("arc9_networkweapon", function(len, ply)
		local wpn = net.ReadEntity()
		if !IsValid(wpn) or !wpn.ARC9 then return end
		if wpn:GetOwner() != ply then return end -- (only your own gun: anyone could have rebuilt anyone's)
		if !BenchOK(ply) then
			wpn:SendWeapon(ply) -- put their view of the gun back
			return
		end
		if nocustomize && nocustomize:GetBool() then return end
		wpn:ReceiveWeapon()
	end)
end)

-- Walk away from the Gun Table: the menu closes
timer.Create("GFR_Attachments_BenchCheck", 1, 0, function()
	if !cvBench:GetBool() then return end
	for _, ply in ipairs(player.GetAll()) do
		local wep = ply:GetActiveWeapon()
		if IsValid(wep) && wep.ARC9 && wep.GetCustomize && wep:GetCustomize() && !BenchOK(ply) then
			wep:ToggleCustomize(false)
		end
	end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Picking an attachment worth finding
local function Usable(att, t)
	if !t or t.Free or t.AdminOnly or t.InvAtt or ARC9.Blacklist[att] then return false end
	if string.StartWith(att, GFR.HANDLOAD_PREFIX) then return false end -- hand-loaded at a workbench, never found
	local s = string.lower(att)
	if string.find(s, "sticker", 1, true) or string.find(s, "camo", 1, true) or string.find(s, "charm", 1, true) or string.find(s, "skin", 1, true) then return false end
	return true
end

local catCache = {}
local function AttsForCats(cats)
	if !istable(cats) then cats = {cats} end
	local key = table.concat(cats, ",")
	if catCache[key] then return catCache[key] end
	local list = {}
	for _, att in ipairs(ARC9.GetAttsForCats(cats)) do
		if Usable(att, ARC9.GetAttTable(att)) then list[#list + 1] = att end
	end
	catCache[key] = list
	return list
end

local anyList
local function RandomAny()
	if !anyList then
		anyList = {}
		for att, t in pairs(ARC9.Attachments or {}) do
			if Usable(att, t) && (t.Model or t.HasAmmoooooooo) then anyList[#anyList + 1] = att end
		end
	end
	return anyList[math.random(math.max(#anyList, 1))]
end

-- Mostly something that fits a gun you carry; sometimes anything
function GFR.RandomAttachment(ply)
	if !ARC9 or !ARC9.Attachments then return end
	if IsValid(ply) && math.random(100) <= 80 then
		local guns = {}
		for _, w in ipairs(ply:GetWeapons()) do
			if w.ARC9 && w.GetSubSlotList then guns[#guns + 1] = w end
		end
		if #guns > 0 then
			for _ = 1, 6 do
				local gun = guns[math.random(#guns)]
				local slots = gun:GetSubSlotList()
				local slot = slots[math.random(math.max(#slots, 1))]
				if slot && slot.Category then
					local list = AttsForCats(slot.Category)
					if #list > 0 then
						local att = list[math.random(#list)]
						if att != slot.Installed then return att end
					end
				end
			end
		end
	end
	return RandomAny()
end

function GFR.SpawnAttachmentBox(att, pos)
	if !att then return end
	local box = ents.Create("gfr_att_box")
	if !IsValid(box) then return end
	box:SetPos(pos)
	box:SetAngles(Angle(0, math.random(0, 359), 0))
	box:Spawn()
	box:SetAtt(att)
	return box
end

-- Armed people sometimes carry spare parts: soldiers often, other groups now and then
hook.Add("OnNPCKilled", "GFR_Attachments_NPCDrop", function(npc, attacker)
	if !cvOwned:GetBool() or !npc.GFR_Group or !ARC9 then return end
	local chance = npc.GFR_Helmet and 35 or 8
	if math.random(100) > chance then return end
	GFR.SpawnAttachmentBox(GFR.RandomAttachment(IsValid(attacker) && attacker:IsPlayer() and attacker or nil), npc:WorldSpaceCenter() + Vector(0, 0, 10))
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Dying: the stash and the parts on your guns go with your belongings (sv_infection.lua CollectGear / gfr_gear_bag)
local function CaptureTree(slot)
	if !slot then return end
	local t = {Installed = slot.Installed, ToggleNum = slot.ToggleNum}
	if slot.SubAttachments then
		t.SubAttachments = {}
		for i, s in pairs(slot.SubAttachments) do t.SubAttachments[i] = CaptureTree(s) end
	end
	return t
end

function GFR.CaptureWeaponAtts(wep)
	if !IsValid(wep) or !wep.ARC9 or !wep.Attachments then return end
	local tree = {}
	for i, slot in ipairs(wep.Attachments) do tree[i] = CaptureTree(slot) end
	return tree
end

function GFR.RestoreWeaponAtts(wep, tree)
	if !IsValid(wep) or !wep.ARC9 or !tree or !wep.BuildSubAttachments then return end
	local ok = pcall(function()
		wep:BuildSubAttachments(tree)
		wep:PostModify()
		wep:SendWeapon()
	end)
	if !ok then print("[GFR] Couldn't restore the attachments on " .. wep:GetClass()) end
end

-- No free ammo with guns: ARC9 hands out "magazine size x arc9_mult_defaultammo" reserve rounds 0.4 s after any gun
-- is created (InitialDefaultClip; this ARC9 version has no off switch) - equipping a gun from your bag, crafting
-- one, buying one... all gave ammo. Guns only get what's actually in them. Single-use things (grenades, flares) still
-- get theirs: that's their one use.
local function PatchDefaultAmmo()
	local base = weapons.GetStored("arc9_base")
	if !base or base.GFR_NoFreeAmmo or !base.InitialDefaultClip then return end
	local orig = base.InitialDefaultClip
	base.InitialDefaultClip = function(self, ...)
		local singleUse = self.Disposable or self.Throwable or self.BottomlessClip
			or (self.GetValue && (self:GetValue("Throwable") or self:GetValue("BottomlessClip") or (self:GetValue("ClipSize") or 0) <= 0))
		if singleUse then return orig(self, ...) end
	end
	base.GFR_NoFreeAmmo = true
end
hook.Add("InitPostEntity", "GFR_ARC9_NoFreeAmmo", PatchDefaultAmmo)
if GAMEMODE then PatchDefaultAmmo() end

-- Put a gun back the way it was (magazine, parts) after it's been given to someone.
-- ARC9 fills the magazine for free the first time a gun is set up, and again on an attachment change if it hasn't
-- "given ammo" yet - which overwrote the saved count with a full mag. So: mark it as already supplied, let the
-- attachment change happen, then put the saved count back once ARC9 is done.
function GFR.ApplyWeaponState(w, clip1, clip2, atts)
	if !IsValid(w) then return end
	local function Settle()
		if !IsValid(w) then return end
		if clip1 && clip1 >= 0 then w:SetClip1(clip1) end
		if clip2 && clip2 >= 0 then w:SetClip2(clip2) end
		if w.ARC9 then
			w.AlreadyGaveAmmo = true
			w.AlreadyGaveUBGLAmmo = true
			if w.GetValue && w.GetProcessedValue then
				w.LastAmmo = w:GetValue("Ammo")
				w.LastClipSize = math.Round(w:GetProcessedValue("ClipSize") or 0)
			end
		end
	end
	timer.Simple(0, Settle)
	if atts && w.ARC9 then
		timer.Simple(0.2, function()
			if !IsValid(w) then return end
			-- A different magazine would otherwise "unload" the current count into your reserve (free ammo);
			-- a free refill is harmless because the saved count goes back in right after
			w.AlreadyGaveAmmo = false
			GFR.RestoreWeaponAtts(w, atts)
			timer.Simple(0.3, Settle)
		end)
	else
		timer.Simple(0.3, Settle)
	end
end

function GFR.TakeAttStash(ply)
	local inv = table.Copy(ply.ARC9_AttInv or {})
	return inv
end

function GFR.GiveAttStash(ply, stash)
	if !ARC9 or !stash then return 0 end
	local n = 0
	for att, count in pairs(stash) do
		if ARC9.GetAttTable(att) then
			ARC9:PlayerGiveAtt(ply, att, count)
			n = n + count
		end
	end
	ARC9:PlayerSendAttInv(ply)
	return n
end

-- Your stash is in your belongings now; a fresh body starts with nothing
hook.Add("PlayerSpawn", "GFR_Attachments_Spawn", function(ply)
	if !ARC9 or !cvOwned:GetBool() then return end
	ply.ARC9_AttInv = {}
	timer.Simple(0.5, function() if IsValid(ply) then ARC9:PlayerSendAttInv(ply) end end)
end)
