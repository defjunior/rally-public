local Ball = {}

local cf = CFrame.new
local v3 = Vector3.new
local nv = v3()
local nc = cf()
local dot = nv.Dot

function FCX(x,y,z) -- arb reasons
	-- arcane shadow wizard money magic
	-- grown dark evil pack

	if not y then
		x,y,z=x.x,x.y,x.z
	end
	local m=(x*x+y*y+z*z)^0.5
	if m>1e-5 then
		local si=math.sin(m/2)/m
		return CFrame.new(0,0,0,si*x,si*y,si*z,math.cos(m/2))
	else
		return CFrame.new()
	end
end


function Ball:New(Velocity,Position)
	local NewBall = {}
	setmetatable(NewBall,{_index = Ball})
	local NewBallPart = Instance.new("Part")
	NewBallPart.Size = Vector3.new(1,1,1)
	NewBallPart.Shape = Enum.PartType.Ball
	NewBallPart.CanCollide = true
	NewBallPart.Anchored = true
	
	NewBall.part = NewBallPart
	NewBall.velocity = Velocity or Vector3.new()
	NewBall.position = Position or Vector3.new()
	NewBall.gravity = Vector3.new(0,-12,0)
	NewBall.rotation = NewBallPart.CFrame.Rotation
	NewBall.initialVelocity = Vector3.new()
	NewBall.bounceOffset = Vector3.new()
	NewBall.elasticity = 0.7
	NewBall.lastCollideTick = 0
	NewBall.cf = CFrame.new()
	NewBall.minimumCollideDelta = 0.1
	NewBall.lastBounce = false
	NewBall.frictionPercentage = 0.001 -- usually like 8 percent
	return NewBall
	
end

function Ball:Step(deltaTime)

	self.part.CFrame = self.cf
	
	local newVelocity = self.velocity + deltaTime * self.gravity
	local newPosition = self.position + deltaTime * newVelocity
	
	local RayParams = RaycastParams.new()
	RayParams.FilterDescendantsInstances = {workspace.Ignore,Ball,Ball.Outline}
	RayParams.RespectCanCollide = true
	local hit = workspace:Raycast(self.position,newVelocity * deltaTime,RayParams)
	local normal
	local timeSince = tick() - self.lastCollideTick

	-- bounce the ball when it gets to either side
	-- detection for if players actually return it properly is not yet added
	--print(BallVelocity)
	if hit and tick() - self.lastCollideTick > self.minimumCollideDelta then

		normal = hit.Normal
		-- Normal is a vector that represents the direction the ball would bounce in after striking that surface
		self.rotation = self.cf.Rotation
		self.bounceOffset = self.elasticity * normal -- how far upwards the ball goes
		self.lastCollideTick = tick()
		self.initialVelocity = normal:Cross(self.velocity) / self.elasticity-- resulting change in velocity depending on elasticity
		self.position = self.position + normal * 0.01 -- never fully clips through and touches the wall, to prevent it from going through
		local normalVelocity = dot(normal,self.velocity) * normal
		local tanVelocity = self.elasticity - normalVelocity
		local friction
		if self.lastBounce  then
			friction = 1 - 0.001 * self.gravity.magnitude *deltaTime / tanVelocity.magnitude
		else
			friction = 1-self.frictionPercentage * (self.gravity.magnitude+(1+self.elasticity) * normalVelocity.magnitude)/tanVelocity.magnitude
		end
		--
		self.velocity = tanVelocity*(friction < 0 and 0 or friction)-self.elasticity*normalVelocity
		self.lastBounce = true
	else
		self.position = newPosition
		self.velocity = newVelocity
		self.lastBounce = false
	end



	self.cf = cf(self.position + self.bounceOffset)*FCX(timeSince*self.initialVelocity)*self.rotation
	self.part.CFrame = self.cf
end

return Ball
