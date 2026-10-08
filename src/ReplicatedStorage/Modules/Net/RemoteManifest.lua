-- Ball/network contracts only; unrelated authored endpoint inventory omitted.
local RemoteManifest = {}
RemoteManifest.Remotes = {
{
		path = "UpdatePaddlePosition",
		className = "RemoteEvent",
		direction = "ClientToServer",
		owner = "Rally/BallSimulationService",
		validation = "player is a live match participant, pose is a CFrame, spin intent is bounded",
	},
{
		path = "ServeBall",
		className = "RemoteEvent",
		direction = "ClientToServer",
		owner = "Rally/ServeService",
		validation = "player is serve owner, serve style is known",
	},
{
		path = "UpdateGameState",
		className = "RemoteEvent",
		direction = "Bidirectional",
		owner = "Rally/BallSimulationService",
		validation = "server snapshots and client hit reports",
	},
{
		path = "RallySnapshot",
		className = "UnreliableRemoteEvent",
		direction = "ServerToClient",
		owner = "Rally/BallSimulationService",
		validation = "server-authored disposable participant simulation snapshot",
	},
{
		path = "RallySpectatorBall",
		className = "UnreliableRemoteEvent",
		direction = "ServerToClient",
		owner = "Rally/BallSimulationService",
		validation = "nearest active match ball CFrame sent only to non-participant observer",
	},
{
		path = "RallyContactClaim",
		className = "RemoteEvent",
		direction = "ClientToServer",
		owner = "Rally/BallSimulationService",
		validation = "participant, monotonic sequence, RTT/jitter rewind window, snapshot revision, side, ball path, paddle pose, and gated near-miss intent",
	},
{
		path = "Ping",
		className = "RemoteFunction",
		direction = "ServerToClient",
		owner = "Rally/MatchService",
		validation = "latency probe only",
	}
}

function RemoteManifest:GetAll()
	return self.Remotes
end
return RemoteManifest
