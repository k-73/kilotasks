/*
    SPDX-FileCopyrightText: 2012-2016 Eike Hein <hein@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQml 2.15

import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.plasma.core 2.0 as PlasmaCore

import org.kde.plasma.workspace.trianglemousefilter 1.0

import org.kde.taskmanager 0.1 as TaskManager
import org.kde.plasma.private.taskmanager 0.1 as TaskManagerApplet

import org.kilo.kilotasks 1.0 as Kilo

import "code/layout.js" as LayoutManager
import "code/tools.js" as TaskTools

MouseArea {
    id: tasks

    anchors.fill: parent
    hoverEnabled: true

    // For making a bottom to top layout since qml flow can't do that.
    // We just hang the task manager upside down to achieve that.
    // This mirrors the tasks as well, so we just rotate them again to fix that (see Task.qml).
    rotation: plasmoid.configuration.reverseMode && plasmoid.formFactor === PlasmaCore.Types.Vertical ? 180 : 0

    readonly property bool shouldShirnkToZero: !LayoutManager.logicalTaskCount()
    property bool vertical: plasmoid.formFactor === PlasmaCore.Types.Vertical
    property bool iconsOnly: plasmoid.pluginName === "org.kilo.plasma.kilotasks"

    property var toolTipOpenedByClick: null

    property QtObject contextMenuComponent: Qt.createComponent("ContextMenu.qml")
    property QtObject pulseAudioComponent: Qt.createComponent("PulseAudio.qml")

    property var toolTipAreaItem: null

    property bool needLayoutRefresh: false;
    property variant taskClosedWithMouseMiddleButton: []
    property alias taskList: taskList
    property alias taskRepeater: taskRepeater
    property alias unifiedModel: unifiedModel

    // Current drop target during an internal drag: the empty slot that the user is
    // hovering with a matching stray. null when nothing eligible is under cursor.
    property var currentDropTarget: null

    Kilo.UnifiedTasksModel {
        id: unifiedModel
        sourceModel: tasksModel

        // Gate persistence until after initial load finishes. Prevents the cold-boot race
        // where plasmoid.configuration is still loading when Component.onCompleted fires:
        // reading `slots` as undefined → [] → writing [] back → wiped user config permanently.
        property bool slotsLoaded: false

        Component.onCompleted: {
            // Defer one tick so plasmoid.configuration has a chance to settle.
            Qt.callLater(unifiedModel.restoreSlots);
        }

        function restoreSlots() {
            const cfg = plasmoid.configuration.slots;
            if (cfg && cfg.length > 0) {
                slotsConfig = cfg;
            } else {
                const legacy = plasmoid.configuration.launchers || [];
                legacy.forEach(function (url) { addSlot(url, "", "", ""); });
            }
            slotsLoaded = true;
        }

        onSlotsConfigChanged: {
            if (!slotsLoaded) return;
            plasmoid.configuration.slots = slotsConfig;
        }
    }

    // Thin QML wrappers delegating to the C++ UnifiedTasksModel. Kept so Task.qml /
    // ContextMenu.qml references stay stable; all model state lives in C++.
    //
    // NOTE: "slotIdx" here is the unified-model row index (the same delegate index),
    //       not a separate slots-only index — the two collapse under single-list design.
    function activateOrSpawnSlot(unifiedRow /*=slotIdx*/, modifiers) {
        unifiedModel.activateOrSpawnSlotAt(unifiedRow);
    }

    function addSlotFromTask(taskItem) {
        if (!taskItem || taskItem.taskIdx < 0) return;
        unifiedModel.addSlotFromSourceRow(taskItem.taskIdx);
    }

    function duplicateSlot(unifiedRow) {
        unifiedModel.duplicateSlotAt(unifiedRow);
    }

    function removeSlot(unifiedRow) {
        unifiedModel.removeSlotAt(unifiedRow);
    }

    readonly property Component _slotDialogComponent: Qt.createComponent("SlotCommandDialog.qml", Component.PreferSynchronous)

    // Single live dialog instance — repeated Edit-slot clicks reuse it instead
    // of racing createObject against the previous dialog's pending destroy().
    property var _activeEditDialog: null
    property string _activeEditAppId: ""         // snapshotted at open()
    property string _activeEditLauncherUrl: ""   // — used to cancel dialog if slot disappears

    // Deferred opener. ContextMenu dismissal is asynchronous and can steal
    // focus right as we call open(); a small timer pause lets the menu finish
    // tearing down before we show and raise the dialog.
    Timer {
        id: _slotDialogOpenTimer
        interval: 60
        repeat: false
        onTriggered: {
            const dlg = tasks._activeEditDialog;
            if (dlg) dlg.open();
        }
    }

    // If the slot being edited is removed (or its identity changes) while the
    // dialog is open, close the dialog — otherwise subsequent Save would
    // persist preview state onto whatever row ended up at the cached index.
    // We walk the existing Task delegates and check for any empty-or-bound
    // slot that still carries the edited (appId, launcherUrl) identity.
    Connections {
        target: unifiedModel
        function onSlotsConfigChanged() {
            const dlg = tasks._activeEditDialog;
            if (!dlg || !dlg.visible || !tasks._activeEditAppId) return;

            let stillPresent = false;
            for (let i = 0; i < taskRepeater.count; ++i) {
                const t = taskRepeater.itemAt(i);
                if (!t || t.slotIdx < 0) continue;
                const mdl = t.m;
                if (!mdl) continue;
                if (mdl.slotAppId !== tasks._activeEditAppId) continue;
                // launcherUrl is a secondary key — require equality only when
                // the originating slot actually had one (custom-command-only
                // slots have empty launcherUrl on both sides).
                if (tasks._activeEditLauncherUrl
                    && mdl.slotLauncherUrl
                    && mdl.slotLauncherUrl !== tasks._activeEditLauncherUrl) continue;
                stillPresent = true;
                break;
            }
            if (!stillPresent) dlg.cancel();
        }
    }

    function _readSlotBarColorSafe(row) {
        // Guard against running against an old C++ plugin (user upgraded QML
        // but hasn't reinstalled the C++ side). Returning "" keeps the dialog
        // opening instead of failing the whole createObject() evaluation.
        try {
            if (typeof unifiedModel.slotBarColorAt === "function") {
                return unifiedModel.slotBarColorAt(row) || "";
            }
        } catch (e) {
            console.warn("kilotasks: slotBarColorAt unavailable:", e);
        }
        return "";
    }

    function editSlotCommand(taskItem) {
        if (!taskItem || taskItem.slotIdx < 0) return;
        if (!_slotDialogComponent || _slotDialogComponent.status !== Component.Ready) {
            console.warn("kilotasks: SlotCommandDialog not ready:",
                         _slotDialogComponent ? _slotDialogComponent.errorString() : "null");
            return;
        }

        // Re-entry: bring the existing dialog to front instead of creating
        // a second one that would fight the first for focus.
        if (_activeEditDialog && _activeEditDialog.visible) {
            _activeEditDialog.requestActivate();
            _activeEditDialog.raise();
            return;
        }

        const appId = taskItem.appId || "";
        const rowIdx = taskItem.itemIndex;
        const anchorRect = backend.globalRect(taskItem);
        const scrGeom = plasmoid.screenGeometry;
        let edge;
        switch (plasmoid.location) {
            case PlasmaCore.Types.TopEdge:    edge = "top";    break;
            case PlasmaCore.Types.LeftEdge:   edge = "left";   break;
            case PlasmaCore.Types.RightEdge:  edge = "right";  break;
            default:                          edge = "bottom"; break;
        }
        const dlg = _slotDialogComponent.createObject(null, {
            unifiedRow: rowIdx,
            appId: appId,
            appName: taskItem.appName || appId,
            iconName: taskItem.m && taskItem.m.decoration ? String(taskItem.m.decoration) : appId,
            launcherUrl: taskItem.m && taskItem.m.slotLauncherUrl ? String(taskItem.m.slotLauncherUrl) : "",
            currentCommand: unifiedModel.slotCommandAt(rowIdx),
            defaultCommand: unifiedModel.defaultCommandForAppId(appId),
            currentBgColor: unifiedModel.slotBgColorAt(rowIdx),
            currentBarColor: _readSlotBarColorSafe(rowIdx),
            anchorRect: anchorRect,
            screenGeometry: scrGeom,
            anchorEdge: edge,
        });
        if (!dlg) {
            console.warn("kilotasks: SlotCommandDialog createObject returned null");
            return;
        }

        _activeEditDialog = dlg;
        _activeEditAppId = appId;
        _activeEditLauncherUrl = taskItem.m && taskItem.m.slotLauncherUrl
            ? String(taskItem.m.slotLauncherUrl) : "";
        // Drop the tracked reference as soon as the user closes the dialog so
        // the next Edit-slot click creates a fresh instance.
        dlg.visibleChanged.connect(function () {
            if (!dlg.visible && tasks._activeEditDialog === dlg) {
                tasks._activeEditDialog = null;
                tasks._activeEditAppId = "";
                tasks._activeEditLauncherUrl = "";
            }
        });

        _slotDialogOpenTimer.restart();
    }

    Plasmoid.preferredRepresentation: Plasmoid.fullRepresentation

    Plasmoid.constraintHints: PlasmaCore.Types.CanFillArea

    Plasmoid.onUserConfiguringChanged: {
        if (plasmoid.userConfiguring && !!tasks.groupDialog) {
            tasks.groupDialog.visible = false;
        }
    }

    Layout.fillWidth: tasks.vertical ? true : plasmoid.configuration.fill
    Layout.fillHeight: !tasks.vertical ? true : plasmoid.configuration.fill
    Layout.minimumWidth: {
        if (shouldShirnkToZero) {
            return PlasmaCore.Units.gridUnit; // For edit mode
        }
        return tasks.vertical ? 0 : LayoutManager.preferredMinWidth();
    }
    Layout.minimumHeight: {
        if (shouldShirnkToZero) {
            return PlasmaCore.Units.gridUnit; // For edit mode
        }
        return !tasks.vertical ? 0 : LayoutManager.preferredMinHeight();
    }

//BEGIN TODO: this is not precise enough: launchers are smaller than full tasks
    Layout.preferredWidth: {
        if (shouldShirnkToZero) {
            return 0.01;
        }
        if (tasks.vertical) {
            return PlasmaCore.Units.gridUnit * 10;
        }
        return (LayoutManager.logicalTaskCount() * LayoutManager.preferredMaxWidth()) / LayoutManager.calculateStripes();
    }
    Layout.preferredHeight: {
        if (shouldShirnkToZero) {
            return 0.01;
        }
        if (tasks.vertical) {
            return (LayoutManager.logicalTaskCount() * LayoutManager.preferredMaxHeight()) / LayoutManager.calculateStripes();
        }
        return PlasmaCore.Units.gridUnit * 2;
    }
//END TODO

    property Item dragSource: null

    signal requestLayout
    signal windowsHovered(variant winIds, bool hovered)
    signal activateWindowView(variant winIds)

    onDragSourceChanged: {
        if (dragSource == null) {
            tasksModel.syncLaunchers();
        }
    }

    onExited: {
        if (needLayoutRefresh) {
            LayoutManager.layout(taskRepeater)
            needLayoutRefresh = false;
        }
    }

    function publishIconGeometries(taskItems) {
        if (TaskTools.taskManagerInstanceCount >= 2) {
            return;
        }
        for (var i = 0; i < taskItems.length - 1; ++i) {
            var task = taskItems[i];

            if (task && task.m && task.taskIdx >= 0 && task.m.IsLauncher !== true && task.m.IsStartup !== true) {
                tasks.tasksModel.requestPublishDelegateGeometry(tasks.tasksModel.makeModelIndex(task.taskIdx),
                    backend.globalRect(task), task);
            }
        }
    }

    property TaskManager.TasksModel tasksModel: TaskManager.TasksModel {
        id: tasksModel

        readonly property int logicalLauncherCount: {
            if (plasmoid.configuration.separateLaunchers) {
                return launcherCount;
            }

            var startupsWithLaunchers = 0;

            for (var i = 0; i < taskRepeater.count; ++i) {
                var item = taskRepeater.itemAt(i);

                if (item && item.m && item.m.IsStartup === true && item.m.HasLauncher === true) {
                    ++startupsWithLaunchers;
                }
            }

            return launcherCount + startupsWithLaunchers;
        }

        virtualDesktop: virtualDesktopInfo.currentDesktop
        screenGeometry: plasmoid.screenGeometry
        activity: activityInfo.currentActivity

        filterByVirtualDesktop: plasmoid.configuration.showOnlyCurrentDesktop
        filterByScreen: plasmoid.configuration.showOnlyCurrentScreen
        filterByActivity: plasmoid.configuration.showOnlyCurrentActivity
        filterNotMinimized: plasmoid.configuration.showOnlyMinimized

        sortMode: sortModeEnumValue(plasmoid.configuration.sortingStrategy)
        launchInPlace: plasmoid.configuration.sortingStrategy === 1
        separateLaunchers: plasmoid.configuration.sortingStrategy !== 1

        // Grouping is user-controlled via groupingStrategy.
        //   1 (default): collapse per-app windows into one entry. Helper windows that slip
        //                past the phantom-row filter (Firefox PiP / audio-stream dummies,
        //                Discord overlay, Telegram dialog, etc.) fold under the group parent.
        //   0:           each real window = its own icon. Phantom rows are still suppressed
        //                by UnifiedTasksModel::shouldTrackSource (SkipTaskbar, IsHidden,
        //                empty AppId, empty WinIdList, no decoration).
        groupMode: plasmoid.configuration.groupingStrategy === 0
            ? TaskManager.TasksModel.GroupDisabled
            : TaskManager.TasksModel.GroupApplications
        groupInline: false
        groupingWindowTasksThreshold: -1

        // Launcher list is kept empty on purpose: manual slots handle pinning.
        onLauncherListChanged: {
            if (launcherList.length > 0) {
                launcherList = [];
            }
            layoutTimer.restart();
        }

        onGroupingAppIdBlacklistChanged: {
            plasmoid.configuration.groupingAppIdBlacklist = groupingAppIdBlacklist;
        }

        onGroupingLauncherUrlBlacklistChanged: {
            plasmoid.configuration.groupingLauncherUrlBlacklist = groupingLauncherUrlBlacklist;
        }

        function sortModeEnumValue(index) {
            switch (index) {
                case 0:
                    return TaskManager.TasksModel.SortDisabled;
                case 1:
                    return TaskManager.TasksModel.SortManual;
                case 2:
                    return TaskManager.TasksModel.SortAlpha;
                case 3:
                    return TaskManager.TasksModel.SortVirtualDesktop;
                case 4:
                    return TaskManager.TasksModel.SortActivity;
                default:
                    return TaskManager.TasksModel.SortDisabled;
            }
        }

        function groupModeEnumValue(index) {
            switch (index) {
                case 0:
                    return TaskManager.TasksModel.GroupDisabled;
                case 1:
                    return TaskManager.TasksModel.GroupApplications;
            }
        }

        Component.onCompleted: {
            launcherList = [];
            groupingAppIdBlacklist = plasmoid.configuration.groupingAppIdBlacklist;
            groupingLauncherUrlBlacklist = plasmoid.configuration.groupingLauncherUrlBlacklist;
            // Plasma startup race: filterByScreen can latch in with a zero-geometry filter
            // when plasmoid.screenGeometry is not yet populated, dropping all windows until
            // a later event. Kick it after a short delay to force re-evaluation.
            screenFilterKick.start();
        }
    }

    Timer {
        id: screenFilterKick
        interval: 500
        repeat: false
        onTriggered: {
            if (plasmoid.configuration.showOnlyCurrentScreen) {
                tasksModel.filterByScreen = false;
                tasksModel.filterByScreen = true;
            }
            if (plasmoid.configuration.showOnlyCurrentDesktop) {
                tasksModel.filterByVirtualDesktop = false;
                tasksModel.filterByVirtualDesktop = true;
            }
        }
    }

    // Re-kick the filter when Plasma tells us the screen assignment / geometry changed.
    // Declared at root because TasksModel (not an Item) can't host Connections children.
    Connections {
        target: plasmoid
        function onScreenChanged() { screenFilterKick.restart(); }
        function onScreenGeometryChanged() { screenFilterKick.restart(); }
    }

    TaskManager.VirtualDesktopInfo {
        id: virtualDesktopInfo
    }

    TaskManager.ActivityInfo {
        id: activityInfo
        readonly property string nullUuid: "00000000-0000-0000-0000-000000000000"
    }

    property TaskManagerApplet.Backend backend: TaskManagerApplet.Backend {
        taskManagerItem: tasks
        highlightWindows: plasmoid.configuration.highlightWindows

        onAddLauncher: {
            tasks.addLauncher(url);
        }

        onWindowViewAvailableChanged: TaskTools.windowViewAvailable = windowViewAvailable;

        Component.onCompleted: TaskTools.windowViewAvailable = windowViewAvailable;
    }

    PlasmaCore.DataSource {
        id: mpris2Source
        engine: "mpris2"
        connectedSources: sources
        onSourceAdded: {
            connectSource(source);
        }
        onSourceRemoved: {
            disconnectSource(source);
        }
        function sourceNameForLauncherUrl(launcherUrl, pid) {
            if (!launcherUrl || launcherUrl === "") {
                return "";
            }

            // MPRIS spec explicitly mentions that "DesktopEntry" is with .desktop extension trimmed
            // Moreover, remove URL parameters, like wmClass (part after the question mark)
            var desktopFileName = launcherUrl.toString().split('/').pop().split('?')[0].replace(".desktop", "")
            if (desktopFileName.indexOf("applications:") === 0) {
                desktopFileName = desktopFileName.substr(13)
            }

            let fallbackSource = "";

            for (var i = 0, length = connectedSources.length; i < length; ++i) {
                var source = connectedSources[i];
                // we intend to connect directly, otherwise the multiplexer steals the connection away
                if (source === "@multiplex") {
                    continue;
                }

                var sourceData = data[source];
                if (!sourceData) {
                    continue;
                }

                /**
                 * If the task is in a group, we can't use desktopFileName to match the task.
                 * but in case PID match fails, use the match result from desktopFileName.
                 */
                if (pid && sourceData.InstancePid === pid) {
                    return source;
                }
                if (sourceData.DesktopEntry === desktopFileName) {
                    fallbackSource = source;
                }

                var metadata = sourceData.Metadata;
                if (metadata) {
                    var kdePid = metadata["kde:pid"];
                    if (kdePid && pid === kdePid) {
                        return source;
                    }
                }
            }

            // If PID match fails, return fallbackSource.
            return fallbackSource;
        }

        function startOperation(source, op) {
            var service = serviceForSource(source)
            var operation = service.operationDescription(op)
            return service.startOperationCall(operation)
        }

        function goPrevious(source) {
            startOperation(source, "Previous");
        }
        function goNext(source) {
            startOperation(source, "Next");
        }
        function play(source) {
            startOperation(source, "Play");
        }
        function pause(source) {
            startOperation(source, "Pause");
        }
        function playPause(source) {
            startOperation(source, "PlayPause");
        }
        function stop(source) {
            startOperation(source, "Stop");
        }
        function raise(source) {
            startOperation(source, "Raise");
        }
        function quit(source) {
            startOperation(source, "Quit");
        }
    }

    Loader {
        id: pulseAudio
        sourceComponent: pulseAudioComponent
        active: pulseAudioComponent.status === Component.Ready
    }

    Timer {
        id: iconGeometryTimer

        interval: 500
        repeat: false

        onTriggered: {
            tasks.publishIconGeometries(taskList.children, tasks);
        }
    }

    Binding {
        target: plasmoid
        property: "status"
        value: (tasksModel.anyTaskDemandsAttention && plasmoid.configuration.unhideOnAttention
            ? PlasmaCore.Types.NeedsAttentionStatus : PlasmaCore.Types.PassiveStatus)
        restoreMode: Binding.RestoreBinding
    }

    Connections {
        target: plasmoid

        function onLocationChanged() {
            if (TaskTools.taskManagerInstanceCount >= 2) {
                return;
            }
            // This is on a timer because the panel may not have
            // settled into position yet when the location prop-
            // erty updates.
            iconGeometryTimer.start();
        }
    }

    Connections {
        target: plasmoid.configuration

        function onGroupingAppIdBlacklistChanged() {
            tasksModel.groupingAppIdBlacklist = plasmoid.configuration.groupingAppIdBlacklist;
        }
        function onGroupingLauncherUrlBlacklistChanged() {
            tasksModel.groupingLauncherUrlBlacklist = plasmoid.configuration.groupingLauncherUrlBlacklist;
        }
        function onIconSpacingChanged() { taskList.layout(); }
        function onIconGapChanged()     { taskList.layout(); }
        function onIconPaddingChanged() { taskList.layout(); }
        // Live config updates — previously only initial bindings existed, so
        // toggling these from the settings dialog left the taskbar stale until
        // plasmashell restart.
        function onSortingStrategyChanged() {
            tasksModel.sortMode = tasksModel.sortModeEnumValue(plasmoid.configuration.sortingStrategy);
            tasksModel.launchInPlace = plasmoid.configuration.sortingStrategy === 1;
            tasksModel.separateLaunchers = plasmoid.configuration.sortingStrategy !== 1;
        }
        function onGroupingStrategyChanged() {
            tasksModel.groupMode = plasmoid.configuration.groupingStrategy === 0
                ? TaskManager.TasksModel.GroupDisabled
                : TaskManager.TasksModel.GroupApplications;
        }
        function onShowOnlyCurrentScreenChanged()   { screenFilterKick.restart(); }
        function onShowOnlyCurrentDesktopChanged()  { screenFilterKick.restart(); }
        function onShowOnlyCurrentActivityChanged() { screenFilterKick.restart(); }
        function onShowOnlyMinimizedChanged()       { screenFilterKick.restart(); }
    }

    property Component taskInitComponent: Component {
        Timer {
            id: timer

            interval: PlasmaCore.Units.longDuration
            running: true

            onTriggered: {
                tasksModel.requestPublishDelegateGeometry(parent.modelIndex(), backend.globalRect(parent), parent);
                timer.destroy();
            }
        }
    }

    Component {
        id: busyIndicator
        PlasmaComponents3.BusyIndicator {}
    }

    // Save drag data
    Item {
        id: dragHelper

        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.CopyAction | Qt.MoveAction | Qt.LinkAction
        Drag.onDragFinished: tasks.dragSource = null;
    }

    PlasmaCore.FrameSvgItem {
        id: taskFrame

        visible: false;

        imagePath: "widgets/tasks";
        prefix: "normal"
    }

    PlasmaCore.Svg {
        id: taskSvg

        imagePath: "widgets/tasks"
    }

    MouseHandler {
        id: mouseHandler

        anchors.fill: parent

        target: taskList

        onUrlsDropped: {
            // If all dropped URLs point to application desktop files, we'll add a launcher for each of them.
            var createLaunchers = urls.every(function (item) {
                return backend.isApplication(item)
            });

            if (createLaunchers) {
                urls.forEach(function (item) {
                    addLauncher(item);
                });
                return;
            }

            if (!hoveredItem) {
                return;
            }

            // DeclarativeMimeData urls is a QJsonArray but requestOpenUrls expects a proper QList<QUrl>.
            var urlsList = backend.jsonArrayToUrlList(urls);

            // Otherwise we'll just start a new instance of the application with the URLs as argument,
            // as you probably don't expect some of your files to open in the app and others to spawn launchers.
            tasksModel.requestOpenUrls(hoveredItem.modelIndex(), urlsList);
        }
    }

    ToolTipDelegate {
        id: openWindowToolTipDelegate
        visible: false
    }

    ToolTipDelegate {
        id: pinnedAppToolTipDelegate
        visible: false
    }

    TriangleMouseFilter {
        id: tmf
        filterTimeOut: 300
        active: tasks.toolTipAreaItem && tasks.toolTipAreaItem.toolTipOpen
        blockFirstEnter: false

        edge: {
            switch (plasmoid.location) {
                case PlasmaCore.Types.BottomEdge:
                    return Qt.TopEdge;
                case PlasmaCore.Types.TopEdge:
                    return Qt.BottomEdge;
                case PlasmaCore.Types.LeftEdge:
                    return Qt.RightEdge;
                case PlasmaCore.Types.RightEdge:
                    return Qt.LeftEdge;
                default:
                    return Qt.TopEdge;
            }
        }

        secondaryPoint: {
            if (tasks.toolTipAreaItem === null) {
                return Qt.point(0, 0);
            }
            const x = tasks.toolTipAreaItem.x;
            const y = tasks.toolTipAreaItem.y;
            const height = tasks.toolTipAreaItem.height;
            const width = tasks.toolTipAreaItem.width;
            return Qt.point(x+width/2, height);
        }

        anchors {
            left: parent.left
            top: parent.top
        }

        height: taskList.implicitHeight
        width: taskList.implicitWidth

        TaskList {
            id: taskList

            anchors {
                left: parent.left
                top: parent.top
            }
            width: tasks.shouldShirnkToZero ? 0 : LayoutManager.layoutWidth()
            height: tasks.shouldShirnkToZero ? 0 : LayoutManager.layoutHeight()

            flow: {
                if (tasks.vertical) {
                    return plasmoid.configuration.forceStripes ? Flow.LeftToRight : Flow.TopToBottom
                }
                return plasmoid.configuration.forceStripes ? Flow.TopToBottom : Flow.LeftToRight
            }

            onAnimatingChanged: {
                if (!animating) {
                    tasks.publishIconGeometries(children, tasks);
                }
            }
            onWidthChanged: layoutTimer.restart()
            onHeightChanged: layoutTimer.restart()

            function layout() {
                LayoutManager.layout(taskRepeater);
            }

            Timer {
                id: layoutTimer

                interval: 0
                repeat: false

                onTriggered: taskList.layout()
            }

            Repeater {
                id: taskRepeater

                model: unifiedModel
                delegate: Task {}
                onItemAdded: taskList.layout()
                onItemRemoved: {
                    if (tasks.containsMouse && index != taskRepeater.count &&
                        item.winIdList && item.winIdList.length > 0 &&
                        taskClosedWithMouseMiddleButton.indexOf(item.winIdList[0]) > -1) {
                        needLayoutRefresh = true;
                    } else {
                        taskList.layout();
                    }
                    taskClosedWithMouseMiddleButton = [];
                }
            }
        }
    }

    readonly property Component groupDialogComponent: Qt.createComponent("GroupDialog.qml")
    property GroupDialog groupDialog: null

    function hasLauncher(url) {
        return tasksModel.launcherPosition(url) != -1;
    }

    function addLauncher(url) {
        if (plasmoid.immutability !== PlasmaCore.Types.SystemImmutable) {
            tasksModel.requestAddLauncher(url);
        }
    }

    // This is called by plasmashell in response to a Meta+number shortcut.
    function activateTaskAtIndex(index) {
        if (typeof index !== "number") {
            return;
        }

        var task = taskRepeater.itemAt(index);
        if (task) {
            TaskTools.activateTask(task.modelIndex(), task.m, null, task, plasmoid, tasks);
        }
    }

    function createContextMenu(rootTask, modelIndex, args = {}) {
        const initialArgs = Object.assign(args, {
            visualParent: rootTask,
            modelIndex,
            mpris2Source,
            backend,
        });
        return contextMenuComponent.createObject(rootTask, initialArgs);
    }

    Component.onCompleted: {
        TaskTools.taskManagerInstanceCount += 1;
        tasks.requestLayout.connect(layoutTimer.restart);
        tasks.requestLayout.connect(iconGeometryTimer.restart);
        tasks.windowsHovered.connect(backend.windowsHovered);
        tasks.activateWindowView.connect(backend.activateWindowView);
    }

    Component.onDestruction: {
        TaskTools.taskManagerInstanceCount -= 1;
    }
}
