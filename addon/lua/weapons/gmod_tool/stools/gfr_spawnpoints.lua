--[[
	Custom Apocalypse - Spawn Points tool (lua/autorun/gfr_spawnpoints.lua does the saving and the markers)
	Pick what spawns there in the tool menu, then:
		left click   place a point where you look
		right click  remove the nearest point (any type)
		reload       remove every point of the chosen type on this map
	Saved per map straight away. Works in Sandbox too, so you can set a map up there.
]]
TOOL.Category = "Green Flu: Reimagined"
TOOL.Name = "#tool.gfr_spawnpoints.name"
TOOL.ClientConVar["kind"] = "loot"
TOOL.Information = {{name = "left"}, {name = "right"}, {name = "reload"}}

if CLIENT then
	language.Add("tool.gfr_spawnpoints.name", "Spawn Points")
	language.Add("tool.gfr_spawnpoints.desc", "Mark where loot, zombies and survivor / bandit / military groups can turn up on this map")
	language.Add("tool.gfr_spawnpoints.left", "Place a point")
	language.Add("tool.gfr_spawnpoints.right", "Remove the nearest point")
	language.Add("tool.gfr_spawnpoints.reload", "Remove every point of this type")
end

local function Allowed(ply) return game.SinglePlayer() or ply:IsSuperAdmin() end

local function Tell(ply, msg)
	if IsValid(ply) then ply:ChatPrint("[Spawn Points] " .. msg) end
end

function TOOL:LeftClick(tr)
	if !tr.Hit or tr.HitSky then return false end
	if CLIENT then return true end
	local ply = self:GetOwner()
	if !Allowed(ply) or !GFR_SP then return false end
	local kind = self:GetClientInfo("kind")
	if !GFR_SP.KindById[kind] then return false end
	return GFR_SP.Add(kind, tr.HitPos + tr.HitNormal * 2)
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
	panel:Help("Points are saved for this map as you place them (data/greenflu/spawns_<map>.txt). In the gamemode they're used alongside its usual random spots, and only when nobody is close by or watching. A group spawned at a bandit point is bandits, and so on.")
	panel:CheckBox("Only use placed points (no random spots for kinds this map has points for)", "gfr_spawnpoints_only")
end
