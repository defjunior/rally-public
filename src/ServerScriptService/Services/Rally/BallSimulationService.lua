-- Ball/contact/replication service excerpt. Private policy and authored tuning omitted.
-- ServiceFramework/configs/match runtime are external; this is not runnable alone.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ServiceFramework = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ServiceFramework"))
local BallContactResolver = require(script.Parent:WaitForChild("BallContactResolver"))
local PlayerAssistService = require(script.Parent:WaitForChild("PlayerAssistService"))
local PlayerAssistance = require(
	ReplicatedStorage
		:WaitForChild("Modules")
		:WaitForChild("Data")
		:WaitForChild("Rally")
		:WaitForChild("PlayerAssistance")
)
local RallyPaceConfig = require(
	ReplicatedStorage:WaitForChild("Modules")
		:WaitForChild("Data")
		:WaitForChild("Rally")
		:WaitForChild("RallyPace")
)

local function getClientPaddleContactAssistScale(match, playerKey: string): number
	local scales = match and match._clientPaddleContactAssistScale
	return math.clamp(tonumber(type(scales) == "table" and scales[playerKey]) or 1, 0, 1)
end
local RallyPerformance = require(
	ReplicatedStorage
		:WaitForChild("Modules")
		:WaitForChild("Data")
		:WaitForChild("Rally")
		:WaitForChild("RallyPerformance")
)
local BallReplicationLod = require(script.Parent:WaitForChild("BallReplicationLod"))

local BallSimulationService = {
	Name = "BallSimulationService",
}

local COLLISION_SURFACES = table.freeze({
	PaddleHitbox = true,
	Paddle = true,
	Main = true,
	Net = true,
	PrecisionBarrier = true,
})

local TABLETOP_NORMAL_MIN_DOT = nil -- Omitted: authored tuning/presentation value.
local CONTACT_WINDOW_BASE = nil -- Omitted: authored tuning/presentation value.
local CONTACT_WINDOW_MAX = nil -- Omitted: authored tuning/presentation value.
local CONTACT_FUTURE_TOLERANCE = nil -- Omitted: authored tuning/presentation value.
local CONTACT_PENDING_LIFETIME = nil -- Omitted: authored tuning/presentation value.
local CONTACT_NEAR_MISS_MARGIN = nil -- Omitted: authored tuning/presentation value.
local CONTACT_SWING_MAX_AGE = nil -- Omitted: authored tuning/presentation value.
local COLLISION_COOLDOWN = nil -- Omitted: authored tuning/presentation value.
local LOW_SPIN_SPARKLE_COLOR = nil -- Omitted: authored tuning/presentation value.
local HIGH_SPIN_SPARKLE_COLOR = nil -- Omitted: authored tuning/presentation value.

local function lerp(a, b, alpha)
	return a + ((b - a) * alpha)
end

local function isFiniteNumber(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function isFiniteVector3(value)
	return typeof(value) == "Vector3"
		and isFiniteNumber(value.X)
		and isFiniteNumber(value.Y)
		and isFiniteNumber(value.Z)
end

local function getPlayerKey(match, player)
	if player == match.player1 then
		return "Player1"
	elseif player == match.player2 then
		return "Player2"
	end
	return nil
end

local function getPaddleAndHitbox(match, playerKey)
	local paddle = playerKey == "Player1" and match.player1Paddle or match.player2Paddle
	if typeof(paddle) ~= "Instance" then
		return nil, nil
	end
	local hitbox = paddle:FindFirstChild("PaddleHitbox", true)
	if not (hitbox and hitbox:IsA("BasePart")) then
		return paddle, nil
	end
	return paddle, hitbox
end

local function isPlayer2PaddlePart(match, instance)
	local paddle = match and match.player2Paddle
	return typeof(paddle) == "Instance"
		and typeof(instance) == "Instance"
		and (instance == paddle or instance:IsDescendantOf(paddle))
end

local function getNetworkPing(player)
	local ok, value = pcall(function()
		return player:GetNetworkPing()
	end)
	return ok and math.clamp(tonumber(value) or 0, 0, 1) or 0
end

local function recordContactMetric(match, key)
	match._contactMetrics = match._contactMetrics or {}
	match._contactMetrics[key] = (match._contactMetrics[key] or 0) + 1
end
local SPECTATOR_BALL_CONFIG = RallyPerformance.SpectatorBall
local participantSnapshotRemote = nil
local spectatorBallRemote = nil
local matchService = nil
local spectatorTargetsByMatch = {}
local spectatorDistanceByMatch = {}
local spectatorTargetsRefreshedAt = 0

local function getMatchService()
	if matchService then
		return matchService
	end

	matchService = ServiceFramework.GetService("MatchService")
	return matchService
end

local function getParticipantSnapshotRemote()
	if participantSnapshotRemote then
		return participantSnapshotRemote
	end

	local eventService = ServiceFramework.GetService("EventService")
	local remotes = eventService:GetRoot()
	participantSnapshotRemote = remotes:WaitForChild("RallySnapshot")
	return participantSnapshotRemote
end

local function getSpectatorBallRemote()
	if spectatorBallRemote then
		return spectatorBallRemote
	end

	local eventService = ServiceFramework.GetService("EventService")
	local remotes = eventService:GetRoot()
	spectatorBallRemote = remotes:WaitForChild("RallySpectatorBall")
	return spectatorBallRemote
end

local function refreshSpectatorTargets(now, force)
	if not force and now < spectatorTargetsRefreshedAt then
		return
	end

	spectatorTargetsRefreshedAt = now + (1 / math.max(SPECTATOR_BALL_CONFIG.ObserverRefreshHz, 1))
	table.clear(spectatorTargetsByMatch)
	table.clear(spectatorDistanceByMatch)

	local activeMatches = {}
	for _, candidate in getMatchService():IterMatches() do
		local tableMain = candidate and candidate.table and candidate.table:FindFirstChild("Main")
		if candidate
			and candidate.gameStarted == true
			and candidate.ball
			and candidate.ball.Parent
			and tableMain
			and tableMain:IsA("BasePart")
		then
			table.insert(activeMatches, { Match = candidate, Position = tableMain.Position })
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		if not getMatchService():IsPlayerInActiveMatch(player) then
			local character = player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if rootPart and rootPart:IsA("BasePart") then
				local nearestMatch = nil
				local nearestDistance = math.huge
				for _, entry in ipairs(activeMatches) do
					local distance = (rootPart.Position - entry.Position).Magnitude
					if distance < nearestDistance then
						nearestMatch = entry.Match
						nearestDistance = distance
					end
				end
				if nearestMatch then
					local targets = spectatorTargetsByMatch[nearestMatch]
					if not targets then
						targets = {}
						spectatorTargetsByMatch[nearestMatch] = targets
					end
					table.insert(targets, player)
					spectatorDistanceByMatch[nearestMatch] = math.min(
						spectatorDistanceByMatch[nearestMatch] or math.huge,
						nearestDistance
					)
				end
			end
		end
	end
end

function BallSimulationService:ResetSharedBallReplication(match)
	if not match then return end
	match._spectatorBallNextReplicationAt = nil
	spectatorTargetsRefreshedAt = 0
	match._ballRaycastParams = nil
	match._ballRaycastParamsFor = nil
end

function BallSimulationService:GetRaycastParams(match)
	if not (match and match.ball) then
		return nil
	end
	if match._ballRaycastParams and match._ballRaycastParamsFor == match.ball then
		return match._ballRaycastParams
	end

	local params = RaycastParams.new()
	local outline = match.ball:FindFirstChild("Outline")
	local joinButtons = workspace:FindFirstChild("JoinButtons")
	local filterInstances = { workspace.Ignore, match.ball }
	if outline then
		table.insert(filterInstances, outline)
	end
	if joinButtons then
		table.insert(filterInstances, joinButtons)
	end
	params.FilterDescendantsInstances = filterInstances
	params.RespectCanCollide = true
	match._ballRaycastParams = params
	match._ballRaycastParamsFor = match.ball
	return params
end

-- Participants render their own authoritative stream. Lobby players receive
-- only the nearest active game's ball through an exact-player remote.
function BallSimulationService:SyncSharedBall(match, force)
	if not (match and match.ball and match.ball.Parent and typeof(match.ballCF) == "CFrame") then
		return false
	end

	local now = os.clock()
	refreshSpectatorTargets(now, force == true)
	local targets = spectatorTargetsByMatch[match]
	if not targets then
		match._spectatorBallNextReplicationAt = nil
		return false
	end

	local interval = BallReplicationLod.GetInterval(spectatorDistanceByMatch[match], SPECTATOR_BALL_CONFIG)
	if force ~= true and now < (match._spectatorBallNextReplicationAt or 0) then
		return false
	end
	match._spectatorBallNextReplicationAt = interval < math.huge and (now + interval) or nil

	local remote = getSpectatorBallRemote()
	for _, player in ipairs(targets) do
		if not getMatchService():IsPlayerInActiveMatch(player) then
			remote:FireClient(player, match.table, match.ballCF)
		end
	end
	return true
end

function BallSimulationService:IsCollisionSurface(instance)
	if not instance then
		return false
	end
	if COLLISION_SURFACES[instance.Name] == true then
		return true
	end
	return string.match(instance.Name, "^PrecisionBarrier_%d+$") ~= nil
end

function BallSimulationService:ConfigureMatchContact(match, config)
	if not match then
		return
	end
	config = config or {}
	match._contactConfig = {
		Padding = typeof(config.Padding) == "Vector3" and config.Padding or Vector3.new(0.5, 0.24, 0.78),
		NearMissMargin = math.clamp(tonumber(config.NearMissMargin) or CONTACT_NEAR_MISS_MARGIN, 0, 0.75),
		SampleSpacing = math.clamp(tonumber(config.SampleSpacing) or 0.18, 0.05, 0.5),
		MaxSteps = math.clamp(math.floor(tonumber(config.MaxSteps) or 24), 4, 48),
	}
	match._contactRevision = 0
	match._ballMotionRevision = 0
	match._ballSnapshotUrgent = false
	match._pendingContactClaims = {}
	match._contactClaimState = {}
	match._contactMetrics = {}
	match._lastResolvedCollisionName = nil
	BallContactResolver:SyncPaddleHistory(match)
end

function BallSimulationService:ResetMatchContact(match)
	if not match then
		return
	end
	match._contactRevision = (tonumber(match._contactRevision) or 0) + 1
	match._ballMotionRevision = (tonumber(match._ballMotionRevision) or 0) + 1
	match._ballSnapshotUrgent = true
	match._pendingContactClaims = {}
	match._lastResolvedCollisionName = nil
	BallContactResolver:SyncPaddleHistory(match)
end

function BallSimulationService:ShouldResolveCollision(match, hit, now)
	if not match or not hit then
		return false
	end

	local resolvedAt = tonumber(now) or tick()
	if resolvedAt - (tonumber(match.LastHitTick) or 0) > COLLISION_COOLDOWN then
		return true
	end

	-- The cooldown prevents a ray from repeatedly resolving against the same
	-- surface while the ball is being separated from it. It must not suppress a
	-- different surface: a low return can contact a paddle and reach the tabletop
	-- within the same 0.1-second window. Ignoring that Main hit advances the ball
	-- below the thin tabletop, where later rays cannot find it.
	local instance = hit.Instance
	return instance ~= nil and instance.Name ~= match._lastResolvedCollisionName
end

function BallSimulationService:RecordResolvedContact(match, source, hitInstance)
	if not match then
		return
	end
	match._contactRevision = (tonumber(match._contactRevision) or 0) + 1
	match._ballMotionRevision = (tonumber(match._ballMotionRevision) or 0) + 1
	match._ballSnapshotUrgent = true
	match._lastResolvedCollisionName = hitInstance and hitInstance.Name or nil
	recordContactMetric(match, source or "server_raycast")
end

function BallSimulationService:MarkMotionDiscontinuity(match)
	if not match then
		return
	end
	match._ballMotionRevision = (tonumber(match._ballMotionRevision) or 0) + 1
	match._ballSnapshotUrgent = true
end

function BallSimulationService:ConsumeUrgentSnapshot(match)
	if not match or match._ballSnapshotUrgent ~= true then
		return false
	end
	match._ballSnapshotUrgent = false
	return true
end

function BallSimulationService:BuildParticipantSnapshot(match, serverTime, trajectory)
	if not (match and match.player1Paddle and match.player2Paddle and match.ball) then
		return nil
	end
	trajectory = trajectory or {}
	local p1Pivot = match.player1Paddle:GetPivot()
	local p2Pivot = match.player2Paddle:GetPivot()
	return {
		tick = serverTime,
		ballPosition = match.ballPosition,
		ballVelocity = match.ballVelocity,
		ballAcceleration = trajectory.ballAcceleration or Vector3.zero,
		ballInitialVelocity = match.ballInitialVelocity,
		ballSpin = match.ballSpin,
		ballCF = match.ballCF,
		Player1Velocity = match.Player1Velocity,
		LastPlayer1Pos = p1Pivot.Position,
		LastPlayer1Rot = p1Pivot.Rotation,
		Player2Velocity = match.Player2Velocity,
		LastPlayer2Pos = p2Pivot.Position,
		LastPlayer2Rot = p2Pivot.Rotation,
		ballInPlay = match.ballInPlay,
		contactRevision = tonumber(match._contactRevision) or 0,
		motionRevision = tonumber(match._ballMotionRevision) or 0,
		spinSparkleRevision = tonumber(match._spinSparkleRevision) or 0,
		spinSparkleColor = match._spinSparkleColor,
		spinSparkleCount = match._spinSparkleCount,
	}
end

function BallSimulationService:PlaySpinSparkles(match, level, emitCount)
	if not (match and match.ball) then
		return
	end

	local color = LOW_SPIN_SPARKLE_COLOR:Lerp(HIGH_SPIN_SPARKLE_COLOR, math.clamp(tonumber(level) or 0, 0, 1))
	local count = math.clamp(math.floor(tonumber(emitCount) or 1), 1, 8)
	match._spinSparkleRevision = (tonumber(match._spinSparkleRevision) or 0) + 1
	match._spinSparkleColor = color
	match._spinSparkleCount = count

	local emitter = match.ball:FindFirstChild("Stars", true)
	if emitter and emitter:IsA("ParticleEmitter") then
		emitter.Color = ColorSequence.new(color)
		emitter:Emit(count)
	end
end

function BallSimulationService:SendParticipantSnapshot(match, serverTime, snapshot)
	if not (match and type(serverTime) == "number" and type(snapshot) == "table") then
		return false
	end

	local remote = getParticipantSnapshotRemote()
	for _, player in ipairs({ match.player1, match.player2 }) do
		if player then
			-- Ball state is disposable and buffered client-side. At 30 Hz this
			-- remains half the original 60 Hz stream without reliable queue buildup.
			remote:FireClient(player, serverTime, snapshot)
		end
	end

	return true
end

function BallSimulationService:SyncPaddleContactHistory(match)
	BallContactResolver:SyncPaddleHistory(match)
end

function BallSimulationService:RecordPaddleContactPose(match, playerKey)
	BallContactResolver:RecordPaddlePose(match, playerKey)
end

function BallSimulationService:UpdateSoloAIContactEligibility(match)
	-- Omitted: AI, assistance-policy, telemetry/reward or authored presentation glue.
end

function BallSimulationService:ShouldIgnoreSoloAIContact(match, hitInstance)
	-- Omitted: AI, assistance-policy, telemetry/reward or authored presentation glue.
end

function BallSimulationService:ResolveSweptPaddleContact(match, ballStart, ballEnd, ballRadius)
	local config = match and match._contactConfig or {}
	local options = match and match._contactSweepOptions
	if not options then
		options = {}
		if match then
			match._contactSweepOptions = options
		end
	end
	options.BallRadius = ballRadius
	options.Padding = config.Padding
	options.PaddingByPlayer = nil
	if typeof(config.Padding) == "Vector3" then
		options.PaddingByPlayer = {
			Player1 = config.Padding * getClientPaddleContactAssistScale(match, "Player1"),
			Player2 = config.Padding * getClientPaddleContactAssistScale(match, "Player2"),
		}
	end
	local fastReceiver = match and match.rallyPaceState and match.rallyPaceState.FastReceiver
	local fastPadding = fastReceiver and PlayerAssistService:GetFastReceiverPadding(match, fastReceiver) or nil
	if fastPadding and options.PaddingByPlayer then
		options.PaddingByPlayer[fastReceiver] += fastPadding
	end
	options.SampleSpacing = config.SampleSpacing
	options.MaxSteps = config.MaxSteps
	return BallContactResolver:ResolveServerSweep(match, ballStart, ballEnd, options)
end

function BallSimulationService:GetContactTimingWindow(match, playerKey, player)
	match._contactClaimState = match._contactClaimState or {}
	local state = match._contactClaimState[playerKey] or {}
	local ping = getNetworkPing(player)
	local previousPing = tonumber(state.LastPing) or ping
	local sampleJitter = math.abs(ping - previousPing)
	state.Jitter = ((tonumber(state.Jitter) or sampleJitter) * 0.8) + (sampleJitter * 0.2)
	state.LastPing = ping
	match._contactClaimState[playerKey] = state
	local assist = match and match.onboardingAssist
	local profile = PlayerAssistService:GetProfile(match, playerKey)
	local profileBonus = profile
		and (math.max(0, tonumber(PlayerAssistance.TimingWindowBonus) or 0) * math.clamp(tonumber(profile.Strength) or 0, 0, 1))
		or 0
	local onboardingBonus = playerKey == "Player1" and math.max(0, tonumber(assist and assist.TimingWindowBonus) or 0) or 0
	local fastStrength = PlayerAssistService:GetFastReceiverStrength(match, playerKey)
	local fastBonus = math.max(0, tonumber(RallyPaceConfig.FastAssistTimingBonus) or 0) * fastStrength
	local timingBonus = math.max(profileBonus, onboardingBonus) + fastBonus
	local window = math.clamp(
		CONTACT_WINDOW_BASE + ping + (state.Jitter * 2) + timingBonus,
		CONTACT_WINDOW_BASE,
		CONTACT_WINDOW_MAX + timingBonus
	)
	return window, ping, state
end

function BallSimulationService:ApplyOnboardingMagnetism(match, velocity, deltaTime)
	-- Omitted: AI, assistance-policy, telemetry/reward or authored presentation glue.
end

function BallSimulationService:ShapeOnboardingReturn(match, velocity)
	-- Omitted: AI, assistance-policy, telemetry/reward or authored presentation glue.
end

function BallSimulationService:ApplyContactClaim(matchService, player, matchId, payload)
	local match = self:GetMatchForClientHit(matchService, matchId)
	if not match or match.gameStarted ~= true or match._settled == true or type(payload) ~= "table" then
		return false
	end
	local playerKey = getPlayerKey(match, player)
	if not playerKey or match.ballInPlay ~= true then
		return false
	end

	local sequence = payload.sequence
	local observedAt = payload.observedAt
	if not isFiniteNumber(sequence) or sequence < 1 or sequence > 1e9 or sequence % 1 ~= 0 or not isFiniteNumber(observedAt) then
		return false
	end
	if not isFiniteVector3(payload.ballPosition)
		or not isFiniteVector3(payload.contactPosition)
		or typeof(payload.paddleCFrame) ~= "CFrame"
		or not isFiniteVector3(payload.paddleCFrame.Position)
		or not isFiniteVector3(payload.paddleCFrame.LookVector) then
		return false
	end

	local timingWindow, ping, state = self:GetContactTimingWindow(match, playerKey, player)
	if sequence <= (tonumber(state.LastSequence) or 0) then
		return false
	end
	state.LastSequence = sequence
	local receivedAt = os.clock()
	if receivedAt - (tonumber(state.LastReceivedAt) or 0) < (1 / 30) then
		recordContactMetric(match, "claim_rejected_rate")
		return false
	end
	state.LastReceivedAt = receivedAt

	local now = workspace:GetServerTimeNow()
	local age = now - observedAt
	if age < -CONTACT_FUTURE_TOLERANCE or age > timingWindow then
		recordContactMetric(match, "claim_rejected_time")
		return false
	end

	local snapshot, snapshotDifference = BallContactResolver:FindNearestSnapshot(match, observedAt)
	if not snapshot or snapshotDifference > math.min(timingWindow, 0.06) or snapshot.ballInPlay ~= true then
		recordContactMetric(match, "claim_rejected_snapshot")
		return false
	end
	if tonumber(snapshot.contactRevision) ~= (tonumber(match._contactRevision) or 0) then
		recordContactMetric(match, "claim_rejected_stale")
		return false
	end
	if type(match.getBallSide) ~= "function"
		or match:getBallSide(snapshot.ballPosition) ~= playerKey
		or match:getBallSide(match.ballPosition) ~= playerKey
		or match.sideTouchUsed == true then
		recordContactMetric(match, "claim_rejected_side")
		return false
	end

	local _, hitbox = getPaddleAndHitbox(match, playerKey)
	if not hitbox then
		return false
	end
	local expectedPaddleCF = BallContactResolver:GetSnapshotPaddleCFrame(match, snapshot, playerKey, hitbox)
	if not expectedPaddleCF then
		return false
	end

	local snapshotVelocity = typeof(snapshot.ballVelocity) == "Vector3" and snapshot.ballVelocity or Vector3.zero
	local ballTolerance = 0.55 + (snapshotVelocity.Magnitude * math.min(snapshotDifference, 0.03))
	if (payload.ballPosition - snapshot.ballPosition).Magnitude > ballTolerance
		or (payload.contactPosition - payload.ballPosition).Magnitude > 0.75 then
		recordContactMetric(match, "claim_rejected_ball")
		return false
	end

	-- The authored local swing moves the visible paddle by up to 0.7 studs. Network
	-- tolerance covers delivery delay, but is capped so a client cannot place a
	-- claimed paddle anywhere on its half of the court.
	local paddleTolerance = 0.95 + math.min((ping * 18) + ((tonumber(state.Jitter) or 0) * 12), 2.5)
	local snapshotPaddleDistance = (payload.paddleCFrame.Position - expectedPaddleCF.Position).Magnitude
	local currentPaddleDistance = (payload.paddleCFrame.Position - hitbox.CFrame.Position).Magnitude
	local snapshotLookMatch = math.abs(payload.paddleCFrame.LookVector:Dot(expectedPaddleCF.LookVector))
	local currentLookMatch = math.abs(payload.paddleCFrame.LookVector:Dot(hitbox.CFrame.LookVector))
	if math.min(snapshotPaddleDistance, currentPaddleDistance) > paddleTolerance
		or math.max(snapshotLookMatch, currentLookMatch) < 0.65 then
		recordContactMetric(match, "claim_rejected_paddle")
		return false
	end

	local contactConfig = match._contactConfig or {}
	if not (match.ball and match.ball:IsA("BasePart")) then
		return false
	end
	local ballRadius = math.clamp(math.min(match.ball.Size.X, match.ball.Size.Y, match.ball.Size.Z) * 0.5, 0.05, 1)
	local contactAssistScale = getClientPaddleContactAssistScale(match, playerKey)
	local claimPadding = typeof(contactConfig.Padding) == "Vector3"
		and contactConfig.Padding * contactAssistScale
		or contactConfig.Padding
	local fastPadding = PlayerAssistService:GetFastReceiverPadding(match, playerKey)
	if fastPadding and typeof(claimPadding) == "Vector3" then
		claimPadding += fastPadding
	end
	local strictHalfSize = BallContactResolver:GetExpandedHalfSize(hitbox, ballRadius, claimPadding)
	local missDistance = BallContactResolver:GetPointBoxDistance(payload.contactPosition, payload.paddleCFrame, strictHalfSize)
	local source = "client_claim"
	if missDistance > 1e-4 then
		local sample = match.playerSpinInput and match.playerSpinInput[playerKey]
		local profile = PlayerAssistService:GetProfile(match, playerKey)
		local profileSwingAge = profile and lerp(
			CONTACT_SWING_MAX_AGE,
			tonumber(PlayerAssistance.SwingMaxAge) or CONTACT_SWING_MAX_AGE,
			math.clamp(tonumber(profile.Strength) or 0, 0, 1)
		) or CONTACT_SWING_MAX_AGE
		local onboardingSwingAge = playerKey == "Player1"
			and math.max(CONTACT_SWING_MAX_AGE, tonumber(match.onboardingAssist and match.onboardingAssist.SwingMaxAge) or 0)
			or CONTACT_SWING_MAX_AGE
		local assistSwingAge = math.max(profileSwingAge, onboardingSwingAge)
		local recentSwing = type(sample) == "table"
			and sample.isSpinAssistHeld == true
			and type(sample.tick) == "number"
			and tick() - sample.tick <= assistSwingAge
		if not recentSwing then
			local history = match.playerSpinInputHistory and match.playerSpinInputHistory[playerKey]
			for index = type(history) == "table" and #history or 0, 1, -1 do
				local historicalSample = history[index]
				local sampleAge = type(historicalSample) == "table"
					and type(historicalSample.tick) == "number"
					and tick() - historicalSample.tick
					or math.huge
				if sampleAge > assistSwingAge then
					break
				end
				if type(historicalSample) == "table" and historicalSample.isSpinAssistHeld == true then
					recentSwing = true
					break
				end
			end
		end
		local toPaddle = expectedPaddleCF.Position - snapshot.ballPosition
		local inbound = toPaddle.Magnitude <= 1e-3 or snapshotVelocity:Dot(toPaddle.Unit) > -0.5
		local profileMargin = profile and lerp(
			CONTACT_NEAR_MISS_MARGIN,
			tonumber(PlayerAssistance.NearMissMargin) or CONTACT_NEAR_MISS_MARGIN,
			math.clamp(tonumber(profile.Strength) or 0, 0, 1)
		) or CONTACT_NEAR_MISS_MARGIN
		local fastStrength = PlayerAssistService:GetFastReceiverStrength(match, playerKey)
		local nearMissMargin = math.max(tonumber(contactConfig.NearMissMargin) or CONTACT_NEAR_MISS_MARGIN, profileMargin)
		nearMissMargin *= contactAssistScale
		nearMissMargin += (tonumber(RallyPaceConfig.FastAssistNearMissBonus) or 0) * fastStrength
		if missDistance > nearMissMargin or not recentSwing or not inbound then
			recordContactMetric(match, "claim_rejected_near_miss")
			return false
		end
		source = "near_miss"
	end

	match._pendingContactClaims = match._pendingContactClaims or {}
	match._pendingContactClaims[playerKey] = {
		Sequence = sequence,
		Revision = tonumber(match._contactRevision) or 0,
		ExpiresAt = os.clock() + CONTACT_PENDING_LIFETIME,
		Source = source,
		ClaimedPosition = payload.contactPosition,
	}
	recordContactMetric(match, source .. "_validated")
	return true
end

function BallSimulationService:ConsumePendingContactClaim(match, playerKey)
	local pendingByPlayer = match and match._pendingContactClaims
	local pending = pendingByPlayer and pendingByPlayer[playerKey]
	if not pending then
		return nil
	end
	pendingByPlayer[playerKey] = nil
	if os.clock() > pending.ExpiresAt
		or pending.Revision ~= (tonumber(match._contactRevision) or 0)
		or match.ballInPlay ~= true
		or match.sideTouchUsed == true then
		return nil
	end
	local _, hitbox = getPaddleAndHitbox(match, playerKey)
	if not hitbox then
		return nil
	end
	match._activationPointContacts = (tonumber(match._activationPointContacts) or 0) + 1
	local player = playerKey == "Player1" and match.player1 or match.player2
	-- Omitted: activation telemetry.
	local normal = hitbox.CFrame.LookVector
	if typeof(match.ballVelocity) == "Vector3" and match.ballVelocity:Dot(normal) > 0 then
		normal = -normal
	end
	return {
		Instance = hitbox,
		Normal = normal,
		Position = match.ballPosition,
		Source = pending.Source,
	}
end

-- `Main` is a box, so a ray can hit its vertical sides as well as its top.
-- Only a world-upward contact inside a horizontal face is a legal table bounce.
-- Do not assume the authored part's local +Y points upward: visually identical
-- courts may have an inverted Main axis (tables 13+ use this orientation).
-- Side contacts are faults and must never increment tableHits.
function BallSimulationService:IsLegalTabletopBounce(match, hit)
	if not match or not hit or not hit.Instance or hit.Instance.Name ~= "Main" then
		return false
	end

	local tableModel = match.table
	local tableMain = tableModel and tableModel:FindFirstChild("Main")
	if not (tableMain and tableMain:IsA("BasePart")) then
		return false
	end

	local impactPosition = typeof(hit.Position) == "Vector3" and hit.Position or tableMain.Position
	local localPosition = tableMain.CFrame:PointToObjectSpace(impactPosition)
	local halfSize = tableMain.Size * 0.5
	local onHorizontalFace = math.abs(localPosition.Y) >= (halfSize.Y - 0.35)
		and math.abs(localPosition.Y) <= (halfSize.Y + 0.35)
	local insideBounds = math.abs(localPosition.X) <= (halfSize.X + 0.2)
		and math.abs(localPosition.Z) <= (halfSize.Z + 0.2)

	if typeof(hit.Normal) ~= "Vector3" then
		-- Keep legacy collision results playable if a synthetic/fallback hit has
		-- no normal; only reject contacts we can positively identify as side hits.
		return onHorizontalFace and insideBounds
	end

	if hit.Normal:Dot(Vector3.yAxis) < TABLETOP_NORMAL_MIN_DOT then
		return false
	end

	return onHorizontalFace and insideBounds
end

function BallSimulationService:GetOffTableScorer(match, ballSide)
	if not match or (ballSide ~= "Player1" and ballSide ~= "Player2") then
		return nil
	end

	-- If the striker sends the ball out without crossing the net, the opponent
	-- wins the point. Paddle contact resets tableHits, so playerLastHit is needed
	-- to distinguish this fault from a shot that went out past the receiver.
	if match.playerLastHit == ballSide and (tonumber(match.tableHits) or 0) == 0 then
		return ballSide == "Player1" and "Player2" or "Player1"
	end

	if (tonumber(match.tableHits) or 0) == 1 then
		return ballSide == "Player1" and "Player2" or "Player1"
	end
	return ballSide
end

local function getQuestService()
	-- Omitted: AI, assistance-policy, telemetry/reward or authored presentation glue.
end

local function getPlayer(match, playerKey)
	local player = playerKey == "Player1" and match.player1 or playerKey == "Player2" and match.player2 or nil
	return typeof(player) == "Instance" and player:IsA("Player") and player or nil
end

function BallSimulationService:PlayPaddleFXHit(match, playerKey, hasSpin)
	-- Omitted: AI, assistance-policy, telemetry/reward or authored presentation glue.
end

function BallSimulationService:HasPaddleSpinSoundOverride(match, playerKey)
	-- Omitted: AI, assistance-policy, telemetry/reward or authored presentation glue.
end

function BallSimulationService:CaptureAcceptedClientHit(match, player)
	-- Omitted: AI, assistance-policy, telemetry/reward or authored presentation glue.
end

function BallSimulationService:RecordPaddleReturn(match, playerKey)
	-- Omitted: AI, assistance-policy, telemetry/reward or authored presentation glue.
end

function BallSimulationService:RecordPoint(match, scoringPlayerKey)
	-- Omitted: AI, assistance-policy, telemetry/reward or authored presentation glue.
end

function BallSimulationService:RecordRallyMilestones(match)
	-- Omitted: AI, assistance-policy, telemetry/reward or authored presentation glue.
end

function BallSimulationService:GetMatchForClientHit(matchService, matchId)
	if not matchService or type(matchService.GetMatch) ~= "function" then
		return nil
	end
	return matchService:GetMatch(matchId)
end

function BallSimulationService:ApplyClientHit(matchService, player, matchId, tickTime, payload, ping)
	local match = self:GetMatchForClientHit(matchService, matchId)
	if not match or type(match.updateClientHit) ~= "function" then
		return false
	end
	-- Only a participant of a live, un-settled match may submit a client hit. This
	-- rejects late events on a completed match and state submission from spectators
	-- or unrelated clients spoofing another court's id.
	if match.gameStarted ~= true or match._settled == true then
		return false
	end
	if player ~= match.player1 and player ~= match.player2 then
		return false
	end
	match:updateClientHit(player, tickTime, payload, ping)
	return true
end

return BallSimulationService
