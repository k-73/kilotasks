/*
    SPDX-FileCopyrightText: 2026 kilo
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15 as QQC2

import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Window {
    id: dlg

    // Inputs set by caller
    property int unifiedRow: -1
    property string appName: ""
    property string appId: ""
    property string iconName: ""
    property string launcherUrl: ""
    property string currentCommand: ""
    property string defaultCommand: ""
    property string currentBgColor: ""       // "#aarrggbb" or empty
    property string currentBarColor: ""      // "#rrggbb" top-bar override, empty = disabled

    // Positioning inputs: rect of the task in global coords, and the screen rect.
    property rect anchorRect: Qt.rect(0, 0, 0, 0)
    property rect screenGeometry: Qt.rect(0, 0, 0, 0)
    property string anchorEdge: "bottom"  // bottom / top / left / right

    // Snapshot of original state for revert-on-cancel.
    property string _origBgColor: ""
    property string _origBarColor: ""
    property bool   _committed: false

    // --- Color state (base + alpha%) -----------------------------------------
    // Shared palette with ConfigAppearance. Kept 20 items (incl. "None") so
    // the swatch row wraps into two balanced lines.
    readonly property var presets: [
        { key: "",        label: i18n("None"),     rgb: "" },
        { key: "#7f8c8d", label: i18n("Gray"),     rgb: "#7f8c8d" },
        { key: "#3498db", label: i18n("Blue"),     rgb: "#3498db" },
        { key: "#1abc9c", label: i18n("Teal"),     rgb: "#1abc9c" },
        { key: "#2ecc71", label: i18n("Green"),    rgb: "#2ecc71" },
        { key: "#f1c40f", label: i18n("Yellow"),   rgb: "#f1c40f" },
        { key: "#e67e22", label: i18n("Orange"),   rgb: "#e67e22" },
        { key: "#e74c3c", label: i18n("Red"),      rgb: "#e74c3c" },
        { key: "#9b59b6", label: i18n("Purple"),   rgb: "#9b59b6" },
        { key: "#ec87c0", label: i18n("Pink"),     rgb: "#ec87c0" },
        { key: "#34495e", label: i18n("Slate"),    rgb: "#34495e" },
        { key: "#5b6abf", label: i18n("Indigo"),   rgb: "#5b6abf" },
        { key: "#74b9ff", label: i18n("Sky"),      rgb: "#74b9ff" },
        { key: "#4dd0a7", label: i18n("Mint"),     rgb: "#4dd0a7" },
        { key: "#a1b79b", label: i18n("Sage"),     rgb: "#a1b79b" },
        { key: "#d4a72c", label: i18n("Gold"),     rgb: "#d4a72c" },
        { key: "#ff8a80", label: i18n("Coral"),    rgb: "#ff8a80" },
        { key: "#c78b9a", label: i18n("Rose"),     rgb: "#c78b9a" },
        { key: "#b39ddb", label: i18n("Lavender"), rgb: "#b39ddb" },
        { key: "#000000", label: i18n("Black"),    rgb: "#000000" },
    ]

    property string baseColor: ""
    property int alphaPercent: 35

    readonly property string composedBgColor: {
        if (!baseColor) return "";
        const a = Math.round(Math.max(0, Math.min(100, alphaPercent)) * 2.55);
        const ah = a.toString(16).toUpperCase();
        const aa = ah.length === 1 ? ("0" + ah) : ah;
        return "#" + aa + baseColor.slice(1).toUpperCase();
    }

    function _parseBg(s) {
        if (!s || s.length === 0) {
            baseColor = "";
            alphaPercent = 35;
            return;
        }
        if (s.length === 9 && s.charAt(0) === "#") {
            baseColor = "#" + s.slice(3).toLowerCase();
            alphaPercent = Math.round(parseInt(s.slice(1, 3), 16) / 2.55);
        } else if (s.length === 7 && s.charAt(0) === "#") {
            baseColor = s.toLowerCase();
            alphaPercent = 100;
        } else {
            baseColor = "";
            alphaPercent = 35;
        }
    }

    // --- Top-bar colour (simple, fully opaque) ------------------------------
    // Same 20-swatch palette as the shared config picker for consistency.
    readonly property var barPresets: [
        { key: "",        label: i18n("None"),     rgb: "" },
        { key: "#000000", label: i18n("Black"),    rgb: "#000000" },
        { key: "#ffffff", label: i18n("White"),    rgb: "#ffffff" },
        { key: "#7f8c8d", label: i18n("Gray"),     rgb: "#7f8c8d" },
        { key: "#3498db", label: i18n("Blue"),     rgb: "#3498db" },
        { key: "#1abc9c", label: i18n("Teal"),     rgb: "#1abc9c" },
        { key: "#2ecc71", label: i18n("Green"),    rgb: "#2ecc71" },
        { key: "#f1c40f", label: i18n("Yellow"),   rgb: "#f1c40f" },
        { key: "#e67e22", label: i18n("Orange"),   rgb: "#e67e22" },
        { key: "#e74c3c", label: i18n("Red"),      rgb: "#e74c3c" },
        { key: "#34495e", label: i18n("Slate"),    rgb: "#34495e" },
        { key: "#5b6abf", label: i18n("Indigo"),   rgb: "#5b6abf" },
        { key: "#74b9ff", label: i18n("Sky"),      rgb: "#74b9ff" },
        { key: "#4dd0a7", label: i18n("Mint"),     rgb: "#4dd0a7" },
        { key: "#a1b79b", label: i18n("Sage"),     rgb: "#a1b79b" },
        { key: "#d4a72c", label: i18n("Gold"),     rgb: "#d4a72c" },
        { key: "#ff8a80", label: i18n("Coral"),    rgb: "#ff8a80" },
        { key: "#c78b9a", label: i18n("Rose"),     rgb: "#c78b9a" },
        { key: "#9b59b6", label: i18n("Purple"),   rgb: "#9b59b6" },
        { key: "#b39ddb", label: i18n("Lavender"), rgb: "#b39ddb" },
    ]

    property bool barEnabled: false
    property string barBaseColor: ""
    readonly property string composedBarColor: barEnabled && barBaseColor ? barBaseColor : ""

    // --- Live preview: apply on every change ---------------------------------
    property bool _ready: false
    onComposedBgColorChanged: if (_ready && unifiedRow >= 0) tasks.unifiedModel.setSlotBgColorAt(unifiedRow, composedBgColor)
    onComposedBarColorChanged: if (_ready && unifiedRow >= 0) tasks.unifiedModel.setSlotBarColorAt(unifiedRow, composedBarColor)

    // --- Window plumbing ------------------------------------------------------
    title: i18n("Edit slot — %1", appName || appId || i18n("Slot"))
    width: Math.round(PlasmaCore.Units.gridUnit * 36)
    height: Math.round(PlasmaCore.Units.gridUnit * 34)
    minimumWidth: Math.round(PlasmaCore.Units.gridUnit * 28)
    minimumHeight: Math.round(PlasmaCore.Units.gridUnit * 30)
    flags: Qt.Dialog | Qt.WindowStaysOnTopHint
    modality: Qt.NonModal
    color: theme.backgroundColor
    visible: false

    function open() {
        _parseBg(currentBgColor);

        // Top-bar colour — seed from current override (empty = disabled).
        barEnabled = (currentBarColor && currentBarColor.length > 0);
        barBaseColor = barEnabled ? currentBarColor : "";

        _origBgColor = currentBgColor;
        _origBarColor = currentBarColor;
        _committed = false;

        // Position relative to the task icon on its own screen.
        const pad = 12;
        const sx = screenGeometry.width > 0 ? screenGeometry.x : 0;
        const sy = screenGeometry.height > 0 ? screenGeometry.y : 0;
        const sw = screenGeometry.width > 0 ? screenGeometry.width : Screen.width;
        const sh = screenGeometry.height > 0 ? screenGeometry.height : Screen.height;

        let px, py;
        if (anchorRect.width > 0 && anchorRect.height > 0) {
            switch (anchorEdge) {
            case "top":
                px = anchorRect.x + anchorRect.width / 2 - width / 2;
                py = anchorRect.y + anchorRect.height + pad;
                break;
            case "left":
                px = anchorRect.x + anchorRect.width + pad;
                py = anchorRect.y + anchorRect.height / 2 - height / 2;
                break;
            case "right":
                px = anchorRect.x - width - pad;
                py = anchorRect.y + anchorRect.height / 2 - height / 2;
                break;
            case "bottom":
            default:
                px = anchorRect.x + anchorRect.width / 2 - width / 2;
                py = anchorRect.y - height - pad;
                break;
            }
        } else {
            px = sx + (sw - width) / 2;
            py = sy + (sh - height) / 2;
        }
        x = Math.round(Math.max(sx + pad, Math.min(sx + sw - width - pad, px)));
        y = Math.round(Math.max(sy + pad, Math.min(sy + sh - height - pad, py)));

        _ready = true;
        visible = true;
        // Defer activation one event-loop turn. Qt allocates the native window
        // handle on visible=true; requestActivate/raise called synchronously in
        // the same tick can silently no-op on some compositors / X11 servers.
        Qt.callLater(function () {
            if (!visible) return;
            requestActivate();
            raise();
        });
    }

    function commit() {
        const typed = field.text.trim();
        const cmdToStore = (typed === dlg.defaultCommand.trim()) ? "" : typed;
        tasks.unifiedModel.setSlotCommandAt(unifiedRow, cmdToStore);
        // bg + opacity already live — nothing to do here.
        _committed = true;
        visible = false;
    }

    function revertLive() {
        if (unifiedRow < 0) return;
        tasks.unifiedModel.setSlotBgColorAt(unifiedRow, _origBgColor);
        tasks.unifiedModel.setSlotBarColorAt(unifiedRow, _origBarColor);
    }

    function cancel() {
        revertLive();
        visible = false;
    }

    function resetAll() {
        tasks.unifiedModel.setSlotCommandAt(unifiedRow, "");
        tasks.unifiedModel.setSlotBgColorAt(unifiedRow, "");
        tasks.unifiedModel.setSlotBarColorAt(unifiedRow, "");
        _committed = true;
        visible = false;
    }

    onClosing: (close) => {
        if (!_committed) revertLive();
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: dlg.cancel()

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: PlasmaCore.Units.largeSpacing
            spacing: PlasmaCore.Units.largeSpacing

            // Header ----------------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: PlasmaCore.Units.largeSpacing

                PlasmaCore.IconItem {
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: PlasmaCore.Units.iconSizes.large
                    Layout.preferredHeight: PlasmaCore.Units.iconSizes.large
                    source: dlg.iconName || dlg.appId
                    usesPlasmaTheme: false
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Math.round(PlasmaCore.Units.smallSpacing / 2)

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: i18n("Edit slot")
                        font.weight: Font.Bold
                        font.pixelSize: Math.round(theme.defaultFont.pixelSize * 1.2)
                        elide: Text.ElideRight
                    }

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: dlg.appName || dlg.appId || i18n("Unnamed slot")
                        elide: Text.ElideRight
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: theme.textColor
                opacity: 0.12
            }

            // Info block ------------------------------------------------------
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                rowSpacing: Math.round(PlasmaCore.Units.smallSpacing / 2)
                columnSpacing: PlasmaCore.Units.largeSpacing

                PlasmaComponents3.Label { text: i18n("App ID"); opacity: 0.7 }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: dlg.appId || "—"
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }

                PlasmaComponents3.Label {
                    text: i18n("Launcher URL"); opacity: 0.7
                    visible: dlg.launcherUrl !== ""
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: dlg.launcherUrl
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    visible: dlg.launcherUrl !== ""
                }

                PlasmaComponents3.Label { text: i18n("Default command"); opacity: 0.7 }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: dlg.defaultCommand || i18n("(none — custom command required)")
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    opacity: dlg.defaultCommand ? 1 : 0.6
                }
            }

            // Custom command --------------------------------------------------
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Math.round(PlasmaCore.Units.smallSpacing / 2)

                PlasmaComponents3.Label {
                    text: i18n("Custom command")
                    font.weight: Font.Medium
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.round(PlasmaCore.Units.gridUnit * 3.5)
                    color: Qt.rgba(theme.textColor.r, theme.textColor.g, theme.textColor.b, 0.05)
                    border.color: Qt.rgba(theme.textColor.r, theme.textColor.g, theme.textColor.b, 0.2)
                    border.width: 1
                    radius: Math.round(PlasmaCore.Units.devicePixelRatio * 3)

                    QQC2.ScrollView {
                        anchors.fill: parent
                        anchors.margins: 1
                        clip: true

                        QQC2.TextArea {
                            id: field
                            text: dlg.currentCommand || dlg.defaultCommand
                            placeholderText: dlg.defaultCommand
                            wrapMode: TextEdit.Wrap
                            selectByMouse: true
                            textFormat: TextEdit.PlainText
                            font.family: "monospace"
                            color: theme.textColor
                            background: null
                            Keys.onPressed: (event) => {
                                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                    && (event.modifiers & Qt.ControlModifier)) {
                                    dlg.commit();
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Escape) {
                                    dlg.cancel();
                                    event.accepted = true;
                                }
                            }
                        }
                    }
                }

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: i18n("Ctrl+Enter saves, Esc cancels. Empty means use the .desktop Exec.")
                    opacity: 0.65
                    wrapMode: Text.Wrap
                    font.pixelSize: Math.round(theme.defaultFont.pixelSize * 0.9)
                }
            }

            // Background tint -------------------------------------------------
            ColumnLayout {
                Layout.fillWidth: true
                spacing: PlasmaCore.Units.smallSpacing

                PlasmaComponents3.Label {
                    text: i18n("Background tint")
                    font.weight: Font.Medium
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: PlasmaCore.Units.smallSpacing

                    Repeater {
                        model: dlg.presets

                        delegate: Rectangle {
                            readonly property bool selected: dlg.baseColor === modelData.rgb
                            readonly property bool isNone: modelData.rgb === ""
                            width: Math.round(PlasmaCore.Units.iconSizes.medium * 0.9)
                            height: width
                            radius: width / 2
                            color: isNone ? "transparent" : modelData.rgb
                            border.width: selected ? 2 : 1
                            border.color: selected
                                ? theme.highlightColor
                                : Qt.rgba(theme.textColor.r, theme.textColor.g, theme.textColor.b, 0.25)
                            antialiasing: true

                            Canvas {
                                anchors.fill: parent
                                visible: parent.isNone
                                onPaint: {
                                    const ctx = getContext("2d");
                                    ctx.reset();
                                    ctx.strokeStyle = theme.textColor;
                                    ctx.globalAlpha = 0.55;
                                    ctx.lineWidth = 1.5;
                                    ctx.beginPath();
                                    ctx.moveTo(width * 0.2, height * 0.8);
                                    ctx.lineTo(width * 0.8, height * 0.2);
                                    ctx.stroke();
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: dlg.baseColor = modelData.rgb
                                QQC2.ToolTip.visible: containsMouse
                                QQC2.ToolTip.text: modelData.label
                                QQC2.ToolTip.delay: 400
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: PlasmaCore.Units.smallSpacing
                    enabled: dlg.baseColor !== ""
                    opacity: enabled ? 1 : 0.5

                    PlasmaComponents3.Label {
                        text: i18n("Opacity")
                        Layout.preferredWidth: Math.round(PlasmaCore.Units.gridUnit * 5)
                        opacity: 0.8
                    }
                    QQC2.Slider {
                        Layout.fillWidth: true
                        from: 5
                        to: 100
                        stepSize: 5
                        snapMode: QQC2.Slider.SnapAlways
                        value: dlg.alphaPercent
                        onMoved: dlg.alphaPercent = value
                    }
                    PlasmaComponents3.Label {
                        Layout.preferredWidth: Math.round(PlasmaCore.Units.gridUnit * 2.5)
                        text: dlg.alphaPercent + "%"
                        horizontalAlignment: Text.AlignRight
                    }
                    Rectangle {
                        Layout.preferredWidth: Math.round(PlasmaCore.Units.iconSizes.medium * 1.6)
                        Layout.preferredHeight: Math.round(PlasmaCore.Units.iconSizes.medium * 0.9)
                        radius: Math.round(PlasmaCore.Units.devicePixelRatio * 4)
                        color: dlg.composedBgColor || "transparent"
                        border.width: 1
                        border.color: Qt.rgba(theme.textColor.r, theme.textColor.g, theme.textColor.b, 0.25)
                        antialiasing: true

                        PlasmaComponents3.Label {
                            anchors.centerIn: parent
                            visible: !dlg.baseColor
                            text: i18n("no tint")
                            opacity: 0.6
                            font.pixelSize: Math.round(theme.defaultFont.pixelSize * 0.85)
                        }
                    }
                }
            }

            // Top bar colour — compact single row: checkbox + swatches ------
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Math.round(PlasmaCore.Units.smallSpacing / 2)

                PlasmaComponents3.Label {
                    text: i18n("Top bar colour")
                    font.weight: Font.Medium
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: PlasmaCore.Units.smallSpacing

                    QQC2.CheckBox {
                        id: barEnableCheck
                        text: i18n("Enable")
                        checked: dlg.barEnabled
                        onToggled: {
                            dlg.barEnabled = checked;
                            if (checked && !dlg.barBaseColor) {
                                dlg.barBaseColor = "#3498db";
                            }
                        }
                    }

                    Repeater {
                        model: dlg.barPresets
                        delegate: Rectangle {
                            readonly property bool selected: dlg.barBaseColor === modelData.rgb && dlg.barEnabled
                            readonly property bool isNone: modelData.rgb === ""
                            width: Math.round(PlasmaCore.Units.iconSizes.medium * 0.85)
                            height: width
                            radius: width / 2
                            color: isNone ? "transparent" : modelData.rgb
                            border.width: selected ? 2 : 1
                            border.color: selected
                                ? theme.highlightColor
                                : Qt.rgba(theme.textColor.r, theme.textColor.g, theme.textColor.b, 0.25)
                            antialiasing: true
                            opacity: dlg.barEnabled ? 1 : 0.45

                            Canvas {
                                anchors.fill: parent
                                visible: parent.isNone
                                onPaint: {
                                    const ctx = getContext("2d");
                                    ctx.reset();
                                    ctx.strokeStyle = theme.textColor;
                                    ctx.globalAlpha = 0.55;
                                    ctx.lineWidth = 1.5;
                                    ctx.beginPath();
                                    ctx.moveTo(width * 0.2, height * 0.8);
                                    ctx.lineTo(width * 0.8, height * 0.2);
                                    ctx.stroke();
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    dlg.barBaseColor = modelData.rgb;
                                    if (modelData.rgb === "") {
                                        dlg.barEnabled = false;
                                    } else if (!dlg.barEnabled) {
                                        dlg.barEnabled = true;
                                    }
                                }
                                QQC2.ToolTip.visible: containsMouse
                                QQC2.ToolTip.text: modelData.label
                                QQC2.ToolTip.delay: 400
                            }
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }

            // Buttons ---------------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: PlasmaCore.Units.smallSpacing

                PlasmaComponents3.Button {
                    text: i18n("Reset all")
                    icon.name: "edit-reset"
                    enabled: dlg.currentCommand !== "" || dlg.currentBgColor !== "" || dlg.currentBarColor !== ""
                    onClicked: dlg.resetAll()
                }

                Item { Layout.fillWidth: true }

                PlasmaComponents3.Button {
                    text: i18n("Cancel")
                    icon.name: "dialog-cancel"
                    onClicked: dlg.cancel()
                }

                PlasmaComponents3.Button {
                    text: i18n("Save")
                    icon.name: "dialog-ok-apply"
                    highlighted: true
                    onClicked: dlg.commit()
                }
            }
        }
    }

    onVisibleChanged: {
        if (visible) {
            Qt.callLater(() => { field.forceActiveFocus(); field.selectAll(); });
        } else {
            Qt.callLater(destroy);
        }
    }
}
