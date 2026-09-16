#include <QGuiApplication>
#include <QPointingDevice>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickView>
#include <QWheelEvent>
#include <QEventLoop>
#include <QTimer>
#include <cmath>
#include <iostream>

static void waitEvents(int ms) {
    QEventLoop loop;
    QTimer::singleShot(ms, &loop, &QEventLoop::quit);
    loop.exec();
}

// Qt Quick Test's mouseWheel() supplies angle deltas only. Replay real pixel
// deltas and touchpad phases through the window to cover the other input path.
int main(int argc, char **argv) {
    QGuiApplication app(argc, argv);
    QQuickView view;
    view.engine()->addImportPath("tests/imports");
    view.setSource(QUrl::fromLocalFile("tests/TouchpadScroll.qml"));
    waitEvents(200);
    if (view.status() != QQuickView::Ready)
        return 2;
    view.show();
    waitEvents(100);
    auto *list = view.rootObject();
    QPointingDevice pad("replay touchpad", 42, QInputDevice::DeviceType::TouchPad,
                        QPointingDevice::PointerType::Finger,
                        QInputDevice::Capability::Position, 5, 0);
    auto send = [&](int pixel, int angle, Qt::ScrollPhase phase) {
        QWheelEvent event(QPointF(150, 110), QPointF(150, 110), QPoint(0, pixel),
                          QPoint(0, angle), Qt::NoButton, Qt::NoModifier, phase,
                          false, Qt::MouseEventSynthesizedBySystem, &pad);
        QCoreApplication::sendEvent(&view, &event);
        waitEvents(8);
    };
    auto y = [&] { return list->property("contentY").toDouble(); };
    send(0, 0, Qt::ScrollBegin);
    for (int i = 0; i < 20; ++i)
        send(-2, -16, Qt::ScrollUpdate);
    double distance = y();
    std::cout << "20 small trackpad events: " << distance << " px\n";
    if (distance < 200 || distance > 400)
        return 1;
    send(-2, -16, Qt::ScrollMomentum);
    if (y() <= distance)
        return 1;
    distance = y();
    send(2, 16, Qt::ScrollUpdate);
    if (y() >= distance)
        return 1;
    distance = y();
    send(0, 0, Qt::ScrollEnd);
    if (std::abs(y() - distance) > 0.1)
        return 1;
    send(10000, 80000, Qt::ScrollUpdate);
    if (std::abs(y() - list->property("originY").toDouble()) > 0.1)
        return 1;
    send(-10000, -80000, Qt::ScrollUpdate);
    double end = list->property("originY").toDouble()
        + list->property("contentHeight").toDouble() - list->height();
    if (std::abs(y() - end) > 0.1)
        return 1;
    std::cout << "PASS: trackpad speed, momentum, reversal, end phase and bounds\n";
}
