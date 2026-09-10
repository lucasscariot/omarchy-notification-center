#include "gesture.hpp"
#include <cassert>
#include <iostream>
int main() {
    using D = Decision;
    auto f = [](double x, double y = 20) { return std::vector<Finger>{{1, x, y}, {2, x, y + 10}}; };
    Gesture g;
    assert(g.frame(f(60), 0).flow == D::PASS);    // ordinary middle scrolling
    assert(g.frame(f(110), .01).flow == D::PASS); // never activate halfway
    g.frame({}, .02);
    assert(g.frame(f(110), 1).flow == D::HOLD);
    assert(g.frame(f(110, 24), 1.01).flow == D::PASS); // vertical edge scrolling
    g.frame({}, 1.02);
    g.frame(f(110), 2);
    assert(std::string(g.frame(f(106), 2.01).event) == "start");
    auto d = g.frame(f(85), 2.05);
    assert(d.progress > .6 && d.progress < .7);
    g.frame(f(85), 2.3); // pause, no fling
    d = g.frame({}, 2.5);
    assert(d.progress == 1 && g.opened);
    g.frame(f(50), 3); // swipe right to close from anywhere
    assert(g.frame(f(54), 3.01).event);
    g.frame(f(80), 3.1);
    assert(g.frame({}, 3.3).progress == 0 && !g.opened);
    g.frame(f(110), 4);
    g.frame(f(106), 4.01);
    g.frame(f(108), 4.3);
    assert(g.frame({}, 4.5).progress == 0); // reverse/cancel partial opening
    assert(g.frame({{1, 110, 20}}, 5).flow == D::HOLD);
    assert(g.frame({{1, 110, 20}}, 5.15).flow == D::PASS); // single finger timeout
    g.frame({}, 5.2);
    auto three = f(110);
    three.push_back({3, 110, 40});
    assert(g.frame(three, 6).flow == D::PASS); // workspace swipe passes through
    g.frame({}, 6.2);
    assert(g.frame(f(110), 7, true).flow == D::PASS); // clicks pass through
    g.frame({}, 7.1);
    g.frame(f(110), 8);
    g.frame(f(105), 8.01);
    assert(g.frame(three, 8.02).progress == 0);    // third finger cancels
    assert(g.frame(f(100), 8.03).flow == D::DROP); // swallow until all lift
    g.frame({}, 8.1);
    assert(g.frame(f(50), 8.2).flow == D::PASS);
    for (bool open : {false, true}) {
        Gesture pointer;
        pointer.opened = open;
        const double x = open ? 50 : 110;
        assert(pointer.frame({{1, x, 20}}, 10).flow == D::HOLD);
        assert(pointer.frame({{1, x + .2, 20}}, 10.008).flow == D::PASS);
        assert(pointer.frame({{1, x + 1, 20}}, 10.016).flow == D::PASS);
        assert(pointer.frame({{1, x + 5, 20}}, 10.024).flow == D::PASS);
        pointer.frame({}, 10.1);
        // A stationary first finger can still be joined by a second finger.
        pointer.frame({{1, x, 20}}, 11);
        assert(pointer.frame(f(x), 11.06).flow == D::HOLD);
        assert(pointer.frame(f(x + (open ? 4 : -4)), 11.07).event);
    }
    Gesture vertical;
    vertical.opened = true;
    vertical.frame({{1, 50, 20}}, 12);
    assert(vertical.frame({{1, 50, 20.2}}, 12.008).flow == D::PASS);
    std::cout << "PASS: edge recognition, normal scroll, single/three fingers, clicks, progress, "
                 "reversal, close, cancellation\n";
}
