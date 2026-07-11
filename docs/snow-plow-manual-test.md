# Snow Plow Smoke Test Procedure

Use this procedure after every Snow Plow code change, build/deploy run, or failed gameplay test. Record the FS25 savegame, vehicle, route markers, and exact log lines for failures.

## Preconditions

- FS25 is fully exited before installing a new build.
- Only one UltraDrive/AutoDrive artifact is active in the FS25 mods folder, preferably `FS25_UltraDrive.zip`.
- Savegame has an AutoDrive route network with named map markers.
- Test vehicle has AutoDrive enabled and a compatible front snow tool attached.
- Optional: attach a salt spreader or other snow-service tool to confirm activation remains safe.

## Build / Install Smoke Check

- [ ] `FS25_UltraDrive.zip` was built or downloaded successfully.
- [ ] Before copying or launching, inspect the archive by content and confirm it contains `scripts/Utils/RecoveryManeuver.lua`, the `register.lua` source line for that file, profile marker `snowPlowReverseLiftForwardLower`, and `ADRecoveryManeuver:new` wiring in both `SnowPlowDriveToStartTask.lua` and `SnowPlowLoopTask.lua`.
- [ ] Record the feature branch and commit represented by the archive under test; do not identify a build by timestamp or filename alone.
- [ ] `FS25_UltraDrive.zip` was copied to the FS25 mods folder.
- [ ] FS25 starts without `Lua call stack` entries.
- [ ] FS25 log shows AutoDrive version `3.0.1.2`.
- [ ] No missing l10n messages appear for Snow Plow mode, speed, route errors, or money service labels.
- [ ] No savegame XML schema error appears for `AutoDrive#snowPlowMarkers`.

## HUD Smoke Check

- [ ] Mode selector shows Snow Plow Loop with the snowflake icon.
- [ ] Snow Plow HUD shows exactly three route rows:
  - primary destination
  - Place 2
  - Place 3
- [ ] All three route rows use the location-pin icon style.
- [ ] The route rows do not overlap the bottom control buttons.
- [ ] Place 2 and Place 3 are hidden when leaving Snow Plow mode.
- [ ] Only the active Snow Plow target row is green.
- [ ] While driving to the route start, the primary destination row is green.
- [ ] During loop driving, the green row advances to the next target: Place 2, Place 3, then primary destination.
- [ ] Road speed control changes Snow Plow speed while in Snow Plow mode.
- [ ] Field speed control remains independent.

## Route Selection Cases

Use real marker names in notes.

- [ ] One selected marker refuses to start and reports `missingMultiStopMarkers`.
- [ ] Two selected markers create `A -> B -> A`.
- [ ] Three selected markers create `A -> B -> C -> A`.
- [ ] Duplicate selected markers are ignored instead of creating repeated stops.
- [ ] Invalid route leaves the HUD in Snow Plow mode so markers can be corrected.
- [ ] Valid route drives to the first selected marker before beginning the loop.
- [ ] Valid route repeats until the loop counter or manual stop ends the job.

## Snow Tool / Driving Cases

- [ ] Starting Snow Plow lowers compatible snow tools.
- [ ] Starting Snow Plow turns on compatible powered tools.
- [ ] Manual stop deactivates snow tools.
- [ ] Raise-on-stop enabled raises compatible tools after stop.
- [ ] Raise-on-stop disabled leaves compatible tools lowered after stop.
- [x] Drive-to-start recovery logs `caller=SnowPlowDriveToStartTask` and completes the exact visual sequence: blower down, reverse straight 0.5 m, full stop, raise and dwell for 3000 ms before verifying raised, move straight forward 1.0 m, full stop, lower and dwell for 3000 ms before verifying lowered, then continue toward the original route start. Verified twice on July 11 near Field 110.
- [x] Loop recovery logs `caller=SnowPlowLoopTask`, completes the same exact visual sequence, and resumes toward the same active target without reinstalling or resetting the loop path. Verified during the first active loop on July 11; log returned `STATE_RECOVERY -> STATE_DRIVING`.
- [x] When the blower is already lowered at recovery start, the profile takes the fast path: it begins with `reverseWithToolDown` and does not issue or dwell on an unnecessary initial lower transition. Verified for both callers on July 11.
- [ ] Automated/source-contract coverage confirms that when the blower is not initially lowered, recovery stops first, issues the lower command, and remains in `verifyInitiallyLowered` for at least 3000 ms before reversing. Treat this as diagnostic-only during live testing unless a controlled setup can safely produce that initial state.
- [x] The 3000 ms physical dwell applies before checking raising and final lowering; an early state report does not advance the runner before the dwell expires. July 11 phase timestamps show each verified transition advanced approximately three seconds after entering its verification phase. The initially-not-lowered branch remains automated/diagnostic coverage.
- [ ] Measure the raise/lower dwell with a visible stopwatch or video timestamps. Current phase logs show phase entry and terminal result but do not timestamp verification success, so logs alone do not prove the 3000 ms dwell.
- [x] During raise and lower recovery phases, the tractor stops applying drive force while the front linkage moves. Observed in both caller scenarios on July 11.
- [x] Recovery command logs report `method=handleLowerImplementEvent` for a tractor-mounted tool. Verified with Tornado 252 on July 11.
- [ ] Any runner `FAILED` or `ABORTED` result stops AutoDrive immediately. For a running maneuver that fails, confirm the structured line identifies the phase and runtime reason. For an abort, record `abortedByCaller` or the caller-supplied reason such as `taskAbort`.
- [ ] Three-attempt policy counts completed recovery maneuvers followed by renewed stalls: after three `SUCCEEDED` maneuvers each followed by another detected stall, AutoDrive stops on the next detection instead of starting a fourth maneuver.
- [ ] If the tractor gets sideways on a bridge while driving to the first selected marker, it does not spin in place for more than one recovery cycle.
- [ ] Snow Plow speed override applies during drive-to-start and loop driving.
- [ ] Switching back to Drive To Destination restores normal speed behavior.

## Payment Cases

- [ ] Snow plow service income appears in the normal money-change HUD under the clock.
- [ ] Money label reads `Snow plow service`.
- [ ] Partial work accrues during slow loops from AutoDrive driver wages plus tracked motorized fuel usage, including helper auto-fuel diesel charges.
- [ ] Debug payment lines include `wageCost`, `fuelCost`, and `margin=15%`.
- [ ] Pending pay settles on loop completion.
- [ ] Pending pay settles on manual route stop.
- [ ] No Snow Plow payment toast appears in the warning/issue notification area.

## Log Evidence To Capture

After each recovery attempt, search:

```powershell
Select-String -LiteralPath "$env:USERPROFILE\Documents\My Games\FarmingSimulator2025\log.txt" -Pattern 'RecoveryManeuver','Snow plow','SnowPlow','missingMultiStop','invalidMultiStopLoop','snowPlowMarkers','Lua call stack','Error:','Warning:' -Context 2,5
```

Expected useful Snow Plow lines include:

```text
Snow plow route request: markerCount=...
Snow plow segment 1/2: A(id=...) -> B(id=...)
Snow plow segment 1/2 ok: A(id=...) -> B(id=...) waypoints=...
Snow plow multi-stop loop invalid: waypoints=... start=... end=...
Snow plow route failed: reason=...
Snow loop selected: ...
RecoveryManeuver start profile=snowPlowReverseLiftForwardLower caller=SnowPlowDriveToStartTask attempt=...
RecoveryManeuver phase profile=snowPlowReverseLiftForwardLower phase=reverseWithToolDown ...
RecoveryManeuver phase profile=snowPlowReverseLiftForwardLower phase=stopBeforeRaise ...
RecoveryManeuver phase profile=snowPlowReverseLiftForwardLower phase=raiseTools ...
RecoveryManeuver phase profile=snowPlowReverseLiftForwardLower phase=verifyRaised ...
RecoveryManeuver phase profile=snowPlowReverseLiftForwardLower phase=forwardWithToolsRaised ...
RecoveryManeuver phase profile=snowPlowReverseLiftForwardLower phase=stopBeforeLower ...
RecoveryManeuver phase profile=snowPlowReverseLiftForwardLower phase=lowerTools ...
RecoveryManeuver phase profile=snowPlowReverseLiftForwardLower phase=verifyLowered ...
RecoveryManeuver succeeded profile=snowPlowReverseLiftForwardLower caller=SnowPlowDriveToStartTask attempt=...
SnowPlowDriveToStartTask:update recovery finished destination=...
RecoveryManeuver start profile=snowPlowReverseLiftForwardLower caller=SnowPlowLoopTask attempt=...
RecoveryManeuver succeeded profile=snowPlowReverseLiftForwardLower caller=SnowPlowLoopTask attempt=...
SnowPlowLoopTask:update recovery finished
RecoveryManeuver failed profile=snowPlowReverseLiftForwardLower phase=... reason=... elapsed=... attempt=... distance=...
Snow plow service pending: $... elapsed=... distance=... wageCost=... fuelCost=...
Snow plow service paid: +$... reason=... elapsed=... distance=... wageCost=... fuelCost=... margin=15%
```

When reporting a failure, include:

- FS25 savegame number.
- Vehicle name.
- Selected route markers in visible order.
- Whether the tractor moved, stopped, or switched mode.
- Screenshot of the HUD if layout or controls are involved.
- Relevant Snow Plow log lines from the command above.
- Runner caller, phase, terminal reason, elapsed time, attempt number, and measured movement distance.
- Whether the profile took the already-lowered fast path or performed `stopBeforeInitialLower`, `ensureLowered`, and `verifyInitiallyLowered`.

Start rejection:

```text
invalidProfile
```

`invalidProfile` is returned by `start()` before the runner enters `RUNNING`. It produces no runner terminal status and no `RecoveryManeuver failed` line; the calling task can log the rejected start.

Runtime `FAILED` reasons are exactly:

```text
movementTimeout
stopTimeout
actionUnsupported
actionError
verificationTimeout
verificationError
```

Runtime failures should preserve their accompanying `phase=...`; do not translate them into the former task-specific movement/tool timeout messages.

Runtime `ABORTED` reasons are `abortedByCaller` by default or a caller-supplied reason such as `taskAbort`. Preserve the abort reason and phase from the runner's structured abort line.

## Safe End Procedure

- [ ] Stop the AutoDrive task before leaving the test vehicle.
- [ ] Exit the save without saving and return to the FS25 desktop launcher/menu.
- [ ] Exit FS25 completely and confirm `FarmingSimulator2025Game.exe` is no longer running.
- [ ] In `log.txt`, locate the final `Used Start Parameters` marker and review only that latest launch segment for `RecoveryManeuver`, `SnowPlow`, `Error:`, `Warning:`, and `Lua call stack`.

## Regression Checks

- [ ] Normal Drive To Destination still drives at user-selected road speed.
- [ ] Normal load/unload destination rows still show their original icons.
- [ ] Courseplay HUD can coexist without overlapping the AutoDrive Snow Plow route rows.
- [ ] Save/reload keeps selected Snow Plow markers without Lua errors.
- [ ] Multiplayer warning state remains unchanged; no new stream/read/write errors appear.
