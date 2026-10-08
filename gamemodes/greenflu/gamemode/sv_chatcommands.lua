--[[
	Green Flu: Reimagined - chat commands (type them in chat, / or !)
		/drop              drop the weapon in your hands (not your fists)
		/stash             put the weapon in your hands into your bag
		/dropcap <amount>  drop that many caps in front of you (/dropcaps works too)
		/commands          list these
]]

local function Usable(ply)
	return IsValid(ply) && ply:Alive() && !ply.GFR_IsZombie && !ply.GFR_Tied && !ply.GFR_Sleeping
end

local commands = {}

commands.drop = function(ply)
	local wep = ply:GetActiveWeapon()
	if !IsValid(wep) or GFR.IsFists(wep:GetClass()) then GFR.Notify(ply, "You're not holding anything to drop.") return end
	GFR.DropPlayerWeapon(ply, wep)
end

commands.stash = function(ply)
	local wep = ply:GetActiveWeapon()
	if !IsValid(wep) or GFR.IsFists(wep:GetClass()) then GFR.Notify(ply, "You're not holding anything to put away.") return end
	GFR.StashWeapon(ply, wep)
end

commands.dropcap = function(ply, args)
	local amount = math.floor(tonumber(args[1] or "") or 0)
	if amount <= 0 then GFR.Notify(ply, "Usage: /dropcap <amount>") return end
	local have = GFR.GetCaps(ply)
	if have <= 0 then GFR.Notify(ply, "You don't have any caps.") return end
	amount = math.min(amount, have)
	local tr = util.TraceLine({start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * 50, filter = ply})
	local ent = ents.Create("gfr_currency")
	if !IsValid(ent) then return end
	ent.Amount = amount
	ent:SetPos(tr.HitPos + tr.HitNormal * 8)
	ent:Spawn()
	GFR.AddCaps(ply, -amount)
	ent:EmitSound("physics/metal/metal_box_impact_soft" .. math.random(1, 3) .. ".wav", 60, 140)
	GFR.Notify(ply, "Dropped " .. amount .. " caps.")
end
commands.dropcaps = commands.dropcap

-- Staff menu (sv_admin.lua)
commands.gfr = function(ply) if GFR.OpenStaffMenu then GFR.OpenStaffMenu(ply) end end

commands.commands = function(ply)
	GFR.Notify(ply, "/drop - drop your weapon   /stash - weapon into your bag   /dropcap <amount> - drop caps")
end

hook.Add("PlayerSay", "GFR_ChatCommands", function(ply, text)
	local prefix = string.sub(text, 1, 1)
	if prefix != "/" && prefix != "!" then return end
	local args = string.Explode("%s+", string.Trim(string.sub(text, 2)), true)
	local fn = commands[string.lower(table.remove(args, 1) or "")]
	if !fn then return end
	if (ply.GFR_NextChatCmd or 0) <= CurTime() && (fn == commands.commands or fn == commands.gfr or Usable(ply)) then
		ply.GFR_NextChatCmd = CurTime() + 0.5
		fn(ply, args)
	end
	return "" -- (the command doesn't show in chat)
end)
