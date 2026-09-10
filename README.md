# Notification Center for Omarchy

A themed notification drawer with expandable app stacks, individual and bulk
dismissal, and links back to the sending application. Open it through Omarchy
IPC, or use the optional two-finger edge gesture helper.

> **Touchpad compatibility:** Edge swipes currently support only the
> **FTCS1012:00 2808:0251 Touchpad** (vendor `2808`, product `0251`). The helper
> also requires **UID/GID 1000**. Other touchpads are not supported by the
> current device selection code. The drawer can still be opened through IPC
> without the gesture helper. See [gesture setup and limitations](gestures/README.md).

This project targets the Omarchy Quickshell plugin system. The development
environment is Omarchy 4.0.3, Quickshell 0.3.1, and Qt 6.11.2. Other releases
have not been verified. It uses Omarchy's internal notification file format
and `qs.Commons` theme API, so upstream changes may require updates.

## Install the drawer

Requirements: Omarchy with its Quickshell shell and panel plugin support,
Python 3.9 or newer at `/usr/bin/python`, and the usual Omarchy application
tools (`hyprctl`, `xdg-open`, and `gtk-launch`) for opening notifications.
Python uses only the standard library.

Place this project's contents in
`~/.config/omarchy/plugins/lucas.notification-center/`, including `backend/`,
then enable it:

```sh
omarchy plugin validate ~/.config/omarchy/plugins/lucas.notification-center
omarchy plugin enable lucas.notification-center
omarchy-shell notification-center open
```

No separately installed history script is needed. The drawer prefers display
`eDP-1`, falling back to the first display. Escape, the close button, or clicking
outside the drawer closes it. Click a collapsed stack to expand it, then click
a notification to open it. Tab, Enter, and Space work on notification titles
and clear controls.

The optional gesture service is **specific to the FTCS1012:00 2808:0251
Touchpad and UID/GID 1000**. It is not required for opening the drawer through
IPC. See [gestures/README.md](gestures/README.md) for its build, installation,
limitations, and recovery instructions.

## Notification behavior

- Reads current and archived JSON files under
  `~/.local/state/omarchy/notifications/`; displays the newest 50 of the files
  scanned (at most 200 from each directory).
- Groups by the installed desktop application's identity, with a sender-name
  fallback. Notification bodies are converted to plain text.
- Keeps drawer dismissals in
  `~/.local/state/omarchy/notification-center-dismissed.json`. Clearing an item
  does not delete Omarchy's history or dismiss its live toast. Up to 4,096
  dismissed identifiers are retained.
- Opens supported explicit URLs, otherwise focuses a matching running app or
  launches its desktop entry. Arbitrary notification command hints are not
  executed. Archived notifications cannot replay unpersisted live actions.

The drawer does not collect telemetry. Opening a notification can launch an
application or browser. Notification contents remain in Omarchy's local store.

## IPC

```sh
omarchy-shell notification-center open
omarchy-shell notification-center close
omarchy-shell notification-center status
omarchy-shell notification-center suspend
omarchy-shell notification-center resume
```

`suspend` closes the drawer and disconnects gesture input; `resume` reconnects
it. Developer IPC also provides `expandApp(key)`, `preview(progress)`, and
`previewData(base64JsonGroups)`. Preview data is a development tool, not an
isolated data store: clear and activation controls still use the real backend.

To unload the drawer, remove its entry from the `plugins` array in
`~/.config/omarchy/shell.json`. Disable the optional service separately if
installed. Existing notification history and dismissal state are preserved.

## Development

```sh
make test       # Python, headless QML, and pure C++ gesture tests
make test-runtime # Real Quickshell store with a temporary synthetic backend
make validate   # Installed Omarchy manifest checks and QML syntax
make helper     # Build the optional helper; does not install or run it
```

Tests require a C++20 compiler and Qt 6 Declarative/QtTest tools. The runtime
smoke test also requires the Quickshell executable. Override
`QT_BIN`, `PYTHON`, or `CXX` when needed. Building the helper also requires
`pkg-config` and libevdev development files. See
[CONTRIBUTING.md](CONTRIBUTING.md) for architecture and manual verification.

## License

Project sources are available under the [MIT License](LICENSE). Omarchy,
Quickshell, Qt, and libevdev are external dependencies with their own licenses.
Local development skills are excluded from this project's distribution.
