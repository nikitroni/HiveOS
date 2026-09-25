[English](roadmap.md) | [Русский](roadmap.ru.md)

# HiveOS — Roadmap

- [v1.0 — current release](#v10--current-release)
- [v1.x — ongoing improvements](#v1x--ongoing-improvements)
- [v2.0 — goal](#v20--goal)

## v1.0 — current release

Everything below already works:

- **Three terminals** — HeartOS (control), BeeOS (hives), LabOS (lab) coordinated over rednet.
- **Hive map** — paginated grid of up to 96 hives with live status colors and a relay signalling cycle.
- **Breeding** — automated 3-cycle breeding chamber + incubator flow with a Just Dire Things automation pulse.
- **Genetics** — gene reading, missing-gene production through a redstone relay, and bee upgrades in crafters + incubator up to elite values.
- **Provisioning wizard** — chat-driven scanning and configuration of every peripheral, pushed to the target terminal.
- **Installer** — one-command setup (`wget run`) with role selection.

## v1.x — ongoing improvements

Between v1.0 and v2.0 the focus is on flexible, small quality-of-life improvements: clearer diagnostics, better error messages, more forgiving configuration and general polish. This list grows as feedback comes in.

## v2.0 — goal

The main goals for the next major version:

- **Portable management terminal instead of chat** — a handheld device for controlling and monitoring the farm, especially useful on servers where the chat is noisy and shared.
- **Universal hive map** — a hive map that adapts to any physical layout the user builds, instead of the current fixed three-group arrangement.
