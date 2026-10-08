--[[
	Custom Apocalypse - character creation (server; the window is cl_customize.lua)
	Joining, you're held out of the world (frozen, unseen, untouchable) until you've picked your survivor:
	playermodel, skin, bodygroups, clothes colour. The choice is applied straight away and also stored in GMod's own
	cl_playermodel / cl_playerskin / cl_playerbodygroups / cl_playercolor settings (client side), so respawns keep it
	and it's filled in next time. gfr_customize opens it again later.
]]
util.AddNetworkString("GFR_Customize")

local function Hold(ply, on)
	ply.GFR_Customizing = on or nil
	ply:SetNW2Bool("GFR_Customizing", on)
	ply:Freeze(on)
	ply:SetNoDraw(on)
	ply:SetNoTarget(on)
	if on then ply:GodEnable() else ply:GodDisable() end
end

hook.Add("PlayerInitialSpawn", "GFR_Customize_Join", function(ply)
	ply.GFR_NeedCustomize = true
end)

hook.Add("PlayerSpawn", "GFR_Customize_Hold", function(ply)
	if !ply.GFR_NeedCustomize then return end
	ply.GFR_NeedCustomize = nil
	timer.Simple(0, function() if IsValid(ply) then Hold(ply, true) end end)
end)

-- SFW mode (sh_sfw.lua): a character saved with a model that isn't a stock one spawns as a stock citizen instead
hook.Add("PlayerSetModel", "GFR_SFW_Model", function(ply)
	if !GFR.SFWCharacter(ply) then return end
	local name = ply:GetInfo("cl_playermodel")
	if GFR.ModelAllowed(name, ply) && player_manager.AllValidModels()[name] then return end
	ply:SetModel(player_manager.TranslatePlayerModel("male07"))
	return true
end)

net.Receive("GFR_Customize", function(_, ply)
	local name = net.ReadString()
	local skin = net.ReadUInt(8)
	local groups = net.ReadString()
	local color = net.ReadVector()
	if (ply.GFR_NextCustomize or 0) > CurTime() then return end
	ply.GFR_NextCustomize = CurTime() + 0.5

	if ply:Alive() && !ply.GFR_IsZombie && player_manager.AllValidModels()[name] && GFR.ModelAllowed(name, ply) then
		ply:SetModel(player_manager.TranslatePlayerModel(name))
		ply:SetSkin(math.min(skin, math.max(ply:SkinCount() - 1, 0)))
		local i = 0
		for v in string.gmatch(groups, "%d+") do
			if i >= ply:GetNumBodyGroups() then break end
			ply:SetBodygroup(i, math.min(tonumber(v), math.max(ply:GetBodygroupCount(i) - 1, 0)))
			i = i + 1
		end
		ply:SetPlayerColor(Vector(math.Clamp(color.x, 0, 1), math.Clamp(color.y, 0, 1), math.Clamp(color.z, 0, 1)))
		-- Hands follow the model (read from cl_playermodel, which the client has just set)
		timer.Simple(0.5, function() if IsValid(ply) then ply:SetupHands() end end)
	end
	if ply.GFR_Customizing then Hold(ply, false) end
end)
