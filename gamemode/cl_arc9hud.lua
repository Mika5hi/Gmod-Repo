--[[
	Custom Apocalypse - ARC9's weapon HUD tweaks (moving it to the bottom right is cl_hud.lua, gfr_arc9hud_right)

	This used to push ARC9's panel right by raising arc9_hud_deadzonex. ARC9's customize menu sizes its attachment bar
	and tabs from that same setting, so the menu opened with no attachment list. Your own value (kept in a cookie
	while the old offset was applied) is put back once, or reset if it's still the big offset.
]]
local function RestoreDeadzone()
	local dz = GetConVar("arc9_hud_deadzonex")
	if !dz then return end
	local saved = cookie.GetNumber("gfr_arc9_deadzone_orig")
	local want = saved or (dz:GetInt() > ScrW() / 4 and 0 or nil)
	cookie.Delete("gfr_arc9_deadzone_orig")
	if want && dz:GetInt() != want then RunConsoleCommand("arc9_hud_deadzonex", tostring(want)) end
end
hook.Add("InitPostEntity", "GFR_ARC9HUD_Deadzone", RestoreDeadzone)
timer.Simple(0, RestoreDeadzone) -- (Lua refresh)

-- ARC9's weapon panel pops up for its fists too ("MELEE", no ammo: nothing to show) and over a container search.
-- Hidden for fists, and while you're searching.
local function Wrap()
	if !ARC9 or !ARC9.ShouldDrawHUD or ARC9.GFR_Wrapped then return end
	ARC9.GFR_Wrapped = true
	local orig = ARC9.ShouldDrawHUD
	ARC9.ShouldDrawHUD = function(...)
		if GFR.IsSearching && GFR.IsSearching() then return end
		local wep = IsValid(LocalPlayer()) && LocalPlayer():GetActiveWeapon()
		if IsValid(wep) && GFR.IsFists && GFR.IsFists(wep:GetClass()) && !(wep.GetCustomize && wep:GetCustomize()) then return end
		return orig(...)
	end
end
hook.Add("InitPostEntity", "GFR_ARC9HUD_Wrap", Wrap)
Wrap() -- (Lua refresh)
