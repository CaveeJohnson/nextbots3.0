if ( SERVER ) then
	AddCSLuaFile( "shared.lua" )
end

--Convars--
local nb_targetmethod = GetConVar("nb_targetmethod")
local ai_disabled = GetConVar("ai_disabled")
local ai_ignoreplayers = GetConVar("ai_ignoreplayers")

local nb_doorinteraction = GetConVar("nb_doorinteraction")
local nb_friendlyfire = GetConVar("nb_friendlyfire")
local nb_death_animations = GetConVar("nb_death_animations")
local nb_allow_backingup = GetConVar("nb_allow_backingup")

ENT.Base = "nb_rebel_melee_base"
ENT.Spawnable        = false
ENT.AdminSpawnable   = false

--Stats--
ENT.ChaseDistance = 3000

ENT.CollisionHeight = 64
ENT.CollisionSide = 7

ENT.HealthAmount = 100

ENT.Speed = 150
ENT.SprintingSpeed = 230
ENT.FlinchWalkSpeed = 80
ENT.CrouchSpeed = 40

ENT.AccelerationAmount = 400
ENT.DecelerationAmount = 400

ENT.JumpHeight = 58
ENT.StepHeight = 18
ENT.MaxDropHeight = 200

ENT.ShootDelay = 0.4
ENT.MeleeDelay = 1.6

ENT.ShootRange = 65
ENT.MeleeRange = 65
ENT.StopRange = 40
ENT.BackupRange = 20

ENT.MeleeDamage = 25
ENT.MeleeDamageType = DMG_SLASH
 
ENT.MeleeDamageForce = Vector( math.random( ENT.MeleeDamage, ENT.MeleeDamage, ENT.MeleeDamage ) )

--Weapon--
ENT.WeaponClass = "ent_melee_weapon"
ENT.WeaponModel = "models/weapons/w_crowbar.mdl"

--Model--
ENT.WalkAnim = ACT_HL2MP_RUN_MELEE2
ENT.BlockWalkAnim = ACT_HL2MP_RUN_MAGIC
ENT.SprintingAnim = ACT_HL2MP_RUN_MELEE2
ENT.FlinchWalkAnim = ACT_HL2MP_WALK_MELEE2 
ENT.CrouchAnim = ACT_HL2MP_WALK_CROUCH_MELEE2
ENT.JumpAnim = ACT_HL2MP_JUMP_MELEE2

--ENT.MeleeAnim = {"aoc_slash_01","aoc_slash_02","aoc_slash_03","aoc_slash_04","aoc_dagger2_throw"}

ENT.BlockAnimation = "aoc_kite_deflect"

function ENT:Initialize()

	if SERVER then
		self:CustomInitialize()
	
		self.loco:SetDeathDropHeight( self.MaxDropHeight )	
		self.loco:SetAcceleration( self.AccelerationAmount )		
		self.loco:SetDeceleration( self.DecelerationAmount )
		self.loco:SetStepHeight( self.StepHeight )
		self.loco:SetJumpHeight( self.JumpHeight )
	
		self:CollisionSetup( self.CollisionSide, self.CollisionHeight, COLLISION_GROUP_PLAYER )
	
		self.NEXTBOTFACTION = 'NEXTBOTCOMBINE'
		self.NEXTBOTCOMBINE = true
		self.NEXTBOT = true
		
		--Status
		self.NextCheckTimer = CurTime() + 4
		self.StuckAttempts = 0
		self.TotalTimesStuck = 0
		self.IsJumping = false
		self.ReloadAnimation = false
		self.HitByVehicle = false
		self.TouchedDoor = false
		self.IsAlerted = false
		self.AlertedEntity = nil
		
		self:MovementFunction()
	end
	
	if CLIENT then
		self.NEXTBOTFACTION = 'NEXTBOTCOMBINE'
		self.NEXTBOTCOMBINE = true
		self.NEXTBOT = true
	end
	
end

function ENT:CustomInitialize()

	local model = table.Random( self.Models )
		if model == "" or nil then
			self:SetModel( "models/player/charple.mdl" )
		else
			--util.PrecacheModel( table.ToString( self.Models ) )
			self:SetModel( model )
		end
	
	self:SetHealth( self.HealthAmount )

	self:EquipWeapon()
	
end

function ENT:CustomOnContact( ent )

	if ent:IsVehicle() then
		if self.HitByVehicle then return end
		if self:Health() < 0 then return end
		if ( math.Round(ent:GetVelocity():Length(),0) < 5 ) then return end 
		
		local veh = ent:GetPhysicsObject()
		local dmg = math.Round( (ent:GetVelocity():Length() / 5 + ( veh:GetMass() / 100 ) ), 1 )

		if dmg > self:Health() then
		
			if ent:GetOwner():IsValid() then
				self:TakeDamage( dmg, ent:GetOwner() )
			else
				self:TakeDamage( dmg, ent )
			end
		
		else
		
			self.HitByVehicle = true
			self:VehicleHit( ent, "nb_rise_base", self:GetClass(), "", ( self:Health() - dmg ), true )
		
		end

	end

	if ent != self.Enemy then
		if ( self.NextMeleeTimer or 0 ) < CurTime() then
			if self:CanTargetThisEnemy( ent ) then
				self:Melee( ent )
				--print( "contacted: ", ent, "nb: ", self )
				self.NextMeleeTimer = CurTime() + self.MeleeDelay
			end
		end
			
		if ( self.NextSwitchTargetTimer or 0 ) < CurTime() then
			if self:CanTargetThisEnemy( ent ) then
				self:SetEnemy( ent )
				--self:BehaveStart()
				self.NextSwitchTargetTimer = CurTime() + 1
			end
		end
	end
	
	self:CustomOnContact2( ent )
	
end

function ENT:Use( activator, caller )
end

function ENT:MovementFunction( type )
	if type == "crouching" then
		self:StartActivity( self.CrouchAnim )
		self.loco:SetDesiredSpeed( self.CrouchSpeed )
	elseif type == "running" then
		self:StartActivity( self.SprintingAnim )
		self.loco:SetDesiredSpeed( self.SprintingSpeed )
	elseif type == "panicked" then
		self:StartActivity( ACT_HL2MP_RUN_PANICKED )
		self.loco:SetDesiredSpeed( self.SprintingSpeed )
	elseif type == nil then
		if self.Patrolling then
			self:StartActivity( self.PatrolWalkAnim )
			self.loco:SetDesiredSpeed( self.PatrolSpeed )
		else
			self:StartActivity( self.WalkAnim )
			self.loco:SetDesiredSpeed( self.Speed )
		end
	end
end

function ENT:RunBehaviour()

	while ( true ) do

		if self:HaveEnemy() then

			self.Patrolling = false
		
			pos = self:GetEnemy():GetPos()

			if ( pos ) then
				
				local enemy = self:GetEnemy()
				
				self:MovementFunction()	
					
				local maxageScaled=math.Clamp(pos:Distance(self:GetPos())/1000,0.1,3)	
				local opts = {	lookahead = 30,
						tolerance = 20,
						draw = false,
						maxage = maxageScaled 
						}
					
				self:ChaseEnemy( opts )
					
			end
			
		else
		
			self.Patrolling = true
		
			self:PlayIdleSound()

			self:MovementFunction()
				
			local pos = self:FindSpot( "random", { radius = 5000 } )

			if ( pos ) then

				self:MoveToPos( pos )

			end	
				
		end

		coroutine.yield()

	end

end

function ENT:CustomBehaveUpdate()

	if self:HaveEnemy() and self.Enemy then
		
		if ( self:GetRangeSquaredTo( self.Enemy ) < self.MeleeRange*self.MeleeRange and self:IsLineOfSightClear( self.Enemy ) ) then

			if ( self.NextMeleeAttackTimer or 0 ) < CurTime() then
			
				if self.Blocking then return end

				self:Melee( self.Enemy )
					
				if math.random(1,2) == 1 then
					timer.Simple( 0.9, function()
						if !self:IsValid() then return end
						if self:Health() < 0 then return end
						self:StartBlocking( math.random( 0.5, 1.5 ) )
					end)
				end
				
				self.NextMeleeAttackTimer = CurTime() + self.MeleeDelay
			end

		end
				
		if self.IsAttacking then
			if self.FacingTowards:IsValid() and self.FacingTowards:Health() > 0 then
				self.loco:FaceTowards( self.FacingTowards:GetPos() )
			end
		end
				
	end

end

function ENT:Melee( ent, type )

	if self.IsAttacking then return end

	self.IsAttacking = true 
	self.FacingTowards = ent	
	
	self:PlayAttackSound()
	
	self:PlayGestureSequence( table.Random( self.MeleeAnim ), 1 )
		
	self.loco:SetDesiredSpeed( 0 )
	
	timer.Simple( 0.3, function()
		if ( IsValid(self) and self:Health() > 0) then
			self:EmitSound( "weapons/tfa_kf2/katana/katana_swing_miss"..math.random(1,4)..".wav" )
		end
	end)

	timer.Simple( 0.45, function()
		if ( IsValid(self) and self:Health() > 0) and IsValid(ent) then
		
			if self:GetRangeSquaredTo( ent ) > self.MeleeRange*self.MeleeRange then return end

			if ent:Health() > 0 then
				self:DoDamage( self.MeleeDamage, self.MeleeDamageType, ent )
				
				if ent:IsPlayer() then
					if ( ent:GetActiveWeapon().CanBlock ) then
						if ( ent:GetActiveWeapon():GetStatus( TFA.GetStatus("blocking") ) ) == 21 then
							--blocksound
						else
							self:EmitSound("physics/flesh/flesh_squishy_impact_hard"..math.random(4)..".wav")
							self:EmitSound("physics/body/body_medium_break"..math.random(2, 4)..".wav")
						end
					else
						if ( ent:GetNetworkedBool("Block") ) then
							--blocksound
						else
							self:EmitSound("physics/flesh/flesh_squishy_impact_hard"..math.random(4)..".wav")
							self:EmitSound("physics/body/body_medium_break"..math.random(2, 4)..".wav")
						end
					end
				else
					if ent.NEXTBOT then
						if !ent.Blocking then
							self:EmitSound("physics/flesh/flesh_squishy_impact_hard"..math.random(4)..".wav")
							self:EmitSound("physics/body/body_medium_break"..math.random(2, 4)..".wav")
						end
					end
				end
			end
		
			if type == 1 then --Prop
				local phys = ent:GetPhysicsObject()
				if (phys != nil && phys != NULL && phys:IsValid() ) then
					phys:ApplyForceCenter(self:GetForward():GetNormalized()*( ( self.MeleeDamage * 1000 ) ) + Vector(0, 0, 2))
				end
				--Prop hit sound
			elseif type == 2 then --Door
				ent.Hitsleft = ent.Hitsleft - 10
			end
		
		end
	end)
	
	timer.Simple( 0.8, function()
		if ( IsValid(self) and self:Health() > 0) then
			self.IsAttacking = false
			self.loco:SetDesiredSpeed( self.Speed )
		end
	end)
	
end

function ENT:FindEnemy()

	if ( self.NextLookForTimer or 0 ) < CurTime() then

		local enemies
			
		if ai_ignoreplayers:GetInt() == 1 then
			enemies = table.Add( ents.FindByClass("nb_*") )
		else
			enemies = table.Add( player.GetAll(), ents.FindByClass("nb_*") )
		end
		
		if #enemies > 0 then
			for i=1,table.Count( enemies ) do -- Goal is to reduce amount of values to be sorted through in the table for better performance
				for k,v in pairs( enemies ) do
					if v.BASENEXTBOT then --Remove base nextbot entities (eg. nb_deathanim_base)
						table.remove( enemies, k )
					end
					if ( self.NEXTBOTFACTION == v.NEXTBOTFACTION ) then --Remove same faction from pool of enemies
						table.remove( enemies, k )
					end
					if !IsValid( v ) then --Remove unvalid targets from pool of enemies
						table.remove( enemies, k )
					end
					if v:Health() < 0 then --Remove dead targets from pool of enemies
						table.remove( enemies, k )
					end
					if ai_ignoreplayers:GetInt() == 0 then --Remove players from pool of enemies if ignore players is true
						if v:IsPlayer() then
							if !v:Alive() then --Remove dead players from pool of enemies
								table.remove( enemies, k )
							end
						end
					end
				end
			end
			
			table.sort( enemies, 
			function( a,b ) 
				return self:GetRangeSquaredTo( a ) < self:GetRangeSquaredTo( b ) --Sort in order of closeness from pool of enemies
			end )

			self:SearchForEnemy( enemies )
			--PrintTable( enemies )
		end
	
		self.NextLookForTimer = CurTime() + ( self.EnemyCheckTime or 0.5 )
	end
	
end

function ENT:BodyUpdate()

	--if !self.IsAttacking then

		if ( self:GetActivity() == self.WalkAnim ) then
				
			self:BodyMoveXY()
		
		elseif ( self:GetActivity() == self.SprintingAnim ) then
		
			self:BodyMoveXY()
		
		end

	--else
	
		--self:SetPoseParameter("move_x", 0.8 )
	
	--end
	
	self:FrameAdvance()

end

function ENT:MoveToPos( pos, options )

	local options = options or {}

	local path = Path( "Follow" )
	path:SetMinLookAheadDistance( options.lookahead or 300 )
	path:SetGoalTolerance( options.tolerance or 20 )
	path:Compute( self, pos )

	if ( !path:IsValid() ) then return "failed" end

	while ( path:IsValid() ) do
	
		if self:HaveEnemy() and self.Patrolling then
			return "failed"
		end
	
		if nb_doorinteraction:GetInt() == 1 then
			if !self:CheckDoor() then
			
			elseif ( self:CheckDoor():IsValid() and self:GetRangeSquaredTo( self:CheckDoor() ) < (self.StopRange + 20)*(self.StopRange + 20) and self:IsLineOfSightClear( self:CheckDoor() ) ) then
				self:ContactDoor( self:CheckDoor() )
				return "ok"
			end
		end
	
		path:Update( self )

		if ( options.draw ) then
			path:Draw()
		end

		if !self.Downed then
			if ( self.loco:IsStuck() ) then
				self:HandleStuck()
				return "stuck"
			end
		end
		
		if ( options.maxage ) then
			if ( path:GetAge() > options.maxage ) then return "timeout" end
		end

		if ( options.repath ) then
			if ( path:GetAge() > options.repath ) then path:Compute( self, pos ) end
		end
		
		coroutine.yield()

	end

	return "ok"

end

function ENT:OnInjured( dmginfo )

	if self:CheckFriendlyFire( dmginfo:GetAttacker() ) then 
		dmginfo:ScaleDamage(0)
	return end
	
	if ( dmginfo:IsBulletDamage() ) then

		local attacker = dmginfo:GetAttacker()
	
			local trace = {}
			trace.start = attacker:EyePos()

			trace.endpos = trace.start + ( ( dmginfo:GetDamagePosition() - trace.start ) * 2 )  
			trace.mask = MASK_SHOT
			trace.filter = attacker
		
			local tr = util.TraceLine( trace )
			hitgroup = tr.HitGroup
			
			if hitgroup == ( HITGROUP_LEFTLEG or HITGROUP_RIGHTLEG ) then
				dmginfo:ScaleDamage(0.45)	
			end

			if hitgroup == HITGROUP_HEAD then
				dmginfo:ScaleDamage(8)
				self:EmitSound("hits/headshot_"..math.random(9)..".wav", 70)
			end
		
		if math.random(1,3) == 1 then
			if !self.Attacking then
				--self:MovementFunction( "panicked" )
				self.loco:SetDesiredSpeed( self.Speed * 1.5 )
			end
		end
		
	end

	if ( dmginfo:IsDamageType(DMG_SLASH) or dmginfo:IsDamageType(DMG_CLUB) ) and self:GetRangeSquaredTo( dmginfo:GetAttacker() ) < 80*80 and !self.IsAttacking then
		if math.random(1,2) == 1 then
			
			local enemyforward = dmginfo:GetAttacker():GetForward()
			local forward = self:GetForward() 
					
			if enemyforward:Distance( forward ) > 1 then
				--Hit from front
				self:StartBlocking( math.random( 1, 3 ) )
			else
				--Hit from behind
			end
			
		end
	end
	
	self:BlockDamage( dmginfo )
	
	self:CheckEnemyPosition( dmginfo )
	
end

function ENT:StartBlocking( time )
	if self.Blocking then return end
	if self.Attacking then return end
	
	self.Blocking = true
	self.WalkAnim = self.BlockWalkAnim
	self.loco:SetDesiredSpeed( self.Speed / 3 )
	self:MovementFunction()
	
	timer.Simple( time, function()
		if !self:IsValid() then return end
		if self:Health() < 0 then return end 
		self.Blocking = false 
		self.WalkAnim = self.OrgWalkAnim or self.WalkAnim
		self:MovementFunction()
	end)
end

function ENT:ArmorVisual( pos )

	local effectdata = EffectData()
		effectdata:SetStart( pos ) 
		effectdata:SetOrigin( pos )
		effectdata:SetScale( 1 )
		util.Effect( "StunStickImpact", effectdata )

end

function ENT:BlockDamage( dmginfo )

	if self.Blocking then

		if ( dmginfo:IsDamageType(DMG_SLASH) or dmginfo:IsDamageType(DMG_CLUB) ) and self:GetRangeSquaredTo( dmginfo:GetAttacker() ) < 80*80 and !self.IsAttacking then

			self:ArmorVisual( ( self:GetPos() + Vector(0,0,50) + (self:GetForward() * 10) ) )
			
			self:PlayGestureSequence( "aoc_kite_deflect" )
			self.loco:SetDesiredSpeed( 0 )
		
			self:EmitSound( "weapons/tfa_kf2/katana/block0"..math.random(1,3)..".wav" )
			dmginfo:ScaleDamage( 0.3 )
		
		end

	else
	
		self:PlayPainSound()
	
	end
	
end

function ENT:OnKilled( dmginfo )
	
	if self.HitByVehicle then 
	return end
	
	if dmginfo:GetAttacker().NEXTBOTZOMBIE or self:IsPlayerZombie( dmginfo:GetAttacker() ) then
	
		self:RiseAsZombie( self, "nb_rise_base", "nb_freshdead", "", 100, true )
	
		if self.Weapon then
			SafeRemoveEntity( self.Weapon)
		end
	
	else
	
		self:BecomeRagdoll( dmginfo )
		self:DropWeapon()
	
	end
	
	self:PlayDeathSound()
	
end