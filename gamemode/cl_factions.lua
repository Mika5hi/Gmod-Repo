--[[
	Custom Apocalypse - faction labels when you look at a person, and hiding engine ragdolls
	Server side: sv_spawner.lua
]]
local factionNames = {survivor = "Survivor", bandit = "Bandit", military = "Military"}
local dispInfo = {
	[D_HT] = {"Hostile", Color(220, 70, 60)},
	[D_NU] = {"Neutral", Color(220, 200, 120)},
	[D_LI] = {"Friendly", Color(110, 200, 110)}
}

local function S(x) return math.Round(x * ScrH() / 1080) end
surface.CreateFont("GFR_Faction_Name", {font = "Roboto", size = S(19), weight = 700, extended = true})

hook.Add("HUDPaint", "GFR_Faction_Label", function()
	local ply = LocalPlayer()
	if !IsValid(ply) or !ply:Alive() then return end
	local tr = ply:GetEyeTrace()
	local ent = tr.Entity
	if !IsValid(ent) or !ent:IsNPC() or tr.HitPos:DistToSqr(ply:EyePos()) > 1500 * 1500 then return end
	local faction = ent:GetNW2String("GFR_Faction", "")
	if faction == "" then return end
	local info = dispInfo[ent:GetNW2Int("GFR_Disp", D_NU)] or dispInfo[D_NU]
	local x, y = ScrW() / 2, ScrH() / 2 + S(70)
	-- One of yours: their name and what they're doing (sv_companions.lua)
	if ent:GetNW2Entity("GFR_CompOwner") == ply then
		local order = ent:GetNW2String("GFR_Order", "follow") == "stay" and "Holding position" or "Following you"
		draw.SimpleTextOutlined(ent:GetNW2String("GFR_Name", "Companion"), "GFR_Faction_Name", x, y, Color(150, 220, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 180))
		draw.SimpleTextOutlined(order .. "   [E] Orders & gear   [Crouch+E] " .. (order == "Following you" and "Hold" or "Follow"), "GFR_Search_Hint", x, y + S(20), Color(190, 190, 190), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 180))
		return
	end
	draw.SimpleTextOutlined(factionNames[faction] or faction, "GFR_Faction_Name", x, y, Color(230, 230, 230), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 180))
	draw.SimpleTextOutlined(info[1], "GFR_Search_Hint", x, y + S(20), info[2], TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 180))
end)

-- The NPC under the playermodel is invisible; its ragdoll would be too. The server leaves a playermodel corpse instead.
hook.Add("CreateClientsideRagdoll", "GFR_Faction_HideRagdoll", function(ent, ragdoll)
	if IsValid(ent) && ent:GetNW2Bool("GFR_PM") then
		ragdoll:SetNoDraw(true)
		SafeRemoveEntityDelayed(ragdoll, 0)
	end
end)
