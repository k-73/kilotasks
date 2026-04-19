/*
    SPDX-FileCopyrightText: 2012-2016 Eike Hein <hein@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick 2.15

import org.kde.draganddrop 2.0

import org.kde.taskmanager 0.1 as TaskManager

import "code/tools.js" as TaskTools

Item {
    signal urlsDropped(var urls)

    property Item target
    property Item ignoredItem
    property bool isGroupDialog: false
    property bool moved: false

    property alias hoveredItem: dropHandler.hoveredItem
    property alias handleWheelEvents: wheelHandler.active

    function insertIndexAt(above, x, y) {
        if (above) {
            return above.itemIndex;
        } else {
            var distance = tasks.vertical ? x : y;
            var step = tasks.vertical ? LayoutManager.taskWidth() : LayoutManager.taskHeight();
            var stripe = Math.ceil(distance / step);

            // Use the unified model count — we're reordering the unified list
            // (slots + strays), not Plasma's source tasksModel. For a panel
            // with empty slots the two counts can disagree, and the old code
            // landed drops on the wrong row.
            var count = tasks.unifiedModel.rowCount();
            if (stripe === LayoutManager.calculateStripes()) {
                return count - 1;
            } else {
                return stripe * LayoutManager.tasksPerStripe();
            }
        }
    }

    Timer {
        id: ignoreItemTimer

        repeat: false
        interval: 750

        onTriggered: {
            ignoredItem = null;
        }
    }

    Connections {
        target: tasks

        function onDragSourceChanged() {
            if (!dragSource) {
                ignoredItem = null;
                ignoreItemTimer.stop();
                tasks.currentDropTarget = null;
            }
        }
    }

    WheelHandler {
        id: wheelHandler

        property bool active: true
        property int wheelDelta: 0;

        enabled: active && plasmoid.configuration.wheelEnabled

        onWheel: {
            wheelDelta = TaskTools.wheelActivateNextPrevTask(null, wheelDelta, event.angleDelta.y, plasmoid.configuration.wheelSkipMinimized, tasks);
        }
    }

    DropArea {
        id: dropHandler

        anchors.fill: parent

        preventStealing: true;

        property Item hoveredItem

        //ignore anything that is neither internal to TaskManager or a URL list
        onDragEnter: {
            if (event.mimeData.formats.indexOf("text/x-plasmoidservicename") >= 0) {
                event.ignore();
            }
        }

        // Pick a delegate under the cursor. For the main TaskList (a Flow
        // container), if the cursor falls into iconGap between cells we
        // fall back to the visually closest task — otherwise the gap would
        // silently no-op drag-reorder ("task refused to move").
        // For GroupDialog (ListView) we trust itemAt and do not invent a
        // fallback, because ListView.children is its contentItem, not rows.
        function pickTarget(x, y) {
            if (isGroupDialog) {
                return target.itemAt(x, y);
            }
            let above = target.childAt(x, y);
            if (above) return above;

            let nearest = null;
            let nearestDist = Number.POSITIVE_INFINITY;
            const kids = target.children;
            for (let i = 0; i < kids.length; ++i) {
                const c = kids[i];
                if (!c || !c.m) continue; // skip non-Task siblings (timers, etc.)
                const cx = c.x + c.width  / 2;
                const cy = c.y + c.height / 2;
                const d = Math.abs(cx - x) + Math.abs(cy - y);
                if (d < nearestDist) {
                    nearestDist = d;
                    nearest = c;
                }
            }
            return nearest;
        }

        onDragMove: {
            // During an active drag we keep moving the task even while the
            // layout is animating — otherwise fast drags skip over cells and
            // land in the wrong spot. For non-drag hovers we still honour the
            // animating guard to avoid activating group parents mid-animation.
            if (target.animating && !tasks.dragSource) {
                return;
            }

            let above = pickTarget(event.x, event.y);

            if (!above) {
                hoveredItem = null;
                activationTimer.stop();

                return;
            }

            // If we're mixing launcher tasks with other tasks and are moving
            // a (small) launcher task across a non-launcher task, don't allow
            // the latter to be the move target twice in a row for a while, as
            // it will naturally be moved underneath the cursor as result of the
            // initial move, due to being far larger than the launcher delegate.
            // TODO: This restriction (minus the timer, which improves things)
            // has been proven out in the EITM fork, but could be improved later
            // by tracking the cursor movement vector and allowing the drag if
            // the movement direction has reversed, establishing user intent to
            // move back.
            if (!plasmoid.configuration.separateLaunchers && tasks.dragSource != null
                 && tasks.dragSource.m.IsLauncher === true && above.m.IsLauncher !== true
                 && above === ignoredItem) {
                return;
            } else {
                ignoredItem = null;
            }

            if (tasks.dragSource) {
                // Reject drags between different TaskList instances.
                if (tasks.dragSource.parent !== above.parent) {
                    return;
                }

                // Stray -> empty slot with matching app: show drop hint, suppress reorder.
                const src = tasks.dragSource;
                const compatibleBind = above.isEmptySlot === true
                                    && src.slotIdx < 0
                                    && src.appId
                                    && src.appId === above.appId;

                if (compatibleBind) {
                    tasks.currentDropTarget = above;
                    return;
                }
                tasks.currentDropTarget = null;

                var insertAt = insertIndexAt(above, event.x, event.y);

                if (tasks.dragSource !== above && tasks.dragSource.itemIndex !== insertAt) {
                    tasks.unifiedModel.moveItem(tasks.dragSource.itemIndex, insertAt);
                    ignoredItem = above;
                    ignoreItemTimer.restart();
                }
            } else if (!tasks.dragSource && hoveredItem !== above) {
                hoveredItem = above;
                activationTimer.restart();
            }
        }

        onDragLeave: {
            hoveredItem = null;
            activationTimer.stop();
            tasks.currentDropTarget = null;
        }

        onDrop: {
            // Internal drop: if we have a compatible slot under cursor, convert stray -> slot-bound.
            if (event.mimeData.formats.indexOf("application/x-orgkdeplasmataskmanager_taskbuttonitem") >= 0) {
                if (tasks.currentDropTarget && tasks.dragSource
                    && tasks.currentDropTarget.isEmptySlot === true
                    && tasks.dragSource.slotIdx < 0)
                {
                    tasks.unifiedModel.bindStrayToSlot(
                        tasks.currentDropTarget.itemIndex,
                        tasks.dragSource.itemIndex);
                }
                tasks.currentDropTarget = null;
                event.ignore();
                return;
            }

            // Reject plasmoid drops.
            if (event.mimeData.formats.indexOf("text/x-plasmoidservicename") >= 0) {
                event.ignore();
                return;
            }

            if (event.mimeData.hasUrls) {
                parent.urlsDropped(event.mimeData.urls);
                return;
            }
        }

        Timer {
            id: activationTimer

            interval: 250
            repeat: false

            onTriggered: {
                if (parent.hoveredItem.m.IsGroupParent === true) {
                    TaskTools.createGroupDialog(parent.hoveredItem, tasks);
                } else if (parent.hoveredItem.m.IsLauncher !== true) {
                    tasksModel.requestActivate(parent.hoveredItem.modelIndex());
                }
            }
        }
    }
}
