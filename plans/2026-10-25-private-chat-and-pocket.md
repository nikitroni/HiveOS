# Private notifications and mobile HeartOS wizard

## Agreed direction

- Work on the local `upgrade` branch; preserve `main`.
- Keep the three existing roles and their intended behavior.
- Replace public chat output with private notifications.
- Move HeartOS wizard prompts and answers to a mobile terminal.
- Reduce repeated confirmations when connecting many peripherals.
- Commit each substantial milestone, then hand it over for in-game testing.
- Do not publish or merge before the user's test feedback and publication instruction.
- Environment: ATM10 8.3, separate test world with computer folders linked directly to `0/1/2`.
- Branch switching does not isolate ignored runtime sources from the running test world.

## Decisions pending

- Notification recipient: configured owner or operation initiator; obtain the owner's in-game name if applicable.
- Exact mobile computer item, proposed Advanced Wireless Pocket Computer.
- Proposed interaction: accept an unambiguous device automatically, ask when multiple candidates exist, and confirm the complete configuration once before saving.

## Milestones

1. Private notifications across all three roles. No public fallback on missing recipient or delivery failure. During the transition, accept wizard replies only from the intended player.
2. Pair a mobile client with HeartOS and carry wizard prompts, choices, cancellation, and results over a session-bound protocol. HeartOS remains responsible for scanning its attached peripherals and saving configs.
3. Reduce confirmations and provide a final editable summary. Preserve explicit confirmation for replacement of existing configuration.
4. Extend installation for the mobile client and verify upgrade-branch installation independently of main.

## Execution and review

- Resolve recipient and device questions before dependent runtime edits.
- Define notification settings and session contracts centrally before delegating role-specific changes.
- Coordinator owns integration, mobile protocol, deployment checkpoints, and final review.
- Agents may own disjoint BeeOS, LabOS, and HeartOS files once contracts are defined.
- Existing deploy script pushes automatically. Local milestone commits must not invoke that push path; prepare a local-only checkpoint workflow before runtime commits.
- Preserve existing user modifications to `.gitignore` and do not commit them incidentally.

## Acceptance checks

- A second player sees no HiveOS notifications or wizard messages.
- A second player's chat replies cannot advance the active wizard.
- Offline or unset recipient never causes public broadcast.
- Mobile reconnect or duplicate reply cannot apply a step twice or overwrite another session.
- One clearly identified device requires no extra yes/no dialogue.
- Ambiguous device detection provides a choice instead of guessing.
- Cancellation leaves the previous configuration intact and restores the target terminal's running state.
- Each milestone has its own commit and an explicit in-game checklist.

## API evidence

- AP 0.8 uses `sendMessage(message, { player = name, ... })` for private delivery.
- AP 0.7 exposes `sendMessageToPlayer(message, username, ...)`.
- Check the installed API before selecting a compatibility path; never fall back to a public send.
- References: https://docs.advanced-peripherals.de/0.8/peripherals/chat_box/ and https://docs.advanced-peripherals.de/0.7/peripherals/chat_box/.
