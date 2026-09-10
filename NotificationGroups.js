.pragma library

// Groups and items are plain JSON objects supplied by backend/read_history.py.
// Return new groups so QML bindings observe optimistic dismissals.
function visibleGroups(groups, hiddenIds) {
    return groups.map(function(group) {
        return {
            key: group.key,
            app: group.app,
            icon: group.icon,
            items: group.items.filter(item => !hiddenIds[item.id])
        };
    }).filter(group => group.items.length > 0);
}

function itemIds(groups) {
    var ids = [];
    groups.forEach(group => group.items.forEach(item => ids.push(item.id)));
    return ids;
}

function itemCount(groups) {
    return groups.reduce((total, group) => total + group.items.length, 0);
}
