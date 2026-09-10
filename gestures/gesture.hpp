#pragma once
#include <algorithm>
#include <cmath>
#include <vector>

struct Finger {
    int id;
    double x, y;
    bool palm = false;
};
struct Decision {
    enum Flow { HOLD, PASS, DROP } flow = PASS;
    const char *event = nullptr;
    double progress = 0;
};

// Coordinates are millimetres, so sensitivity is independent of hardware DPI.
// Only a fresh contact at the right edge can open the drawer. All fingers
// must lift before a completed/rejected gesture can be reconsidered.
class Gesture {
  public:
    enum State { IDLE, CANDIDATE, NORMAL, DRAG, DRAIN } state = IDLE;
    bool opened = false;
    double width = 120, x0 = 0, y0 = 0, t0 = 0, progress = 0;
    double lastX = 0, lastT = 0, velocity = 0, base = 0;
    double singleX = 0, singleY = 0;
    std::vector<int> ids;

    Decision frame(const std::vector<Finger> &f, double now, bool button = false) {
        if (state == DRAIN) {
            if (f.empty())
                state = IDLE;
            return {Decision::DROP};
        }
        if (state == NORMAL) {
            if (f.empty())
                state = IDLE;
            return {};
        }
        if (state == IDLE) {
            if (f.empty())
                return {};
            if (button || f.size() > 2 || (!opened && f.front().x < width * .82)) {
                state = NORMAL;
                return {};
            }
            state = CANDIDATE;
            t0 = now;
            ids.clear();
            singleX = f.front().x;
            singleY = f.front().y;
        }
        if (state == CANDIDATE) {
            bool valid = !button && !f.empty() && f.size() <= 2;
            for (auto &p : f)
                valid &= !p.palm && (opened || p.x >= width * .82);
            if (!valid || now - t0 > .14) {
                state = f.empty() ? IDLE : NORMAL;
                return {};
            }
            if (f.size() < 2) {
                // Wait for a second finger only while the first is resting.
                // Once it starts pointing, flush immediately and pass through
                // the rest of this contact. Holding moving one-finger frames
                // until the 140 ms timeout causes cursor lag and destroys the
                // event timing used by libinput's pointer acceleration.
                if (std::hypot(f[0].x - singleX, f[0].y - singleY) >= .15) {
                    state = NORMAL;
                    return {};
                }
                return {Decision::HOLD};
            }
            const double x = (f[0].x + f[1].x) / 2, y = (f[0].y + f[1].y) / 2;
            if (ids.empty()) {
                ids = {f[0].id, f[1].id};
                x0 = x;
                y0 = y;
                return {Decision::HOLD};
            }
            if (ids != std::vector<int>{f[0].id, f[1].id}) {
                state = NORMAL;
                return {};
            }
            const double dx = x - x0, dy = y - y0;
            if (std::abs(dy) > 1.5 && std::abs(dy) >= std::abs(dx)) {
                state = NORMAL;
                return {};
            }
            const double directional = opened ? dx : -dx;
            if (directional < -1.5) {
                state = NORMAL;
                return {};
            }
            if (directional < 1.5 || directional < std::abs(dy) * 1.5)
                return {Decision::HOLD};
            state = DRAG;
            base = opened ? 1 : 0;
            lastX = x;
            lastT = now;
            velocity = 0;
            progress = std::clamp(base - dx / 38.0, 0.0, 1.0);
            return {Decision::DROP, "start", progress};
        }
        if (state == DRAG) {
            const bool same = f.size() == 2 && !button && !f[0].palm && !f[1].palm &&
                              ids == std::vector<int>{f[0].id, f[1].id};
            if (!same) {
                const bool cancelled = f.size() > 2 || button;
                bool target = cancelled ? base > .5 : progress >= .5;
                if (!cancelled && now - lastT < .12 && std::abs(velocity) > 2.0)
                    target = velocity > 0;
                opened = target;
                progress = target ? 1 : 0;
                state = f.empty() ? IDLE : DRAIN;
                return {Decision::DROP, "finish", progress};
            }
            const double x = (f[0].x + f[1].x) / 2;
            if (now > lastT)
                velocity = .6 * velocity + .4 * (lastX - x) / (38.0 * (now - lastT));
            lastX = x;
            lastT = now;
            progress = std::clamp(base - (x - x0) / 38.0, 0.0, 1.0);
            return {Decision::DROP, "update", progress};
        }
        return {};
    }
};
