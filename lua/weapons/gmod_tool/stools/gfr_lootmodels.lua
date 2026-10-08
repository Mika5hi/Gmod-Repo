--[[
	Custom Apocalypse - Lootbox Models tool: which props are which kind of searchable container
	(the list itself, saving and syncing: gamemode sh_lootmodels.lua; the types and their loot: sh_containers.lua)
	Pick a container type in the tool menu, then:
		left click   that prop's model is that type (moved / re-weighted if it's already listed)
		right click  take that prop's model off the list (and if its name would still make it a container, it's
		             listed as "Not a container" so it really stops being one)
		reload       what that prop is right now, and why
	The list starts empty: nothing is a container until you assign it (gfr_container_namematch 1: props also count by
	their model name, as before).
	Inside / Outside: how often map loot spawns that model in buildings / out in the open (0 = never; it's still
	searchable where the map or a loot point puts it). Changes are saved for every map straight away.
	Only in Green Flu: Reimagined. Admins and up (single-player: anyone).
]]
TOOL.Category = "Green Flu: Reimagined"
TOOL.Name = "#tool.gfr_lootmodels.name"
TOOL.ClientConVar["type"] = "crate"
TOOL.ClientConVar["indoor"] = "2"
TOOL.ClientConVar["outdoor"] = "2"
TOOL.ClientConVar["useskin"] = "1"
TOOL.Information = {{name = "left"}, {name = "right"}, {name = "reload"}}

if CLIENT then
	language.Add("tool.gfr_lootmodels.name", "Lootbox Models")
	language.Add("tool.gfr_lootmodels.desc", "Choose which props are searchable containers, and what kind")
	language.Add("tool.gfr_lootmodels.left", "Make this prop's model the chosen type")
	language.Add("tool.gfr_lootmodels.right", "Take this prop's model off the list")
	language.Add("tool.gfr_lootmodels.reload", "What is this prop?")
end

local function LM() return GFR && GFR.LootModels end

-- The gamemode's side of this (sh_containers.lua / sh_lootmodels.lua), new enough for this tool. An older copy of the
-- gamemode loaded instead (one left in garrysmod/gamemodes/greenflu wins over the addon's) doesn't have it.
local function GamemodeReady()
	return GFR && GFR.ContainerTypes && GFR.ContainerType && GFR.ContainerListEntry && GFR.LootModels && true or false
end
local NOT_READY = "Needs the Green Flu: Reimagined gamemode, up to date. (An old copy in garrysmod/gamemodes/greenflu would be loaded instead of this one.)"

local function Tell(ply, msg)
	if IsValid(ply) then ply:ChatPrint("[Lootbox Models] " .. msg) end
end

-- Only props can be containers (sh_containers.lua)
local props = {prop_physics = true, prop_physics_multiplayer = true, prop_physics_override = true, prop_dynamic = true, prop_dynamic_override = true}

local function Target(tr)
	local ent = tr.Entity
	if !IsValid(ent) or !props[ent:GetClass()] or ent:GetNW2Bool("GFR_Placed") then return end
	local mdl = ent:GetModel()
	if !mdl or mdl == "" or string.StartWith(mdl, "*") then return end -- (brush entities have no model file)
	return ent, string.lower(mdl)
end

-- The skin to save: none (every skin) unless "match skin" is on and the model has more than one
local function SkinOf(tool, ent)
	if tool:GetClientNumber("useskin") != 0 && ent:SkinCount() > 1 then return ent:GetSkin() end
end

local function Ready(tool)
	local ply = tool:GetOwner()
	if !GamemodeReady() then Tell(ply, NOT_READY) return false end
	if !LM().CanEdit(ply) then Tell(ply, "Admins only.") return false end
	return true
end

function TOOL:LeftClick(tr)
	local ent, mdl = Target(tr)
	if !ent then return false end
	if CLIENT then return true end
	local ply = self:GetOwner()
	if !Ready(self) then return false end
	local skin = SkinOf(self, ent)
	local e, why = LM().Set(mdl, skin, self:GetClientInfo("type"), self:GetClientNumber("indoor"), self:GetClientNumber("outdoor"))
	if !e then Tell(ply, why) return false end
	-- A prop spawned as one type keeps it; this one now follows the list
	ent:SetNW2String("GFR_CType", "")
	local where = e.type == "none" and "" or ("  (inside " .. (e.indoor or 0) .. ", outside " .. (e.outdoor or 0) .. ")")
	Tell(ply, string.GetFileFromFilename(mdl) .. (skin and (" skin " .. skin) or "") .. " is now: " .. LM().TypeName(e.type) .. where)
	return true
end

function TOOL:RightClick(tr)
	local ent, mdl = Target(tr)
	if !ent then return false end
	if CLIENT then return true end
	local ply = self:GetOwner()
	if !Ready(self) then return false end
	local skin = SkinOf(self, ent)
	local n = LM().Remove(mdl, skin)
	if n == 0 && skin then n = LM().Remove(mdl, nil) end -- (listed for every skin)
	ent:SetNW2String("GFR_CType", "")
	-- Still a container by its name (sh_containers.lua patterns): list it as "none" so it really isn't
	local still = GFR.ContainerType(ent)
	if still then
		LM().Set(mdl, skin, "none", 0, 0)
		Tell(ply, string.GetFileFromFilename(mdl) .. ": its name made it a " .. LM().TypeName(still) .. ", so it's now listed as Not a container.")
	elseif n > 0 then
		Tell(ply, string.GetFileFromFilename(mdl) .. " is off the list: not a container any more.")
	else
		Tell(ply, string.GetFileFromFilename(mdl) .. " wasn't a container.")
		return false
	end
	return true
end

function TOOL:Reload(tr)
	local ent, mdl = Target(tr)
	if !ent then return false end
	if CLIENT then return true end
	local ply = self:GetOwner()
	if !GamemodeReady() then Tell(ply, NOT_READY) return false end
	local t = GFR.ContainerType(ent)
	local e = GFR.ContainerListEntry(mdl, ent:GetSkin())
	local forced = ent:GetNW2String("GFR_CType", "")
	local why
	if forced != "" then why = "spawned as that type"
	elseif e && e.type == "none" then why = "listed as not a container"
	elseif e then why = "on the list" .. (e.skin and (" for skin " .. e.skin) or "") .. ", inside " .. (e.indoor or 0) .. " / outside " .. (e.outdoor or 0)
	elseif t then why = "by its model name (not on the list)"
	else why = "not on the list" end
	Tell(ply, mdl .. " (skin " .. ent:GetSkin() .. "): " .. (t and LM().TypeName(t) or "not a container") .. " - " .. why)
	return false
end

if SERVER then return end

---------------------------------------------------------------------------------------------------------------------------------------------
-- What's what while you hold the tool: the type over every container close by (grey = by name only, not listed)
local function Holding()
	local ply = LocalPlayer()
	local wep = IsValid(ply) && ply:GetActiveWeapon()
	return IsValid(wep) && wep:GetClass() == "gmod_tool" && wep:GetMode() == "gfr_lootmodels"
end

surface.CreateFont("GFR_LM_Label", {font = "Roboto", size = 34, weight = 800, extended = true})
local near, nextScan = {}, 0

hook.Add("PostDrawTranslucentRenderables", "GFR_LM_Labels", function(depth, sky)
	if sky or !Holding() or !GamemodeReady() then return end
	local eye = EyePos()
	if CurTime() > nextScan then
		nextScan = CurTime() + 0.5
		near = {}
		for _, ent in ipairs(ents.FindInSphere(eye, 1200)) do
			if props[ent:GetClass()] && GFR.ContainerType(ent) then near[#near + 1] = ent end
		end
	end
	for _, ent in ipairs(near) do
		if !IsValid(ent) then continue end
		local t = GFR.ContainerType(ent)
		if !t then continue end
		local listed = GFR.ContainerListEntry(ent:GetModel(), ent:GetSkin()) != nil or ent:GetNW2String("GFR_CType", "") != ""
		local top = ent:WorldSpaceCenter() + Vector(0, 0, ent:OBBMaxs().z - ent:OBBCenter().z + 8)
		local ang = (eye - top):Angle()
		cam.Start3D2D(top, Angle(0, ang.y + 90, 90), 0.12)
			draw.SimpleTextOutlined(string.upper(GFR.LootModels.TypeName(t)), "GFR_LM_Label", 0, 0, listed and Color(235, 190, 70) or Color(170, 170, 170),
				TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, Color(0, 0, 0, 220))
		cam.End3D2D()
	end
end)

---------------------------------------------------------------------------------------------------------------------------------------------
-- Menu: the type, the weights, and that type's models (remove / re-weight / add by path)
local function SortedTypes()
	local list = {}
	for id, def in pairs(GFR && GFR.ContainerTypes or {}) do list[#list + 1] = {id = id, name = def.name or id} end
	table.sort(list, function(a, b) return a.name < b.name end)
	list[#list + 1] = {id = "none", name = "Not a container"}
	return list
end

function TOOL.BuildCPanel(panel)
	panel:Help("#tool.gfr_lootmodels.desc")
	if !GamemodeReady() then
		panel:Help(NOT_READY)
		return
	end
	local LMod = GFR.LootModels

	local typeBox = vgui.Create("DComboBox", panel)
	typeBox:SetTall(24)
	local cur = GetConVarString("gfr_lootmodels_type")
	for _, t in ipairs(SortedTypes()) do typeBox:AddChoice(t.name, t.id, t.id == cur) end
	panel:AddItem(typeBox)

	panel:NumSlider("Inside (how often in buildings)", "gfr_lootmodels_indoor", 0, 20, 1)
	panel:NumSlider("Outside (how often in the open)", "gfr_lootmodels_outdoor", 0, 20, 1)
	panel:CheckBox("Only this skin (for models with several skins)", "gfr_lootmodels_useskin")
	panel:Help("0 = map loot never spawns it, but it's still searchable wherever it is. Higher = more often, compared with the other models.")

	local list = vgui.Create("DListView", panel)
	list:SetTall(260)
	list:SetMultiSelect(false)
	list:AddColumn("Model")
	list:AddColumn("Skin"):SetFixedWidth(36)
	list:AddColumn("In"):SetFixedWidth(30)
	list:AddColumn("Out"):SetFixedWidth(30)
	panel:AddItem(list)

	local function Fill()
		if !IsValid(list) then return end
		list:Clear()
		local ctype = GetConVarString("gfr_lootmodels_type")
		for _, e in ipairs(GFR.ContainerModels or {}) do
			if e.type == ctype then
				local line = list:AddLine(string.GetFileFromFilename(e[1]), e.skin or "any", e.indoor or 0, e.outdoor or 0)
				line.Entry = e
				line:SetTooltip(e[1])
			end
		end
		if #list:GetLines() == 0 then list:AddLine("(no models yet: left click a prop to add one)", "", "", "") end
	end

	typeBox.OnSelect = function(_, _, _, id)
		RunConsoleCommand("gfr_lootmodels_type", id)
		timer.Simple(0.1, Fill)
	end

	local function Selected()
		local _, line = list:GetSelectedLine()
		return line && line.Entry
	end

	list.OnRowRightClick = function(_, _, line)
		local e = line.Entry
		if !e then return end
		local menu = DermaMenu()
		menu:AddOption("Use the slider weights", function()
			LMod.Request("set", e[1], e.skin, e.type, GetConVarNumber("gfr_lootmodels_indoor"), GetConVarNumber("gfr_lootmodels_outdoor"))
		end):SetIcon("icon16/arrow_refresh.png")
		menu:AddOption("Remove from the list", function() LMod.Request("remove", e[1], e.skin) end):SetIcon("icon16/delete.png")
		menu:AddOption("Copy model path", function() SetClipboardText(e[1]) end):SetIcon("icon16/page_copy.png")
		menu:Open()
	end

	local remove = panel:Button("Remove selected model")
	remove.DoClick = function()
		local e = Selected()
		if e then LMod.Request("remove", e[1], e.skin) end
	end

	-- A model that isn't on this map: type its path
	panel:Help("Add a model by its path (for models not on this map):")
	local entry = vgui.Create("DTextEntry", panel)
	entry:SetPlaceholderText("models/props_junk/wood_crate001a.mdl")
	panel:AddItem(entry)
	local add = panel:Button("Add to the chosen type")
	add.DoClick = function()
		local mdl = string.Trim(entry:GetValue())
		if mdl == "" then return end
		LMod.Request("set", mdl, nil, GetConVarString("gfr_lootmodels_type"), GetConVarNumber("gfr_lootmodels_indoor"), GetConVarNumber("gfr_lootmodels_outdoor"))
		entry:SetValue("")
	end

	panel:CheckBox("Props not on the list count by their model name (crate, fridge, locker...)", "gfr_container_namematch")
	panel:Help("Off: only the models you assign are containers.")

	local clear = panel:Button("Clear all (no containers)")
	clear.DoClick = function()
		Derma_Query("Take every model off the list? Nothing will be a container until you assign models again.", "Clear all",
			"Clear", function() LMod.Request("clear") end, "Cancel")
	end
	local builtin = panel:Button("Load the old built-in list")
	builtin.DoClick = function()
		Derma_Query("Replace the list with the gamemode's old built-in one (about 70 models), as a starting point?", "Load the old built-in list",
			"Load", function() LMod.Request("builtin") end, "Cancel")
	end
	panel:Help("Changes are saved for every map (data/greenflu/containers.json). Gold labels: on the list. Grey: a container only because of its model name - click it to put it on the list.")

	Fill()
	hook.Add("GFR_LootModelsChanged", list, Fill)
end
