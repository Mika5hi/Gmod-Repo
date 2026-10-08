--[[
	Custom Apocalypse Project - infection/bleeding screen effects and on-screen messages
	Server side: gfr_infection.lua
]]

---------------------------------------------------------------------------------------------------------------------------------------------
-- Messages ("You've been bitten!" etc.), shown above the HUD and fading out
local messages = {}

net.Receive("GFR_Notify", function()
	table.insert(messages, 1, {text = net.ReadString(), time = CurTime()})
	if #messages > 4 then messages[5] = nil end
end)

surface.CreateFont("GFR_Notify", {font = "Roboto", size = math.Round(22 * ScrH() / 1080), weight = 600, italic = true, extended = true})

hook.Add("HUDPaint", "GFR_Notify_Draw", function()
	local now = CurTime()
	local y = ScrH() * 0.72
	for i = #messages, 1, -1 do
		local m = messages[i]
		local age = now - m.time
		if age > 5 then
			table.remove(messages, i)
		else
			local a = math.Clamp(math.min(age * 4, (5 - age) * 1.5), 0, 1) * 255
			draw.SimpleTextOutlined(m.text, "GFR_Notify", ScrW() / 2, y - (i - 1) * 28 * ScrH() / 1080, Color(235, 225, 215, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, a * 0.8))
		end
	end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Blood splash in the face: red smears that slowly fade
local splatStart = 0
local splats = {}
local SPLAT_TIME = 3

net.Receive("GFR_BloodSplat", function()
	splatStart = CurTime()
	splats = {}
	for i = 1, math.random(5, 9) do
		splats[i] = {x = math.Rand(0.15, 0.85), y = math.Rand(0.1, 0.8), r = math.Rand(0.05, 0.16)}
	end
	surface.PlaySound("physics/flesh/flesh_squishy_impact_hard" .. math.random(1, 4) .. ".wav")
end)

local circle = Material("sgm/playercircle")

---------------------------------------------------------------------------------------------------------------------------------------------
-- Symptoms
local gradDown = Material("vgui/gradient-d")
local gradUp = Material("vgui/gradient-u")
local gradLeft = Material("vgui/gradient-l")
local gradRight = Material("vgui/gradient-r")

local function Vignette(alpha, r, g, b)
	local w, h = ScrW(), ScrH()
	local edge = h * 0.35
	surface.SetDrawColor(r, g, b, alpha)
	surface.SetMaterial(gradUp)    surface.DrawTexturedRect(0, 0, w, edge)
	surface.SetMaterial(gradDown)  surface.DrawTexturedRect(0, h - edge, w, edge)
	surface.SetMaterial(gradLeft)  surface.DrawTexturedRect(0, 0, edge, h)
	surface.SetMaterial(gradRight) surface.DrawTexturedRect(w - edge, 0, edge, h)
end

hook.Add("RenderScreenspaceEffects", "GFR_Infection_Effects", function()
	local ply = LocalPlayer()
	if !IsValid(ply) or !ply:Alive() then return end
	local inf = ply:GetNW2Float("GFR_Infection", 0)
	if inf < 0.34 then return end
	local k = ply:GetNW2Bool("GFR_InfSuppressed") and 0.4 or 1

	-- Fever: washed out, warm, smeary vision
	local fever = math.Clamp((inf - 0.34) / 0.33, 0, 1) * k
	DrawColorModify({
		["$pp_colour_addr"] = 0.02 * fever,
		["$pp_colour_addg"] = 0,
		["$pp_colour_addb"] = 0,
		["$pp_colour_brightness"] = 0,
		["$pp_colour_contrast"] = 1 + 0.08 * fever,
		["$pp_colour_colour"] = 1 - 0.3 * fever,
		["$pp_colour_mulr"] = 0,
		["$pp_colour_mulg"] = 0,
		["$pp_colour_mulb"] = 0
	})
	DrawMotionBlur(0.15, 0.35 * fever, 0.01)
end)

hook.Add("HUDPaintBackground", "GFR_Infection_Overlay", function()
	local ply = LocalPlayer()
	if !IsValid(ply) or !ply:Alive() then return end
	local now = CurTime()

	-- Turning: dark, pulsing edges like a slow heartbeat
	local inf = ply:GetNW2Float("GFR_Infection", 0)
	if inf >= 0.67 then
		local k = ply:GetNW2Bool("GFR_InfSuppressed") and 0.4 or 1
		local beat = math.max(math.sin(now * 2.2), 0) ^ 4
		local strength = math.Clamp((inf - 0.67) / 0.33, 0.3, 1) * k
		Vignette((140 + 100 * beat) * strength, 0, 0, 0)
	end

	-- Bleeding: faint red at the edges
	if ply:GetNW2Bool("GFR_Bleeding") then
		Vignette(40 + 30 * math.abs(math.sin(now * 1.5)), 120, 0, 0)
	end

	-- Blood splash
	local age = now - splatStart
	if age < SPLAT_TIME then
		local a = (1 - age / SPLAT_TIME) ^ 0.7
		local w, h = ScrW(), ScrH()
		surface.SetMaterial(circle)
		for _, s in ipairs(splats) do
			local size = s.r * h * (1 + age * 0.1)
			surface.SetDrawColor(110, 0, 0, 220 * a)
			surface.DrawTexturedRect(s.x * w - size / 2, s.y * h - size / 2 + age * 20, size, size)
		end
		surface.SetDrawColor(90, 0, 0, 90 * a)
		surface.DrawRect(0, 0, w, h)
	end
end)
