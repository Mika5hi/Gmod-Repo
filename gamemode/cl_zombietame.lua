--[[
	Custom Apocalypse - HUD for living with the living as a zombie (server: sv_zombietame.lua)
	What the nearest group thinks of you, your current job (with a marker on who/what it's about) and what you carry.
]]
local function S(x) return math.Round(x * ScrH() / 1080) end

local function Fonts()
	surface.CreateFont("GFR_ZTame", {font = "Roboto", size = S(17), weight = 700, extended = true})
	surface.CreateFont("GFR_ZTameSmall", {font = "Roboto", size = S(15), weight = 600, extended = true})
end
Fonts()
hook.Add("OnScreenSizeChanged", "GFR_ZTame_Fonts", Fonts)

local colOrder = Color(235, 200, 120)
local colStatus = Color(200, 200, 190)
local colOutline = Color(0, 0, 0, 200)

hook.Add("HUDPaint", "GFR_ZTame_HUD", function()
	local ply = LocalPlayer()
	if !IsValid(ply) or !ply:GetNW2Bool("GFR_IsZombie") then return end
	local cx = ScrW() / 2
	local y = S(70)

	local order = ply:GetNW2String("GFR_ZOrder", "")
	if order != "" then
		draw.SimpleTextOutlined(order, "GFR_ZTame", cx, y, colOrder, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, colOutline)
		y = y + S(24)
		-- Marker over who it's about
		local ent = ply:GetNW2Entity("GFR_ZOrderEnt")
		if IsValid(ent) then
			local pos = ent:GetPos() + Vector(0, 0, ent:OBBMaxs().z + 14)
			local sp = pos:ToScreen()
			if sp.visible then
				local dist = math.floor(LocalPlayer():GetPos():Distance(ent:GetPos()) / 52.5)
				local pulse = 0.6 + 0.4 * math.sin(CurTime() * 5)
				draw.SimpleTextOutlined("v", "GFR_ZTame", sp.x, sp.y, Color(colOrder.r, colOrder.g, colOrder.b, 255 * pulse), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, colOutline)
				draw.SimpleTextOutlined(dist .. " m", "GFR_ZTameSmall", sp.x, sp.y - S(18), colOrder, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, colOutline)
			end
		end
	end

	local carry = ply:GetNW2String("GFR_ZCarry", "")
	if carry != "" then
		draw.SimpleTextOutlined("Carrying: " .. carry, "GFR_ZTameSmall", cx, y, colStatus, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, colOutline)
		y = y + S(20)
	end

	-- They're testing you: what they shouted, and how long you have (lower middle of the screen, can't miss it)
	local test = ply:GetNW2String("GFR_ZTest", "")
	if test != "" then
		local ends, len = ply:GetNW2Float("GFR_ZTestEnd", 0), math.max(ply:GetNW2Float("GFR_ZTestLen", 1), 0.1)
		local frac = math.Clamp((ends - CurTime()) / len, 0, 1)
		local ty = ScrH() * 0.68
		local pulse = 0.75 + 0.25 * math.sin(CurTime() * 6)
		draw.SimpleTextOutlined(test, "GFR_ZTame", cx, ty, Color(255, 225 * pulse + 30, 140), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, colOutline)
		local w, h = S(240), S(5)
		draw.RoundedBox(2, cx - w / 2, ty + S(16), w, h, Color(0, 0, 0, 170))
		draw.RoundedBox(2, cx - w / 2, ty + S(16), math.max(w * frac, h), h, colOrder)
	end

	local status = ply:GetNW2String("GFR_ZStatus", "")
	if status != "" then
		draw.SimpleTextOutlined(status, "GFR_ZTameSmall", cx, y, colStatus, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, colOutline)
	end
end)

-- Your zombie's hunger (sv_zombiehunger.lua): a bar at the bottom, its stage named, pulsing red when feral.
-- Drawn after the whole HUD (PostDrawHUD), so no other addon's HUD hook can stop it from showing.
hook.Add("PostDrawHUD", "GFR_ZHunger_HUD", function()
	local ply = LocalPlayer()
	if !IsValid(ply) or !ply:GetNW2Bool("GFR_IsZombie") then GFR.ZHungerBucket = nil return end -- (turning again: shown again)
	local hunger = ply:GetNW2Float("GFR_ZHunger", -1)
	if hunger < 0 then hunger = 70 end -- (not arrived from the server yet)
	cam.Start2D()
	local cx = ScrW() / 2
	local stage, col
	if hunger >= 70 then stage, col = "SATED", Color(150, 200, 120)
	elseif hunger >= 40 then stage, col = "HUNGRY", Color(220, 190, 110)
	elseif hunger >= 15 then stage, col = "STARVING", Color(230, 120, 70)
	else stage, col = "FERAL", Color(230, 50 + 40 * math.sin(CurTime() * 8), 40) end
	-- Lost to the hunger (sv_zombiehunger.lua): it's in charge until it's full
	if ply:GetNW2Bool("GFR_ZLost") then
		-- (fades out after 10 s)
		GFR.ZLostSince = GFR.ZLostSince or CurTime()
		local a = math.Clamp(1 - (CurTime() - GFR.ZLostSince - 10), 0, 1)
		if a > 0 then
			local pulse = 0.7 + 0.3 * math.sin(CurTime() * 3)
			local ol = Color(0, 0, 0, 200 * a)
			draw.SimpleTextOutlined("LOST TO THE HUNGER", "GFR_ZTame", cx, ScrH() * 0.22, Color(220 * pulse + 35, 60, 50, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, ol)
			draw.SimpleTextOutlined("It hunts and eats on its own. You take back control once it's full.", "GFR_ZTameSmall", cx, ScrH() * 0.22 + S(22), ColorAlpha(colStatus, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, ol)
		end
	elseif ply:GetNW2Bool("GFR_ZIdleAI") then
		-- Left alone a while: it wanders by itself until you move. The note fades out after 5 s
		GFR.ZDriftSince = GFR.ZDriftSince or CurTime()
		local a = math.Clamp(1 - (CurTime() - GFR.ZDriftSince - 5), 0, 1)
		if a > 0 then
			local ol = Color(0, 0, 0, 200 * a)
			draw.SimpleTextOutlined("DRIFTING", "GFR_ZTame", cx, ScrH() * 0.22, Color(170, 170, 160, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, ol)
			draw.SimpleTextOutlined("Your body shambles on by itself. Move to take it back.", "GFR_ZTameSmall", cx, ScrH() * 0.22 + S(22), ColorAlpha(colStatus, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, ol)
		end
	end
	if !ply:GetNW2Bool("GFR_ZIdleAI") then GFR.ZDriftSince = nil end -- (next time it drifts, the note shows again)
	if !ply:GetNW2Bool("GFR_ZLost") then GFR.ZLostSince = nil end
	-- (feral: the vein overlay pulses darker, sh_zombieplayer.lua)
	-- The meter only shows for 10 s each time it crosses a 10% mark (and when you first turn), then fades away
	local bucket = math.floor(hunger / 10)
	if bucket != GFR.ZHungerBucket then
		GFR.ZHungerBucket = bucket
		GFR.ZHungerShowT = CurTime()
	end
	local a = math.Clamp(1 - (CurTime() - (GFR.ZHungerShowT or 0) - 10), 0, 1)
	if a > 0 then
		local w, h = S(260), S(8)
		local bx, by = cx - w / 2, ScrH() - S(54)
		draw.RoundedBox(3, bx, by, w, h, Color(0, 0, 0, 170 * a))
		draw.RoundedBox(3, bx, by, math.max(w * hunger / 100, h), h, ColorAlpha(col, 255 * a))
		draw.SimpleTextOutlined("HUNGER  -  " .. stage, "GFR_ZTameSmall", cx, by - S(4), ColorAlpha(col, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, 200 * a))
	end
	cam.End2D()
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Drifting (sv_zombiehunger.lua): middle mouse drops in / out of it (a debug shortcut - not shown anywhere).
-- (Your zombie can't skip time: only living players can, by sleeping, when gfr_timeskip is on - sv_base.lua)
local midWas

local function Typing()
	local ply = LocalPlayer()
	return ply:IsTyping() or vgui.GetKeyboardFocus() != nil or gui.IsGameUIVisible() or gui.IsConsoleVisible()
end

hook.Add("Think", "GFR_ZDrift_Keys", function()
	local ply = LocalPlayer()
	if !IsValid(ply) then return end
	local mid = input.IsMouseDown(MOUSE_MIDDLE)
	if mid && !midWas && ply:GetNW2Bool("GFR_IsZombie") && !Typing() then
		net.Start("GFR_ZDriftToggle")
		net.SendToServer()
	end
	midWas = mid
end)
