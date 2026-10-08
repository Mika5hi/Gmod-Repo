ENT.Base = "npc_vj_creature_base"
ENT.Type = "ai"
ENT.PrintName = "Playermodel Zombie"
ENT.Author = "Green Flu: Reimagined"
ENT.Category = "Green Flu: Reimagined"

ENT.VJ_ID_Undead = true
ENT.VJ_GOTDR_Zombie = true
---------------------------------------------------------------------------------------------------------------------------------------------
-- The animation rig is invisible, the bonemerged playermodel is what gets drawn
function ENT:Draw() return end
