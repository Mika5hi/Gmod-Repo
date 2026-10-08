--[[
	Green Flu: Reimagined - carrying settings over from the old names, once
	Everything used to be "cap_" (Custom Apocalypse): settings, commands, the one-time fix markers. Renamed to "gfr_",
	nothing would remember what you'd set. The first time this runs (on the server and on your client separately):
		- the one-time fix markers (cookies) are copied, so those fixes don't run again over your settings
		- every saved setting is read from the old names in cfg/server.vdf and cfg/client.vdf and put on the new one
	Settings that no longer exist (parasites) are skipped. Loaded first, from shared.lua.
]]
local OLD, NEW = "c" .. "ap_", "gfr_" -- (spelled out so a find-and-replace can never turn this into a no-op)
local DONE = NEW .. "renamed_from_old"

local markers = {"daylen_v2", "inv_slots_v2", "maploot_v2", "perf_half", "spawn_v2", "body_remove_v2",
	"zonemap_key_orig", "arc9_deadzone_orig", "arc9_saved", "fallout_saved"}

if cookie.GetString(DONE) != "1" then
	for _, m in ipairs(markers) do
		local v = cookie.GetString(OLD .. m)
		if v != nil && cookie.GetString(NEW .. m) == nil then cookie.Set(NEW .. m, v) end
	end
end

hook.Add("Initialize", "GFR_RenameSettings", function()
	if cookie.GetString(DONE) == "1" then return end
	cookie.Set(DONE, "1")
	local path = SERVER and "cfg/server.vdf" or "cfg/client.vdf"
	local raw = file.Read(path, "MOD") or file.Read(path, "GAME")
	if !raw then return end
	local moved = 0
	for name, value in string.gmatch(raw, '"' .. OLD .. '([%w_]+)"%s+"([^"]*)"') do
		local new = NEW .. name
		local cv = GetConVar(new)
		-- (on the client only its own settings: the server's are the server's to set)
		if cv && (SERVER or !cv:IsFlagSet(FCVAR_REPLICATED)) && cv:GetString() != value then
			RunConsoleCommand(new, value)
			moved = moved + 1
		end
	end
	if moved > 0 then print("[Green Flu: Reimagined] Carried over " .. moved .. " settings from the old names (" .. path .. ")") end
end)
