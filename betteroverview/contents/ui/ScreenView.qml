/*
    SPDX-FileCopyrightText: 2026 mj0x0
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents
import org.kde.plasma.components as PC3

FocusScope {
    id: root
    focus: true

    readonly property QtObject targetScreen: KWinComponents.SceneView.screen
    readonly property QtObject currentDesktop: KWinComponents.SceneView.currentDesktop
    readonly property var desktops: KWinComponents.Workspace.desktops
    readonly property int desktopCount: Math.max(1, desktops.length)
    readonly property QtObject cfg: effect.configuration

    readonly property real screenW: targetScreen.geometry.width
    readonly property real screenH: targetScreen.geometry.height
    readonly property real screenX: targetScreen.geometry.x
    readonly property real screenY: targetScreen.geometry.y
    readonly property real dpr: targetScreen.devicePixelRatio
    readonly property int spacing: 5
    readonly property int padding: 10
    readonly property bool blur: cfg.Blur
    readonly property bool hideEmptyRows: cfg.HideEmptyRows

    readonly property int columns: {
        const n = desktopCount;
        if (cfg.Columns > 0) {
            return Math.min(cfg.Columns, n);
        }
        if (cfg.Rows > 0) {
            return Math.ceil(n / cfg.Rows);
        }
        // near-square panel: wide tiles want more columns than rows
        let c = Math.ceil(Math.sqrt(n * screenW / screenH));
        const r = Math.ceil(n / c);
        while (c > 1 && Math.ceil(n / (c - 1)) === r) {
            c--;
        }
        return c;
    }
    readonly property int rows: Math.ceil(desktopCount / columns)

    readonly property real tileScale: {
        const availW = screenW * cfg.PanelWidth / 100 - 2 * padding;
        const availH = screenH - cfg.TopMargin - Kirigami.Units.gridUnit * 4 - 2 * padding;
        const fit = Math.min(availW / (columns * screenW + (columns - 1) * spacing),
                             availH / (rows * screenH + (rows - 1) * spacing));
        return Math.max(0.05, Math.min(fit, cfg.MaxScale));
    }
    readonly property int tileW: Math.round(screenW * tileScale)
    readonly property int tileH: Math.round(screenH * tileScale)
    readonly property real tileRadius: Math.max(4, 24 * tileScale)
    readonly property real panelRadius: tileRadius + padding

    property var rowVisible: []
    property var rowOffset: []
    property int visibleRowCount: rows
    property Item dropTarget: null
    property Item hoveredWindow: null
    readonly property var otherScreens: KWinComponents.Workspace.screens.filter(s => s !== targetScreen)
    property bool dragActive: false

    property bool ready: false
    property real openProgress: ready && effect.activated ? 1 : 0
    Behavior on openProgress {
        NumberAnimation {
            duration: effect.animationDuration
            easing.type: Easing.OutCubic
        }
    }
    Component.onCompleted: Qt.callLater(() => { root.ready = true; root.updateRows(); })

    Item {
        id: panelTheme
        Kirigami.Theme.inherit: false
        Kirigami.Theme.colorSet: root.colorSet(root.cfg.PanelColorSet)
    }
    Item {
        id: tileTheme
        Kirigami.Theme.inherit: false
        Kirigami.Theme.colorSet: root.colorSet(root.cfg.TileColorSet)
    }
    Item {
        id: windowTheme
        Kirigami.Theme.inherit: false
        Kirigami.Theme.colorSet: root.colorSet(root.cfg.WindowColorSet)
    }
    readonly property color panelColor: panelTheme.Kirigami.Theme.backgroundColor
    readonly property color panelText: panelTheme.Kirigami.Theme.textColor
    readonly property color tileColor: tileTheme.Kirigami.Theme.backgroundColor
    readonly property color tileText: tileTheme.Kirigami.Theme.textColor
    readonly property color windowColor: windowTheme.Kirigami.Theme.backgroundColor
    readonly property color outlineColor: windowTheme.Kirigami.Theme.textColor
    readonly property color accentColor: {
        switch (cfg.ActiveBorderColor) {
        case 1: return Kirigami.Theme.focusColor;
        case 2: return Kirigami.Theme.linkColor;
        case 3: return Kirigami.Theme.textColor;
        default: return Kirigami.Theme.highlightColor;
        }
    }

    function colorSet(index) {
        switch (index) {
        case 1: return Kirigami.Theme.Window;
        case 2: return Kirigami.Theme.Button;
        case 3: return Kirigami.Theme.Tooltip;
        case 4: return Kirigami.Theme.Complementary;
        case 5: return Kirigami.Theme.Header;
        default: return Kirigami.Theme.View;
        }
    }

    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    function switchTo(desktop) {
        root.KWinComponents.SceneView.currentDesktop = desktop;
    }

    function activateWindow(window) {
        if (window.minimized) {
            window.minimized = false;
        }
        KWinComponents.Workspace.activeWindow = window;
        effect.deactivate();
    }

    function stepDesktop(delta) {
        const n = desktops.length;
        if (n < 2) {
            return;
        }
        const i = desktops.indexOf(currentDesktop);
        switchTo(desktops[((i + delta) % n + n) % n]);
    }

    function updateRows() {
        const vis = [];
        const off = [];
        let count = 0;
        for (let r = 0; r < rows; r++) {
            let show = !hideEmptyRows;
            for (let c = 0; !show && c < columns; c++) {
                const i = r * columns + c;
                if (i >= desktops.length) {
                    break;
                }
                const tile = tiles.itemAt(i);
                show = desktops[i] === currentDesktop || (tile !== null && tile.windowCount > 0);
            }
            vis.push(show);
            off.push(count);
            if (show) {
                count++;
            }
        }
        rowVisible = vis;
        rowOffset = off;
        visibleRowCount = Math.max(1, count);
    }

    onRowsChanged: updateRows()
    onColumnsChanged: updateRows()
    onDesktopCountChanged: updateRows()
    onCurrentDesktopChanged: updateRows()
    onHideEmptyRowsChanged: updateRows()

    Connections {
        target: effect
        function onItemDroppedOutOfScreen(globalPos, item, screen) {
            if (screen !== root.targetScreen) {
                return;
            }
            const local = root.targetScreen.mapFromGlobal(globalPos);
            const p = grid.mapFromItem(root, local.x, local.y);
            for (let i = 0; i < tiles.count; i++) {
                const t = tiles.itemAt(i);
                if (t && t.visible && p.x >= t.x && p.x < t.x + t.width && p.y >= t.y && p.y < t.y + t.height) {
                    const w = item.window;
                    KWinComponents.Workspace.sendClientToScreen(w, screen);
                    if (w.desktops.length > 0) {
                        w.desktops = [t.desktop];
                    }
                    return;
                }
            }
        }
    }

    Keys.onPressed: (event) => {
        const idx = Math.max(0, desktops.indexOf(currentDesktop));
        const col = idx % columns;
        const row = Math.floor(idx / columns);
        let target = -1;
        switch (event.key) {
        case Qt.Key_Escape:
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            effect.deactivate();
            event.accepted = true;
            return;
        case Qt.Key_Left:
        case Qt.Key_H:
            target = row * columns + (col - 1 + columns) % columns;
            if (target >= desktopCount) {
                target = desktopCount - 1;
            }
            break;
        case Qt.Key_Right:
        case Qt.Key_L:
            target = row * columns + (col + 1) % columns;
            if (target >= desktopCount) {
                target = row * columns;
            }
            break;
        case Qt.Key_Up:
        case Qt.Key_K:
            target = ((row - 1 + rows) % rows) * columns + col;
            break;
        case Qt.Key_Down:
        case Qt.Key_J:
            target = ((row + 1) % rows) * columns + col;
            break;
        case Qt.Key_0:
            target = 9;
            break;
        default:
            if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                target = event.key - Qt.Key_1;
            }
        }
        if (target >= 0 && target < desktops.length) {
            switchTo(desktops[target]);
            event.accepted = true;
        }
    }

    component SharpThumbnail: Item {
        id: thumb

        required property QtObject window
        property real radius: 0

        // at least half the window's pixels so the first downsample stays <= 2x; mipmaps do the rest
        readonly property size textureSize: {
            const winW = window.width * root.dpr;
            const winH = window.height * root.dpr;
            const w = Math.min(winW, Math.max(width * root.dpr * 2, winW / 2));
            const h = Math.min(winH, Math.max(height * root.dpr * 2, winH / 2));
            return Qt.size(Math.max(1, Math.round(w)), Math.max(1, Math.round(h)));
        }

        KWinComponents.WindowThumbnail {
            anchors.fill: parent
            wId: thumb.window.internalId
            layer.enabled: true
            layer.mipmap: true
            layer.smooth: true
            layer.textureSize: thumb.textureSize
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: mask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
        }

        Item {
            id: mask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            layer.smooth: true
            Rectangle {
                anchors.fill: parent
                radius: thumb.radius
            }
        }
    }

    component WindowTile: Item {
        id: win

        required property QtObject window
        required property Item tile

        readonly property real s: tile.scale
        readonly property real wx: (window.x - tile.screen.geometry.x) * s
        readonly property real wy: (window.y - tile.screen.geometry.y) * s
        readonly property real ww: window.width * s
        readonly property real wh: window.height * s
        // the on-screen part of the window, in tile coordinates
        readonly property real initX: Math.round(Math.max(0, wx))
        readonly property real initY: Math.round(Math.max(0, wy))
        readonly property real initW: Math.round(Math.min(wx + ww, tile.width) - initX)
        readonly property real initH: Math.round(Math.min(wy + wh, tile.height) - initY)
        readonly property bool mini: window.minimized
        readonly property int slot: mini ? tile.minimizedItems.indexOf(win) : -1
        readonly property real chip: tile.chipSize
        readonly property bool shown: !window.skipPager && (mini ? root.cfg.ShowMinimized : initW > 0 && initH > 0)
        readonly property bool compact: Math.min(width, height) < 56
        readonly property bool dragging: dragArea.drag.active
        readonly property bool hovered: dragArea.containsMouse
        readonly property real radius: Math.max(2, 18 * s)

        x: mini ? 6 + slot * (chip + 4) : initX
        y: mini ? tile.height - chip - 6 : initY
        width: mini ? chip : Math.max(1, initW)
        height: mini ? chip : Math.max(1, initH)
        visible: shown
        clip: true
        // minimized chips sit above everything so they stay reachable
        z: dragging ? 100000 : (mini ? 20000 + slot : window.stackingOrder)

        Drag.source: win.window
        Drag.keys: ["kwin-window"]

        Behavior on x {
            enabled: !win.dragging
            NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
        }
        Behavior on y {
            enabled: !win.dragging
            NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
        }

        Item {
            x: win.mini ? 0 : Math.round(Math.min(0, win.wx))
            y: win.mini ? 0 : Math.round(Math.min(0, win.wy))
            width: win.mini ? win.chip : Math.round(win.ww)
            height: win.mini ? win.chip : Math.round(win.wh)

            Rectangle {
                anchors.fill: parent
                radius: win.radius
                color: root.windowColor
                opacity: win.mini ? 0.7 : 1
            }

            SharpThumbnail {
                anchors.fill: parent
                window: win.window
                radius: win.radius
                visible: !win.window.minimized
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: win.radius
            color: root.alpha(root.windowColor, dragArea.pressed ? 0.5 : (win.hovered ? 0.4 : 0.22))
            border.width: 1
            border.color: root.alpha(root.outlineColor, win.window.minimized ? 0.5 : 0.3)
        }

        Kirigami.Icon {
            anchors.centerIn: parent
            readonly property int iconSize: Math.round(Math.min(win.width, win.height) * (win.mini ? 0.6 : (win.compact ? 0.45 : 0.25)))
            width: iconSize
            height: iconSize
            source: win.window.icon
            opacity: win.window.minimized ? 0.7 : 1
        }

        MouseArea {
            id: dragArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            drag.target: win
            onPressed: (mouse) => {
                if (mouse.button !== Qt.LeftButton) {
                    return;
                }
                win.Drag.hotSpot = Qt.point(mouse.x, mouse.y);
                win.Drag.active = true;
                win.tile.dragging = true;
                root.dragActive = true;
            }
            onReleased: (mouse) => {
                const target = root.dropTarget;
                const w = win.window;
                const globalPos = root.targetScreen.mapToGlobal(root.mapFromItem(dragArea, mouse.x, mouse.y));
                win.Drag.active = false;
                win.tile.dragging = false;
                root.dragActive = false;
                root.dropTarget = null;
                const otherScreen = target && w.output !== target.screen;
                const otherDesktop = target && w.desktops.length > 0 && w.desktops.indexOf(target.desktop) === -1;
                if (otherScreen || otherDesktop) {
                    // deferred: the model removes this delegate as soon as the window moves
                    Qt.callLater(() => {
                        if (otherScreen) {
                            KWinComponents.Workspace.sendClientToScreen(w, target.screen);
                        }
                        if (otherDesktop) {
                            w.desktops = [target.desktop];
                        }
                    });
                } else {
                    win.x = Qt.binding(() => win.mini ? 6 + win.slot * (win.chip + 4) : win.initX);
                    win.y = Qt.binding(() => win.mini ? win.tile.height - win.chip - 6 : win.initY);
                    // another screen's view answers via onItemDroppedOutOfScreen
                    effect.checkItemDroppedOutOfScreen(globalPos, win);
                }
            }
            onClicked: (mouse) => {
                if (mouse.button === Qt.LeftButton) {
                    root.activateWindow(win.window);
                } else if (mouse.button === Qt.MiddleButton) {
                    win.window.closeWindow();
                } else if (mouse.button === Qt.RightButton) {
                    win.window.desktops = win.window.desktops.length > 0 ? [] : [win.tile.desktop];
                }
            }
        }

        onHoveredChanged: root.hoveredWindow = hovered ? win : (root.hoveredWindow === win ? null : root.hoveredWindow)
    }

    component DesktopTile: Item {
        id: desktopTile

        required property QtObject desktop
        property QtObject screen: root.targetScreen
        property real scale: root.tileScale
        property string label: String(desktop.x11DesktopNumber)
        required property int index

        readonly property int column: index % root.columns
        readonly property int row: Math.floor(index / root.columns)
        readonly property var minimizedItems: {
            const items = [];
            for (let i = 0; i < windows.count; i++) {
                const item = windows.itemAt(i);
                if (item && item.shown && item.window.minimized) {
                    items.push(item);
                }
            }
            return items;
        }
        readonly property real chipSize: Math.max(24, Math.min(Math.round(height * 0.2), (width - 12) / Math.max(1, minimizedItems.length) - 4))

        // only windows the tile draws; sticky windows sit in every tile and must not keep rows alive
        readonly property int windowCount: {
            let n = 0;
            for (let i = 0; i < windows.count; i++) {
                const item = windows.itemAt(i);
                if (item && item.shown && !item.window.onAllDesktops) {
                    n++;
                }
            }
            return n;
        }
        property bool dropHover: false
        property bool dragging: false

        width: Math.round(screen.geometry.width * scale)
        height: Math.round(screen.geometry.height * scale)
        z: dragging ? 10 : 0

        Rectangle {
            anchors.fill: parent
            radius: root.tileRadius
            color: root.alpha(root.tileColor, desktopTile.dropHover ? 0.95 : 0.86)
            border.width: desktopTile.dropHover ? 2 : 0
            border.color: root.alpha(root.accentColor, 0.75)
        }

        Loader {
            anchors.fill: parent
            active: root.cfg.WallpaperTiles
            sourceComponent: Item {
                KWinComponents.DesktopBackground {
                    id: wallpaper
                    anchors.fill: parent
                    activity: KWinComponents.Workspace.currentActivity
                    desktop: desktopTile.desktop
                    outputName: desktopTile.screen.name
                    visible: false
                }
                Kirigami.ShadowedTexture {
                    anchors.fill: parent
                    source: wallpaper
                    radius: root.tileRadius
                    color: "transparent"
                }
                Rectangle {
                    anchors.fill: parent
                    radius: root.tileRadius
                    color: root.alpha(root.tileColor, desktopTile.dropHover ? 0.35 : 0.15)
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: !root.cfg.WallpaperTiles && desktopTile.label.length > 0
            text: desktopTile.label
            font.pixelSize: Math.max(12, Math.round(desktopTile.height * 0.42))
            font.weight: Font.DemiBold
            color: root.alpha(root.tileText, 0.2)
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            enabled: desktopTile.screen === root.targetScreen
            onClicked: {
                root.switchTo(desktopTile.desktop);
                effect.deactivate();
            }
        }

        DropArea {
            anchors.fill: parent
            keys: ["kwin-window"]
            onEntered: (drag) => {
                const w = drag.source;
                const sameScreen = w && w.output === desktopTile.screen;
                const onDesktop = w && (w.desktops.length === 0 || w.desktops.indexOf(desktopTile.desktop) !== -1);
                if (!w || (sameScreen && onDesktop)) {
                    return;
                }
                desktopTile.dropHover = true;
                root.dropTarget = desktopTile;
            }
            onExited: {
                desktopTile.dropHover = false;
                if (root.dropTarget === desktopTile) {
                    root.dropTarget = null;
                }
            }
        }

        Repeater {
            id: windows
            model: KWinComponents.WindowFilterModel {
                activity: KWinComponents.Workspace.currentActivity
                desktop: desktopTile.desktop
                screenName: desktopTile.screen.name
                windowModel: KWinComponents.WindowModel {}
                minimizedWindows: true
                windowType: ~KWinComponents.WindowFilterModel.Dock &
                            ~KWinComponents.WindowFilterModel.Desktop &
                            ~KWinComponents.WindowFilterModel.Notification &
                            ~KWinComponents.WindowFilterModel.CriticalNotification
            }
            delegate: WindowTile {
                tile: desktopTile
            }
        }
    }

    // KWin paints nothing beneath a SceneEffect, so the live desktop is drawn here
    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    Item {
        id: backdrop
        // container keeps the thumbnails' z (stacking order) from competing with the panel
        anchors.fill: parent
        Repeater {
            model: KWinComponents.WindowFilterModel {
                activity: KWinComponents.Workspace.currentActivity
                desktop: root.currentDesktop
                screenName: root.targetScreen.name
                windowModel: KWinComponents.WindowModel {}
                minimizedWindows: false
            }
            KWinComponents.WindowThumbnail {
                required property QtObject window
                wId: window.internalId
                x: window.x - root.screenX
                y: window.y - root.screenY
                width: window.width
                height: window.height
                z: window.stackingOrder
                visible: !window.hidden
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.openProgress * root.cfg.BackdropDim / 100
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: effect.deactivate()
        onWheel: (wheel) => root.stepDesktop(wheel.angleDelta.y > 0 ? -1 : 1)
    }

    // one popup for all windows: a ToolTip per window made every open ~15 popups heavier
    PC3.ToolTip {
        parent: root.hoveredWindow ?? root
        visible: root.hoveredWindow !== null && !root.dragActive
        delay: Kirigami.Units.toolTipDelay
        text: root.hoveredWindow ? root.hoveredWindow.window.caption + "\n[" + root.hoveredWindow.window.resourceClass + "]" : ""
    }

    ShaderEffectSource {
        id: panelBackdrop
        visible: false
        live: root.blur
        sourceItem: root.blur ? backdrop : null
        sourceRect: Qt.rect(panel.x, panel.y, panel.width, panel.height)
    }

    Item {
        id: panelMask
        visible: false
        width: panel.width
        height: panel.height
        layer.enabled: true
        layer.smooth: true
        Rectangle {
            anchors.fill: parent
            radius: root.panelRadius
        }
    }

    MultiEffect {
        visible: root.blur
        source: panelBackdrop
        x: panel.x
        y: panel.y
        width: panel.width
        height: panel.height
        opacity: panel.opacity
        scale: panel.scale
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 1.0
        blurMax: root.cfg.BlurRadius
        maskEnabled: true
        maskSource: panelMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }

    Kirigami.ShadowedRectangle {
        id: panel
        x: Math.round((root.width - width) / 2)
        y: root.cfg.TopMargin
        readonly property int gridW: root.columns * root.tileW + (root.columns - 1) * root.spacing
        readonly property int gridH: root.visibleRowCount * root.tileH + (root.visibleRowCount - 1) * root.spacing
        readonly property int sideW: sidebar.visible ? 4 * root.spacing + 1 + sidebar.width : 0
        width: gridW + sideW + 2 * root.padding
        height: Math.max(gridH, sidebar.height) + 2 * root.padding
        radius: root.panelRadius
        color: root.alpha(root.panelColor, root.cfg.PanelOpacity / 100)
        border.width: 1
        border.color: root.alpha(root.panelText, 0.12)
        shadow.size: Kirigami.Units.gridUnit
        shadow.color: Qt.rgba(0, 0, 0, 0.45)
        shadow.yOffset: 2
        opacity: root.openProgress
        scale: 0.96 + 0.04 * root.openProgress

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: (mouse) => mouse.accepted = true
            onWheel: (wheel) => root.stepDesktop(wheel.angleDelta.y > 0 ? -1 : 1)
        }

        Item {
            id: grid
            x: root.padding
            y: root.padding
            width: panel.gridW
            height: panel.gridH

            Repeater {
                id: tiles
                model: KWinComponents.VirtualDesktopModel {}
                delegate: DesktopTile {
                    x: column * (root.tileW + root.spacing)
                    y: (root.rowOffset[row] ?? row) * (root.tileH + root.spacing)
                    visible: root.rowVisible[row] !== false
                    onWindowCountChanged: root.updateRows()
                }
            }

            Rectangle {
                id: activeIndicator
                readonly property int idx: Math.max(0, root.desktops.indexOf(root.currentDesktop))
                readonly property int row: Math.floor(idx / root.columns)
                x: (idx % root.columns) * (root.tileW + root.spacing)
                y: (root.rowOffset[row] ?? row) * (root.tileH + root.spacing)
                z: 5
                width: root.tileW
                height: root.tileH
                radius: root.tileRadius
                color: "transparent"
                border.width: 2
                border.color: root.accentColor
                Behavior on x {
                    NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
                }
                Behavior on y {
                    NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
                }
            }
        }

        // other screens stack beside the grid; drop a window on one to send it over
        Rectangle {
            id: divider
            visible: sidebar.visible
            x: root.padding + panel.gridW + 2 * root.spacing
            y: root.padding
            width: 1
            height: Math.max(panel.gridH, sidebar.height)
            color: root.alpha(root.panelText, 0.12)
        }

        Column {
            id: sidebar
            visible: root.otherScreens.length > 0
            x: divider.x + 1 + 2 * root.spacing
            y: root.padding
            spacing: 2 * root.spacing

            Repeater {
                model: root.otherScreens
                Column {
                    id: card
                    required property QtObject modelData
                    spacing: root.spacing

                    DesktopTile {
                        id: otherTile
                        index: -1
                        screen: card.modelData
                        scale: root.tileW * 0.5 / card.modelData.geometry.width
                        desktop: KWinComponents.Workspace.currentDesktopForScreen(card.modelData)
                        label: ""
                    }

                    Text {
                        width: otherTile.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideMiddle
                        text: card.modelData.name
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        color: root.alpha(root.panelText, 0.6)
                    }

                    Connections {
                        target: KWinComponents.Workspace
                        function onCurrentDesktopChanged(previous, current, output) {
                            if (output === card.modelData) {
                                otherTile.desktop = current;
                            }
                        }
                    }
                }
            }
        }
    }
}
