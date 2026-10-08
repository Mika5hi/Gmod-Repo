--[[
	Custom Apocalypse - Spawn Points tool (lua/autorun/gfr_spawnpoints.lua does the saving and the markers)
	Pick what spawns there in the tool menu, then:
		left click   place a point where you look
		right click  remove the nearest point (any type)
		reload       remove every point of the chosen type on this map
	Loot points can ask for one container type (Weapon Crate, Medical...) and even one model of it; "Any" keeps the
	random pick. The types and models are the gamemode's list (the Lootbox Models tool edits it), so in Sandbox a loot
	point is always "any".
	Saved per map straight away. Works in Sandbox too, so you can set a map up there.
]]
TOOL.Category = "Green Flu: Reimagined"
TOOL.Name = "#tool.gfr_spawnpoints.name"
TOOL.ClientConVar["kind"] = "loot"
TOOL.ClientConVar["ctype"] = ""  -- loot: "" = any type
TOOL.ClientConVar["model"] = ""  -- loot: "" = any model of the type
TOOL.ClientConVar["skin"] = "-1"
TOOL.Information = {{name = "left"}, {name = "right"}, {name = "reload"}}

if CLIENT then
	language.Add("tool.gfr_spawnpoints.name", "Spawn Points")
	language.Add("tool.gfr_spawnpoints.desc", "Mark where loot, zombies and survivor / bandit / military groups can turn up on this map")
	language.Add("tool.gfr_spawnpoints.left", "Place a point")
	language.Add("tool.gfr_spawnpoints.right", "Remove the nearest point")
	language.Add("tool.gfr_spawnpoints.reload", "Remove every point of this type")
end

local function Allowed(ply)
	if game.SinglePlayer() or ply:IsSuperAdmin() then return true end
	return GFR && GFR.LootModels && GFR.LootModels.CanEdit(ply) or false -- (admins too, in the gamemode)
end

local function Tell(ply, msg)
	if IsValid(ply) then ply:ChatPrint("[Spawn Points] " .. msg) end
end

-- The loot point settings, checked against the gamemode's list (nothing in Sandbox)
local function LootExtra(tool)
	if !GFR or !GFR.ContainerTypes then return nil end
	local ctype, model = tool:GetClientInfo("ctype"), tool:GetClientInfo("model")
	local skin = tonumber(tool:GetClientInfo("skin")) or -1
	if ctype == "" or ctype == "none" or !GFR.ContainerTypes[ctype] then return nil end
	local extra = {ctype = ctype}
	if model != "" then
		local e = GFR.ContainerListEntry && GFR.ContainerListEntry(model, skin >= 0 and skin or nil)
		if e && e.type == ctype then extra.model, extra.skin = e[1], e.skin end
	end
	return extra
end

function TOOL:LeftClick(tr)
	if !tr.Hit or tr.HitSky then return false end
	if CLIENT then return true end
	local ply = self:GetOwner()
	if !Allowed(ply) or !GFR_SP then return false end
	local kind = self:GetClientInfo("kind")
	if !GFR_SP.KindById[kind] then return false end
	return GFR_SP.Add(kind, tr.HitPos + tr.HitNormal * 2, kind == "loot" and LootExtra(self) or nil)
end

function TOOL:RightClick(tr)
	if CLIENT then return true end
	local ply = self:GetOwner()
	if !Allowed(ply) or !GFR_SP then return false end
	local removed = GFR_SP.RemoveNear(tr.HitPos, 96)
	if !removed then Tell(ply, "No point close to where you're looking.") return false end
	return true
end

function TOOL:Reload()
	if CLIENT then return true end
	local ply = self:GetOwner()
	if !Allowed(ply) or !GFR_SP then return false end
	local kind = self:GetClientInfo("kind")
	local n = GFR_SP.ClearKind(kind)
	local k = GFR_SP.KindById[kind]
	Tell(ply, "Removed " .. n .. " " .. (k and string.lower(k.name) or kind) .. " point" .. (n == 1 and "" or "s") .. " on this map.")
	return n > 0
end

if SERVER then return end

-- Container types, by name ("none" left out: a loot point always spawns something)
local function SortedTypes()
	local list = {}
	for id, def in pairs(GFR && GFR.ContainerTypes or {}) do list[#list + 1] = {id = id, name = def.name or id} end
	table.sort(list, function(a, b) return a.name < b.name end)
	return list
end

function TOOL.BuildCPanel(panel)
	panel:Help("#tool.gfr_spawnpoints.desc")
	local combo = vgui.Create("DComboBox", panel)
	combo:SetTall(24)
	local cur = GetConVarString("gfr_spawnpoints_kind")
	for _, k in ipairs(GFR_SP and GFR_SP.Kinds or {}) do
		combo:AddChoice(k.name, k.id, k.id == cur)
	end
	combo.OnSelect = function(_, _, _, id) RunConsoleCommand("gfr_spawnpoints_kind", id) end
	panel:AddItem(combo)

	-- Loot points: which container
	if GFR && GFR.ContainerTypes then
		panel:Help("Loot stash: what turns up at the point")
		local typeBox = vgui.Create("DComboBox", panel)
		typeBox:SetTall(24)
		panel:AddItem(typeBox)
		local modelBox = vgui.Create("DComboBox", panel)
		modelBox:SetTall(24)
		panel:AddItem(modelBox)

		local function FillModels()
			modelBox:Clear()
			local ctype = GetConVarString("gfr_spawnpoints_ctype")
			local curModel, curSkin = GetConVarString("gfr_spawnpoints_model"), tonumber(GetConVarString("gfr_spawnpoints_skin")) or -1
			modelBox:AddChoice("Any model of this type", {"", -1}, curModel == "")
			if ctype == "" then modelBox:SetEnabled(false) return end
			modelBox:SetEnabled(true)
			for _, e in ipairs(GFR.ContainerModels or {}) do
				if e.type == ctype then
					local label = string.GetFileFromFilename(e[1]) .. (e.skin and ("  (skin " .. e.skin .. ")") or "")
					modelBox:AddChoice(label, {e[1], e.skin or -1}, e[1] == curModel && (e.skin or -1) == curSkin)
				end
			end
		end

		local function FillTypes()
			typeBox:Clear()
			local cur = GetConVarString("gfr_spawnpoints_ctype")
			typeBox:AddChoice("Any type (random, like map loot)", "", cur == "")
			for _, t in ipairs(SortedTypes()) do typeBox:AddChoice(t.name, t.id, t.id == cur) end
			FillModels()
		end

		typeBox.OnSelect = function(_, _, _, id)
			RunConsoleCommand("gfr_spawnpoints_ctype", id)
			RunConsoleCommand("gfr_spawnpoints_model", "")
			RunConsoleCommand("gfr_spawnpoints_skin", "-1")
			timer.Simple(0.1, function() if IsValid(modelBox) then FillModels() end end) -- (once the convar has changed)
		end
		modelBox.OnSelect = function(_, _, _, data)
			RunConsoleCommand("gfr_spawnpoints_model", data[1])
			RunConsoleCommand("gfr_spawnpoints_skin", tostring(data[2]))
		end
		FillTypes()
		-- (the list was edited with the Lootbox Models tool)
		hook.Add("GFR_LootModelsChanged", typeBox, function() if IsValid(typeBox) then FillTypes() end end)
		panel:Help("Only for loot points. A model that isn't installed turns up as the wooden crate, still that type.")
	end

	panel:Help("Points are saved for this map as you place them (data/greenflu/spawns_<map>.txt). In the gamemode they're used alongside its usual random spots, and only when nobody is close by or watching. A group spawned at a bandit point is bandits, and so on.")
	panel:CheckBox("Only use placed points (no random spots for kinds this map has points for)", "gfr_spawnpoints_only")
end
