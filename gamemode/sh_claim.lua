--[[
	Custom Apocalypse - claim flags: your base is yours
	A Claim Flag (built from a kit, sh_items.lua gfr_deploy_claim) protects everything within gfr_claim_radius of it:
		- no zombies, survivor/bandit/soldier groups or airdrop hordes spawn inside (sv_spawner.lua, sv_airdrop.lua)
		- no map loot or junk spawns inside (sv_loot.lua): your base doesn't fill up with crates
		- roaming zombies don't pick a spot inside as somewhere to wander to (sv_zombieworld.lua)
	Things can still walk in from outside: drawn by noise, chasing you, smelling bodies. Build walls.
	Each player can have gfr_claim_max flags. The flag is a building like any other: zombies and bandits can wreck it
	(the claim goes with it), E repairs it, Crouch+E picks it up.
	Near a claim you see its edge as a ring on the ground; inside, "Claimed area" shows at the top of the screen.
]]
AddCSLuaFile()
GFR = GFR or {}

local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)
local cvRadius = CreateConVar("gfr_claim_radius", "1600", flags, "Radius around a claim flag where nothing spawns")
local cvMax    = CreateConVar("gfr_claim_max", "2", flags, "Claim flags each player can have")

function GFR.ClaimRadius() return cvRadius:GetFloat() end

-- The flags in the world (refreshed every second; a placed flag adds itself right away)
local claims = {}
local nextScan = 0

local function Claims()
	if CurTime() >= nextScan then
		nextScan = CurTime() + 1
		claims = {}
		for _, class in ipairs({"prop_physics", "prop_dynamic"}) do -- (pieces without physics are built as prop_dynamic)
			for _, ent in ipairs(ents.FindByClass(class)) do
				if ent:GetNW2Bool("GFR_Claim") then claims[#claims + 1] = ent end
			end
		end
	end
	return claims
end
GFR.Claims = Claims

-- Is pos inside any claim (grown by margin)?
function GFR.InClaim(pos, margin)
	local r = cvRadius:GetFloat() + (margin or 0)
	r = r * r
	for _, flag in ipairs(Claims()) do
		if IsValid(flag) && flag:GetPos():DistToSqr(pos) <= r then return flag end
	end
	return false
end

if SERVER then
	function GFR.ClaimCount(ply)
		local n = 0
		for _, flag in ipairs(Claims()) do
			if IsValid(flag) && flag.GFR_Builder == ply then n = n + 1 end
		end
		return n
	end

	-- Called by sv_crafting.lua before a flag goes down; false + message if not allowed
	function GFR.CanClaim(ply, pos)
		if GFR.ClaimCount(ply) >= cvMax:GetInt() then
			return false, "You already have " .. cvMax:GetInt() .. " claim flag(s). Pick one up (Crouch+E) to move your claim."
		end
		return true
	end

	function GFR.RegisterClaim(ent)
		ent:SetNW2Bool("GFR_Claim", true)
		claims[#claims + 1] = ent
		local ply = ent.GFR_Builder
		if IsValid(ply) then
			GFR.Notify(ply, "Area claimed: nothing spawns within " .. math.Round(cvRadius:GetFloat() * 0.019) .. " m of the flag.")
		end
	end
	return
end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Client: the edge of the claim as a ring on the ground when you're near it, and a note while you're inside
local ringCol = Color(110, 200, 140, 90)
local SEGMENTS = 64

hook.Add("PostDrawTranslucentRenderables", "GFR_Claim_Ring", function(depth, sky)
	if sky then return end
	local ply = LocalPlayer()
	if !IsValid(ply) then return end
	local r = cvRadius:GetFloat()
	for _, flag in ipairs(Claims()) do
		if IsValid(flag) then
			local d = flag:GetPos():Distance(ply:GetPos())
			if math.abs(d - r) < 700 then
				local c = flag:GetPos()
				local prev
				render.SetColorMaterial()
				for i = 0, SEGMENTS do
					local a = (i / SEGMENTS) * math.pi * 2
					local p = c + Vector(math.cos(a) * r, math.sin(a) * r, 0)
					-- Sit it on the ground
					local tr = util.TraceLine({start = p + Vector(0, 0, 200), endpos = p - Vector(0, 0, 400), mask = MASK_SOLID_BRUSHONLY})
					p = tr.Hit and (tr.HitPos + Vector(0, 0, 3)) or p
					if prev && prev:DistToSqr(ply:GetPos()) < 2500 * 2500 then render.DrawBeam(prev, p, 4, 0, 1, ringCol) end
					prev = p
				end
			end
		end
	end
end)

local function S(x) return math.Round(x * ScrH() / 1080) end
surface.CreateFont("GFR_Claim", {font = "Roboto", size = S(15), weight = 700, extended = true})

hook.Add("HUDPaint", "GFR_Claim_Inside", function()
	local ply = LocalPlayer()
	if !IsValid(ply) or !ply:Alive() or ply:GetNW2Bool("GFR_IsZombie") then return end
	if GFR.InClaim(ply:GetPos()) then
		draw.SimpleTextOutlined("CLAIMED AREA  -  nothing spawns here", "GFR_Claim", ScrW() / 2, S(14), Color(140, 210, 160), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 170))
	end
end)
