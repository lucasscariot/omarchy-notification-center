import QtQuick
import QtTest
import ".."

TestCase {
    id: testCase

    function test_clear_button_keyboard_and_pointer() {
        var button = createTemporaryObject(buttonComponent, testCase);
        verify(button !== null);
        clickSpy.target = button;
        clickSpy.clear();
        verify(waitForRendering(button));
        button.forceActiveFocus();
        keyClick(Qt.Key_Return);
        keyClick(Qt.Key_Space);
        mouseClick(button, button.width / 2, button.height / 2);
        compare(clickSpy.count, 3);
    }
    function test_single_notification_activates_directly() {
        var item = {
            id: "1",
            timestamp: 0,
            summary: "Only one",
            body: ""
        };
        var stack = createTemporaryObject(stackComponent, testCase, {
            group: {
                key: "app",
                app: "App",
                icon: "",
                items: [item]
            }
        });
        verify(stack !== null);
        activationSpy.target = stack;
        activationSpy.clear();
        stack.openItem(item);
        compare(activationSpy.count, 1);
    }
    function test_stack_expands_before_activating() {
        var first = {
            id: "1",
            timestamp: 0,
            summary: "First",
            body: "Body"
        };
        var stack = createTemporaryObject(stackComponent, testCase, {
            group: {
                key: "app",
                app: "App",
                icon: "",
                items: [first,
                    {
                        id: "2",
                        timestamp: 1,
                        summary: "Second",
                        body: ""
                    }
                ]
            }
        });
        verify(stack !== null);
        toggleSpy.target = stack;
        activationSpy.target = stack;
        toggleSpy.clear();
        activationSpy.clear();
        stack.openItem(first);
        compare(toggleSpy.count, 1);
        compare(activationSpy.count, 0);
        verify(waitForRendering(stack));
        var collapsedHeight = stack.implicitHeight;
        stack.expanded = true;
        tryVerify(function () { return stack.implicitHeight > collapsedHeight; });
        stack.openItem(first);
        compare(activationSpy.count, 1);
        compare(activationSpy.signalArguments[0][0].id, "1");
    }

    height: 800
    name: "NotificationComponents"
    visible: true
    when: windowShown
    width: 400

    Component {
        id: stackComponent

        AppStack {
            width: 350
        }
    }
    Component {
        id: buttonComponent

        ClearButton {
            label: "Clear all"
        }
    }
    SignalSpy {
        id: toggleSpy

        signalName: "toggleRequested"
    }
    SignalSpy {
        id: activationSpy

        signalName: "activateRequested"
    }
    SignalSpy {
        id: clickSpy

        signalName: "clicked"
    }
}
