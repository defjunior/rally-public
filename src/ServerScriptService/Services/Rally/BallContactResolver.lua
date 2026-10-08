local BallContactResolver = {}

local DEFAULT_SAMPLE_SPACING = 0.18
local DEFAULT_MAX_STEPS = 24
local PLAYER_KEYS = table.freeze({ "Player1", "Player2" })

local function getHitbox(paddle)
	if typeof(paddle) ~= "Instance" then
		return nil
	end
	local hitbox = paddle:FindFirstChild("PaddleHitbox", true)
	return hitbox and hitbox:IsA("BasePart") and hitbox or nil
end

local function getRotationTravel(fromCF, toCF, radius)
	local lookDelta = (fromCF.LookVector - toCF.LookVector).Magnitude
	local upDelta = (fromCF.UpVector - toCF.UpVector).Magnitude
	return math.max(lookDelta, upDelta) * radius
end

function BallContactResolver:GetPointBoxDistance(worldPoint, boxCF, halfSize)
	local localPoint = boxCF:PointToObjectSpace(worldPoint)
	local outside = Vector3.new(
		math.max(math.abs(localPoint.X) - halfSize.X, 0),
		math.max(math.abs(localPoint.Y) - halfSize.Y, 0),
		math.max(math.abs(localPoint.Z) - halfSize.Z, 0)
	)
	return outside.Magnitude
end

function BallContactResolver:GetExpandedHalfSize(hitbox, ballRadius, padding)
	local radius = math.max(tonumber(ballRadius) or 0, 0)
	local extra = typeof(padding) == "Vector3" and padding or Vector3.zero
	return (hitbox.Size * 0.5) + Vector3.new(radius, radius, radius) + extra
end

function BallContactResolver:_sweepAgainstPaddle(ballStart, ballEnd, hitbox, fromCF, toCF, halfSize, options)
	local ballTravel = (ballEnd - ballStart).Magnitude
	local paddleTravel = (toCF.Position - fromCF.Position).Magnitude
	local rotationTravel = getRotationTravel(fromCF, toCF, halfSize.Magnitude)
	local spacing = math.max(tonumber(options.SampleSpacing) or DEFAULT_SAMPLE_SPACING, 0.05)
	local maxSteps = math.max(math.floor(tonumber(options.MaxSteps) or DEFAULT_MAX_STEPS), 1)
	local stepCount = math.clamp(math.ceil((ballTravel + paddleTravel + rotationTravel) / spacing), 1, maxSteps)
	for step = 0, stepCount do
		local fraction = step / stepCount
		local ballPosition = ballStart:Lerp(ballEnd, fraction)
		local paddleCF = fromCF:Lerp(toCF, fraction)
		local distance = self:GetPointBoxDistance(ballPosition, paddleCF, halfSize)
		if distance <= 1e-4 then
			local normal = paddleCF.LookVector
			local ballDelta = ballEnd - ballStart
			if ballDelta:Dot(normal) > 0 then
				normal = -normal
			end
			return {
				Instance = hitbox,
				Normal = normal,
				Position = ballPosition,
				Fraction = fraction,
				Distance = 0,
				Source = "server_sweep",
			}
		end
	end

	return nil
end

function BallContactResolver:SyncPaddleHistory(match)
	if not match then
		return
	end
	match._paddleContactHistory = match._paddleContactHistory or {}
	match._paddleContactPoseQueue = match._paddleContactPoseQueue or {}
	for _, playerKey in ipairs(PLAYER_KEYS) do
		local paddle = playerKey == "Player1" and match.player1Paddle or match.player2Paddle
		local hitbox = getHitbox(paddle)
		match._paddleContactHistory[playerKey] = hitbox and hitbox.CFrame or nil
		match._paddleContactPoseQueue[playerKey] = {}
	end
end

function BallContactResolver:RecordPaddlePose(match, playerKey)
	if not match or (playerKey ~= "Player1" and playerKey ~= "Player2") then
		return
	end
	local paddle = playerKey == "Player1" and match.player1Paddle or match.player2Paddle
	local hitbox = getHitbox(paddle)
	if not hitbox then
		return
	end
	match._paddleContactPoseQueue = match._paddleContactPoseQueue or {}
	local queue = match._paddleContactPoseQueue[playerKey] or {}
	local lastCF = queue[#queue] or (match._paddleContactHistory and match._paddleContactHistory[playerKey])
	local currentCF = hitbox.CFrame
	if not lastCF
		or (lastCF.Position - currentCF.Position).Magnitude > 1e-4
		or lastCF.LookVector:Dot(currentCF.LookVector) < 0.9999 then
		table.insert(queue, currentCF)
		while #queue > 12 do
			table.remove(queue, 1)
		end
	end
	match._paddleContactPoseQueue[playerKey] = queue
end

function BallContactResolver:ResolveServerSweep(match, ballStart, ballEnd, options)
	if not match or typeof(ballStart) ~= "Vector3" or typeof(ballEnd) ~= "Vector3" then
		return nil
	end
	options = options or {}
	match._paddleContactHistory = match._paddleContactHistory or {}
	match._paddleContactPoseQueue = match._paddleContactPoseQueue or {}
	match._paddleSweepPoses = match._paddleSweepPoses or {}
	local bestHit = nil

	for _, playerKey in ipairs(PLAYER_KEYS) do
		local paddle = playerKey == "Player1" and match.player1Paddle or match.player2Paddle
		local hitbox = getHitbox(paddle)
		if hitbox then
			local currentCF = hitbox.CFrame
			local previousCF = match._paddleContactHistory[playerKey] or currentCF
			local paddingByPlayer = options.PaddingByPlayer
			local padding = type(paddingByPlayer) == "table" and paddingByPlayer[playerKey] or options.Padding
			local halfSize = self:GetExpandedHalfSize(hitbox, options.BallRadius, padding)
			local poses = match._paddleSweepPoses[playerKey]
			if not poses then
				poses = {}
				match._paddleSweepPoses[playerKey] = poses
			else
				table.clear(poses)
			end
			table.insert(poses, previousCF)
			local poseQueue = match._paddleContactPoseQueue[playerKey]
			for _, queuedCF in ipairs(poseQueue or {}) do
				table.insert(poses, queuedCF)
			end
			if poses[#poses] ~= currentCF then
				table.insert(poses, currentCF)
			end
			local segmentCount = math.max(#poses - 1, 1)
			for segment = 1, segmentCount do
				local startFraction = (segment - 1) / segmentCount
				local endFraction = segment / segmentCount
				local segmentBallStart = ballStart:Lerp(ballEnd, startFraction)
				local segmentBallEnd = ballStart:Lerp(ballEnd, endFraction)
				local fromCF = poses[segment] or previousCF
				local toCF = poses[segment + 1] or currentCF
				local hit = self:_sweepAgainstPaddle(segmentBallStart, segmentBallEnd, hitbox, fromCF, toCF, halfSize, options)
				if hit then
					hit.Fraction = startFraction + ((endFraction - startFraction) * hit.Fraction)
					if not bestHit or hit.Fraction < bestHit.Fraction then
						bestHit = hit
					end
				end
			end
			match._paddleContactHistory[playerKey] = currentCF
			if poseQueue then
				table.clear(poseQueue)
			else
				match._paddleContactPoseQueue[playerKey] = {}
			end
		else
			match._paddleContactHistory[playerKey] = nil
			local poseQueue = match._paddleContactPoseQueue[playerKey]
			if poseQueue then
				table.clear(poseQueue)
			else
				match._paddleContactPoseQueue[playerKey] = {}
			end
		end
	end

	return bestHit
end

function BallContactResolver:GetSnapshotPaddleCFrame(match, snapshot, playerKey, hitbox)
	local posKey = playerKey == "Player1" and "LastPlayer1Pos" or "LastPlayer2Pos"
	local rotKey = playerKey == "Player1" and "LastPlayer1Rot" or "LastPlayer2Rot"
	local paddle = playerKey == "Player1" and match.player1Paddle or match.player2Paddle
	local position = snapshot and snapshot[posKey]
	local rotation = snapshot and snapshot[rotKey]
	if typeof(position) ~= "Vector3" or typeof(rotation) ~= "CFrame" or typeof(paddle) ~= "Instance" then
		return nil
	end
	local currentPivot = paddle:GetPivot()
	local hitboxOffset = currentPivot:ToObjectSpace(hitbox.CFrame)
	return (CFrame.new(position) * rotation) * hitboxOffset
end

function BallContactResolver:FindNearestSnapshot(match, timestamp)
	local nearest = nil
	local nearestDifference = math.huge
	for _, snapshot in ipairs(match and match.tableSnapshots or {}) do
		if type(snapshot) == "table" and type(snapshot.tick) == "number" then
			local difference = math.abs(snapshot.tick - timestamp)
			if difference < nearestDifference then
				nearest = snapshot
				nearestDifference = difference
			end
		end
	end
	return nearest, nearestDifference
end

return BallContactResolver
