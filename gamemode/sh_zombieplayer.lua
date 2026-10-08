--[[
	Custom Apocalypse - "[J] Give in" prompt while a zombie has you in its grip (sv_extract.lua: GFR.GiveIn)
	Your zombie itself is a VJ-controlled NPC (sv_extract.lua), so there's nothing else to do client-side.
]]
AddCSLuaFile()

if SERVER then return end

local function S(x) return math.Round(x * ScrH() / 1080) end

-- Third-person camera for the zombie you control (any kind: infected, hunter): over the shoulder of the body,
-- at head height measured from its actual head (tall playermodels, a hunter's crouch, feeding all follow).
-- Used by the VJ controller through the NPC's Controller_OnCalcView (npc_gfr_infected shared.lua; hunters below).
-- The playermodel the zombie wears: on the NPC itself, or (grabbing / feeding / crawling) on the animation rig under it
local function WornBody(npc)
	for _, c in ipairs(npc:GetChildren()) do
		if IsValid(c) && c:GetModel() then
			if c:IsEffectActive(EF_BONEMERGE) && c:LookupBone("ValveBiped.Bip01_Head1") && !c:GetNW2Bool("GFR_HideBase") then return c end
			for _, cc in ipairs(c:GetChildren()) do
				if IsValid(cc) && cc:GetModel() && cc:IsEffectActive(EF_BONEMERGE) && cc:LookupBone("ValveBiped.Bip01_Head1") then return cc end
			end
		end
	end
	return npc
end

local CAM_HULL_MIN, CAM_HULL_MAX = Vector(-5, -5, -5), Vector(5, 5, 5)

-- (sent to the server: 0 over the shoulder, 1 full body, 2 through its eyes)
CreateClientConVar("gfr_zcam_mode", "0", false, true, "Zombie camera in use (set by the game)")

-- Looking through its eyes, the body you wear is drawn with its head cut away (GFR.ZFPBody, set below); this puts
-- it back to normal
function GFR.ZFPShow(ent)
	if !IsValid(ent) then return end
	ent.RenderOverride = ent.GFR_FPOrigRO
	ent.GFR_FPOrigRO = nil
end

-- want: the body to see out of (nil: none). Cuts away whatever's around the eyes (the head, hair, face) with a plane
-- just in front of the camera: look down and your chest, arms and legs are there; the inside of your own face never is
function GFR.ZFPSet(want, eye, fwd)
	if GFR.ZFPBody != want then
		GFR.ZFPShow(GFR.ZFPBody)
		GFR.ZFPBody = want
		if IsValid(want) then
			want.GFR_FPOrigRO = want.RenderOverride
			want.RenderOverride = function(self, flags)
				local e, f = GFR.ZFPEye, GFR.ZFPFwd
				if !e then return end
				local was = render.EnableClipping(true)
				render.PushCustomClipPlane(f, f:Dot(e + f * 7))
				self:DrawModel(flags)
				render.PopCustomClipPlane()
				render.EnableClipping(was)
			end
		end
	end
	if want then GFR.ZFPEye, GFR.ZFPFwd = eye, fwd end
end

function GFR.ZombieCalcView(npc, cont, ply, origin, angles, fov)
	if !npc:GetNW2Bool("GFR_PlayerZombie") && npc != GFR.ZWatching then return false end
	local pos = npc:GetPos()
	local headZ = pos.z + 64
	local body = WornBody(npc)
	local head = body:LookupBone("ValveBiped.Bip01_Head1")
	local hp = head && body:GetBonePosition(head)
	local filter = {npc, ply, body}
	local camPos
	local firstPerson = false
	-- (the zoom glides to where you scrolled it, so going into the head is a smooth push in)
	GFR.ZCamZoomS = Lerp(math.min(FrameTime() * 8, 1), GFR.ZCamZoomS or GFR.ZCamZoom or 100, GFR.ZCamZoom or 100)
	GFR.ZFPLast = CurTime()

	-- Seated / lying (crouch, sv_extract.lua) or feeding: a close camera on the body itself - centred between its hips
	-- and head - so you see it sit, lie or eat, instead of standing head height over its feet
	local sitting, eating = npc:GetNW2Bool("GFR_ZSitting"), npc:GetNW2Bool("GFR_ZEating")
	local close = sitting or eating
	if close && (GFR.ZCamZoomS or 100) < 14 then
		-- Scrolled all the way in while eating / sitting: through its eyes, the way the face is pointing (hunched over a
		-- meal that's down at the body), looking around freely
		local att = body:LookupAttachment("eyes")
		local ap = att && att > 0 && body:GetAttachment(att)
		local eye = ap and (ap.Pos + ap.Ang:Forward() * 5) or (hp and hp + Vector(0, 0, 3)) or (pos + Vector(0, 0, 40))
		npc.GFR_CamWasClose = true
		npc.GFR_CamOrigin = eye
		GFR.ZFPSet(body != npc && body or nil, eye, angles:Forward())
		return {origin = eye, angles = angles, fov = fov, speed = 14, znear = 1}
	end
	if close then
		-- (the close cameras look at the body: it's drawn, even if you'd been looking through its eyes)
		GFR.ZFPShow(GFR.ZFPBody)
		GFR.ZFPBody = nil
		local focus
		if eating then
			-- A low orbit around the body hunched over its meal: aimed at its middle (between hips and head), the mouse
			-- turning around it, the height kept low (looking down from above, you only saw the top of its head)
			local pelvis = body:LookupBone("ValveBiped.Bip01_Pelvis")
			local pp = pelvis && body:GetBonePosition(pelvis)
			local mid = (hp && pp) and LerpVector(0.4, pp, hp) or (pos + Vector(0, 0, 24))
			npc.GFR_CamFocus = npc.GFR_CamFocus and LerpVector(math.min(FrameTime() * 5, 1), npc.GFR_CamFocus, mid) or mid
			npc.GFR_CamZ = npc.GFR_CamFocus.z
			local pitch = math.Clamp(angles.p, 2, 28) -- (mouse up/down still tilts it, within limits)
			local dir = Angle(pitch, angles.y, 0):Forward()
			local dist = math.Clamp((GFR.ZCamZoom or 100) * 0.6, 22, 110)
			camPos = util.TraceHull({
				start = npc.GFR_CamFocus, endpos = npc.GFR_CamFocus - dir * dist,
				filter = filter, mins = CAM_HULL_MIN, maxs = CAM_HULL_MAX, mask = MASK_SOLID_BRUSHONLY
			}).HitPos
			npc.GFR_CamWasClose = true
			npc.GFR_CamOrigin = camPos
			return {origin = camPos, angles = (npc.GFR_CamFocus - camPos):Angle(), fov = fov, speed = 14}
		end
		-- Seated / lying
		local pelvis = body:LookupBone("ValveBiped.Bip01_Pelvis")
		local pp = pelvis && body:GetBonePosition(pelvis)
		focus = (hp && pp) and LerpVector(0.6, pp, hp) or (pos + Vector(0, 0, 30))
		npc.GFR_CamFocus = npc.GFR_CamFocus and LerpVector(math.min(FrameTime() * 6, 1), npc.GFR_CamFocus, focus) or focus
		npc.GFR_CamZ = npc.GFR_CamFocus.z -- (standing up again eases back from here)
		local dist = math.Clamp((GFR.ZCamZoom or 100) * 0.7, 22, 160)
		camPos = util.TraceHull({
			start = npc.GFR_CamFocus,
			endpos = npc.GFR_CamFocus - angles:Forward() * dist + angles:Up() * 8,
			filter = filter, mins = CAM_HULL_MIN, maxs = CAM_HULL_MAX, mask = MASK_SOLID_BRUSHONLY
		}).HitPos
	elseif GFR.ZFullBodyCam && (GFR.ZCamZoomS or 100) > 25 then
		-- Full body (Alt): pulled back and centred on the body's middle, so you see all of it head to feet
		npc.GFR_CamFocus = nil
		local pelvis = body:LookupBone("ValveBiped.Bip01_Pelvis")
		local pp = pelvis && body:GetBonePosition(pelvis)
		local mid = (hp && pp && hp.z > pos.z + 20) and LerpVector(0.35, pp, hp) or (pos + Vector(0, 0, 40))
		npc.GFR_CamZ = npc.GFR_CamZ and Lerp(math.min(FrameTime() * 6, 1), npc.GFR_CamZ, mid.z) or mid.z
		local focus = Vector(pos.x, pos.y, npc.GFR_CamZ)
		local dist = math.Clamp((GFR.ZCamZoom or 100) * 0.75, 25, 200)
		camPos = util.TraceHull({
			start = focus, endpos = focus - angles:Forward() * dist,
			filter = filter, mins = CAM_HULL_MIN, maxs = CAM_HULL_MAX, mask = MASK_SOLID_BRUSHONLY
		}).HitPos
	else
		npc.GFR_CamFocus = nil
		if hp && hp.z > pos.z + 20 then headZ = hp.z end
		local target = math.max(headZ + 4, pos.z + 50)
		npc.GFR_CamZ = npc.GFR_CamZ and Lerp(math.min(FrameTime() * 6, 1), npc.GFR_CamZ, target) or target
		local headPos = Vector(pos.x, pos.y, npc.GFR_CamZ)
		-- Over the right shoulder (scroll zooms). Scrolled all the way in it slides off the shoulder, up to the head and
		-- into it: at 0 you see through its eyes (the body isn't drawn then, below)
		local zoom = GFR.ZCamZoomS or 100
		local t = math.Clamp(zoom / 40, 0, 1) -- (1 = over the shoulder, 0 = its eyes)
		-- Its eyes: the model's own "eyes" point (or a bit above the head bone), pushed a little out in front of its
		-- face along the way the body faces - not along where you look, which (looking down) sank the camera into
		-- its neck and you saw the inside of the body
		local eye = headPos
		local att = body:LookupAttachment("eyes")
		local ap = att && att > 0 && body:GetAttachment(att)
		if ap then eye = ap.Pos elseif hp then eye = hp + Vector(0, 0, 3) end
		eye = eye + Angle(0, npc:GetAngles().y, 0):Forward() * 6
		local base = LerpVector(t, eye, headPos)
		local dist = math.Clamp(zoom * 0.45, 0, 150)
		local shoulder = t > 0 and util.TraceHull({
			start = base, endpos = base + angles:Right() * 20 * t,
			filter = filter, mins = CAM_HULL_MIN, maxs = CAM_HULL_MAX, mask = MASK_SOLID_BRUSHONLY
		}).HitPos or base
		camPos = dist > 0.5 and util.TraceHull({
			start = shoulder,
			endpos = shoulder - angles:Forward() * dist + angles:Up() * 4 * t,
			filter = filter, mins = CAM_HULL_MIN, maxs = CAM_HULL_MAX, mask = MASK_SOLID_BRUSHONLY
		}).HitPos or shoulder
		firstPerson = zoom < 14
	end
	-- Inside the head: the body you're wearing is drawn with the head cut away (you'd see the inside of its face)
	GFR.ZFPSet(firstPerson && body != npc && body or nil, camPos, angles:Forward())
	-- Which camera you're on, for the server: only over the shoulder does the body turn on the spot to face where you
	-- look (npc_gfr_infected PlayerTurn) - looking at it head to feet, or out of its eyes, it stays put
	local camMode = firstPerson and 2 or ((GFR.ZFullBodyCam && !close && (GFR.ZCamZoomS or 100) > 25) and 1 or 0)
	if camMode != GFR.ZCamModeSent then
		GFR.ZCamModeSent = camMode
		RunConsoleCommand("gfr_zcam_mode", tostring(camMode))
	end

	-- Getting up (from a seat, lying down or a meal): the camera drifts back out to the shoulder over a second or two
	-- instead of jumping. Going into the close camera stays quick.
	if npc.GFR_CamWasClose && !close then npc.GFR_CamBlendT, npc.GFR_CamBlendRate = CurTime() + 2, 2.5 end
	-- (switching between shoulder and full body glides too)
	if npc.GFR_CamWasFull != GFR.ZFullBodyCam then
		if npc.GFR_CamWasFull != nil then npc.GFR_CamBlendT, npc.GFR_CamBlendRate = CurTime() + 1.5, 4 end
		npc.GFR_CamWasFull = GFR.ZFullBodyCam
	end
	npc.GFR_CamWasClose = close
	-- Getting back up after being down (or rising for the first time): the first frames of this zombie's camera start
	-- from where the camera on your body was, and drift over slowly while it drags itself up
	if !npc.GFR_CamOrigin && GFR.LastSpectateCam && CurTime() - GFR.LastSpectateCam.t < 1.5 then
		npc.GFR_CamOrigin = GFR.LastSpectateCam.origin
		npc.GFR_CamBlendT, npc.GFR_CamBlendRate = CurTime() + 4, 1.1
		GFR.LastSpectateCam = nil
	end
	if npc.GFR_CamOrigin && (npc.GFR_CamBlendT or 0) > CurTime() then
		camPos = LerpVector(math.min(FrameTime() * (npc.GFR_CamBlendRate or 2.5), 1), npc.GFR_CamOrigin, camPos)
	end
	npc.GFR_CamOrigin = camPos
	return {origin = camPos, angles = angles, fov = fov, speed = 14}
end

-- Alt toggles the zombie camera between over the shoulder and full body
GFR.ZFullBodyCam = GFR.ZFullBodyCam or false

-- The scroll wheel zooms the zombie cameras (our own: VJ's controller zoom didn't always take the wheel)
GFR.ZCamZoom = GFR.ZCamZoom or 100
-- (our zombie camera is running right now: it drew a frame in the last moment)
local function DrivingCam() return CurTime() - (GFR.ZFPLast or 0) < 0.3 end
GFR.ZombieCamActive = DrivingCam

hook.Add("PlayerBindPress", "GFR_ZombieCam_Zoom", function(ply, bind, pressed)
	if !pressed then return end
	-- (watching your body while down has its own zoom; a leftover "watching" flag mustn't take the wheel off you)
	if !DrivingCam() && (!ply:GetNW2Bool("GFR_IsZombie") or ply:GetNW2Bool("GFR_ZombieSpectate")) then return end
	if string.find(bind, "invprev", 1, true) then GFR.ZCamZoom = math.max(GFR.ZCamZoom - (GFR.ZCamZoom <= 60 and 8 or 15), 0) return true end
	if string.find(bind, "invnext", 1, true) then GFR.ZCamZoom = math.min(GFR.ZCamZoom + 15, 280) return true end
end)
-- Out of the zombie's eyes some other way (sitting, eating, downed, back to human): its body is drawn again
hook.Add("Think", "GFR_ZombieCam_FPRestore", function()
	local b = GFR.ZFPBody
	if b != nil && (!IsValid(b) or CurTime() - (GFR.ZFPLast or 0) > 0.2) then
		GFR.ZFPShow(b)
		GFR.ZFPBody = nil
	end
end)

local altWasDown = false
hook.Add("Think", "GFR_ZombieCam_Toggle", function()
	local down = input.IsKeyDown(KEY_LALT)
	local ply = LocalPlayer()
	if down && !altWasDown && IsValid(ply) && (DrivingCam() or ply:GetNW2Bool("GFR_IsZombie")) && !ply:IsTyping() && !gui.IsGameUIVisible() && !gui.IsConsoleVisible() then
		GFR.ZFullBodyCam = !GFR.ZFullBodyCam
	end
	altWasDown = down
end)

-- Watching your own body (down but not out, turning, giving in, an AI hunter you became): a close camera on the
-- body itself instead of GMod's far-off spectator one. Mouse looks around it, the wheel zooms.
local specZoom = 80
hook.Add("PlayerBindPress", "GFR_ZombieSpectate_Zoom", function(ply, bind, pressed)
	if !pressed or !ply:GetNW2Bool("GFR_ZombieSpectate") or ply:GetObserverMode() == OBS_MODE_NONE then return end
	if DrivingCam() then return end -- (you're driving your zombie: the wheel is its camera's)
	if string.find(bind, "invprev", 1, true) then specZoom = math.max(specZoom - 12, 20) return true end
	if string.find(bind, "invnext", 1, true) then specZoom = math.min(specZoom + 12, 220) return true end
end)

hook.Add("CalcView", "GFR_ZombieSpectate_Cam", function(ply, origin, angles, fov)
	if !ply:GetNW2Bool("GFR_ZombieSpectate") or ply:GetObserverMode() == OBS_MODE_NONE then return end
	local t = ply:GetObserverTarget()
	if !IsValid(t) then return end
	-- The body: a ragdoll's chest (its own bones even when it's hidden under a worn playermodel), or an NPC's middle
	local focus
	local spine = t:LookupBone("ValveBiped.Bip01_Spine2")
	if spine then focus = t:GetBonePosition(spine) end
	if !focus or focus:IsZero() then focus = t:WorldSpaceCenter() end
	local dist = t:IsNPC() and specZoom * 1.4 or specZoom
	local tr = util.TraceHull({
		start = focus, endpos = focus - angles:Forward() * dist + angles:Up() * 10,
		filter = {t, ply}, mins = Vector(-5, -5, -5), maxs = Vector(5, 5, 5), mask = MASK_SOLID_BRUSHONLY
	})
	-- (remembered: when you get back up, your zombie's camera eases over from here instead of jumping)
	GFR.LastSpectateCam = {origin = tr.HitPos, t = CurTime()}
	return {origin = tr.HitPos, angles = angles, fov = fov, drawviewer = false}
end)

-- Your zombie taken away by staff (sv_extract.lua HandleRelease: GFR_ZWatch): you're dead, watching it through the
-- same camera you drove it with (Alt, the wheel, sliding into its eyes all still work) - no control, no hunger -
-- until you click to respawn
local function Watched(ply)
	local z = IsValid(ply) && ply:GetNW2Entity("GFR_ZWatch")
	if IsValid(z) && !ply:Alive() && z:Health() > 0 then return z end
end

hook.Add("CalcView", "GFR_ZombieWatch_Cam", function(ply, origin, angles, fov)
	local z = Watched(ply)
	GFR.ZWatching = z or nil
	if !z then return end
	local view = GFR.ZombieCalcView(z, nil, ply, origin, angles, fov)
	if istable(view) then view.drawviewer = false return view end
end)


-- Hunters (L4D2 pack) have their own camera (50 units under the body): put ours on the one you're driving
timer.Create("GFR_ZombieCam_Hunters", 0.5, 0, function()
	for _, e in ipairs(ents.FindByClass("npc_vj_l4d*")) do
		if e:GetNW2Bool("GFR_PlayerZombie") && e.Controller_OnCalcView != GFR.ZombieCalcView then
			e.Controller_OnCalcView = GFR.ZombieCalcView
		end
	end
end)

-- Skeletons under a worn playermodel (infected, hunters, people, the puppet rig: GFR_HideBase) aren't drawn at all.
-- The invisible material they get server side still glows faintly in some light, a ghost around the body.
-- (The worn body still follows its bones: a bonemerge sets up its parent's skeleton itself.)
local function NoDraw() end
-- The animation rig (grab / eat / crawl, npc_gfr_infected) has to be drawn for its animation to be worked out (the
-- body worn on it copies its bones): drawn, at zero opacity
local function DrawInvisible(self)
	render.SetBlend(0)
	self:DrawModel()
	render.SetBlend(1)
end
timer.Create("GFR_HiddenBases", 0.25, 0, function()
	for _, e in ipairs(ents.GetAll()) do
		local hide = e:GetNW2Bool("GFR_HideBase")
		if hide && e.RenderOverride != NoDraw then
			e.GFR_OldRenderOverride = e.RenderOverride
			e.RenderOverride = NoDraw
		elseif !hide && e.RenderOverride == NoDraw then
			e.RenderOverride = e.GFR_OldRenderOverride
		end
		if !hide && e:GetNW2Bool("GFR_DrawHidden") && e.RenderOverride != DrawInvisible then
			e.RenderOverride = DrawInvisible
		end
	end
end)

surface.CreateFont("GFR_ZHud", {font = "Roboto", size = S(17), weight = 700, extended = true})

-- Seeing through dead eyes: GMod of the Dead's veined "infected vision" overlay while you're a zombie
local veins = Material("vj_gotdr/overlay/infected_vision")
hook.Add("RenderScreenspaceEffects", "GFR_ZombiePlayer_Veins", function()
	local ply = LocalPlayer()
	-- Your own zombie, watching the body you turned into walk off on its own (sv_infection.lua), or your zombie taken
	-- away from you (above)
	if !IsValid(ply) or !(ply:GetNW2Bool("GFR_IsZombie") or ply:GetNW2Bool("GFR_ZombieSpectate") or Watched(ply)) or veins:IsError() then return end
	DrawMaterialOverlay("vj_gotdr/overlay/infected_vision", 0.3)
	-- Feral (your zombie's hunger under 15, sv_zombiehunger.lua): the veins throb - the view darkens and the veins
	-- thicken, then ease back, over and over
	local hunger = ply:GetNW2Float("GFR_ZHunger", -1)
	if ply:GetNW2Bool("GFR_IsZombie") && hunger >= 0 && hunger < 15 then
		local p = (math.sin(CurTime() * 2.6) + 1) / 2
		p = p * p -- (a sharper beat: dark quickly, back slowly)
		DrawColorModify({
			["$pp_colour_addr"] = 0.02 * p, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
			["$pp_colour_brightness"] = -0.18 * p, ["$pp_colour_contrast"] = 1 + 0.2 * p,
			["$pp_colour_colour"] = 1 - 0.35 * p,
			["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0
		})
		if p > 0.35 then DrawMaterialOverlay("vj_gotdr/overlay/infected_vision", 0.3 + 0.3 * p) end
	end
end)

-- The vial spreading (sv_hunter.lua, 10 s after injecting yourself): the veins creep in and throb with a heartbeat
-- that speeds up, and the world sinks into darkness until you drop
local VIAL_TIME = 10
local nextBeat = 0
hook.Add("RenderScreenspaceEffects", "GFR_HunterVial", function()
	local ply = LocalPlayer()
	if !IsValid(ply) then return end
	local t0 = ply:GetNW2Float("GFR_VialT", 0)
	-- (never left dark: past the 10 s it stops by itself even if the server never cleared it)
	if t0 <= 0 or !ply:Alive() or CurTime() - t0 > VIAL_TIME + 2 then return end
	local t = math.Clamp((CurTime() - t0) / VIAL_TIME, 0, 1)
	-- Heartbeat: a sharp beat that comes faster (about 1 a second to 3)
	local rate = Lerp(t, 1.1, 3)
	local phase = (CurTime() * rate) % 1
	local beat = math.max(1 - phase * 4, 0) ^ 2
	if CurTime() > nextBeat then
		nextBeat = CurTime() + 1 / rate
		surface.PlaySound("player/heartbeat1.wav")
	end
	DrawColorModify({
		["$pp_colour_addr"] = 0.03 * beat, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
		["$pp_colour_brightness"] = -0.55 * t - 0.08 * beat, ["$pp_colour_contrast"] = 1 + 0.25 * t,
		["$pp_colour_colour"] = 1 - 0.7 * t,
		["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0
	})
	if !veins:IsError() then
		-- (more and more of it as it spreads, swelling on each beat)
		DrawMaterialOverlay("vj_gotdr/overlay/infected_vision", 0.1 + 0.35 * t + 0.25 * beat * t)
		if t > 0.4 then DrawMaterialOverlay("vj_gotdr/overlay/infected_vision", (t - 0.4) * 0.6 + 0.2 * beat) end
	end
	-- Swimming at the edges near the end
	if t > 0.6 then DrawMotionBlur(0.15, (t - 0.6) * 1.5, 0.01) end
end)

-- Dead eyes (F as a zombie, sv_extract.lua): the dark pulled up into a washed-out, sickly view - shapes, not detail -
-- and the living glowing faintly warm in it
local function NightVis()
	local ply = LocalPlayer()
	return IsValid(ply) && ply:GetNW2Bool("GFR_ZNightVis") && (ply:GetNW2Bool("GFR_IsZombie") or ply:GetNW2Bool("GFR_ZombieSpectate") or Watched(ply) != nil)
end

hook.Add("RenderScene", "GFR_ZombieNightVis_Light", function(origin)
	if !NightVis() then return end
	-- A dim light where you're looking from, so there's something in the dark to brighten
	local l = DynamicLight(LocalPlayer():EntIndex() + 7000)
	if l then
		l.pos = origin
		l.r, l.g, l.b = 170, 60, 50
		l.brightness = 0.6
		l.decay = 2000
		l.size = 900
		l.dietime = CurTime() + 0.2
	end
end)

hook.Add("RenderScreenspaceEffects", "GFR_ZombieNightVis", function()
	if !NightVis() then return end
	DrawColorModify({
		-- (all colour drained, then everything seen through blood red)
		["$pp_colour_addr"] = 0.09, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
		["$pp_colour_brightness"] = -0.02, ["$pp_colour_contrast"] = 1.9,
		["$pp_colour_colour"] = 0,
		["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0
	})
	-- Multiply the grey picture by blood red
	cam.Start2D()
	render.OverrideBlend(true, BLEND_DST_COLOR, BLEND_ZERO, BLENDFUNC_ADD)
	surface.SetDrawColor(255, 45, 35, 255)
	surface.DrawRect(0, 0, ScrW(), ScrH())
	render.OverrideBlend(false)
	cam.End2D()
	DrawToyTown(2, ScrH() * 0.35) -- (blurred towards the edges)
end)

local warm = Color(255, 235, 190) -- (pale and hot against the red: prey stands out)
hook.Add("PreDrawHalos", "GFR_ZombieNightVis_Living", function()
	if !NightVis() then return end
	local me, eye, list = LocalPlayer(), EyePos(), {}
	for _, e in ipairs(ents.FindInSphere(eye, 2500)) do
		-- (an NPC's health isn't sent to clients; a dead one is gone anyway, its ragdoll is another entity)
		local living = (e:IsNPC() && e:GetNW2String("GFR_Faction", "") != "") or (e:IsPlayer() && e != me && e:Alive() && !e:GetNW2Bool("GFR_IsZombie"))
		if living && !e:GetNoDraw() then list[#list + 1] = e end
	end
	if #list > 0 then halo.Add(list, warm, 2, 2, 1, true, false) end
end)

-- Bodies of the turning keep their clothes colour (sv_infection.lua: GFR.DropTurningBody)
local defaultColor = Vector(62 / 255, 88 / 255, 106 / 255)
hook.Add("NetworkEntityCreated", "GFR_TurningBodyColor", function(ent)
	if ent:GetClass() != "prop_ragdoll" or ent.GetPlayerColor then return end
	ent.GetPlayerColor = function(self) return self:GetNW2Vector("GFR_PlyColor", defaultColor) end
end)

-- Pinned by a hunter (sv_hunter.lua)
hook.Add("HUDPaint", "GFR_Hunter_PinPrompt", function()
	local ply = LocalPlayer()
	if !IsValid(ply) or !ply:Alive() or !ply:GetNW2Bool("GFR_Pinned") then return end
	local fast = 0.5 + 0.5 * math.sin(CurTime() * 14)
	draw.SimpleTextOutlined("A HUNTER HAS YOU PINNED", "GFR_ZHud", ScrW() / 2, ScrH() * 0.72 - S(30), Color(220, 80, 70), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 220))
	draw.SimpleTextOutlined("MASH [E] TO KICK IT OFF", "GFR_ZHud", ScrW() / 2, ScrH() * 0.72, Color(240, 220 + 35 * fast, 120 + 80 * fast), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 220))
end)

hook.Add("HUDPaint", "GFR_ZombiePlayer_GiveInPrompt", function()
	local ply = LocalPlayer()
	if !IsValid(ply) or !ply:Alive() or !ply:GetNW2Bool("GFR_Grabbed") then return end
	local pulse = 0.5 + 0.5 * math.sin(CurTime() * 4)
	local fast = 0.5 + 0.5 * math.sin(CurTime() * 14)
	draw.SimpleTextOutlined("MASH [E] TO BREAK FREE", "GFR_ZHud", ScrW() / 2, ScrH() * 0.72 - S(30), Color(240, 220 + 35 * fast, 120 + 80 * fast), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 220))
	-- (J still gives in - a secret now, not shown)
end)
