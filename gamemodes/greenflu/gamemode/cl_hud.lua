--[[
	Custom Apocalypse Project - HUD
	Bottom left, like Red Dead Redemption 2's cores: a row of dark circles, each with a white ring that drains as the stat
	drops and an icon inside - health (heart), stamina (bolt), water (drop), hunger (apple), and infection (virus) once
	it shows. No numbers. Low ones pulse in their warning colour; armor is a blue outline around health; a pale trail on
	the health ring shows what you just lost. Warnings (bleeding, exhausted, starving, fever...) as tags above the row.
	Bottom right: ammo for guns that don't draw their own (ARC9 guns keep ARC9's HUD). Half-Life 2's health, suit and
	ammo panels are hidden, so nothing sits on top of anything else.
]]
local cvHud = CreateClientConVar("gfr_hud", "1", true, false, "Show the Green Flu: Reimagined HUD")
local cvScale = CreateClientConVar("gfr_hud_scale", "1", true, false, "HUD size multiplier")

local hidden = {CHudHealth = true, CHudBattery = true, CHudAmmo = true, CHudSecondaryAmmo = true}
hook.Add("HUDShouldDraw", "GFR_HUD_HideDefault", function(name)
	if hidden[name] && cvHud:GetBool() then return false end
end)

local lastScale
local function UpdateFonts(s)
	if lastScale == s then return end
	lastScale = s
	surface.CreateFont("GFR_HUD_Label", {font = "Roboto", size = math.Round(13 * s), weight = 700, extended = true})
	surface.CreateFont("GFR_HUD_Tag", {font = "Roboto", size = math.Round(12 * s), weight = 800, extended = true})
	surface.CreateFont("GFR_HUD_Ammo", {font = "Roboto", size = math.Round(44 * s), weight = 800, extended = true})
	surface.CreateFont("GFR_HUD_AmmoSmall", {font = "Roboto", size = math.Round(20 * s), weight = 700, extended = true})
end

local colText = Color(235, 232, 222)
local colDim = Color(170, 166, 156)
local colWhite = Color(240, 238, 232)
local colTrack = Color(255, 255, 255, 40)
local colArmor = Color(90, 155, 230)
local gradUp = Material("gui/gradient_up")

local function Text(text, font, x, y, col, ax, ay, a)
	a = a or 1
	draw.SimpleText(text, font, x + 1, y + 1, Color(0, 0, 0, 170 * a), ax, ay)
	draw.SimpleText(text, font, x, y, ColorAlpha(col, col.a * a), ax, ay)
end

local function Pulse() return 0.55 + 0.45 * math.abs(math.sin(CurTime() * 4)) end

---------------------------------------------------------------------------------------------------------------------------------------------
-- Drawing: filled shapes (surface.DrawPoly wants convex, clockwise polygons - turned round here if they aren't)
local function Poly(pts)
	local sum = 0
	for i = 1, #pts do
		local a, b = pts[i], pts[i % #pts + 1]
		sum = sum + a.x * b.y - b.x * a.y
	end
	if sum < 0 then
		local r = {}
		for i = #pts, 1, -1 do r[#r + 1] = pts[i] end
		pts = r
	end
	surface.DrawPoly(pts)
end

local function Disc(cx, cy, r, n)
	local pts = {}
	n = n or 24
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		pts[#pts + 1] = {x = cx + math.cos(a) * r, y = cy + math.sin(a) * r}
	end
	Poly(pts)
end

-- A ring, filled clockwise from the top for frac of the way round
local function Arc(cx, cy, r, thick, frac)
	if frac <= 0.002 then return end
	local top = -math.pi / 2
	local to = top + math.pi * 2 * math.Clamp(frac, 0, 1)
	local n = math.max(math.ceil(48 * frac), 1)
	for i = 0, n - 1 do
		local a1 = top + (to - top) * i / n
		local a2 = top + (to - top) * (i + 1) / n
		local c1, s1, c2, s2 = math.cos(a1), math.sin(a1), math.cos(a2), math.sin(a2)
		Poly({
			{x = cx + c1 * r, y = cy + s1 * r}, {x = cx + c2 * r, y = cy + s2 * r},
			{x = cx + c2 * (r - thick), y = cy + s2 * (r - thick)}, {x = cx + c1 * (r - thick), y = cy + s1 * (r - thick)}
		})
	end
end

-- The icons, drawn in a box of size k around (cx, cy) (shape coordinates -1..1)
local function P(cx, cy, k, list)
	local out = {}
	for i = 1, #list, 2 do out[#out + 1] = {x = cx + list[i] * k, y = cy + list[i + 1] * k} end
	return out
end

local icons = {
	heart = function(cx, cy, k)
		Disc(cx - 0.27 * k, cy - 0.18 * k, 0.32 * k)
		Disc(cx + 0.27 * k, cy - 0.18 * k, 0.32 * k)
		Poly(P(cx, cy, k, {-0.585, -0.08, 0.585, -0.08, 0, 0.62}))
	end,
	bolt = function(cx, cy, k)
		Poly(P(cx, cy, k, {0.22, -0.7, 0.36, -0.7, 0.06, -0.02, -0.34, 0.1}))
		Poly(P(cx, cy, k, {-0.34, 0.1, 0.36, -0.1, -0.2, 0.72}))
		Poly(P(cx, cy, k, {0.36, -0.1, 0.06, -0.02, -0.34, 0.1}))
	end,
	drop = function(cx, cy, k)
		Disc(cx, cy + 0.18 * k, 0.4 * k)
		Poly(P(cx, cy, k, {0, -0.68, 0.37, 0.03, -0.37, 0.03}))
	end,
	apple = function(cx, cy, k)
		Disc(cx - 0.19 * k, cy + 0.12 * k, 0.38 * k)
		Disc(cx + 0.19 * k, cy + 0.12 * k, 0.38 * k)
		Poly(P(cx, cy, k, {-0.04, -0.32, 0.06, -0.32, 0.1, -0.62, 0.0, -0.62}))  -- stem
		Poly(P(cx, cy, k, {0.08, -0.42, 0.42, -0.62, 0.3, -0.4}))               -- leaf
	end,
	virus = function(cx, cy, k)
		Disc(cx, cy, 0.34 * k)
		for i = 0, 7 do
			local a = i / 8 * math.pi * 2
			local dx, dy, px, py = math.cos(a), math.sin(a), -math.sin(a), math.cos(a)
			local w = 0.06
			Poly({
				{x = cx + (dx * 0.3 + px * w) * k, y = cy + (dy * 0.3 + py * w) * k},
				{x = cx + (dx * 0.56 + px * w) * k, y = cy + (dy * 0.56 + py * w) * k},
				{x = cx + (dx * 0.56 - px * w) * k, y = cy + (dy * 0.56 - py * w) * k},
				{x = cx + (dx * 0.3 - px * w) * k, y = cy + (dy * 0.3 - py * w) * k}
			})
			Disc(cx + dx * 0.6 * k, cy + dy * 0.6 * k, 0.11 * k, 10)
		end
	end
}

---------------------------------------------------------------------------------------------------------------------------------------------
local function InfectionStage(f)
	if f < 0.34 then return "Infected" elseif f < 0.67 then return "Fever" else return "Turning" end
end

-- Each core: frac 0-1, warn (tag text, and it pulses), hidden (not shown at all)
local cores = {
	{id = "health", icon = "heart", warnCol = Color(215, 60, 55), get = function(p)
		local v = p:Health()
		return v / math.max(p:GetMaxHealth(), 1), (p:GetNW2Bool("GFR_Bleeding") and "Bleeding") or (v <= 25 and "Critical") or nil
	end},
	{id = "stamina", icon = "bolt", warnCol = Color(230, 205, 100), get = function(p)
		return p:GetNW2Float("GFR_Stamina", 100) / 100, p:GetNW2Bool("GFR_Exhausted") and "Exhausted" or nil
	end},
	{id = "thirst", icon = "drop", warnCol = Color(80, 170, 230), get = function(p)
		local v = p:GetNW2Float("GFR_Thirst", 100)
		return v / 100, (v <= 0 and "Dehydrated") or (v < 20 and "Thirsty") or nil
	end},
	{id = "hunger", icon = "apple", warnCol = Color(220, 140, 60), get = function(p)
		local v = p:GetNW2Float("GFR_Hunger", 100)
		return v / 100, (v <= 0 and "Starving") or (v < 20 and "Hungry") or nil
	end},
	{id = "infection", icon = "virus", warnCol = Color(130, 195, 60), always = true, get = function(p)
		local f = p:GetNW2Float("GFR_Infection", 0)
		if f <= 0 then return 0, nil, true end -- (no symptoms yet: not shown)
		local status = InfectionStage(f)
		if p:GetNW2Bool("GFR_InfSuppressed") then status = status .. " (treated)" end
		return f, status
	end}
}

local state = {}
local hpGhost

-- No HUD while you're dead, down (watching your body, turning, being eaten) or a zombie (it has its own hunger bar:
-- cl_zombietame.lua)
local function NoHUD(ply)
	return !IsValid(ply) or !ply:Alive() or ply:GetNW2Bool("GFR_IsZombie") or ply:GetNW2Bool("GFR_ZombieSpectate")
		or ply:GetObserverMode() != OBS_MODE_NONE
end
GFR.NoHUD = NoHUD

hook.Add("HUDPaint", "GFR_HUD_Draw", function()
	if !cvHud:GetBool() then return end
	local ply = LocalPlayer()
	if NoHUD(ply) then return end

	local s = ScrH() / 1080 * math.Clamp(cvScale:GetFloat(), 0.5, 2)
	UpdateFonts(s)
	local ft = FrameTime()
	local r, gap = 23 * s, 12 * s
	local x, cy = 30 * s + r, ScrH() - 30 * s - r
	local tags = {}

	draw.NoTexture()
	for _, c in ipairs(cores) do
		local frac, warn, off = c.get(ply)
		frac = math.Clamp(frac or 0, 0, 1)
		local st = state[c.id] or {a = 0}
		state[c.id] = st
		st.frac = Lerp(math.min(ft * 8, 1), st.frac or frac, frac)
		st.a = Lerp(math.min(ft * 5, 1), st.a, off and 0 or 1)
		if warn then tags[#tags + 1] = {string.upper(warn), c.warnCol} end
		if st.a > 0.01 then
			local a = st.a
			local pulse = warn and Pulse() or 1
			local tint = warn and c.warnCol or colWhite
			-- The dark disc, the empty track, then the ring
			surface.SetDrawColor(10, 10, 12, 175 * a)
			Disc(x, cy, r, 32)
			surface.SetDrawColor(colTrack.r, colTrack.g, colTrack.b, colTrack.a * a)
			Arc(x, cy, r - 2 * s, 3.5 * s, 1)
			if c.id == "health" then
				-- What you just lost, fading back down to where you are
				hpGhost = hpGhost or st.frac
				if frac >= hpGhost then hpGhost = frac else hpGhost = math.max(hpGhost - ft * 0.2, frac) end
				if hpGhost > st.frac + 0.004 then
					surface.SetDrawColor(240, 200, 190, 150 * a)
					Arc(x, cy, r - 2 * s, 3.5 * s, hpGhost)
				end
			end
			surface.SetDrawColor(tint.r, tint.g, tint.b, 255 * a * pulse)
			Arc(x, cy, r - 2 * s, 3.5 * s, st.frac)
			if c.id == "health" && ply:Armor() > 0 then
				surface.SetDrawColor(colArmor.r, colArmor.g, colArmor.b, 230 * a)
				Arc(x, cy, r + 2.5 * s, 2.5 * s, math.Clamp(ply:Armor() / math.max(ply:GetMaxArmor(), 1), 0, 1))
			end
			-- The icon: dims as the stat runs low, turns the warning colour when it's a problem
			local iconA = (0.45 + 0.55 * math.Clamp(st.frac * 2, 0, 1)) * a * pulse
			surface.SetDrawColor(tint.r, tint.g, tint.b, 255 * iconA)
			icons[c.icon](x, cy, r * 0.5)
			x = x + (r * 2 + gap) * a -- (the next one slides in beside it)
		end
	end

	-- Warning tags above the row
	local tx, ty = 30 * s, cy - r - 8 * s
	surface.SetFont("GFR_HUD_Tag")
	for _, t in ipairs(tags) do
		local tw, th = surface.GetTextSize(t[1])
		local w, h = tw + 12 * s, th + 4 * s
		local c = t[2]
		draw.RoundedBox(3 * s, tx, ty - h, w, h, Color(c.r * 0.4, c.g * 0.4, c.b * 0.4, 200))
		surface.SetDrawColor(c.r, c.g, c.b, 255 * Pulse())
		surface.DrawOutlinedRect(tx, ty - h, w, h, 1)
		draw.SimpleText(t[1], "GFR_HUD_Tag", tx + w / 2, ty - h / 2, colText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		tx = tx + w + 5 * s
	end

	-- Buffs and debuffs (sh_status.lua): a row of their own, above the warnings - green ones help, orange ones hurt;
	-- the ones that wear off show the time left
	if !GFR.StatusDefs then return end
	local have = GFR.Statuses(ply)
	local _, th0 = surface.GetTextSize("A")
	local rowH = th0 + 4 * s
	local sx, sy = 30 * s, ty - (#tags > 0 and (rowH + 5 * s) or 0)
	local now = CurTime()
	for _, d in ipairs(GFR.StatusDefs) do
		local e = have[d.id]
		if e != nil then
			local label = string.upper(d.name)
			if e > 0 then
				local left = math.max(e - now, 0)
				label = label .. "  " .. (left >= 60 and string.format("%d:%02d", math.floor(left / 60), math.floor(left % 60)) or string.format("%ds", math.ceil(left)))
			end
			local c = d.buff and Color(110, 195, 95) or Color(225, 125, 60)
			local tw = surface.GetTextSize(label)
			local w = tw + 12 * s
			draw.RoundedBox(3 * s, sx, sy - rowH, w, rowH, Color(c.r * 0.3, c.g * 0.3, c.b * 0.3, 200))
			surface.SetDrawColor(c.r, c.g, c.b, 230)
			surface.DrawOutlinedRect(sx, sy - rowH, w, rowH, 1)
			draw.SimpleText(label, "GFR_HUD_Tag", sx + w / 2, sy - rowH / 2, colText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			sx = sx + w + 5 * s
		end
	end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- ARC9's own gun HUD has a health bar (a heart, the bar, an armor line) that doubles ours. ARC9 has no setting for it,
-- so while its HUD draws, just those pieces are skipped: they're drawn at fixed spots on its panel (arc9/client/cl_hud.lua,
-- ARC9.DrawHUD: bar at x 30 y 12, 24 or 18 tall; armor line at y 32, 3 tall; the "♥" / "⌂:" text). ARC9's files
-- aren't touched; with gfr_hud 0 it's left as it was.
local function SkipRect(x, y, w, h)
	if x != 30 && x != 32 then return false end
	return ((y == 12 or y == 13) && (h == 24 or h == 18)) or ((y == 32 or y == 33) && h == 3)
end
local function SkipLine(x1, y1, x2, y2)
	return x1 == x2 && (y1 == 12 or y1 == 13) && (x1 == 239 or x1 == 241 or x1 == 170 or x1 == 172)
end
local function SkipText(t)
	return isstring(t) && (string.StartWith(t, "♥") or string.StartWith(t, "⌂:"))
end

-- Where ARC9's panel sits: moved into the bottom-right corner, clear of the gun. ARC9 renders it inside a square box on
-- the screen (its cam.Start3D viewport), so sideways the whole box moves (in pixels at 1080p, kept on screen - moving
-- the panel inside the box cut it off at the box's edge); down, the panel moves within the box (ARC9 units, ~120 px each)
local cvArcX = CreateClientConVar("gfr_arc9hud_right", "210", true, false, "Move ARC9's gun HUD right in pixels (negative: left)")
local cvArcY = CreateClientConVar("gfr_arc9hud_down", "0.25", true, false, "Move ARC9's gun HUD down (negative: up)")
-- Hardcore: no ammo count anywhere - ARC9's gun HUD and ours are both gone; you count your shots (or check the mag)
local cvAmmoHud = CreateClientConVar("gfr_hud_ammo", "1", true, false, "Show ammo HUDs (0 = hardcore: ARC9's gun HUD and the ammo counter are hidden)")

-- It only comes up while you reload - the mag's out and you see what you've got - and fades out 5 s after
local cvArcFade = CreateClientConVar("gfr_arc9hud_fade", "1", true, false, "ARC9's gun HUD shows only while reloading, then fades after 5 s (0 = always shown)")
local ARC_SHOW, ARC_FADE = 5, 0.6
local arcShownAt = -100

local function ARC9HUDAlpha()
	if !cvArcFade:GetBool() then return 1 end
	local wep = LocalPlayer():GetActiveWeapon()
	local now = RealTime()
	if IsValid(wep) && wep.GetReloading && wep:GetReloading() then arcShownAt = now end
	return math.Clamp(1 - (now - arcShownAt - ARC_SHOW) / ARC_FADE, 0, 1)
end

local function PatchARC9HUD()
	local hooks = hook.GetTable().HUDPaint
	local orig = hooks && hooks.ARC9_DrawHud
	if !orig or GFR.ARC9HUDPatched == orig then return end
	local wrapped = function(...)
		if !cvAmmoHud:GetBool() or NoHUD(LocalPlayer()) then return end
		if !cvHud:GetBool() then return orig(...) end
		local alpha = ARC9HUDAlpha()
		if alpha <= 0 then return end
		local dr, dl, dt, c3, s3 = surface.DrawRect, surface.DrawLine, surface.DrawText, cam.Start3D2D, cam.Start3D
		surface.DrawRect = function(x, y, w, h) if SkipRect(x, y, w, h) then return end return dr(x, y, w, h) end
		surface.DrawLine = function(x1, y1, x2, y2) if SkipLine(x1, y1, x2, y2) then return end return dl(x1, y1, x2, y2) end
		surface.DrawText = function(t, ...) if SkipText(t) then return end return dt(t, ...) end
		local down = -EyeAngles():Up() * cvArcY:GetFloat()
		cam.Start3D2D = function(pos, ang, scale) return c3(pos + down, ang, scale) end
		local dx = cvArcX:GetFloat() * ScrH() / 1080
		cam.Start3D = function(pos, ang, fov, x, y, w, h, ...)
			if x && w then x = math.Clamp(x + dx, 0, math.max(ScrW() - w, 0)) end
			return s3(pos, ang, fov, x, y, w, h, ...)
		end
		surface.SetAlphaMultiplier(alpha)
		local ok, err = pcall(orig, ...)
		-- (always put back, even if it errored)
		surface.SetAlphaMultiplier(1)
		surface.DrawRect, surface.DrawLine, surface.DrawText, cam.Start3D2D, cam.Start3D = dr, dl, dt, c3, s3
		if !ok then ErrorNoHalt("[ARC9 HUD] " .. tostring(err) .. "\n") end
	end
	GFR.ARC9HUDPatched = wrapped
	hook.Add("HUDPaint", "ARC9_DrawHud", wrapped)
end
hook.Add("InitPostEntity", "GFR_HUD_PatchARC9", function() timer.Simple(1, PatchARC9HUD) end)
timer.Simple(2, PatchARC9HUD) -- (reloaded mid-game)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Ammo, bottom right (Half-Life 2's panel is hidden). ARC9 guns draw their own unless its HUD is switched off.
local function OwnHUD(wep)
	if !wep.ARC9 then return false end
	local cv, off = GetConVar("arc9_hud_arc9"), GetConVar("arc9_hud_force_disable")
	if off && off:GetBool() then return false end
	return !cv or cv:GetBool()
end

local function AmmoName(id)
	local name = game.GetAmmoName(id)
	if !name then return "" end
	local phrase = language.GetPhrase(name .. "_ammo")
	return string.upper(phrase != name .. "_ammo" and phrase or name)
end

hook.Add("HUDPaint", "GFR_HUD_Ammo", function()
	if !cvHud:GetBool() or !cvAmmoHud:GetBool() then return end
	local ply = LocalPlayer()
	if NoHUD(ply) or ply:InVehicle() then return end
	local wep = ply:GetActiveWeapon()
	if !IsValid(wep) or OwnHUD(wep) then return end
	if wep.DrawAmmo == false then return end
	local p1, p2 = wep:GetPrimaryAmmoType(), wep:GetSecondaryAmmoType()
	local clip = wep:Clip1()
	if p1 < 0 && clip < 0 then return end -- (melee, tools)

	local s = ScrH() / 1080 * math.Clamp(cvScale:GetFloat(), 0.5, 2)
	UpdateFonts(s)
	local rx, base = ScrW() - 32 * s, ScrH() - 30 * s

	surface.SetMaterial(gradUp)
	surface.SetDrawColor(0, 0, 0, 110)
	surface.DrawTexturedRect(ScrW() - 340 * s, ScrH() - 130 * s, 340 * s, 130 * s)

	local reserve = p1 >= 0 and ply:GetAmmoCount(p1) or 0
	local main = clip >= 0 and clip or reserve
	local maxClip = wep:GetMaxClip1()
	local low = clip >= 0 && maxClip > 0 && clip <= math.max(math.floor(maxClip * 0.25), 1)
	local mainCol = (main == 0 or low) and Color(235, 90, 70, 255 * Pulse()) or colText

	local x = rx
	if clip >= 0 && p1 >= 0 then
		Text(reserve, "GFR_HUD_AmmoSmall", x, base, colDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
		surface.SetFont("GFR_HUD_AmmoSmall")
		x = x - surface.GetTextSize(tostring(reserve)) - 4 * s
		Text("/", "GFR_HUD_AmmoSmall", x, base, colDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
		x = x - 14 * s
	end
	Text(main, "GFR_HUD_Ammo", x, base + 6 * s, mainCol, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
	if p1 >= 0 then Text(AmmoName(p1), "GFR_HUD_Label", rx, base - 44 * s, colDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM) end

	-- Secondary (grenade launcher rounds and the like)
	if p2 >= 0 then
		local n = ply:GetAmmoCount(p2)
		if n > 0 then Text(AmmoName(p2) .. "  " .. n, "GFR_HUD_Label", rx, base - 62 * s, colDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM) end
	end
end)
