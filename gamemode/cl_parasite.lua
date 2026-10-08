--[[
	Custom Apocalypse - parasite latched on: "MASH E" prompt with a closing timer and a pulsing red edge
	Server side: sv_parasite.lua
]]
local latchEnd, latchLen

net.Receive("GFR_ParasiteLatch", function()
	local len = net.ReadFloat()
	if len > 0 then
		latchLen, latchEnd = len, CurTime() + len
	else
		latchEnd = nil
	end
end)

local function S(x) return math.Round(x * ScrH() / 1080) end
surface.CreateFont("GFR_Parasite_Big", {font = "Roboto", size = S(42), weight = 900, extended = true})

hook.Add("HUDPaint", "GFR_Parasite_Latch", function()
	if !latchEnd then return end
	local left = latchEnd - CurTime()
	if left <= 0 or !LocalPlayer():Alive() then latchEnd = nil return end
	local w, h = ScrW(), ScrH()
	local pulse = 0.5 + 0.5 * math.sin(CurTime() * 14)
	-- red vignette edges
	local a = 60 + 80 * pulse
	surface.SetDrawColor(140, 0, 0, a)
	surface.DrawRect(0, 0, w, S(40))
	surface.DrawRect(0, h - S(40), w, S(40))
	surface.DrawRect(0, 0, S(40), h)
	surface.DrawRect(w - S(40), 0, S(40), h)

	local cx, cy = w / 2, h * 0.62
	draw.SimpleTextOutlined("MASH  [E]", "GFR_Parasite_Big", cx, cy, Color(255, 90 + 120 * pulse, 90 + 120 * pulse), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, Color(0, 0, 0, 220))
	local bw, bh = S(320), S(10)
	local frac = math.Clamp(left / latchLen, 0, 1)
	draw.RoundedBox(bh / 2, cx - bw / 2, cy + S(34), bw, bh, Color(0, 0, 0, 180))
	draw.RoundedBox(bh / 2, cx - bw / 2, cy + S(34), math.max(bw * frac, bh), bh, Color(200, 40, 40))
	-- (J still gives in to it - a secret now, not shown)
end)
