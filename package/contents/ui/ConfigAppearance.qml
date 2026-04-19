/*
    SPDX-FileCopyrightText: 2013 Eike Hein <hein@kde.org>
    SPDX-FileCopyrightText: 2026 kilo

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

import org.kde.kirigami 2.19 as Kirigami
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.plasmoid 2.0

ColumnLayout {
    id: form

    anchors.left: parent.left
    anchors.right: parent.right
    spacing: 0

    readonly property bool plasmaPaAvailable: Qt.createComponent("PulseAudio.qml").status === Component.Ready
    readonly property bool plasmoidVertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

    // Compact metrics — tuned so a full row (label + control + value) fits
    // within the stock Plasma config dialog without forcing it wider.
    readonly property real controlWidth: Kirigami.Units.gridUnit * 12
    readonly property real valueWidth: Math.round(Kirigami.Units.gridUnit * 3.2)
    readonly property real swatchSize: Math.round(Kirigami.Units.iconSizes.small * 1.1)
    readonly property real rowSpacing: Math.round(Kirigami.Units.smallSpacing * 0.75)

    // 20 presets — fills two balanced rows of 10 when the swatch row wraps.
    // First row: theme + neutrals + core accent. Second row: subtle / elegant
    // tones meant to sit quietly alongside Plasma themes without shouting.
    readonly property var colorPresets: [
        { label: i18n("Theme"),    value: ""        },
        { label: i18n("Black"),    value: "#000000" },
        { label: i18n("White"),    value: "#ffffff" },
        { label: i18n("Gray"),     value: "#7f8c8d" },
        { label: i18n("Blue"),     value: "#3498db" },
        { label: i18n("Teal"),     value: "#1abc9c" },
        { label: i18n("Green"),    value: "#2ecc71" },
        { label: i18n("Yellow"),   value: "#f1c40f" },
        { label: i18n("Orange"),   value: "#e67e22" },
        { label: i18n("Red"),      value: "#e74c3c" },
        { label: i18n("Slate"),    value: "#34495e" },
        { label: i18n("Indigo"),   value: "#5b6abf" },
        { label: i18n("Sky"),      value: "#74b9ff" },
        { label: i18n("Mint"),     value: "#4dd0a7" },
        { label: i18n("Sage"),     value: "#a1b79b" },
        { label: i18n("Gold"),     value: "#d4a72c" },
        { label: i18n("Coral"),    value: "#ff8a80" },
        { label: i18n("Rose"),     value: "#c78b9a" },
        { label: i18n("Purple"),   value: "#9b59b6" },
        { label: i18n("Lavender"), value: "#b39ddb" },
    ]

    // -- cfg bindings ---------------------------------------------------------
    property alias cfg_showToolTips: showToolTips.checked
    property alias cfg_highlightWindows: highlightWindows.checked
    property bool cfg_indicateAudioStreams
    property alias cfg_fill: fill.checked
    property alias cfg_maxStripes: maxStripes.value
    property alias cfg_forceStripes: forceStripes.checked
    property alias cfg_iconGap: iconGap.value
    property alias cfg_iconPadding: iconPadding.value
    property alias cfg_iconSize: iconSize.value
    property alias cfg_inactiveIconOpacity: inactiveIconOpacity.value
    property alias cfg_inactiveIconSaturation: inactiveIconSaturation.value
    property alias cfg_animationSpeed: animationSpeed.value
    property alias cfg_maxTextLines: maxTextLines.value

    property string cfg_activeTintColor: ""
    property alias cfg_activeTintOpacity: activeTintOpacity.value
    property alias cfg_showActiveBar: showActiveBar.checked
    property alias cfg_activeBarThickness: activeBarThickness.value
    property alias cfg_taskHoverEffect: taskHoverEffect.checked
    property alias cfg_hoverTintEnabled: hoverTintEnabled.checked
    property alias cfg_hoverTintOpacity: hoverTintOpacity.value
    property string cfg_hoverTintColor: ""
    property string cfg_attentionBarColor: ""

    property string cfg_runningTintColor: ""
    property alias cfg_runningTintOpacity: runningTintOpacity.value

    property string cfg_emptySlotTintColor: ""
    property alias cfg_emptySlotTintOpacity: emptySlotTintOpacity.value

    property alias cfg_bgStyle: bgStyleActive.currentIndex
    property alias cfg_bgStyleInactive: bgStyleInactive.currentIndex
    property alias cfg_bgStyleEmptySlot: bgStyleEmptySlot.currentIndex

    property alias cfg_iconShadowEnabled: iconShadowEnabled.checked
    property alias cfg_iconShadowBlur: iconShadowBlur.value
    property alias cfg_iconShadowOpacity: iconShadowOpacity.value
    property alias cfg_iconShadowOffsetX: iconShadowOffsetX.value
    property alias cfg_iconShadowOffsetY: iconShadowOffsetY.value
    property string cfg_iconShadowColor: ""

    // Per-state shape & border
    property alias cfg_activeCornerRadius: activeCornerRadius.value
    property alias cfg_inactiveCornerRadius: inactiveCornerRadius.value
    property alias cfg_emptySlotCornerRadius: emptySlotCornerRadius.value
    property alias cfg_activeBorderThickness: activeBorderThickness.value
    property alias cfg_inactiveBorderThickness: inactiveBorderThickness.value
    property alias cfg_emptySlotBorderThickness: emptySlotBorderThickness.value
    property alias cfg_activeBorderOpacity: activeBorderOpacity.value
    property alias cfg_inactiveBorderOpacity: inactiveBorderOpacity.value
    property alias cfg_emptySlotBorderOpacity: emptySlotBorderOpacity.value
    property alias cfg_taskBorderActiveEnabled: taskBorderActiveEnabled.checked
    property alias cfg_taskBorderInactiveEnabled: taskBorderInactiveEnabled.checked
    property alias cfg_taskBorderEmptySlotEnabled: taskBorderEmptySlotEnabled.checked
    property string cfg_taskBorderActiveColor: ""
    property string cfg_taskBorderInactiveColor: ""
    property string cfg_taskBorderEmptySlotColor: ""

    readonly property var bgStyleOptions: [i18n("None"), i18n("Solid"), i18n("Glass"), i18n("Gradient")]

    // ---------- reusable slider row (label + slider + value) ----------------
    component LabeledSlider : RowLayout {
        id: ls
        spacing: form.rowSpacing
        property alias from: slider.from
        property alias to: slider.to
        property alias stepSize: slider.stepSize
        property alias value: slider.value
        property string suffix: " px"
        property string zeroLabel: ""
        property int zeroThreshold: -2147483648

        Slider {
            id: slider
            snapMode: Slider.SnapAlways
            Layout.preferredWidth: form.controlWidth
            Layout.fillWidth: false
        }
        Label {
            Layout.preferredWidth: form.valueWidth
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            text: (ls.zeroLabel !== "" && slider.value === ls.zeroThreshold)
                ? ls.zeroLabel
                : (slider.value + ls.suffix)
            opacity: (ls.zeroLabel !== "" && slider.value === ls.zeroThreshold) ? 0.55 : 1.0
        }
    }

    // ---------- reusable color swatch row -----------------------------------
    component ColorSwatchRow : Flow {
        id: swatchRow
        property string currentValue: ""
        property var presets: form.colorPresets
        signal colorPicked(string value)
        spacing: Math.round(Kirigami.Units.smallSpacing * 0.6)
        Layout.preferredWidth: form.controlWidth
        Layout.fillWidth: false

        Repeater {
            model: swatchRow.presets
            delegate: Rectangle {
                readonly property bool selected: swatchRow.currentValue === modelData.value
                readonly property bool isTheme: modelData.value === ""
                width: form.swatchSize
                height: width
                radius: width / 2
                color: isTheme ? "transparent" : modelData.value
                border.width: selected ? 2 : 1
                border.color: selected
                    ? Kirigami.Theme.highlightColor
                    : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.28)
                antialiasing: true

                Label {
                    anchors.centerIn: parent
                    visible: parent.isTheme
                    text: "T"
                    opacity: 0.7
                    font.pixelSize: Math.round(parent.height * 0.55)
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: swatchRow.colorPicked(modelData.value)
                    ToolTip.visible: containsMouse
                    ToolTip.text: modelData.label
                    ToolTip.delay: 400
                }

                Behavior on border.width { NumberAnimation { duration: 90 } }
            }
        }
    }

    component CompactSection : Kirigami.Separator {
        Kirigami.FormData.isSection: true
    }

    // -------------------------------------------------------------------------
    //  TabBar. Flat, modern look — no frames, no floating boxes. A single
    //  hairline runs full-width along the bottom edge of the bar; the active
    //  tab paints a 2-px accent line (Kirigami highlight colour) over that
    //  hairline, which both identifies the selection and visually ties the
    //  tabs to the content below (same style as VS Code / GNOME Adwaita /
    //  Material Design). Inactive tabs are dimmed text only, no buttons.
    // -------------------------------------------------------------------------
    readonly property real _tabHairline: Math.max(1, Math.round(Kirigami.Units.devicePixelRatio))
    readonly property real _tabAccent: Math.max(2, Math.round(Kirigami.Units.devicePixelRatio * 2))

    component StyledTabButton : TabButton {
        id: stb
        padding: Kirigami.Units.smallSpacing
        leftPadding: Kirigami.Units.largeSpacing
        rightPadding: Kirigami.Units.largeSpacing
        implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.9)

        background: Item {
            // Accent underline: fades in/out as the tab activates. Sits on
            // top of the TabBar hairline so there is no visual seam.
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: form._tabAccent
                color: Kirigami.Theme.highlightColor
                opacity: stb.checked ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
            }
            // Subtle hover feedback for inactive tabs — very soft, no box.
            Rectangle {
                anchors.fill: parent
                color: Kirigami.Theme.textColor
                opacity: (stb.hovered && !stb.checked) ? 0.06 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
        }

        contentItem: Label {
            text: stb.text
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            color: stb.checked ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
            opacity: stb.checked ? 1.0 : 0.65
            font.weight: stb.checked ? Font.DemiBold : Font.Normal
            Behavior on opacity { NumberAnimation { duration: 140 } }
        }
    }

    TabBar {
        id: tabs
        Layout.fillWidth: true

        background: Rectangle {
            color: "transparent"
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: form._tabHairline
                color: Qt.rgba(Kirigami.Theme.textColor.r,
                               Kirigami.Theme.textColor.g,
                               Kirigami.Theme.textColor.b, 0.18)
            }
        }

        StyledTabButton { text: i18n("Icons") }
        StyledTabButton { text: i18n("Background") }
        StyledTabButton { text: i18n("Indicators") }
        StyledTabButton { text: i18n("Layout") }
    }

    StackLayout {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.largeSpacing
        currentIndex: tabs.currentIndex

        // ================= TAB 1: ICONS ======================================
        Kirigami.FormLayout {
            id: iconsForm
            Layout.fillWidth: true
            twinFormLayouts: [bgForm, indicatorsForm, layoutForm]

            LabeledSlider {
                id: iconSize
                Kirigami.FormData.label: i18n("Icon size:")
                from: 0; to: 128; stepSize: 2
                zeroLabel: i18n("auto"); zeroThreshold: 0
            }

            LabeledSlider {
                id: iconPadding
                Kirigami.FormData.label: i18n("Padding:")
                from: 0; to: 12; stepSize: 1
                zeroLabel: i18n("none"); zeroThreshold: 0
            }

            CompactSection { Kirigami.FormData.label: i18n("Inactive icons") }

            LabeledSlider {
                id: inactiveIconOpacity
                Kirigami.FormData.label: i18n("Opacity:")
                from: 10; to: 100; stepSize: 5
                suffix: " %"
                zeroLabel: "100 %"; zeroThreshold: 100
            }

            LabeledSlider {
                id: inactiveIconSaturation
                Kirigami.FormData.label: i18n("Saturation:")
                from: 0; to: 100; stepSize: 5
                suffix: " %"
                zeroLabel: i18n("full"); zeroThreshold: 100
            }

            CompactSection { Kirigami.FormData.label: i18n("Drop shadow") }

            CheckBox {
                id: iconShadowEnabled
                Kirigami.FormData.label: i18n("Enable:")
                text: i18n("Shadow under icons")
            }

            LabeledSlider {
                id: iconShadowBlur
                Kirigami.FormData.label: i18n("Blur:")
                enabled: iconShadowEnabled.checked
                opacity: enabled ? 1 : 0.5
                from: 0; to: 24; stepSize: 1
            }

            LabeledSlider {
                id: iconShadowOpacity
                Kirigami.FormData.label: i18n("Opacity:")
                enabled: iconShadowEnabled.checked
                opacity: enabled ? 1 : 0.5
                from: 0; to: 100; stepSize: 5
                suffix: " %"
            }

            RowLayout {
                Kirigami.FormData.label: i18n("Offset X / Y:")
                enabled: iconShadowEnabled.checked
                opacity: enabled ? 1 : 0.5
                spacing: form.rowSpacing

                Slider {
                    id: iconShadowOffsetX
                    from: -12; to: 12; stepSize: 1
                    snapMode: Slider.SnapAlways
                    Layout.preferredWidth: Math.round(form.controlWidth / 2) - form.rowSpacing
                }
                Slider {
                    id: iconShadowOffsetY
                    from: -12; to: 12; stepSize: 1
                    snapMode: Slider.SnapAlways
                    Layout.preferredWidth: Math.round(form.controlWidth / 2) - form.rowSpacing
                }
                Label {
                    Layout.preferredWidth: form.valueWidth
                    horizontalAlignment: Text.AlignRight
                    text: iconShadowOffsetX.value + " / " + iconShadowOffsetY.value
                }
            }

            ColorSwatchRow {
                Kirigami.FormData.label: i18n("Color:")
                enabled: iconShadowEnabled.checked
                opacity: enabled ? 1 : 0.5
                currentValue: cfg_iconShadowColor
                onColorPicked: value => cfg_iconShadowColor = value
            }
        }

        // ================= TAB 2: BACKGROUND =================================
        Kirigami.FormLayout {
            id: bgForm
            Layout.fillWidth: true
            twinFormLayouts: [iconsForm, indicatorsForm, layoutForm]

            CompactSection { Kirigami.FormData.label: i18n("Active window") }

            ComboBox {
                id: bgStyleActive
                Kirigami.FormData.label: i18n("Style:")
                model: bgStyleOptions
                Layout.preferredWidth: form.controlWidth
            }

            ColorSwatchRow {
                Kirigami.FormData.label: i18n("Tint:")
                enabled: bgStyleActive.currentIndex !== 0
                opacity: enabled ? 1 : 0.5
                currentValue: cfg_activeTintColor
                onColorPicked: value => cfg_activeTintColor = value
            }

            LabeledSlider {
                id: activeTintOpacity
                Kirigami.FormData.label: i18n("Opacity:")
                enabled: bgStyleActive.currentIndex !== 0
                opacity: enabled ? 1 : 0.5
                from: 0; to: 100; stepSize: 1
                suffix: " %"
            }

            CheckBox {
                id: hoverTintEnabled
                Kirigami.FormData.label: ""
                text: i18n("Also tint on hover")
                enabled: bgStyleActive.currentIndex !== 0
                opacity: enabled ? 1 : 0.5
            }

            ColorSwatchRow {
                Kirigami.FormData.label: i18n("Hover color:")
                enabled: bgStyleActive.currentIndex !== 0 && hoverTintEnabled.checked
                opacity: enabled ? 1 : 0.5
                currentValue: cfg_hoverTintColor
                onColorPicked: value => cfg_hoverTintColor = value
            }

            LabeledSlider {
                id: hoverTintOpacity
                Kirigami.FormData.label: i18n("Hover intensity:")
                enabled: bgStyleActive.currentIndex !== 0 && hoverTintEnabled.checked
                opacity: enabled ? 1 : 0.5
                from: 10; to: 100; stepSize: 5
                suffix: " %"
            }

            CompactSection { Kirigami.FormData.label: i18n("Inactive window") }

            ComboBox {
                id: bgStyleInactive
                Kirigami.FormData.label: i18n("Style:")
                model: bgStyleOptions
                Layout.preferredWidth: form.controlWidth
            }

            ColorSwatchRow {
                Kirigami.FormData.label: i18n("Tint:")
                enabled: bgStyleInactive.currentIndex !== 0
                opacity: enabled ? 1 : 0.5
                currentValue: cfg_runningTintColor
                onColorPicked: value => cfg_runningTintColor = value
            }

            LabeledSlider {
                id: runningTintOpacity
                Kirigami.FormData.label: i18n("Opacity:")
                enabled: bgStyleInactive.currentIndex !== 0
                opacity: enabled ? 1 : 0.5
                from: 0; to: 100; stepSize: 1
                suffix: " %"
                zeroLabel: i18n("off"); zeroThreshold: 0
            }

            CompactSection { Kirigami.FormData.label: i18n("Empty slot") }

            ComboBox {
                id: bgStyleEmptySlot
                Kirigami.FormData.label: i18n("Style:")
                model: bgStyleOptions
                Layout.preferredWidth: form.controlWidth
            }

            ColorSwatchRow {
                Kirigami.FormData.label: i18n("Tint:")
                enabled: bgStyleEmptySlot.currentIndex !== 0
                opacity: enabled ? 1 : 0.5
                currentValue: cfg_emptySlotTintColor
                onColorPicked: value => cfg_emptySlotTintColor = value
            }

            LabeledSlider {
                id: emptySlotTintOpacity
                Kirigami.FormData.label: i18n("Opacity:")
                enabled: bgStyleEmptySlot.currentIndex !== 0
                opacity: enabled ? 1 : 0.5
                from: 0; to: 100; stepSize: 1
                suffix: " %"
                zeroLabel: i18n("off"); zeroThreshold: 0
            }

            CompactSection { Kirigami.FormData.label: i18n("Shape & border — Active") }

            LabeledSlider {
                id: activeCornerRadius
                Kirigami.FormData.label: i18n("Corner radius:")
                from: 0; to: 16; stepSize: 1
                zeroLabel: i18n("flat"); zeroThreshold: 0
            }

            CheckBox {
                id: taskBorderActiveEnabled
                Kirigami.FormData.label: i18n("Border:")
                text: i18n("Draw around active")
            }

            LabeledSlider {
                id: activeBorderThickness
                Kirigami.FormData.label: i18n("Thickness:")
                enabled: taskBorderActiveEnabled.checked
                opacity: enabled ? 1 : 0.5
                from: 1; to: 4; stepSize: 1
            }

            LabeledSlider {
                id: activeBorderOpacity
                Kirigami.FormData.label: i18n("Opacity:")
                enabled: taskBorderActiveEnabled.checked
                opacity: enabled ? 1 : 0.5
                from: 10; to: 100; stepSize: 5
                suffix: " %"
            }

            ColorSwatchRow {
                Kirigami.FormData.label: i18n("Color:")
                enabled: taskBorderActiveEnabled.checked
                opacity: enabled ? 1 : 0.5
                currentValue: cfg_taskBorderActiveColor
                onColorPicked: value => cfg_taskBorderActiveColor = value
            }

            CompactSection { Kirigami.FormData.label: i18n("Shape & border — Inactive") }

            LabeledSlider {
                id: inactiveCornerRadius
                Kirigami.FormData.label: i18n("Corner radius:")
                from: 0; to: 16; stepSize: 1
                zeroLabel: i18n("flat"); zeroThreshold: 0
            }

            CheckBox {
                id: taskBorderInactiveEnabled
                Kirigami.FormData.label: i18n("Border:")
                text: i18n("Draw around inactive")
            }

            LabeledSlider {
                id: inactiveBorderThickness
                Kirigami.FormData.label: i18n("Thickness:")
                enabled: taskBorderInactiveEnabled.checked
                opacity: enabled ? 1 : 0.5
                from: 1; to: 4; stepSize: 1
            }

            LabeledSlider {
                id: inactiveBorderOpacity
                Kirigami.FormData.label: i18n("Opacity:")
                enabled: taskBorderInactiveEnabled.checked
                opacity: enabled ? 1 : 0.5
                from: 10; to: 100; stepSize: 5
                suffix: " %"
            }

            ColorSwatchRow {
                Kirigami.FormData.label: i18n("Color:")
                enabled: taskBorderInactiveEnabled.checked
                opacity: enabled ? 1 : 0.5
                currentValue: cfg_taskBorderInactiveColor
                onColorPicked: value => cfg_taskBorderInactiveColor = value
            }

            CompactSection { Kirigami.FormData.label: i18n("Shape & border — Empty slot") }

            LabeledSlider {
                id: emptySlotCornerRadius
                Kirigami.FormData.label: i18n("Corner radius:")
                from: 0; to: 16; stepSize: 1
                zeroLabel: i18n("flat"); zeroThreshold: 0
            }

            CheckBox {
                id: taskBorderEmptySlotEnabled
                Kirigami.FormData.label: i18n("Border:")
                text: i18n("Draw around empty")
            }

            LabeledSlider {
                id: emptySlotBorderThickness
                Kirigami.FormData.label: i18n("Thickness:")
                enabled: taskBorderEmptySlotEnabled.checked
                opacity: enabled ? 1 : 0.5
                from: 1; to: 4; stepSize: 1
            }

            LabeledSlider {
                id: emptySlotBorderOpacity
                Kirigami.FormData.label: i18n("Opacity:")
                enabled: taskBorderEmptySlotEnabled.checked
                opacity: enabled ? 1 : 0.5
                from: 10; to: 100; stepSize: 5
                suffix: " %"
            }

            ColorSwatchRow {
                Kirigami.FormData.label: i18n("Color:")
                enabled: taskBorderEmptySlotEnabled.checked
                opacity: enabled ? 1 : 0.5
                currentValue: cfg_taskBorderEmptySlotColor
                onColorPicked: value => cfg_taskBorderEmptySlotColor = value
            }
        }

        // ================= TAB 3: INDICATORS =================================
        Kirigami.FormLayout {
            id: indicatorsForm
            Layout.fillWidth: true
            twinFormLayouts: [iconsForm, bgForm, layoutForm]

            CompactSection { Kirigami.FormData.label: i18n("Edge bar") }

            CheckBox {
                id: showActiveBar
                Kirigami.FormData.label: i18n("State bar:")
                text: i18n("Show on active / attention")
            }

            LabeledSlider {
                id: activeBarThickness
                Kirigami.FormData.label: i18n("Thickness:")
                enabled: showActiveBar.checked
                opacity: enabled ? 1 : 0.5
                from: 1; to: 6; stepSize: 1
            }

            CheckBox {
                id: taskHoverEffect
                Kirigami.FormData.label: ""
                text: i18n("Also show on hover")
                enabled: showActiveBar.checked
                opacity: enabled ? 1 : 0.5
            }

            ColorSwatchRow {
                Kirigami.FormData.label: i18n("Attention:")
                enabled: showActiveBar.checked
                opacity: enabled ? 1 : 0.5
                currentValue: cfg_attentionBarColor
                onColorPicked: value => cfg_attentionBarColor = value
            }

            CompactSection { Kirigami.FormData.label: i18n("Text label") }

            LabeledSlider {
                id: maxTextLines
                Kirigami.FormData.label: i18n("Max lines:")
                from: 0; to: 4; stepSize: 1
                suffix: ""
                zeroLabel: i18n("unlimited"); zeroThreshold: 0
            }
        }

        // ================= TAB 4: LAYOUT =====================================
        Kirigami.FormLayout {
            id: layoutForm
            Layout.fillWidth: true
            twinFormLayouts: [iconsForm, bgForm, indicatorsForm]

            CompactSection { Kirigami.FormData.label: i18n("Tooltips") }

            CheckBox {
                id: showToolTips
                Kirigami.FormData.label: i18n("Previews:")
                text: i18n("Show window previews on hover")
            }

            CheckBox {
                id: highlightWindows
                Kirigami.FormData.label: ""
                text: i18n("Dim others while hovering")
            }

            CheckBox {
                id: indicateAudioStreams
                Kirigami.FormData.label: i18n("Audio:")
                text: i18n("Mark apps that play audio")
                checked: cfg_indicateAudioStreams && plasmaPaAvailable
                onCheckedChanged: cfg_indicateAudioStreams = checked
                enabled: plasmaPaAvailable
            }

            CompactSection { Kirigami.FormData.label: i18n("Arrangement") }

            CheckBox {
                id: fill
                Kirigami.FormData.label: i18n("Space:")
                text: i18nc("@option:check", "Fill free space on panel")
            }

            RowLayout {
                Kirigami.FormData.label: plasmoidVertical ? i18n("Max columns:") : i18n("Max rows:")
                spacing: form.rowSpacing
                SpinBox {
                    id: maxStripes
                    from: 1; to: 8
                    Layout.preferredWidth: Math.round(form.controlWidth / 2)
                }
                CheckBox {
                    id: forceStripes
                    text: i18n("Force")
                    enabled: maxStripes.value > 1
                    opacity: enabled ? 1 : 0.5
                }
            }

            LabeledSlider {
                id: iconGap
                Kirigami.FormData.label: i18n("Icon gap:")
                from: 0; to: 24; stepSize: 1
                zeroLabel: i18n("none"); zeroThreshold: 0
            }

            LabeledSlider {
                id: animationSpeed
                Kirigami.FormData.label: i18n("Animations:")
                from: 0; to: 600; stepSize: 10
                suffix: " ms"
                zeroLabel: i18n("instant"); zeroThreshold: 0
            }
        }
    }
}
