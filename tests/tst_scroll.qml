import QtQuick
import QtTest
import ".."

TestCase {
    id: test
    name: "NotificationScrolling"
    width: 430
    height: 500
    visible: true
    when: windowShown
    Component {
        id: viewComponent
        NotificationList {
            width: 400
            height: 480
        }
    }
    function test_wheel_over_notification_content() {
        var groups = [];
        for (var i = 0; i < 20; i++)
            groups.push({
                key: String(i),
                app: "App " + i,
                icon: "",
                items: [
                    {
                        id: String(i),
                        timestamp: 0,
                        summary: "A notification",
                        body: "Details of this notification"
                    }
                ]
            });
        var view = createTemporaryObject(viewComponent, test, {
            model: groups
        });
        verify(waitForRendering(view));
        wait(50);
        verify(view.contentHeight > view.height);
        mouseWheel(view, 150, 110, 0, -18, Qt.NoButton);
        tryVerify(function () {
            return view.contentY >= 20;
        }, 1000, "A low-delta wheel event must move at least 20 px, got " + view.contentY);
        var previous = view.contentY;
        mouseWheel(view, 150, 110, 0, 18, Qt.NoButton);
        tryVerify(function () {
            return view.contentY < previous;
        });
        mouseWheel(view, 150, 110, 0, 120000, Qt.NoButton);
        tryCompare(view, "contentY", view.originY);
        mouseWheel(view, 150, 110, 0, -120000, Qt.NoButton);
        wait(50);
        verify(view.contentY <= view.originY + view.contentHeight - view.height + 1);
    }
}
