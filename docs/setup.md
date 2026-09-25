[English](setup.md) | [Русский](setup.ru.md)

# HiveOS — Setup Guide

This guide walks you from three bare computers to a working hive farm. It assumes you are playing **All the Mods 10 (ATM10)** with ComputerCraft: Tweaked, Advanced Peripherals and the bee mods installed.

- [Overview](#overview)
- [Step 1 — Place the three computers](#step-1--place-the-three-computers)
- [Step 2 — Connect the modems](#step-2--connect-the-modems)
- [Step 3 — Install HiveOS on each terminal](#step-3--install-hiveos-on-each-terminal)
- [Step 4 — Choose the role](#step-4--choose-the-role)
- [Step 5 — Run the wizard on HeartOS](#step-5--run-the-wizard-on-heartos)
- [Step 6 — Verify everything works](#step-6--verify-everything-works)

## Overview

HiveOS uses three independent terminals:

| Role | Folder | Purpose |
|---|---|---|
| **HeartOS** | `HeartOS/` | Control center: writes and pushes configs, hosts the hive map. |
| **BeeOS** | `BeeOS/` | Reads the hives and shows them on the tech / info monitors. |
| **LabOS** | `LabOS/` | Runs breeding and genetics on the lab monitor and four button monitors. |

Each terminal is just a computer with a wired modem; all coordination happens over rednet.

## Step 1 — Place the three computers

Place three computers where they are convenient:

- **HeartOS** near where you manage the base, with its own monitor.
- **BeeOS** near the hive area, with one tech monitor and any number of info monitors.
- **LabOS** near the breeding and genetics setup, with its main monitor and the four button monitors.

Advanced computers are recommended for the extra colors, but normal computers work.

## Step 2 — Connect the modems

Connect a **Wired Modem + Networking Cable** to each terminal (any free side works). HiveOS finds the modem automatically, so there is nothing to configure for the network itself.

Make sure every terminal's modem is connected to the same Networking Cable. If the modem is not found, the terminal prints a startup error on screen.

## Step 3 — Install HiveOS on each terminal

On **each** computer, run:

```bash
wget run https://raw.githubusercontent.com/nikitroni/HiveOS/main/installer.lua
```

The installer downloads the files for the role you choose into the computer's local folder.

## Step 4 — Choose the role

When prompted, enter one of:

- `BeeOS`
- `LabOS`
- `HeartOS`

Run the installer once per computer with the matching role. After installing BeeOS and LabOS, reboot them:

```bash
reboot
```

HeartOS can be started the same way.

## Step 5 — Run the wizard on HeartOS

On HeartOS, open the **Configure BeeOS**, **Configure LabOS** and **Configure Hive** menus in turn. Each one starts a chat-driven wizard:

1. It scans for the required peripherals (monitors, chests, readers, relays, crafters, incubator).
2. It asks you to confirm each found device in chat.
3. When finished it saves the config locally and pushes it to the target terminal over rednet.

While HeartOS edits a config, the target terminal is frozen (it shows the wait screen) so nothing runs mid-edit. If a terminal is busy with a job, the wizard refuses and tells you to wait.

## Step 6 — Verify everything works

- **BeeOS** should leave its wait screen and show the hive list on the tech monitor.
- **LabOS** should show its main lab screen and light up the button monitors.
- **HeartOS** should list the configured devices under View, and the **Hive Map** screen should show each hive as a green 2-digit cell.

If a terminal keeps waiting, re-check that its config was pushed and that every scanned peripheral still exists and is connected.

## Screenshots

> These are placeholders. Replace each URL with a real capture saved as `docs/screenshots/<name>.png` — see [`screenshots/README.md`](screenshots/README.md).

**HeartOS main menu** — the control center landing screen with the Configure / Library buttons.

![HeartOS main menu](https://placehold.co/800x450/1e1e1e/ffffff?text=HeartOS+Main+Menu)

**BeeOS hive map** — the hive list with live status colors.

![BeeOS hive map](https://placehold.co/800x450/1e1e1e/ffffff?text=BeeOS+Hive+Map)

**LabOS breeding** — the lab screen during a breeding run.

![LabOS breeding](https://placehold.co/800x450/1e1e1e/ffffff?text=LabOS+Breeding)
