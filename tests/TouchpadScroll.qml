import QtQuick
import ".."

NotificationList {
    width: 400
    height: 480
    model: {
        var groups = [];
        for (var i = 0; i < 40; i++)
            groups.push({
                key: String(i),
                app: "Test " + i,
                icon: "",
                items: [
                    {
                        id: String(i),
                        timestamp: 0,
                        summary: "Test notification",
                        body: "Test detail"
                    }
                ]
            });
        return groups;
    }
}
