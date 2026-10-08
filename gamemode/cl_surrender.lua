--[[
	Custom Apocalypse - surrender / tied up screen
	Server side: sv_surrender.lua
]]
local function S(x) return math.Round(x * ScrH() / 1080) end
surface.CreateFont("GFR_Tied_Big", {font = "Roboto", size = S(30), weight = 800, extended = true})
surface.CreateFont("GFR_Tied_Small", {font = "Roboto", size = S(17), weight = 600, extended = true})

-- Same as the server: no shooting with your hands up (keeps prediction from showing shots)
hook.Add("StartCommand", "GFR_Surrender_NoAttack", function(ply, cmd)
	if ply:GetNW2Bool("GFR_HandsUp") or ply:GetNW2Bool("GFR_Tied") then
		cmd:RemoveKey(IN_ATTACK)
		cmd:RemoveKey(IN_ATTACK2)
		cmd:RemoveKey(IN_RELOAD)
	end
end)

hook.Add("HUDPaint", "GFR_Surrender_Draw", function()
	local ply = LocalPlayer()
	if !IsValid(ply) or !ply:Alive() then return end
	local cx = ScrW() / 2
	local y = ScrH() * 0.3

	if ply:GetNW2Bool("GFR_HandsUp") then
		draw.SimpleTextOutlined("HANDS UP", "GFR_Tied_Big", cx, y, Color(230, 220, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 200))
		draw.SimpleTextOutlined("Press J to change your mind", "GFR_Tied_Small", cx, y + S(28), Color(180, 180, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 200))
	elseif ply:GetNW2Bool("GFR_Tied") then
		draw.SimpleTextOutlined("TIED UP", "GFR_Tied_Big", cx, y, Color(220, 90, 70), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 200))
		local struggle = ply:GetNW2Float("GFR_Struggle", 0)
		-- A choice the bandits put to you (sv_surrender.lua bandit games)
		local choice = ply:GetNW2String("GFR_ChoiceText", "")
		if choice != "" then
			local yes, no = string.match(choice, "^(.-)|(.*)$")
			local left = math.max(ply:GetNW2Float("GFR_ChoiceEnd", 0) - CurTime(), 0)
			local frac = left / math.max(ply:GetNW2Float("GFR_ChoiceLen", 1), 0.1)
			local w, h = S(300), S(8)
			draw.SimpleTextOutlined("[E] " .. (yes or "Yes") .. "      [SPACE] " .. (no or "No"), "GFR_Tied_Small", cx, y + S(32), Color(240, 225, 190), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 220))
			draw.RoundedBox(h / 2, cx - w / 2, y + S(52), w, h, Color(0, 0, 0, 170))
			draw.RoundedBox(h / 2, cx - w / 2, y + S(52), math.max(w * frac, h), h, Color(200, 70, 50))
			draw.SimpleTextOutlined("Say nothing and they decide for you", "GFR_Tied_Small", cx, y + S(72), Color(160, 160, 160), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 200))
		end
		if ply:GetNW2Bool("GFR_Struggling") then
			local w, h = S(300), S(10)
			draw.SimpleTextOutlined("Mash SPACE to struggle free!", "GFR_Tied_Small", cx, y + S(30), Color(230, 230, 230), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 200))
			draw.RoundedBox(h / 2, cx - w / 2, y + S(50), w, h, Color(0, 0, 0, 170))
			draw.RoundedBox(h / 2, cx - w / 2, y + S(50), math.max(w * struggle / 100, h), h, Color(220, 170, 80))
		end
	end
end)
