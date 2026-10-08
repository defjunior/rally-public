--!strict

local BallReplicationLod = {}

export type Config = {
	NearObserverDistance: number,
	NearHz: number,
	FarHz: number,
	UnobservedHz: number,
}

function BallReplicationLod.GetHz(nearestObserverDistance: number?, config: Config): number
	if nearestObserverDistance == nil then
		return config.UnobservedHz
	end
	if nearestObserverDistance <= config.NearObserverDistance then
		return config.NearHz
	end
	return config.FarHz
end

function BallReplicationLod.GetInterval(nearestObserverDistance: number?, config: Config): number
	local hz = BallReplicationLod.GetHz(nearestObserverDistance, config)
	return hz > 0 and (1 / hz) or math.huge
end

return BallReplicationLod
