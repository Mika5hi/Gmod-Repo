ENT.Base = "npc_vj_creature_base"
ENT.Type = "ai"
ENT.PrintName = "Ravenholm Grabber"
ENT.Author = "Local edit (models: Return to Ravenholm, AI: GMod of the Dead Reanimated)"
ENT.Category = "Green Flu: Reimagined"

ENT.VJ_ID_Undead = true
ENT.VJ_GOTDR_Zombie = true
---------------------------------------------------------------------------------------------------------------------------------------------
-- The animation rig is invisible, the bonemerged Ravenholm model is what gets drawn
function ENT:Draw() return end
