# Contributing

Keep refactors separate from behavior changes. Add regression coverage for
changed notification or gesture behavior, then run `make test` and
`make validate` on an Omarchy development system.

## Code map

| File | Responsibility |
| --- | --- |
| `Panel.qml` | Drawer layout, gesture socket, open/close state, and IPC |
| `NotificationStore.qml` | History subprocesses, serialized clear queue, optimistic hiding, activation |
| `NotificationGroups.js` | Pure group filtering, counting, and ID collection |
| `AppStack.qml` | App header, stack decoration, and expansion behavior |
| `NotificationCard.qml` | One notification's content and interaction signals |
| `ClearButton.qml` | Shared mouse and keyboard clear control |
| `backend/read_history.py` | Read/normalize/group notifications, atomic dismissal persistence, app activation |
| `gestures/gesture.hpp` | Pure gesture recognition in millimetres |
| `gestures/helper.cpp` | Optional libevdev proxy and authenticated local socket |

The UI consumes groups shaped as
`{key, app, icon, items: [{id, timestamp, summary, body, ...}]}`. Timestamps
are milliseconds since the Unix epoch. The backend retains desktop identity,
aliases, and destination in each item for activation. The backend re-reads
history on activation, so the UI never supplies a command to execute.

Clears hide items immediately and are serialized through one subprocess.
Hidden IDs mask stale history responses. A failed clear removes its IDs from
the mask and refreshes history. Keep this ordering intact when changing I/O.
Activation waits briefly after closing the drawer so focus can be released.

## Verification

Python tests use temporary notification stores and mock app launches. QML
tests use a deterministic theme and a stub for Quickshell icon lookup, since
the real Quickshell plugin is embedded in its executable. They exercise
group filtering, expansion, activation signals, and keyboard/mouse clearing.
The pure C++ tests do not open input devices. `make helper` compiles the real
proxy with warnings treated as errors but does not validate physical input.
`make test-runtime` runs the real Quickshell notification store with a synthetic
backend in a temporary directory. It checks queued clear ordering, rollback
after a failed clear, activation error reporting, and paths containing spaces.
It does not read your notification history or activate real applications.
The overlay itself requires Wayland and is covered by the manual checks below.

Before a release, verify on a running Omarchy shell:

1. Open an empty drawer, then test one notification and a multi-item app stack.
2. Expand/collapse; clear one item, one app, and all items. Reopen the drawer
   and confirm cleared items stay hidden after archival.
3. Test app focus, app launch, an explicit link, and an unavailable app.
4. Check Escape, outside clicks, Tab/Enter/Space, scrolling, and theme changes.
   Open on one workspace, switch to another, then close: the current workspace
   must stay selected. Also check Escape after a rapid close/reopen during the
   closing animation. Keep the layer keyboard-interactive until it unmaps;
   setting its focus mode to `None` during the animation can restore an old
   workspace on Hyprland.
   `python3 tests/check_workspace.py` checks the IPC-close case in a live session
   and restores the starting workspace. This opt-in check is excluded from
   `make test` because it manipulates the desktop.
5. If changing the optional helper, test ordinary pointer movement, scrolling,
   clicks, three-finger gestures, partial/reversed swipes, and service recovery
   on the supported physical touchpad. Keep a terminal available for stopping
   the service.

Format QML with Qt's `qmlformat` and C++ with `clang-format` using the checked-in
style. Do not commit notification data, screenshots containing private
messages, local agent tooling, binaries, or machine-specific backups.

## Release checks

Confirm rights to contributed sources under the project's MIT license before
publishing. Set up the public Git repository and issue tracker, run the checks
above, and state the tested Omarchy/Quickshell versions. Keep the hardware and
UID restriction prominent while the gesture helper remains device-specific.
