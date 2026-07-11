# FS25_UltraDrive

UltraDrive is a custom Farming Simulator 25 fork of Stephan Schlosser's AutoDrive.
It keeps AutoDrive's route automation foundation and adds local UltraDrive-focused
features, packaging, and workflow improvements.

## Releases and version history

UltraDrive releases use tags in the form `ultradrive-v<version>`, where the
four-part version exactly matches `modDesc.xml`. Download the exact release
asset `FS25_UltraDrive.zip` from the corresponding public release.

The existing unprefixed `3.0.x.x` tags are legacy AutoDrive snapshots retained
for upstream provenance; they are not UltraDrive releases. The UltraDrive package version and AutoDrive baseline are separate facts;
the baseline does not control UltraDrive numbering. See Project Status for the
current package and baseline versions.

Install only one competing AutoDrive-family package. Before installing
`FS25_UltraDrive.zip`, move `FS25_AutoDrive.zip` out of the mods folder, delete it,
or rename it so the filename no longer ends in `.zip` (for example,
`FS25_AutoDrive.zip.disabled`). Then restart Farming Simulator 25.

## Project Status

- Public project name: UltraDrive
- FS25 mod package / zip name: `FS25_UltraDrive.zip`
- Current fork package version: `1.0.0.0`
- AutoDrive base version shown in game/log validation: `3.0.1.2`
- License: MIT
- Upstream project: <https://github.com/Stephan-S/FS25_AutoDrive>

UltraDrive intentionally keeps the internal Lua namespace, action identifiers,
route files, savegame XML nodes, and settings paths compatible with AutoDrive.
Do not rename persisted `AutoDrive` data unless a dedicated migration and backup
plan exists.

## What UltraDrive Adds

- UltraDrive package branding, icon, and player-facing HUD/settings titles.
- `FS25_UltraDrive.zip` build artifact for FS25's normal mod naming convention.
- Snow Plow Loop mode with dedicated route-marker selections.
- Two-stop and three-stop snow route chains:
  - `A -> B -> A`
  - `A -> B -> C -> A`
- Snow plow speed override independent of normal road and field speeds.
- Snow tool activation/lowering at route start, with optional raise-on-stop.
- Drive-to-start and loop stuck recovery for snow plow work.
- Snow plow service pay through the normal money-change HUD, including driver
  wages, tracked fuel, helper auto-fuel diesel costs, and service margin.

## Installation

Download or build the mod as:

```text
FS25_UltraDrive.zip
```

Place it in:

```text
Documents\My Games\FarmingSimulator2025\mods
```

Keep only one UltraDrive/AutoDrive package active for a savegame. Do not leave an
old `FS25_AutoDrive.zip` active next to `FS25_UltraDrive.zip`.

After replacing the mod zip, fully exit and relaunch Farming Simulator 25. A
save reload is not enough for all Lua, translation, texture, or `modDesc.xml`
changes.

## Save Compatibility

UltraDrive keeps existing AutoDrive persistence names by design. Existing route
networks and vehicle state may still appear in files such as:

```text
AutoDrive_config.xml
AutoDriveUsersData.xml
vehicles.xml <AutoDrive ...>
modSettings\FS25_AutoDrive
```

Back up savegame folders before large route, graph, or migration experiments.

## Documentation

Useful public documentation:

- `docs/snow-plow-manual-test.md`

## Credits

UltraDrive is based on AutoDrive for Farming Simulator 25 by Stephan Schlosser
and contributors:

<https://github.com/Stephan-S/FS25_AutoDrive>

The MIT license notice preserves Stephan Schlosser's upstream copyright and adds
the UltraDrive fork notice.
