#include "gesture.hpp"
#include <cerrno>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <fcntl.h>
#include <filesystem>
#include <libevdev/libevdev-uinput.h>
#include <libevdev/libevdev.h>
#include <poll.h>
#include <signal.h>
#include <stdexcept>
#include <string>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

static volatile sig_atomic_t stopping = 0;
static void stop(int) { stopping = 1; }
static double now() {
    return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch())
        .count();
}
static void require(bool ok, const char *message) {
    if (!ok)
        throw std::runtime_error(message);
}

struct Touchpad {
    int fd = -1;
    libevdev *dev = nullptr;
    libevdev_uinput *virt = nullptr;
    bool grabbed = false;
    ~Touchpad() {
        release();
        if (dev)
            libevdev_free(dev);
        if (fd >= 0)
            close(fd);
    }
    void release() {
        if (grabbed)
            libevdev_grab(dev, LIBEVDEV_UNGRAB);
        grabbed = false;
        if (virt)
            libevdev_uinput_destroy(virt);
        virt = nullptr;
    }
    void openDevice() {
        for (const auto &p : std::filesystem::directory_iterator("/dev/input")) {
            if (!p.path().filename().string().starts_with("event"))
                continue;
            int candidate = open(p.path().c_str(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
            if (candidate < 0)
                continue;
            libevdev *d = nullptr;
            if (libevdev_new_from_fd(candidate, &d) < 0) {
                close(candidate);
                continue;
            }
            // This laptop's physical touchpad only. Never capture keyboards,
            // mice, or the virtual device created by this helper.
            bool match = libevdev_get_id_vendor(d) == 0x2808 &&
                         libevdev_get_id_product(d) == 0x0251 &&
                         std::string(libevdev_get_name(d)) == "FTCS1012:00 2808:0251 Touchpad" &&
                         libevdev_has_event_code(d, EV_ABS, ABS_MT_SLOT) &&
                         libevdev_has_property(d, INPUT_PROP_BUTTONPAD);
            if (match) {
                fd = candidate;
                dev = d;
                return;
            }
            libevdev_free(d);
            close(candidate);
        }
        throw std::runtime_error("physical FTCS1012 touchpad not found");
    }
    void acquire() {
        // The proxy is a clone of the touchpad, including its input properties
        // and absolute axis ranges. No key remapping or pointer acceleration.
        require(libevdev_get_num_slots(dev) > 0, "touchpad has no MT slots");
        const std::string name = libevdev_get_name(dev);
        libevdev_set_name(dev, "Omarchy Edge Touchpad");
        int result = libevdev_uinput_create_from_device(dev, LIBEVDEV_UINPUT_OPEN_MANAGED, &virt);
        libevdev_set_name(dev, name.c_str());
        require(result == 0, "cannot create virtual touchpad");
        require(libevdev_grab(dev, LIBEVDEV_GRAB) == 0, "cannot grab physical touchpad");
        grabbed = true;
    }
    std::vector<Finger> fingers() {
        std::vector<Finger> f;
        auto x = libevdev_get_abs_info(dev, ABS_MT_POSITION_X);
        auto y = libevdev_get_abs_info(dev, ABS_MT_POSITION_Y);
        require(x && y && x->resolution > 0 && y->resolution > 0, "touchpad needs axis resolution");
        for (int slot = 0; slot < libevdev_get_num_slots(dev); ++slot) {
            int id = libevdev_get_slot_value(dev, slot, ABS_MT_TRACKING_ID);
            if (id < 0)
                continue;
            const bool palm = libevdev_has_event_code(dev, EV_ABS, ABS_MT_TOOL_TYPE) &&
                              libevdev_get_slot_value(dev, slot, ABS_MT_TOOL_TYPE) == MT_TOOL_PALM;
            f.push_back(
                {id,
                 double(libevdev_get_slot_value(dev, slot, ABS_MT_POSITION_X) - x->minimum) /
                     x->resolution,
                 double(libevdev_get_slot_value(dev, slot, ABS_MT_POSITION_Y) - y->minimum) /
                     y->resolution,
                 palm});
        }
        return f;
    }
    void forward(const std::vector<input_event> &events) {
        for (const auto &e : events)
            require(libevdev_uinput_write_event(virt, e.type, e.code, e.value) == 0,
                    "virtual touchpad write failed");
    }
    void syncIdle() {
        // Swallowed gestures can change the hardware's current MT slot and
        // axis values. Restore an idle snapshot, otherwise the next contact
        // could be assigned to a stale slot on the virtual touchpad.
        auto write = [&](unsigned type, unsigned code, int value) {
            require(libevdev_uinput_write_event(virt, type, code, value) == 0, "idle sync failed");
        };
        for (int slot = 0; slot < libevdev_get_num_slots(dev); ++slot) {
            write(EV_ABS, ABS_MT_SLOT, slot);
            for (unsigned code = ABS_MT_TOUCH_MAJOR; code <= ABS_MT_TOOL_Y; ++code)
                if (libevdev_has_event_code(dev, EV_ABS, code))
                    write(EV_ABS, code, libevdev_get_slot_value(dev, slot, code));
        }
        write(EV_ABS, ABS_MT_SLOT, libevdev_get_current_slot(dev));
        for (unsigned code = 0; code < ABS_MT_SLOT; ++code)
            if (libevdev_has_event_code(dev, EV_ABS, code))
                write(EV_ABS, code, libevdev_get_event_value(dev, EV_ABS, code));
        for (unsigned code = 0; code <= KEY_MAX; ++code)
            if (libevdev_has_event_code(dev, EV_KEY, code))
                write(EV_KEY, code, libevdev_get_event_value(dev, EV_KEY, code));
        write(EV_SYN, SYN_REPORT, 0);
    }
};

int main(int argc, char **argv) {
    if (argc != 2 || std::string(argv[1]) != "1000") {
        std::fprintf(stderr, "Usage: edge-notifications-helper 1000\n");
        return 2;
    }
    signal(SIGTERM, stop);
    signal(SIGINT, stop);
    signal(SIGPIPE, SIG_IGN);
    const char *path = "/run/omarchy-edge-notifications/socket";
    int server = -1, client = -1;
    try {
        Touchpad pad;
        pad.openDevice();
        const auto *x = libevdev_get_abs_info(pad.dev, ABS_MT_POSITION_X);
        require(x && x->resolution > 0, "touchpad X axis has no resolution");
        const double width = double(x->maximum - x->minimum) / x->resolution;
        Gesture gesture;
        gesture.width = width;
        server = socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
        require(server >= 0, "socket failed");
        sockaddr_un address{};
        address.sun_family = AF_UNIX;
        std::strncpy(address.sun_path, path, sizeof(address.sun_path) - 1);
        unlink(path); // fixed root-owned runtime directory, never a user path
        require(bind(server, reinterpret_cast<sockaddr *>(&address), sizeof(address)) == 0,
                "bind failed");
        require(chown(path, 0, 1000) == 0 && chmod(path, 0660) == 0, "socket permissions failed");
        require(listen(server, 1) == 0, "listen failed");
        double heartbeat = 0;
        bool ready = false;
        std::string commands;
        std::vector<input_event> frame, pending;
        auto disconnect = [&] {
            pad.release();
            if (client >= 0)
                close(client);
            client = -1;
            ready = false;
            commands.clear();
            frame.clear();
            pending.clear();
            gesture = Gesture{};
            gesture.width = width;
        };
        auto sendEvent = [&](const char *kind, double progress) {
            char out[160];
            int n = std::snprintf(out, sizeof(out), "{\"event\":\"%s\",\"progress\":%.5f}\n", kind,
                                  progress);
            if (send(client, out, n, MSG_DONTWAIT | MSG_NOSIGNAL) != n)
                disconnect();
        };
        auto process = [&] {
            const auto f = pad.fingers();
            bool clicked = libevdev_get_event_value(pad.dev, EV_KEY, BTN_LEFT) ||
                           libevdev_get_event_value(pad.dev, EV_KEY, BTN_RIGHT);
            auto d = gesture.frame(f, now(), clicked);
            if (d.flow == Decision::HOLD) {
                pending.insert(pending.end(), frame.begin(), frame.end());
                require(pending.size() < 32768, "candidate buffer exceeded");
            } else if (d.flow == Decision::PASS) {
                pad.forward(pending);
                pending.clear();
                pad.forward(frame);
            } else {
                pending.clear();
                if (d.event)
                    sendEvent(d.event, d.progress);
                if (pad.grabbed && f.empty())
                    pad.syncIdle();
            }
            frame.clear();
        };
        std::fprintf(
            stderr,
            "Ready: %.1f mm touchpad; raw input is grabbed only while panel heartbeat is healthy\n",
            width);
        while (!stopping) {
            pollfd fds[] = {{server, POLLIN, 0}, {client, POLLIN, 0}, {pad.fd, POLLIN, 0}};
            if (poll(fds, 3, 16) < 0) {
                if (errno == EINTR)
                    continue;
                throw std::runtime_error("poll failed");
            }
            if (fds[0].revents & POLLIN) {
                int c = accept4(server, nullptr, nullptr, SOCK_NONBLOCK | SOCK_CLOEXEC);
                if (c >= 0) {
                    ucred cred{};
                    socklen_t size = sizeof(cred);
                    if (client >= 0 || getsockopt(c, SOL_SOCKET, SO_PEERCRED, &cred, &size) < 0 ||
                        cred.uid != 1000)
                        close(c);
                    else {
                        client = c;
                        heartbeat = now();
                        sendEvent("connected", 0);
                    }
                }
            }
            if (client >= 0 && fds[1].revents & (POLLERR | POLLHUP))
                disconnect();
            if (client >= 0 && fds[1].revents & POLLIN) {
                char buffer[512];
                ssize_t n = recv(client, buffer, sizeof(buffer), MSG_DONTWAIT);
                if (n <= 0)
                    disconnect();
                else {
                    commands.append(buffer, n);
                    if (commands.size() > 4096)
                        disconnect();
                    while (client >= 0 && commands.find('\n') != std::string::npos) {
                        auto eol = commands.find('\n');
                        auto line = commands.substr(0, eol);
                        commands.erase(0, eol + 1);
                        if (line == "ping") {
                            heartbeat = now();
                            ready = true;
                        } else if (line == "closed") {
                            gesture.opened = false;
                        } else if (line == "opened") {
                            gesture.opened = true;
                        } else {
                            disconnect();
                            break;
                        }
                    }
                }
            }
            if (client >= 0 && now() - heartbeat > 1.5)
                disconnect();
            // Drain events even while inactive so libevdev always knows current
            // contacts. Acquire only with every finger lifted and no button held.
            if (fds[2].revents & (POLLERR | POLLHUP))
                throw std::runtime_error("touchpad disconnected");
            if (fds[2].revents & POLLIN) {
                input_event e{};
                int status;
                while ((status = libevdev_next_event(pad.dev, LIBEVDEV_READ_FLAG_NORMAL, &e)) >=
                       0) {
                    require(status != LIBEVDEV_READ_STATUS_SYNC,
                            "input overrun; restarting without grab");
                    if (pad.grabbed) {
                        frame.push_back(e);
                        if (e.type == EV_SYN && e.code == SYN_REPORT)
                            process();
                    }
                }
                require(status == -EAGAIN, "touchpad read failed");
            }
            if (pad.grabbed && gesture.state == Gesture::CANDIDATE && now() - gesture.t0 > .14 &&
                frame.empty())
                process();
            if (client >= 0 && ready && !pad.grabbed && pad.fingers().empty() &&
                !libevdev_get_event_value(pad.dev, EV_KEY, BTN_LEFT) &&
                !libevdev_get_event_value(pad.dev, EV_KEY, BTN_RIGHT)) {
                pad.acquire();
                sendEvent("ready", 0);
            }
        }
        disconnect();
        close(server);
        unlink(path);
    } catch (const std::exception &e) {
        std::fprintf(stderr, "edge notifications: %s (%s)\n", e.what(), std::strerror(errno));
        if (client >= 0)
            close(client);
        if (server >= 0)
            close(server);
        return 1;
    }
}
