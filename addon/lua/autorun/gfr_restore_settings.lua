--[[
	Custom Apocalypse Project - put other addons' settings back after a crash

	While the Custom Apocalypse gamemode runs it changes a few of other addons' settings (ARC9 attachment rules and HUD
	position, the Fallout Looting System's containers) and puts them back when the game closes. If the game crashes,
	the originals are still in a cookie: in any other gamemode they're restored as soon as it loads.
]]
AddCSLuaFile()

local function InOurGamemode() return engine.ActiveGamemode() == "greenflu" end

hook.Add("InitPostEntity", "GFR_RestoreSettings", function()
	if InOurGamemode() then return end -- (the gamemode handles its own)

	if SERVER then
		local arc9 = cookie.GetString("gfr_arc9_saved")
		if arc9 then
			for name, value in pairs(util.JSONToTable(arc9) or {}) do
				if GetConVar(name) then RunConsoleCommand(name, value) end
			end
			cookie.Delete("gfr_arc9_saved")
		end
		local fallout = cookie.GetString("gfr_fallout_saved")
		if fallout then
			if GetConVar("loots_enable_container") then RunConsoleCommand("loots_enable_container", fallout) end
			cookie.Delete("gfr_fallout_saved")
		end
	else
		local dz = cookie.GetString("gfr_arc9_deadzone_orig")
		if dz then
			if GetConVar("arc9_hud_deadzonex") then RunConsoleCommand("arc9_hud_deadzonex", dz) end
			cookie.Delete("gfr_arc9_deadzone_orig")
		end
	end
end)
