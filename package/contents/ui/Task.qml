/*
    SPDX-FileCopyrightText: 2012-2013 Eike Hein <hein@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick 2.15
import QtGraphicalEffects 1.15

import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 2.0 as PlasmaComponents // for DialogStatus
import org.kde.plasma.components 3.0 as PlasmaComponents3

import org.kde.plasma.private.taskmanager 0.1 as TaskManagerApplet

import "code/layout.js" as LayoutManager
import "code/tools.js" as TaskTools

PlasmaCore.ToolTipArea {
    id: task

    activeFocusOnTab: true

    // Initial height before layout.js runs. Keep in sync with preferredMaxHeight(): icon
    // extent + user padding + theme margins, so increasing the iconSize/iconPadding
    // sliders actually enlarges the cell.
    height: LayoutManager.paddedIconCellExtent() + LayoutManager.verticalMargins()

    visible: false

    // To achieve a bottom to top layout, the task manager is rotated by 180 degrees(see main.qml).
    // This makes the tasks mirrored, so we mirror them again to fix that.
    rotation: plasmoid.configuration.reverseMode && plasmoid.formFactor === PlasmaCore.Types.Vertical ? 180 : 0

    LayoutMirroring.enabled: (Qt.application.layoutDirection == Qt.RightToLeft)
    LayoutMirroring.childrenInherit: (Qt.application.layoutDirection == Qt.RightToLeft)

    readonly property var m: model

    readonly property int slotIdx: model.slotIdx !== undefined ? model.slotIdx : -1
    readonly property bool isSlot: slotIdx >= 0
    readonly property bool isEmptySlot: isSlot && model.IsWindow !== true

    readonly property int pid: model.AppPid !== undefined ? model.AppPid : 0
    readonly property string appName: model.AppName || ""
    readonly property string appId: model.AppId ? String(model.AppId).replace(/\.desktop$/, '') : ""
    readonly property variant winIdList: model.WinIdList || []
    property bool toolTipOpen: false
    property int itemIndex: index
    property bool inPopup: false
    property bool isWindow: model.IsWindow === true
    property int childCount: model.ChildCount !== undefined ? model.ChildCount : 0
    property int previousChildCount: 0
    property alias labelText: label.text
    property QtObject contextMenu: null
    readonly property bool smartLauncherEnabled: !inPopup && model.IsStartup !== true
    property QtObject smartLauncherItem: null

    property Item audioStreamIcon: null
    property var audioStreams: []
    property bool delayAudioStreamIndicator: false
    readonly property bool audioIndicatorsEnabled: plasmoid.configuration.indicateAudioStreams
    readonly property bool hasAudioStream: audioStreams.length > 0
    readonly property bool playingAudio: hasAudioStream && audioStreams.some(function (item) {
        return !item.corked
    })
    readonly property bool muted: hasAudioStream && audioStreams.every(function (item) {
        return item.muted
    })

    readonly property bool highlighted: (inPopup && activeFocus) || (!inPopup && containsMouse)
        || (task.contextMenu && task.contextMenu.status === PlasmaComponents.DialogStatus.Open)
        || (!!tasks.groupDialog && tasks.groupDialog.visualParent === task)

    active: (plasmoid.configuration.showToolTips || tasks.toolTipOpenedByClick === task) && !inPopup && !tasks.groupDialog
    interactive: model.IsWindow === true || mainItem.hasPlayer
    location: plasmoid.location
    mainItem: (model.IsWindow === true) ? openWindowToolTipDelegate : pinnedAppToolTipDelegate
    // when the mouse leaves the tooltip area, a timer to hide is set for (timeout / 20) ms
    // see plasma-framework/src/declarativeimports/core/tooltipdialog.cpp function dismiss()
    // to compensate for that we multiply by 20 here, to get an effective leave timeout of 2s.
    timeout: (tasks.toolTipOpenedByClick === task) ? 2000 * 20 : 4000

    Accessible.name: model.display
    Accessible.description: {
        if (!model.display) {
            return "";
        }

        if (model.IsLauncher) {
            return i18nc("@info:usagetip %1 application name", "Launch %1", model.display)
        }

        let smartLauncherDescription = "";
        if (iconBox.active && task.smartLauncherItem) {
            smartLauncherDescription += i18ncp("@info:tooltip", "There is %1 new message.", "There are %1 new messages.", task.smartLauncherItem.count);
        }

        if (model.IsGroupParent) {
            switch (plasmoid.configuration.groupedTaskVisualization) {
            case 0:
                break; // Use the default description
            case 1: {
                if (plasmoid.configuration.showToolTips) {
                    return `${i18nc("@info:usagetip %1 task name", "Show Task tooltip for %1", model.display)}; ${smartLauncherDescription}`;
                }
                // fallthrough
            }
            case 2: {
                if (backend.windowViewAvailable) {
                    return `${i18nc("@info:usagetip %1 task name", "Show windows side by side for %1", model.display)}; ${smartLauncherDescription}`;
                }
                // fallthrough
            }
            default:
                return `${i18nc("@info:usagetip %1 task name", "Open textual list of windows for %1", model.display)}; ${smartLauncherDescription}`;
            }
        }

        return `${i18n("Activate %1", model.display)}; ${smartLauncherDescription}`;
    }
    Accessible.role: Accessible.Button

    onToolTipVisibleChanged: {
        task.toolTipOpen = toolTipVisible;
        if (!toolTipVisible) {
            tasks.toolTipOpenedByClick = null;
        } else {
            tasks.toolTipAreaItem = task;
        }
    }

    onContainsMouseChanged: if (containsMouse) {
        task.forceActiveFocus(Qt.MouseFocusReason);
        task.updateMainItemBindings();
    } else {
        tasks.toolTipOpenedByClick = null;
    }

    onHighlightedChanged: {
        // ensure it doesn't get stuck with a window highlighted
        backend.cancelHighlightWindows();
    }

    onPidChanged: updateAudioStreams({delay: false})
    onAppNameChanged: updateAudioStreams({delay: false})

    onIsWindowChanged: {
        if (isWindow) {
            taskInitComponent.createObject(task);
        }
    }

    onChildCountChanged: {
        if (hasRealTaskRow() && TaskTools.taskManagerInstanceCount < 2 && childCount > previousChildCount) {
            // Publish next tick — on childCount increase the new window row has
            // only just been added to the source model, KWin hasn't seen it yet
            // and a synchronous publish drops the minimise-to-taskbar animation.
            Qt.callLater(function () {
                if (task && task.hasRealTaskRow()) {
                    tasksModel.requestPublishDelegateGeometry(modelIndex(), backend.globalRect(task), task);
                }
            });
        }

        previousChildCount = childCount;
    }

    onItemIndexChanged: {
        hideToolTip();

        if (!inPopup && !tasks.vertical
            && (LayoutManager.calculateStripes() > 1 || !plasmoid.configuration.separateLaunchers)) {
            tasks.requestLayout();
        }
    }

    onSmartLauncherEnabledChanged: {
        if (smartLauncherEnabled && !smartLauncherItem) {
            const smartLauncher = Qt.createQmlObject(`
                import org.kde.plasma.private.taskmanager 0.1 as TaskManagerApplet;

                TaskManagerApplet.SmartLauncherItem { }
            `, task);

            smartLauncher.launcherUrl = Qt.binding(() => model.LauncherUrlWithoutIcon || "");

            smartLauncherItem = smartLauncher;
        }
    }

    onHasAudioStreamChanged: {
        const audioStreamIconActive = hasAudioStream && audioIndicatorsEnabled;
        if (!audioStreamIconActive) {
            if (audioStreamIcon !== null) {
                audioStreamIcon.destroy();
                audioStreamIcon = null;
            }
            return;
        }
        // Create item on demand instead of using Loader to reduce memory consumption,
        // because only a few applications have audio streams. Guard every step —
        // a broken AudioStream.qml must not nuke the whole delegate.
        const component = Qt.createComponent("AudioStream.qml");
        if (component.status === Component.Ready) {
            audioStreamIcon = component.createObject(task);
        } else {
            console.warn("kilotasks: AudioStream.qml failed to load:", component.errorString());
            audioStreamIcon = null;
        }
        component.destroy();
    }
    onAudioIndicatorsEnabledChanged: task.hasAudioStreamChanged()

    Keys.onMenuPressed: contextMenuTimer.start()
    Keys.onReturnPressed: TaskTools.activateTask(modelIndex(), model, event.modifiers, task, plasmoid, tasks)
    Keys.onEnterPressed: Keys.onReturnPressed(event);
    Keys.onSpacePressed: Keys.onReturnPressed(event);
    Keys.onUpPressed: Keys.onLeftPressed(event)
    Keys.onDownPressed: Keys.onRightPressed(event)
    Keys.onLeftPressed: if (!inPopup && hasRealTaskRow() && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier)) {
        tasksModel.move(task.taskIdx, task.taskIdx - 1);
    } else {
        event.accepted = false;
    }
    Keys.onRightPressed: if (!inPopup && hasRealTaskRow() && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier)) {
        tasksModel.move(task.taskIdx, task.taskIdx + 1);
    } else {
        event.accepted = false;
    }

    // Real tasksModel row index for mirrored entries; -1 for empty slots and popup children.
    readonly property int taskIdx: model.taskIdx !== undefined ? model.taskIdx : -1

    function modelIndex() {
        // Popup children are only valid while the group dialog is still live
        // AND still pointing at the task that parents them. If either is gone
        // (dialog just closed, parent task destroyed), fall back to an invalid
        // index — callers already handle that cleanly via `hasRealTaskRow()`.
        if (inPopup) {
            if (!tasks.groupDialog || !tasks.groupDialog.visualParent
                || tasks.groupDialog.visualParent.taskIdx === undefined) {
                return tasksModel.index(-1, -1);
            }
            return tasksModel.makeModelIndex(tasks.groupDialog.visualParent.taskIdx, index);
        }
        // Empty slot: return an invalid index so tasksModel.data() reads return undefined
        // and context menu window-actions hide themselves via their visible checks.
        if (taskIdx < 0) return tasksModel.index(-1, -1);
        return tasksModel.makeModelIndex(taskIdx);
    }

    function hasRealTaskRow() {
        return taskIdx >= 0;
    }

    function showContextMenu(args) {
        task.hideImmediately();
        contextMenu = tasks.createContextMenu(task, modelIndex(), args);
        contextMenu.show();
    }

    function updateAudioStreams(args) {
        if (args) {
            // When the task just appeared (e.g. virtual desktop switch), show the audio indicator
            // right away. Only when audio streams change during the lifetime of this task, delay
            // showing that to avoid distraction.
            delayAudioStreamIndicator = !!args.delay;
        }

        var pa = pulseAudio.item;
        if (!pa) {
            task.audioStreams = [];
            return;
        }

        // Check appid first for app using portal
        // https://docs.pipewire.org/page_portal.html
        var streams = pa.streamsForAppId(task.appId);
        if (!streams.length) {
            streams = pa.streamsForPid(task.pid);
            if (streams.length) {
                pa.registerPidMatch(task.appName);
            } else {
                // We only want to fall back to appName matching if we never managed to map
                // a PID to an audio stream window. Otherwise if you have two instances of
                // an application, one playing and the other not, it will look up appName
                // for the non-playing instance and erroneously show an indicator on both.
                if (!pa.hasPidMatch(task.appName)) {
                    streams = pa.streamsForAppName(task.appName);
                }
            }
        }

        task.audioStreams = streams;
    }

    function toggleMuted() {
        if (muted) {
            task.audioStreams.forEach(function (item) { item.unmute(); });
        } else {
            task.audioStreams.forEach(function (item) { item.mute(); });
        }
    }

    // Will also be called in activateTaskAtIndex(index)
    function updateMainItemBindings() {
        if ((mainItem.parentTask === task && mainItem.rootIndex.row === task.taskIdx) || (tasks.toolTipOpenedByClick === null && !task.active) || (tasks.toolTipOpenedByClick !== null && tasks.toolTipOpenedByClick !== task)) {
            return;
        }

        mainItem.blockingUpdates = (mainItem.isGroup !== (model.IsGroupParent === true)); // BUG 464597 Force unload the previous component

        mainItem.parentTask = task;
        mainItem.rootIndex = tasksModel.makeModelIndex(taskIdx >= 0 ? taskIdx : 0, -1);

        mainItem.appName = Qt.binding(() => model.AppName);
        mainItem.pidParent = Qt.binding(() => model.AppPid !== undefined ? model.AppPid : 0);
        mainItem.windows = Qt.binding(() => model.WinIdList);
        mainItem.isGroup = Qt.binding(() => model.IsGroupParent === true);
        mainItem.icon = Qt.binding(() => model.decoration);
        mainItem.launcherUrl = Qt.binding(() => model.LauncherUrlWithoutIcon || "");
        mainItem.isLauncher = Qt.binding(() => model.IsLauncher === true);
        mainItem.isMinimizedParent = Qt.binding(() => model.IsMinimized === true);
        mainItem.displayParent = Qt.binding(() => model.display);
        mainItem.genericName = Qt.binding(() => model.GenericName);
        mainItem.virtualDesktopParent = Qt.binding(() =>
            (model.VirtualDesktops !== undefined && model.VirtualDesktops.length > 0) ? model.VirtualDesktops : [0]);
        mainItem.isOnAllVirtualDesktopsParent = Qt.binding(() => model.IsOnAllVirtualDesktops === true);
        mainItem.activitiesParent = Qt.binding(() => model.Activities);

        mainItem.smartLauncherCountVisible = Qt.binding(() => task.smartLauncherItem && task.smartLauncherItem.countVisible);
        mainItem.smartLauncherCount = Qt.binding(() => mainItem.smartLauncherCountVisible ? task.smartLauncherItem.count : 0);

        mainItem.blockingUpdates = false;
        tasks.toolTipAreaItem = task;
    }

    Connections {
        target: pulseAudio.item
        ignoreUnknownSignals: true // Plasma-PA might not be available
        function onStreamsChanged() {
            task.updateAudioStreams({delay: true})
        }
    }

    TapHandler {
        id: menuTapHandler
        acceptedButtons: Qt.LeftButton
        acceptedDevices: PointerDevice.TouchScreen | PointerDevice.Stylus
        onLongPressed: {
            // When we're a launcher, there's no window controls, so we can show all
            // places without the menu getting super huge.
            if (model.IsLauncher === true) {
                showContextMenu({showAllPlaces: true})
            } else {
                showContextMenu();
            }
        }
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        acceptedDevices: PointerDevice.Mouse
        gesturePolicy: TapHandler.WithinBounds // Release grab when menu appears
        onPressedChanged: if (pressed) contextMenuTimer.start()
    }

    Timer {
        id: contextMenuTimer
        interval: 0
        onTriggered: menuTapHandler.longPressed()
    }

    // Left-click: activation path. We use the default gesturePolicy
    // (DragThreshold), which holds only a passive grab from press — that is
    // what lets the inner-frame DragHandler claim the pointer once the user
    // actually drags past the drag-distance threshold. Any stronger grab
    // policy (WithinBounds / ReleaseWithinBounds) would starve the
    // DragHandler and silently break drag-to-reorder.
    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: {
            // Cosmetic feedback first — covers the perceived freeze while the
            // new instance is being spawned for empty slots, and also just
            // feels snappy for plain activation clicks.
            tapPulse.restart();

            if (plasmoid.configuration.showToolTips && task.active) {
                hideToolTip();
            }
            if (task.isEmptySlot) {
                tasks.activateOrSpawnSlot(task.slotIdx, eventPoint.event.modifiers);
                return;
            }
            TaskTools.activateTask(modelIndex(), model, eventPoint.event.modifiers, task, plasmoid, tasks);
        }
    }

    TapHandler {
        acceptedButtons: Qt.MidButton | Qt.BackButton | Qt.ForwardButton
        onTapped: {
            const button = eventPoint.event.button;
            if (button == Qt.MidButton) {
                if (task.isEmptySlot) {
                    tasks.activateOrSpawnSlot(task.slotIdx, Qt.ShiftModifier);
                    return;
                }
                if (plasmoid.configuration.middleClickAction === TaskManagerApplet.Backend.NewInstance) {
                    tasksModel.requestNewInstance(modelIndex());
                } else if (plasmoid.configuration.middleClickAction === TaskManagerApplet.Backend.Close) {
                    tasks.taskClosedWithMouseMiddleButton = winIdList.slice()
                    tasksModel.requestClose(modelIndex());
                } else if (plasmoid.configuration.middleClickAction === TaskManagerApplet.Backend.ToggleMinimized) {
                    tasksModel.requestToggleMinimized(modelIndex());
                } else if (plasmoid.configuration.middleClickAction === TaskManagerApplet.Backend.ToggleGrouping) {
                    tasksModel.requestToggleGrouping(modelIndex());
                } else if (plasmoid.configuration.middleClickAction === TaskManagerApplet.Backend.BringToCurrentDesktop) {
                    tasksModel.requestVirtualDesktops(modelIndex(), [virtualDesktopInfo.currentDesktop]);
                }
            } else if (button === Qt.BackButton || button === Qt.ForwardButton) {
                var sourceName = mpris2Source.sourceNameForLauncherUrl(model.LauncherUrlWithoutIcon, model.AppPid);
                if (sourceName) {
                    if (button === Qt.BackButton) {
                        mpris2Source.goPrevious(sourceName);
                    } else {
                        mpris2Source.goNext(sourceName);
                    }
                } else {
                    eventPoint.accepted = false;
                }
            }

            backend.cancelHighlightWindows();
        }
    }

    WheelHandler {
        property int wheelDelta: 0
        enabled: plasmoid.configuration.wheelEnabled && (!task.inPopup || !groupDialog.overflowing)
        onWheel: {
            wheelDelta = TaskTools.wheelActivateNextPrevTask(task, wheelDelta, event.angleDelta.y, plasmoid.configuration.wheelSkipMinimized, tasks);
        }
    }

    // Pure positioning container. Plasma's "widgets/tasks" SVG is intentionally NOT
    // used: its hover prefix renders an extra inset border 1 px above our stateBar
    // (with horizontal margins), which visually doubled the indicator. All state
    // styling is handled by the flat overlays below.
    Item {
        id: frame

        anchors {
            fill: parent

            topMargin: (!tasks.vertical && taskList.rows > 1) ? LayoutManager.iconMargin : 0
            bottomMargin: (!tasks.vertical && taskList.rows > 1) ? LayoutManager.iconMargin : 0
            leftMargin: ((inPopup || tasks.vertical) && taskList.columns > 1) ? LayoutManager.iconMargin : 0
            rightMargin: ((inPopup || tasks.vertical) && taskList.columns > 1) ? LayoutManager.iconMargin : 0
        }

        // Avoid repositioning delegate item after dragFinished
        DragHandler {
            id: dragHandler
            grabPermissions: PointerHandler.TakeOverForbidden

            onActiveChanged: if (active) {
                // Mark the drag source synchronously so MouseHandler.onDragMove
                // cannot misread an early move as "hover" while grabToImage is
                // still async. The image lands a moment later; the ghost just
                // starts empty for that frame, which is invisible to the user.
                tasks.dragSource = task;
                icon.grabToImage((result) => {
                    // BUG 466675: grabToImage is async. Bail on every path that
                    // could have destroyed the delegate or cancelled the drag.
                    if (!dragHandler.active || !task || tasks.dragSource !== task) {
                        return;
                    }
                    dragHelper.Drag.imageSource = result.url;
                    dragHelper.Drag.mimeData = backend.generateMimeData(model.MimeType, model.MimeData, model.LauncherUrlWithoutIcon);
                    dragHelper.Drag.active = dragHandler.active;
                });
            } else {
                dragHelper.Drag.active = false;
                dragHelper.Drag.imageSource = "";
            }
        }
    }

    // Per-state overlay radius. The legacy `cornerRadius` is still read as the
    // fallback so existing configs keep their rounded corners if the user never
    // visits the new per-state UI.
    function _stateRadius(primary, fallback) {
        const v = plasmoid.configuration[primary];
        if (typeof v === "number" && v > 0) return v;
        return plasmoid.configuration[fallback] || 0;
    }
    readonly property int _activeRadius:    _stateRadius("activeCornerRadius",    "cornerRadius")
    readonly property int _inactiveRadius:  _stateRadius("inactiveCornerRadius",  "cornerRadius")
    readonly property int _emptySlotRadius: _stateRadius("emptySlotCornerRadius", "cornerRadius")
    // Used by slotBgTint + dropHint (follow active-state geometry).
    readonly property int _overlayRadius: {
        if (task.isEmptySlot) return _emptySlotRadius;
        if (model.IsActive === true) return _activeRadius;
        return _inactiveRadius;
    }
    readonly property bool _flat: _overlayRadius === 0

    // Per-slot user-chosen background tint.
    Rectangle {
        id: slotBgTint

        anchors.fill: frame
        radius: task._overlayRadius
        color: model.slotBgColor || "transparent"
        visible: !!model.slotBgColor
        antialiasing: !task._flat
    }

    // Shared style Component bank. Three renderers (Solid/Glass/Gradient) parameterised
    // by a base color — used for active, inactive and empty-slot backgrounds alike.
    Component {
        id: bgSolidComponent
        Rectangle {
            property color baseColor: theme.highlightColor
            radius: task._overlayRadius
            color: baseColor
            antialiasing: !task._flat
        }
    }
    Component {
        id: bgGlassComponent
        Rectangle {
            property color baseColor: theme.highlightColor
            radius: task._overlayRadius
            color: Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.35)
            border.width: Math.max(1, Math.round(PlasmaCore.Units.devicePixelRatio))
            border.color: Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.7)
            antialiasing: !task._flat
        }
    }
    Component {
        id: bgGradientComponent
        Rectangle {
            property color baseColor: theme.highlightColor
            radius: task._overlayRadius
            antialiasing: !task._flat
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.9) }
                GradientStop { position: 1.0; color: Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.0) }
            }
        }
    }

    function _styleComponent(styleIdx) {
        switch (styleIdx) {
        case 1: return bgSolidComponent;
        case 2: return bgGlassComponent;
        case 3: return bgGradientComponent;
        default: return null;
        }
    }

    // Inactive-window background: running but not focused. Uses runningTintColor as base.
    Item {
        id: inactiveBackground

        readonly property color baseColor: {
            const c = plasmoid.configuration.runningTintColor;
            return (c && c.length > 0) ? c : theme.highlightColor;
        }
        readonly property int overlayRadius: task._inactiveRadius
        readonly property bool applies: model.IsWindow === true && model.IsActive !== true

        anchors.fill: frame
        visible: opacity > 0 && plasmoid.configuration.bgStyleInactive !== 0
        opacity: applies ? (plasmoid.configuration.runningTintOpacity / 100) : 0
        Behavior on opacity { NumberAnimation { duration: plasmoid.configuration.animationSpeed; easing.type: Easing.OutQuad } }

        Loader {
            id: inactiveBgLoader
            anchors.fill: parent
            sourceComponent: task._styleComponent(plasmoid.configuration.bgStyleInactive)
            onLoaded: if (item) {
                item.baseColor = Qt.binding(() => inactiveBackground.baseColor);
                item.radius   = Qt.binding(() => inactiveBackground.overlayRadius);
            }
        }
    }

    // Empty-slot background. Independent color/opacity so the user can tint
    // empty launcher slots without affecting running-but-inactive windows.
    // Backward-compat: when emptySlotTintOpacity is still at default 0 AND no
    // dedicated empty-slot colour is set, fall back to the legacy running tint
    // so users upgrading from the shared setting keep their visuals.
    Item {
        id: emptySlotBackground

        readonly property bool useLegacyFallback: plasmoid.configuration.emptySlotTintOpacity === 0
            && (!plasmoid.configuration.emptySlotTintColor || plasmoid.configuration.emptySlotTintColor.length === 0)

        readonly property color baseColor: {
            const c = useLegacyFallback ? plasmoid.configuration.runningTintColor
                                        : plasmoid.configuration.emptySlotTintColor;
            return (c && c.length > 0) ? c : theme.highlightColor;
        }
        readonly property real effectiveOpacity: useLegacyFallback
            ? (plasmoid.configuration.runningTintOpacity / 100)
            : (plasmoid.configuration.emptySlotTintOpacity / 100)

        anchors.fill: frame
        visible: opacity > 0 && plasmoid.configuration.bgStyleEmptySlot !== 0
        opacity: task.isEmptySlot ? effectiveOpacity : 0
        Behavior on opacity { NumberAnimation { duration: plasmoid.configuration.animationSpeed; easing.type: Easing.OutQuad } }

        Loader {
            id: emptySlotBgLoader
            anchors.fill: parent
            sourceComponent: task._styleComponent(plasmoid.configuration.bgStyleEmptySlot)
            onLoaded: if (item) {
                item.baseColor = Qt.binding(() => emptySlotBackground.baseColor);
                item.radius   = Qt.binding(() => task._emptySlotRadius);
            }
        }
    }

    // Active-window background (focused) / optional hover tint. Uses activeTintColor,
    // with an optional hover-specific color / opacity factor.
    Item {
        id: activeBackground

        readonly property color activeColor: {
            const c = plasmoid.configuration.activeTintColor;
            return (c && c.length > 0) ? c : theme.highlightColor;
        }
        readonly property color hoverColor: {
            const c = plasmoid.configuration.hoverTintColor;
            return (c && c.length > 0) ? c : activeColor;
        }
        readonly property bool isActive: model.IsActive === true
        readonly property bool isHover: task.highlighted && plasmoid.configuration.hoverTintEnabled && !isActive
        readonly property color baseColor: isHover ? hoverColor : activeColor
        readonly property int overlayRadius: task._activeRadius

        anchors.fill: frame
        visible: opacity > 0 && plasmoid.configuration.bgStyle !== 0
        opacity: {
            const o = plasmoid.configuration.activeTintOpacity / 100;
            if (isActive) return o;
            if (isHover) {
                const f = (plasmoid.configuration.hoverTintOpacity || 0) / 100;
                return o * Math.max(0, Math.min(1, f));
            }
            return 0;
        }
        Behavior on opacity { NumberAnimation { duration: plasmoid.configuration.animationSpeed; easing.type: Easing.OutQuad } }

        Loader {
            id: activeBgLoader
            anchors.fill: parent
            sourceComponent: task._styleComponent(plasmoid.configuration.bgStyle)
            onLoaded: if (item) {
                item.baseColor = Qt.binding(() => activeBackground.baseColor);
                item.radius   = Qt.binding(() => activeBackground.overlayRadius);
            }
        }
    }

    // Per-state border. Active / Inactive / Empty slot toggled independently;
    // thickness and corner radius are also per-state (falling back to the
    // legacy shared values for unmigrated configs).
    Rectangle {
        id: taskBorder

        anchors.fill: frame
        color: "transparent"
        antialiasing: !task._flat
        z: 11 // Above stateBar / topBar (both z: 10) so the configured border
              // always stays on top — user request.

        readonly property bool isActive: model.IsActive === true
        readonly property bool showForState: {
            if (task.isEmptySlot) return plasmoid.configuration.taskBorderEmptySlotEnabled;
            if (isActive) return plasmoid.configuration.taskBorderActiveEnabled;
            return plasmoid.configuration.taskBorderInactiveEnabled;
        }
        readonly property string currentSpec: {
            if (task.isEmptySlot) return plasmoid.configuration.taskBorderEmptySlotColor;
            if (isActive) return plasmoid.configuration.taskBorderActiveColor;
            return plasmoid.configuration.taskBorderInactiveColor;
        }
        readonly property int currentThickness: {
            const legacy = plasmoid.configuration.taskBorderThickness || 1;
            if (task.isEmptySlot) return plasmoid.configuration.emptySlotBorderThickness || legacy;
            if (isActive)        return plasmoid.configuration.activeBorderThickness    || legacy;
            return                     plasmoid.configuration.inactiveBorderThickness  || legacy;
        }
        readonly property real currentOpacity: {
            let v = 100;
            if (task.isEmptySlot) v = plasmoid.configuration.emptySlotBorderOpacity;
            else if (isActive)    v = plasmoid.configuration.activeBorderOpacity;
            else                  v = plasmoid.configuration.inactiveBorderOpacity;
            if (typeof v !== "number" || v <= 0) return 1.0;
            return Math.max(0, Math.min(1, v / 100));
        }
        readonly property color fallbackColor: isActive ? theme.highlightColor : theme.textColor

        radius: task._overlayRadius
        visible: showForState
        opacity: showForState ? currentOpacity : 0
        Behavior on opacity { NumberAnimation { duration: plasmoid.configuration.animationSpeed; easing.type: Easing.OutQuad } }
        border.width: showForState ? currentThickness : 0
        border.color: (currentSpec && currentSpec.length > 0) ? currentSpec : fallbackColor
    }

    // Drop-target hint: lit when a compatible stray is being dragged over this empty slot.
    Rectangle {
        id: dropHint

        anchors.fill: frame
        anchors.margins: Math.round(PlasmaCore.Units.devicePixelRatio)
        radius: task._overlayRadius
        color: "transparent"
        border.color: theme.highlightColor
        border.width: Math.max(1, Math.round(PlasmaCore.Units.devicePixelRatio * 1.5))
        antialiasing: !task._flat

        readonly property bool isTarget: tasks.currentDropTarget === task

        visible: opacity > 0
        opacity: isTarget ? 0.95 : 0
        Behavior on opacity { NumberAnimation { duration: plasmoid.configuration.animationSpeed; easing.type: Easing.OutQuad } }

        Rectangle {
            anchors.fill: parent
            anchors.margins: parent.border.width
            radius: Math.max(0, parent.radius - parent.border.width)
            color: theme.highlightColor
            opacity: 0.15
        }
    }

    // Single flat edge bar for every state (hover / active / attention). Identical
    // geometry — only opacity and colour change. No SVG, no insets, crisp 1 px edges.
    // z: 10 keeps the bar above the icon's drop shadow (shadow bleeds downward via
    // vertical offset + blur radius and would otherwise tint the bar).
    Rectangle {
        id: stateBar

        z: 10

        readonly property bool horizontal: plasmoid.formFactor === PlasmaCore.Types.Horizontal
        readonly property bool onRightEdge: plasmoid.location === PlasmaCore.Types.RightEdge
        readonly property int thickness: Math.max(1, plasmoid.configuration.activeBarThickness)
        readonly property bool isActive: model.IsActive === true
        readonly property bool isAttention: model.IsDemandingAttention === true
            || (task.smartLauncherItem && task.smartLauncherItem.urgent)
        readonly property bool isHover: task.highlighted && plasmoid.configuration.taskHoverEffect

        visible: plasmoid.configuration.showActiveBar && opacity > 0
        opacity: {
            if (isAttention) return 0.95;
            if (isActive) return 0.95;
            if (isHover) return 0.4;
            return 0;
        }
        Behavior on opacity { NumberAnimation { duration: plasmoid.configuration.animationSpeed; easing.type: Easing.OutQuad } }

        color: {
            if (isAttention) {
                const a = plasmoid.configuration.attentionBarColor;
                return (a && a.length > 0) ? a : theme.negativeTextColor;
            }
            const c = plasmoid.configuration.activeTintColor;
            return (c && c.length > 0) ? c : theme.highlightColor;
        }
        radius: 0
        antialiasing: false

        // Anchor to the delegate root (task) at zero margin — flush with its edge.
        anchors.left: horizontal ? task.left : (onRightEdge ? task.left : undefined)
        anchors.right: horizontal ? task.right : (onRightEdge ? undefined : task.right)
        anchors.top: !horizontal ? task.top : undefined
        anchors.bottom: task.bottom
        width: horizontal ? undefined : thickness
        height: horizontal ? thickness : undefined
    }

    // Optional per-slot accent bar. Independent from stateBar (which hugs the
    // screen edge); this one sits on the OPPOSITE edge of the delegate so both
    // can coexist without visual conflict. Shown only when the user explicitly
    // opts in via Edit Slot → "Top bar colour".
    Rectangle {
        id: topBar
        z: 10

        readonly property string perSlotColor: model.slotBarColor || ""
        readonly property bool horizontal: plasmoid.formFactor === PlasmaCore.Types.Horizontal
        readonly property bool onRightEdge: plasmoid.location === PlasmaCore.Types.RightEdge
        readonly property int thickness: Math.max(1, plasmoid.configuration.activeBarThickness)

        // stateBar anchors to the panel-facing edge; topBar mirrors to the
        // opposite one so the two never overlap regardless of panel position.
        anchors.left:   horizontal ? task.left  : (onRightEdge ? undefined : task.left)
        anchors.right:  horizontal ? task.right : (onRightEdge ? task.right : undefined)
        anchors.top:    !horizontal ? task.top  : task.top
        anchors.bottom: !horizontal ? task.bottom : undefined
        width:  horizontal ? undefined : thickness
        height: horizontal ? thickness : undefined

        color: perSlotColor.length > 0 ? perSlotColor : "transparent"
        antialiasing: false
        visible: opacity > 0
        opacity: perSlotColor.length > 0 ? 0.95 : 0
        Behavior on opacity { NumberAnimation { duration: plasmoid.configuration.animationSpeed; easing.type: Easing.OutQuad } }
    }

    Loader {
        id: taskProgressOverlayLoader

        anchors.fill: frame
        asynchronous: true
        active: task.isWindow && task.smartLauncherItem && task.smartLauncherItem.progressVisible

        sourceComponent: TaskProgressOverlay {
            from: 0
            to: 100
            value: task.smartLauncherItem.progress
        }
    }

    // Subtle "tap pulse": icon springs inward and bounces back the instant a
    // click lands. Purely cosmetic — its real job is to mask the KService +
    // QProcess::startDetached latency that otherwise reads as a UI freeze
    // between the click and the new window appearing.
    SequentialAnimation {
        id: tapPulse
        NumberAnimation {
            target: iconBox
            property: "scale"
            to: 0.86
            duration: 80
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: iconBox
            property: "scale"
            to: 1.0
            duration: 280
            easing.type: Easing.OutBack
            easing.overshoot: 1.8
        }
    }

    Loader {
        id: iconBox

        // iconBox spans the full inner cell (theme margins only). Padding is expressed
        // as a spacer between iconBox and the rendered icon, NOT by shrinking iconBox
        // — so increasing the padding slider never shrinks the icon.
        readonly property int extraPad: Math.max(0, plasmoid.configuration.iconPadding || 0)

        transformOrigin: Item.Center
        scale: 1.0

        anchors {
            left: parent.left
            leftMargin: adjustMargin(true, parent.width, taskFrame.margins.left)
            top: parent.top
            topMargin: adjustMargin(false, parent.height, taskFrame.margins.top)
        }

        width: height
        height: Math.max(PlasmaCore.Units.iconSizes.small,
            parent.height - adjustMargin(false, parent.height, taskFrame.margins.top)
                          - adjustMargin(false, parent.height, taskFrame.margins.bottom))

        asynchronous: true
        active: height >= PlasmaCore.Units.iconSizes.small
                && task.smartLauncherItem && task.smartLauncherItem.countVisible
        source: "TaskBadgeOverlay.qml"

        function adjustMargin(vert, size, margin) {
            if (!size) {
                return margin;
            }

            var margins = vert ? LayoutManager.horizontalMargins() : LayoutManager.verticalMargins();

            if ((size - margins) < PlasmaCore.Units.iconSizes.small) {
                return Math.ceil((margin * (PlasmaCore.Units.iconSizes.small / size)) / 2);
            }

            return margin;
        }

        // Effective icon render size. When the user sets an explicit iconSize we honour
        // it as-is — even past the available cell, in which case the icon visually
        // overflows (signal to the user that they need a taller panel). "auto" fills
        // the cell minus user-requested padding.
        readonly property int targetIconExtent: {
            const sized = plasmoid.configuration.iconSize || 0;
            if (sized > 0) return sized;
            return Math.max(PlasmaCore.Units.iconSizes.small,
                            Math.min(iconBox.width, iconBox.height) - 2 * iconBox.extraPad);
        }

        // Wrapper enlarged by (blur + |offset|) on every side so DropShadow has real
        // room to render symmetrically. layer.effect replaces the wrapper's native
        // paint with the effect output — no double-drawing of the icon.
        Item {
            id: iconShadowWrap

            readonly property int shadowBlur: plasmoid.configuration.iconShadowBlur || 0
            readonly property int shadowOffX: plasmoid.configuration.iconShadowOffsetX || 0
            readonly property int shadowOffY: plasmoid.configuration.iconShadowOffsetY || 0
            // Padding needs to accommodate the worst case on each axis: blur radius
            // plus the absolute offset in that direction, plus a safety pixel.
            readonly property int padX: shadowBlur + Math.abs(shadowOffX) + 2
            readonly property int padY: shadowBlur + Math.abs(shadowOffY) + 2

            anchors.centerIn: parent
            width: iconBox.targetIconExtent + 2 * padX
            height: iconBox.targetIconExtent + 2 * padY

            readonly property color shadowBaseColor: {
                const c = plasmoid.configuration.iconShadowColor;
                return (c && c.length > 0) ? c : Qt.rgba(0, 0, 0, 1);
            }

            layer.enabled: plasmoid.configuration.iconShadowEnabled
            layer.effect: DropShadow {
                transparentBorder: true
                horizontalOffset: plasmoid.configuration.iconShadowOffsetX
                verticalOffset: plasmoid.configuration.iconShadowOffsetY
                radius: plasmoid.configuration.iconShadowBlur
                samples: Math.min(33, 2 * plasmoid.configuration.iconShadowBlur + 1)
                color: Qt.rgba(iconShadowWrap.shadowBaseColor.r,
                               iconShadowWrap.shadowBaseColor.g,
                               iconShadowWrap.shadowBaseColor.b,
                               (plasmoid.configuration.iconShadowOpacity || 0) / 100)
                cached: false
            }

            // Inner layer: optional desaturation for inactive icons. Nested inside
            // iconShadowWrap's DropShadow layer so both effects compose cleanly —
            // desaturate first (icon-size bounds), then the outer shadow blur.
            Item {
                id: iconSaturationWrap
                anchors.centerIn: parent
                width: iconBox.targetIconExtent
                height: iconBox.targetIconExtent

                readonly property real desatAmount: {
                    if (model.IsActive === true) return 0;
                    const s = plasmoid.configuration.inactiveIconSaturation;
                    if (typeof s !== "number" || s >= 100) return 0;
                    return Math.max(0, Math.min(1, 1 - s / 100));
                }
                layer.enabled: desatAmount > 0
                layer.effect: Desaturate { desaturation: iconSaturationWrap.desatAmount }

                PlasmaCore.IconItem {
                    id: icon

                    anchors.fill: parent

                    active: task.highlighted
                    enabled: true
                    usesPlasmaTheme: false

                    source: model.decoration
                    opacity: {
                        if (model.IsActive === true) return 1.0;
                        const v = plasmoid.configuration.inactiveIconOpacity;
                        return (typeof v === "number" && v >= 0) ? v / 100.0 : 1.0;
                    }
                    Behavior on opacity { NumberAnimation { duration: plasmoid.configuration.animationSpeed } }
                }
            }
        }

        states: [
            // Using a state transition avoids a binding loop between label.visible and
            // the text label margin, which derives from the icon width.
            State {
                name: "standalone"
                when: !label.visible

                AnchorChanges {
                    target: iconBox
                    anchors.left: undefined
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                PropertyChanges {
                    target: iconBox
                    anchors.leftMargin: 0
                    width: parent.width - adjustMargin(true, task.width, taskFrame.margins.left)
                                        - adjustMargin(true, task.width, taskFrame.margins.right)
                }
            }
        ]

        Loader {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height)
            height: width
            active: model.IsStartup === true
            sourceComponent: busyIndicator
        }
    }

    PlasmaComponents3.Label {
        id: label

        visible: (inPopup || !iconsOnly && model.IsLauncher !== true
            && (parent.width - iconBox.height - PlasmaCore.Units.smallSpacing) >= (theme.mSize(theme.defaultFont).width * LayoutManager.minimumMColumns()))

        anchors {
            fill: parent
            leftMargin: taskFrame.margins.left + iconBox.width + LayoutManager.labelMargin
            topMargin: taskFrame.margins.top
            rightMargin: taskFrame.margins.right + (audioStreamIcon !== null && audioStreamIcon.visible ? (audioStreamIcon.width + LayoutManager.labelMargin) : 0)
            bottomMargin: taskFrame.margins.bottom
        }

        wrapMode: (maximumLineCount == 1) ? Text.NoWrap : Text.Wrap
        elide: Text.ElideRight
        textFormat: Text.PlainText
        verticalAlignment: Text.AlignVCenter
        maximumLineCount: plasmoid.configuration.maxTextLines || undefined

        // use State to avoid unnecessary re-evaluation when the label is invisible
        states: State {
            name: "labelVisible"
            when: label.visible

            PropertyChanges {
                target: label
                text: model.display || ""
            }
        }
    }

    Component.onCompleted: {
        if (!inPopup && model.IsWindow === true) {
            var component = Qt.createComponent("GroupExpanderOverlay.qml");
            component.createObject(task);
            component.destroy();
        }

        if (!inPopup && model.IsWindow !== true) {
            taskInitComponent.createObject(task);
        }

        updateAudioStreams({delay: false})
    }
}
