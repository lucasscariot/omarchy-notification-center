# Optional edge gesture helper

This companion is a hardware-specific prototype. It accepts **only UID 1000**,
sets socket access for **GID 1000**, and selects the physical **FTCS1012:00
2808:0251 Touchpad** by name, vendor/product ID, and buttonpad capabilities.
Changing these restrictions requires code review and physical-device tests;
the helper intentionally does not grab arbitrary input devices.

Place two fingers in the rightmost 18% of the touchpad and swipe left. Release
past halfway or flick to open. Swipe right to close, or reverse a partial
swipe to cancel. One-finger movement, center scrolling, vertical edge
scrolling, clicks, and three-finger gestures pass through.

## Build

From the project root, with a C++20 compiler, pkg-config, and libevdev headers:

```sh
make test-gesture helper
```

The pure recognition tests need no root access. The compiled helper does.
It creates a libevdev/uinput clone of the selected touchpad and grabs the
physical device only while an authenticated panel is connected, heartbeats
are healthy, and all fingers/buttons are lifted. A disconnect or 1.5-second
heartbeat timeout releases the grab and removes the virtual touchpad.

## Install on the supported system

Review the service file and confirm the device and UID/GID restrictions
above before installing. These commands install a root-owned binary; the
service never executes a user-writable binary from this checkout.

```sh
sudo install -D -m 0755 build/edge-notifications-helper /usr/local/libexec/edge-notifications-helper
sudo install -m 0644 gestures/omarchy-edge-notifications.service /etc/systemd/system/omarchy-edge-notifications.service
echo uinput | sudo tee /etc/modules-load.d/omarchy-edge-notifications.conf
sudo modprobe uinput
sudo systemctl daemon-reload
sudo systemctl enable --now omarchy-edge-notifications.service
```

Enable the drawer separately as described in the root README. When replacing
an installed helper, stop its service before copying the new binary, then
start it again.

## Recovery and removal

The keyboard is not intercepted. Stop the service from a terminal:

```sh
sudo systemctl disable --now omarchy-edge-notifications.service
```

For complete removal, also remove the installed service, helper binary, and
`/etc/modules-load.d/omarchy-edge-notifications.conf`, then run
`sudo systemctl daemon-reload`. Disabling the service is enough to stop input
interception; unloading the panel is a separate action.

## Protocol

The root-owned service directory contains
`/run/omarchy-edge-notifications/socket`. The service checks peer credentials
and accepts newline-delimited `ping`, `opened`, and `closed` commands only.
It emits JSON lines with an `event` of `connected`, `ready`, `start`, `update`,
or `finish`, and a numeric `progress` from zero to one. The panel sends a
heartbeat every 250 ms and retries connections every two seconds.

The helper does not record input, access notification contents, launch
applications, or use the network. Tests of its pure state machine do not
substitute for testing the proxy and recovery paths on real hardware.
