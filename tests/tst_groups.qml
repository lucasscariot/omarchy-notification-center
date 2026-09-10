import QtQuick
import QtTest
import "../NotificationGroups.js" as Groups

TestCase {
    function sample() {
        return [
            {
                key: "one",
                app: "One",
                icon: "one",
                items: [
                    {
                        id: "1"
                    },
                    {
                        id: "2"
                    }
                ]
            },
            {
                key: "two",
                app: "Two",
                icon: "two",
                items: [
                    {
                        id: "3"
                    }
                ]
            }
        ];
    }
    function test_clear_all_collects_every_item() {
        compare(Groups.itemIds(sample()), ["1", "2", "3"]);
        compare(Groups.itemCount(sample()), 3);
        compare(Groups.visibleGroups(sample(), {
            "1": true,
            "2": true,
            "3": true
        }), []);
    }
    function test_dismissal_preserves_order_and_source() {
        var source = sample();
        var result = Groups.visibleGroups(source, {
            "1": true,
            "3": true
        });
        compare(result.length, 1);
        compare(result[0].key, "one");
        compare(result[0].icon, "one");
        compare(result[0].items[0].id, "2");
        compare(source[0].items.length, 2);
        compare(source.length, 2);
    }
    function test_empty_history() {
        compare(Groups.itemIds([]), []);
        compare(Groups.itemCount([]), 0);
        compare(Groups.visibleGroups([], {}), []);
    }

    name: "NotificationGroups"
}
