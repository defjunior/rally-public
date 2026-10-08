# Rally ball and networking source

A narrow private source showcase, not the full Rally game.

- `Ball.lua`: original prototype integration/bounce/rotation code. Retained for source inspection, not presented as working physics.
- `Services/Rally/BallSimulationService.lua`: ball/contact and participant/spectator snapshot interfaces and implementation excerpt. AI contact policy, onboarding assistance, reward/telemetry and authored presentation/tuning are excluded with named stubs/comments.
- `BallContactResolver.lua`: swept paddle contact, pose history and snapshot lookup.
- `BallReplicationLod.lua`: observer-distance replication-frequency policy driven by external config.
- `Net/RemoteBridge.lua` and `EventService.lua`: client path lookup/wrappers and remote-folder/instance setup. `RemoteManifest.lua` is narrowed to seven ball/network endpoint contracts.

## What this shows

The selected systems separate ball/contact work from transport and remote discovery. Participant snapshots and observer replication are distinct interfaces; a manifest makes endpoint ownership visible. Manifest validation text is documentation, not proof that every handler enforces it. RemoteBridge itself is not authorization or rate limiting.

## Limits

Prototype Ball.lua contains known source defects: `_index` rather than `__index`, `self.elasticity - normalVelocity` mixes a number/vector, and its ray filter includes a module table. These are preserved rather than silently fixed. No runnable/production-ready claim is made.

The service excerpt needs ServiceFramework, Logger, player-assistance/performance/pace config, match runtime and original court/asset/remote hierarchy. Authored tuning is deliberately nil; named policy stubs do not supply valid behavior. This tree cannot run the full simulation by itself. Roblox collision, replication, security and performance have not been tested here.

Matchmaking, economy, AI/learning/strategy, coaching/dialogue, authored content, assets, secrets and full game bootstrap are out. Originals were not edited except their owner-requested switch to private.

See `source-manifest.json` for live comparisons and hashes. This new repo did not import original git history. Private, no license, no public release pending. Review current files and full extraction history before any future release.
