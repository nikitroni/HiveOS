# HiveOS — Screenshots

This folder holds the real screenshots used by `README.md`, `README.ru.md` and the files under `docs/`. Until they are added, the documentation uses gray placeholders from [placehold.co](https://placehold.co).

## Required screenshots

All five screenshots are required. Save each one into **`docs/screenshots/`** with the exact file name below.

| File name | Full path | What it must show |
|---|---|---|
| `heartos_main.png` | `docs/screenshots/heartos_main.png` | The HeartOS control center main menu: title `=== HeartOS Control Center ===` and the buttons **Configure BeeOS**, **Configure LabOS**, **Configure Hive** and **LIBRARY**. |
| `beeos_hive_map.png` | `docs/screenshots/beeos_hive_map.png` | The BeeOS tech monitor with the hive list / detail and its live status colors: green = hive present, light gray = empty slot, yellow = selected. |
| `labos_breeding.png` | `docs/screenshots/labos_breeding.png` | The LabOS main monitor during a breeding run: cycle progress and the upgrade log. |
| `breeding_setup.png` | `docs/screenshots/breeding_setup.png` | The physical breeding setup in the world: breeding chamber, incubator, relay(s), the Just Dire Things clicker and the connected chests. |
| `hive_setup.png` | `docs/screenshots/hive_setup.png` | The physical wiring of a single hive: the hive block, its Block Reader and its redstone relay. |

## Format

- **Format:** PNG.
- **Resolution:** 1920×1080 recommended; any 16:9 size is fine. You may also capture at the monitor's native in-game proportions — just keep it readable.
- **Content:** capture the monitor (or the in-world blocks) filling most of the frame, with no chat or HUD covering the important parts.

## How to replace a placeholder

1. Take the screenshot in game.
2. Save it into `docs/screenshots/` using the exact file name from the table above.
3. Replace the matching `https://placehold.co/...` URL in the documentation with the relative path to the image.

Before:

```markdown
![HeartOS main menu](https://placehold.co/800x450/1e1e1e/ffffff?text=HeartOS+Main+Menu)
```

After:

```markdown
![HeartOS main menu](docs/screenshots/heartos_main.png)
```

Note the path prefix depends on the file you edit:

- In `README.md` and `README.ru.md` (repo root) use `docs/screenshots/<name>.png`.
- In files under `docs/` (e.g. `docs/setup.md`, `docs/systems.md`) use `screenshots/<name>.png`.

The project logo is already in place at `docs/logo.png` and is referenced by the README files, so no logo screenshot is needed.
