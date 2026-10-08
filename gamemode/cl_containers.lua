--[[
	Custom Apocalypse - container search prompt and progress bar
	Server side: sv_containers.lua
]]
local search -- {ent, start, duration}

net.Receive("GFR_Search", function()
	local ent = net.ReadEntity()
	local duration = net.ReadFloat()
	if IsValid(ent) && duration > 0 then
		search = {ent = ent, start = CurTime(), duration = duration}
	else
		search = nil
	end
end)

-- Debugging what's in front of you: "gfr_whatsthere" prints every entity (clientside ones too) near your line of sight
concommand.Add("gfr_whatsthere", function()
	local ply = LocalPlayer()
	local eye, aim = ply:EyePos(), ply:GetAimVector()
	print("[GFR] Near your crosshair (closest first):")
	local list = {}
	for _, e in ipairs(ents.GetAll()) do
		if IsValid(e) && e != ply && e != ply:GetViewModel() then
			local d = e:WorldSpaceCenter() - eye
			local along = d:Dot(aim)
			if along > 0 && along < 600 && (d - aim * along):Length() < 60 then list[#list + 1] = {e = e, d = along} end
		end
	end
	table.SortByMember(list, "d", true)
	for _, it in ipairs(list) do
		local e = it.e
		print(string.format("  %4.0f  %s  %s  parent=%s  nodraw=%s", it.d, e:GetClass(), e:GetModel() or "-", tostring(e:GetParent()), tostring(e:GetNoDraw())))
	end
end)

-- Searching right now? (cl_arc9hud.lua hides the weapon panel meanwhile)
function GFR.IsSearching()
	return search != nil && IsValid(search.ent)
end

local function S(x) return math.Round(x * ScrH() / 1080) end

local function Fonts()
	surface.CreateFont("GFR_Search_Title", {font = "Roboto", size = S(20), weight = 700, extended = true})
	surface.CreateFont("GFR_Search_Hint", {font = "Roboto", size = S(17), weight = 600, extended = true})
end
Fonts()

hook.Add("OnScreenSizeChanged", "GFR_Search_Fonts", Fonts)

hook.Add("HUDPaint", "GFR_Search_Draw", function()
	local ply = LocalPlayer()
	if !IsValid(ply) or !ply:Alive() then return end
	local cx, cy = ScrW() / 2, ScrH() / 2

	-- Progress bar while searching
	if search then
		if !IsValid(search.ent) then search = nil return end
		local def = GFR.ContainerTypes[GFR.ContainerType(search.ent) or ""]
		local frac = math.Clamp((CurTime() - search.start) / search.duration, 0, 1)
		local w, h = S(260), S(8)
		local y = cy + S(60)
		draw.SimpleTextOutlined("Searching " .. (def and def.name or "") .. "...", "GFR_Search_Title", cx, y - S(14), Color(230, 230, 230), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, 180))
		draw.RoundedBox(h / 2, cx - w / 2, y, w, h, Color(0, 0, 0, 160))
		draw.RoundedBox(h / 2, cx - w / 2, y, math.max(w * frac, h), h, Color(215, 175, 90))
		return
	end

	-- "[Q] Search" prompt when looking at a container (not as a zombie)
	if ply:GetNW2Bool("GFR_IsZombie") then return end
	local tr = ply:GetEyeTrace()
	local ent = tr.Entity
	if !IsValid(ent) or tr.HitPos:DistToSqr(ply:EyePos()) > 110 * 110 then return end
	local typeId = GFR.ContainerType(ent)
	if !typeId then return end
	local def = GFR.ContainerTypes[typeId]
	local searched = ent:GetNW2Bool("GFR_Searched")
	local text = searched and (def.name .. " (searched)") or ("[Q] Search " .. def.name)
	draw.SimpleTextOutlined(text, "GFR_Search_Hint", cx, cy + S(40), searched and Color(150, 150, 150) or Color(235, 225, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 180))
end)

-- Outline the container while you search it
hook.Add("PreDrawHalos", "GFR_Search_Halo", function()
	local ply = LocalPlayer()
	if !IsValid(ply) or !search or !IsValid(search.ent) then return end
	halo.Add({search.ent}, Color(215, 175, 90), 1, 1, 1, true, false)
end)
