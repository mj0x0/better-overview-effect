/*
    SPDX-FileCopyrightText: 2026 mj0x0
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents

KWinComponents.SceneEffect {
    id: effect

    property bool activated: false
    // what KWin actually did: it refuses to start while another full-screen effect runs (e.g. Slide)
    property bool kwinRunning: false
    onActivated: kwinRunning = true
    onDeactivated: kwinRunning = false
    readonly property int animationDuration: Kirigami.Units.longDuration

    // KWin's shared QML engine caches files by URL for the whole session; the stamp makes re-enabling the effect load edited files
    property var mainDelegate: Qt.createComponent("ScreenView.qml?" + Date.now())
    delegate: mainDelegate

    Instantiator {
        model: effect.configuration.BorderActivate
        KWinComponents.ScreenEdgeHandler {
            mode: KWinComponents.ScreenEdgeHandler.Pointer
            edge: modelData
            onActivated: effect.toggle()
        }
    }

    Instantiator {
        model: effect.configuration.TouchBorderActivate
        KWinComponents.ScreenEdgeHandler {
            mode: KWinComponents.ScreenEdgeHandler.Touch
            edge: modelData
            onActivated: effect.toggle()
        }
    }

    KWinComponents.ShortcutHandler {
        name: "Better Overview"
        text: i18nd("kwin_effect_betteroverview", "Toggle Better Overview")
        onActivated: effect.toggle()
    }

    Timer {
        id: deactivateTimer
        interval: effect.animationDuration
        onTriggered: effect.visible = false
    }

    Timer {
        id: retryTimer
        interval: 50
        repeat: true
        property int attempts: 0
        onTriggered: {
            if (++attempts > 20 || effect.activated) {
                stop();
                return;
            }
            effect.activate();
        }
    }

    function toggle() {
        if (activated) {
            deactivate();
        } else {
            activate();
        }
    }

    function activate() {
        if (activated) {
            return;
        }
        // re-opening during the fade-out reuses the live views instead of dropping the press
        deactivateTimer.stop();
        visible = true;
        if (!kwinRunning) {
            visible = false;
            if (!retryTimer.running) {
                retryTimer.attempts = 0;
                retryTimer.start();
            }
            return;
        }
        retryTimer.stop();
        activated = true;
    }

    function deactivate() {
        if (!activated) {
            return;
        }
        activated = false;
        deactivateTimer.start();
    }
}
