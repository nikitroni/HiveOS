# Pocket control for HiveOS

## Scope

- Continue on `upgrade`; preserve the existing roles and main branch.
- Add `3/` as the PocketOS source and `PocketOS/` as the publication mirror.
- Only `3/startup.lua` and `3/pocket_main.lua` are part of PocketOS. Existing unrelated files in `4/` remain untouched and unpublished.
- Installer offers PocketOS as role 4 and can install from a chosen branch.
- HeartOS opens both wired and wireless/Ender modems; the Pocket Computer opens its wireless/Ender upgrade.
- HeartOS bridges notifications from BeeOS and LabOS to the Pocket Computer; private owner chat is the fallback while the Pocket Computer is offline.
- The Pocket Computer pairs to HeartOS with a code shown on the HeartOS monitor.
- HeartOS wizard text and replies move to the Pocket Computer. A single unambiguous device needs no per-device confirmation; the complete config still needs one final confirmation.
- The PocketOS home screen starts BeeOS, LabOS, and hive-map create/edit flows (choices 1-6).

## Protocol

- Protocol label: `hiveos.pocket.v1`.
- HeartOS hosts `heartos/main` and persists the paired Pocket Computer ID in CraftOS settings.
- Pocket sends `{type='pair', code=...}`; Heart responds `{type='paired', ok=boolean, reason?}`.
- A paired Pocket sends `{type='hello'}` periodically and on reconnect; Heart refreshes liveness and responds `paired`.
- Heart sends `{type='message', kind=string, text=string, seq=number|nil}`. A non-nil sequence marks a prompt that accepts one reply.
- Pocket replies `{type='reply', seq=number, text=string}`. Heart validates sender ID, pairing, current sequence, and one-time consumption.
- BeeOS and LabOS may send `{type='notify', role=string, text=string}` to Heart for routing. No public-chat fallback.
- Rednet sender IDs are not cryptographic identity; pairing prevents accidental control, not a malicious computer that spoofs protocol traffic.

## Work ownership

- Pocket agent: `3/startup.lua`, `3/pocket_main.lua`.
- Wizard agent: `2/config_wizard.lua`, `2/hive_wizard.lua`.
- Installer agent: `installer.lua`, user documentation.
- Coordinator: Heart bridge, shared chat transport, Bee/Lab notification routing, `deploy.bat`, integration tests and review.

## Acceptance

- Pairing fails with a wrong code and succeeds with the code displayed on HeartOS.
- A second Pocket Computer cannot submit a wizard answer.
- Duplicate or stale replies cannot advance a later prompt.
- Pocket reconnects after closing and reopening, and missed alerts fall back to private chat.
- BeeOS, LabOS and HeartOS alerts display in PocketOS while it is online.
- All wizard instructions, choices, cancellation and results are usable without game chat.
- Config saves only after final confirmation; unrelated 4/ files never enter PocketOS publication.
- Installer role 4 contains startup and all required scripts.
- Lua checks and mocked protocol tests pass before in-game handoff.

## Local checkpoint

- Source and mirrors prepared for the four roles. The pre-existing `4/1.lua` and `.dfpwm` are excluded from PocketOS.
- Automated checks cover pairing, foreign and duplicate replies, liveness, private fallback, and wizard scan decisions.
- The feature remains unverified in ATM10 8.3 until the user's test-world run.
- Publishing the `upgrade` branch remains a separate step after review.
