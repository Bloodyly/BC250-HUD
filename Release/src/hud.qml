import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Shapes 1.14

// ═══════════════════════════════════════════════════════════════════
//  BC-250  TACTICAL DISPLAY  //  PORTRAIT EDITION  //  480×1920px
//  Basiert auf dem Querformat-Design (mecha/cyberpunk/scifi)
//  Kein Item-Rotation — native 480×1920 Layout
// ═══════════════════════════════════════════════════════════════════
Window {
    id: root
    visible: true
    width:  480
    height: 1920
    color:  "#020B18"
    flags:  Qt.FramelessWindowHint | Qt.Window

    // ── Palette ────────────────────────────────────────────────────
    readonly property color cBg:    "#020B18"
    readonly property color cBlue:  "#00AAFF"
    readonly property color cBlue2: "#0055BB"
    readonly property color cVio:   "#9933FF"
    readonly property color cVio2:  "#CC77FF"
    readonly property color cGreen: "#00FF88"
    readonly property color cAmber: "#FFAA00"
    readonly property color cRed:   "#FF2244"
    readonly property color cDim:   "#0D1F33"

    // ── FPS-Zähler (intern) ────────────────────────────────────────
    property int  fps: 0
    property int  _fpsCount: 0
    property real _tick: 0
    property alias tick: root._tick
    SequentialAnimation on _tick {
        running: true; loops: Animation.Infinite
        NumberAnimation { from: 0; to: 100000; duration: 100000000; easing.type: Easing.Linear }
    }
    onTickChanged: { _fpsCount++ }

    // ── Netzwerk-History (Sparkline-Graphen) ──────────────────────
    property var  netRxHistory: []
    property var  netTxHistory: []
    property real netPeak: 1.0

    // ── Boot-Animation State ───────────────────────────────────────
    property string _prevState:   ""
    property real   _bootAlpha:   1.0
    property int    _revealStage: 6
    property real   _crtYScale:   1.0   // CRT-Ausschalt-Animation (1.0 = normal)

    // Bei erstem Laden UND bei Hot-Reload: sofort in den richtigen Zustand springen,
    // ohne auf ein onAppStateChanged-Signal zu warten (das bei gleichbleibendem State
    // nicht erneut feuert).
    Component.onCompleted: {
        var st = hud.appState
        root._prevState = st
        if (st === "running" || st === "gaming") {
            root._bootAlpha   = 0.0
            root._revealStage = 6
            root._crtYScale   = 1.0
        }
    }

    Timer { interval: 1000; repeat: true; running: true
            onTriggered: {
                root.fps = root._fpsCount; root._fpsCount = 0
                var rx = hud.netRxMbps || 0
                var tx = hud.netTxMbps || 0
                var rh = root.netRxHistory.slice(); rh.push(rx); if(rh.length>40) rh.shift(); root.netRxHistory = rh
                var th = root.netTxHistory.slice(); th.push(tx); if(th.length>40) th.shift(); root.netTxHistory = th
                root.netPeak = Math.max(1.0, Math.max.apply(null, rh.concat(th)))
                netRxCanvas.requestPaint()
                netTxCanvas.requestPaint()
            } }

    // ── Boot-Animation: State-Watcher ─────────────────────────────
    Connections {
        target: hud
        function onAppStateChanged(state) {
            var wasHud = (root._prevState === "running" || root._prevState === "gaming")
            var isHud  = (state === "running" || state === "gaming")
            // CRT-Animation nötig: Übergang von aktivem HUD zu diesen States
            var crtStates = ["disconnected", "shutdown"]

            if (!wasHud && isHud) {
                crtOffAnim.stop()
                bootEnterAnim.stop()
                bootExitAnim.start()
            } else if (wasHud && !isHud) {
                bootExitAnim.stop()
                if (crtStates.indexOf(state) >= 0) {
                    // CRT-Ausschalt-Animation → bootEnterAnim wird am Ende von crtOffAnim gestartet
                    crtOffAnim.start()
                } else {
                    // standby / restarting: normaler Overlay-Fade ohne CRT
                    bootEnterAnim.start()
                }
            }
            root._prevState = state
        }
    }

    // Boot-Exit: Overlay wegwischen, HUD-Panels einzeln initialisieren
    SequentialAnimation {
        id: bootExitAnim
        // Flicker-Phase (~330ms)
        NumberAnimation { target: root; property: "_bootAlpha"; to: 0.1;  duration: 45; easing.type: Easing.Linear }
        NumberAnimation { target: root; property: "_bootAlpha"; to: 1.0;  duration: 30; easing.type: Easing.Linear }
        NumberAnimation { target: root; property: "_bootAlpha"; to: 0.05; duration: 55; easing.type: Easing.Linear }
        NumberAnimation { target: root; property: "_bootAlpha"; to: 0.85; duration: 25; easing.type: Easing.Linear }
        NumberAnimation { target: root; property: "_bootAlpha"; to: 0.0;  duration: 65; easing.type: Easing.Linear }
        NumberAnimation { target: root; property: "_bootAlpha"; to: 0.75; duration: 30; easing.type: Easing.Linear }
        NumberAnimation { target: root; property: "_bootAlpha"; to: 0.0;  duration: 80; easing.type: Easing.Linear }
        // Wipe-Bars: links nach rechts (staggered ~480ms)
        ScriptAction { script: {
            wipe1.x = -(root.width + 120)
            wipe2.x = -(root.width + 120)
            wipe3.x = -(root.width + 120)
        }}
        ParallelAnimation {
            NumberAnimation { target: wipe1; property: "x"; to: root.width + 60; duration: 280; easing.type: Easing.InOutCubic }
            SequentialAnimation {
                PauseAnimation { duration: 120 }
                NumberAnimation { target: wipe2; property: "x"; to: root.width + 60; duration: 260; easing.type: Easing.InOutCubic }
            }
            SequentialAnimation {
                PauseAnimation { duration: 240 }
                NumberAnimation { target: wipe3; property: "x"; to: root.width + 60; duration: 240; easing.type: Easing.InOutCubic }
            }
        }
        // Panel-Reveal: sequenziell (130ms je Stufe)
        ScriptAction { script: root._revealStage = 0 }
        PauseAnimation { duration: 50 }
        ScriptAction { script: root._revealStage = 1 }
        PauseAnimation { duration: 130 }
        ScriptAction { script: root._revealStage = 2 }
        PauseAnimation { duration: 130 }
        ScriptAction { script: root._revealStage = 3 }
        PauseAnimation { duration: 130 }
        ScriptAction { script: root._revealStage = 4 }
        PauseAnimation { duration: 130 }
        ScriptAction { script: root._revealStage = 5 }
        PauseAnimation { duration: 130 }
        ScriptAction { script: root._revealStage = 6 }
    }

    // Boot-Enter: HUD ausblenden, Overlay reinschieben
    SequentialAnimation {
        id: bootEnterAnim
        ScriptAction { script: root._revealStage = 0 }
        PauseAnimation { duration: 220 }
        ScriptAction { script: {
            wipe1.x = root.width + 60
            wipe2.x = root.width + 60
            wipe3.x = root.width + 60
        }}
        ParallelAnimation {
            NumberAnimation { target: wipe3; property: "x"; to: -(root.width + 120); duration: 280; easing.type: Easing.InOutCubic }
            SequentialAnimation {
                PauseAnimation { duration: 120 }
                NumberAnimation { target: wipe2; property: "x"; to: -(root.width + 120); duration: 260; easing.type: Easing.InOutCubic }
            }
            SequentialAnimation {
                PauseAnimation { duration: 240 }
                NumberAnimation { target: wipe1; property: "x"; to: -(root.width + 120); duration: 240; easing.type: Easing.InOutCubic }
            }
        }
        NumberAnimation { target: root; property: "_bootAlpha"; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
    }

    // ── CRT-Ausschalt-Animation ────────────────────────────────────
    // Komprimiert das HUD vertikal zu einer Linie (klassischer CRT-Effekt)
    // → wird automatisch von onAppStateChanged für disconnected/shutdown gestartet
    SequentialAnimation {
        id: crtOffAnim
        // Schnell vertikal zusammendrücken (InCubic = erst langsam, dann schnell)
        NumberAnimation { target: root; property: "_crtYScale"; to: 0.005
                          duration: 160; easing.type: Easing.InCubic }
        // Kurz Glow-Linie zeigen
        ScriptAction { script: { crtGlowLine.visible = true } }
        PauseAnimation { duration: 180 }
        // Linie ausdimmen
        ParallelAnimation {
            NumberAnimation { target: crtGlowLine; property: "height"; to: 0
                              duration: 220; easing.type: Easing.OutCubic }
            NumberAnimation { target: crtGlowLine; property: "opacity"; to: 0.0
                              duration: 220; easing.type: Easing.OutCubic }
        }
        ScriptAction { script: {
            root._revealStage   = 0    // Panels verbergen bevor Scale zurückgesetzt wird
            root._crtYScale     = 1.0  // zurücksetzen (kein Glitch weil revealStage=0)
            crtGlowLine.visible = false
            crtGlowLine.height  = 3
            crtGlowLine.opacity = 1.0
            bootEnterAnim.start()
        }}
    }

    // ══════════════════════════════════════════════════════════════
    //  HELPER-KOMPONENTEN
    // ══════════════════════════════════════════════════════════════

    // Eck-Brackets (Anime-Style)
    component PanelBrackets: Item {
        id: pb
        property color bracketColor: root.cBlue2
        property int   sz: 14
        property int   th: 1
        // Horizontale Balken beinhalten den Eckpixel.
        // Vertikale Balken starten/enden um th versetzt → kein Doppel-Rendering am Eck.
        Rectangle { x:0;              y:0;               width:pb.sz;        height:pb.th;        color:pb.bracketColor } // TL H
        Rectangle { x:0;              y:pb.th;           width:pb.th;        height:pb.sz-pb.th;  color:pb.bracketColor } // TL V
        Rectangle { x:pb.width-pb.sz; y:0;               width:pb.sz;        height:pb.th;        color:pb.bracketColor } // TR H
        Rectangle { x:pb.width-pb.th; y:pb.th;           width:pb.th;        height:pb.sz-pb.th;  color:pb.bracketColor } // TR V
        Rectangle { x:0;              y:pb.height-pb.th; width:pb.sz;        height:pb.th;        color:pb.bracketColor } // BL H
        Rectangle { x:0;              y:pb.height-pb.sz; width:pb.th;        height:pb.sz-pb.th;  color:pb.bracketColor } // BL V
        Rectangle { x:pb.width-pb.sz; y:pb.height-pb.th; width:pb.sz;       height:pb.th;        color:pb.bracketColor } // BR H
        Rectangle { x:pb.width-pb.th; y:pb.height-pb.sz; width:pb.th;       height:pb.sz-pb.th;  color:pb.bracketColor } // BR V
    }

    // Horizontale Trennlinie mit Gradient
    component HSep: Item {
        height: 1
        Rectangle {
            anchors.fill: parent
            gradient: Gradient { orientation: Gradient.Horizontal
                GradientStop { position: 0.0;  color: "transparent" }
                GradientStop { position: 0.15; color: Qt.rgba(0.4,0.1,1,0.4) }
                GradientStop { position: 0.5;  color: Qt.rgba(0,0.67,1,0.35) }
                GradientStop { position: 0.85; color: Qt.rgba(0.4,0.1,1,0.4) }
                GradientStop { position: 1.0;  color: "transparent" }
            }
        }
    }

    // Horizontale Fortschrittsleiste
    component HBar: Item {
        id: hbar
        property real   value:  0.0       // 0–100
        property color  col:    root.cBlue
        property string label:  ""
        property string valStr: Math.round(value) + "%"
        property bool   showGb: false
        property real   usedGb: 0
        property real   totalGb: 0
        height: 36

        Text { id: lbl
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            text: hbar.label; font.family: "DejaVu Sans Mono"; font.pixelSize: 10; font.letterSpacing: 3
            color: Qt.rgba(hbar.col.r, hbar.col.g, hbar.col.b, 0.55); width: 56 }
        // Track
        Rectangle {
            anchors.left: lbl.right; anchors.leftMargin: 6
            anchors.right: valLabel.left; anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter; height: 8; radius: 4
            color: Qt.rgba(hbar.col.r, hbar.col.g, hbar.col.b, 0.08)
            // Fill
            Rectangle {
                width: Math.max(8, parent.width * Math.max(0, Math.min(100, hbar.value)) / 100)
                height: parent.height; radius: 4
                color: Qt.rgba(hbar.col.r, hbar.col.g, hbar.col.b, 0.75)
                Behavior on width { NumberAnimation { duration: 80; easing.type: Easing.OutCubic } }
            }
        }
        Text { id: valLabel
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            font.family: "DejaVu Sans Mono"; font.pixelSize: 12
            color: hbar.col
            text: hbar.showGb
                  ? hbar.usedGb.toFixed(1) + "/" + hbar.totalGb.toFixed(1) + " G"
                  : hbar.valStr
        }
    }

    // Zwei-Spalten Metrikzeile
    component MetricRow: Item {
        id: mrow
        property string labelA: ""; property string valA: ""; property color colA: root.cBlue
        property string labelB: ""; property string valB: ""; property color colB: root.cBlue
        height: 26
        Row {
            anchors.fill: parent; spacing: 0
            Item { width: parent.width/2; height: parent.height
                Row { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; spacing: 8
                    Text { text: mrow.labelA; font.family:"DejaVu Sans Mono"; font.pixelSize:10
                           color:Qt.rgba(mrow.colA.r,mrow.colA.g,mrow.colA.b,0.45); width:52 }
                    Text { text: mrow.valA;   font.family:"DejaVu Sans Mono"; font.pixelSize:13; color:mrow.colA }
                }
            }
            Item { width: parent.width/2; height: parent.height
                Row { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; spacing: 8
                    Text { text: mrow.labelB; font.family:"DejaVu Sans Mono"; font.pixelSize:10
                           color:Qt.rgba(mrow.colB.r,mrow.colB.g,mrow.colB.b,0.45); width:52 }
                    Text { text: mrow.valB;   font.family:"DejaVu Sans Mono"; font.pixelSize:13; color:mrow.colB }
                }
            }
        }
    }

    // ── 180° Dreh-Container (Display ist physisch auf dem Kopf montiert) ──────
    Item {
        id: scene
        anchors.fill: parent
        rotation: 180

    // ══════════════════════════════════════════════════════════════
    //  GLOBALER SCAN-SWEEP (top → bottom)
    // ══════════════════════════════════════════════════════════════
    Rectangle {
        id: scanLine
        width: root.width; height: 1; z: 2
        color: "transparent"
        opacity: gamingPanel.show ? 0.0 : 1.0
        Behavior on opacity { NumberAnimation { duration: 400 } }
        Rectangle { anchors.centerIn:parent; width:parent.width; height:1; color:Qt.rgba(0,0.67,1,0.3) }
        Rectangle { anchors.bottom:parent.top; width:parent.width; height:8
            gradient:Gradient { orientation:Gradient.Vertical
                GradientStop{position:0.0; color:"transparent"}
                GradientStop{position:1.0; color:Qt.rgba(0,0.67,1,0.1)}
            }
        }
        NumberAnimation on y {
            from:0; to:root.height; duration:8000; loops:Animation.Infinite
            easing.type:Easing.Linear; running: !gamingPanel.show
        }
    }

    // Rechter Rand-Streifen (Dekoration)
    Rectangle {
        anchors.right: parent.right; width: 2; height: parent.height
        gradient: Gradient {
            GradientStop { position: 0.0;  color: "transparent" }
            GradientStop { position: 0.25; color: Qt.rgba(0,0.67,1,0.2) }
            GradientStop { position: 0.75; color: Qt.rgba(0.6,0.2,1,0.2) }
            GradientStop { position: 1.0;  color: "transparent" }
        }
    }

    // ══════════════════════════════════════════════════════════════
    //  HAUPT-LAYOUT
    // ══════════════════════════════════════════════════════════════
    Column {
        id: mainColumn
        anchors.fill: parent
        anchors.margins: 8
        spacing: 0
        transform: Scale {
            origin.x: root.width / 2
            origin.y: root.height / 2
            yScale: root._crtYScale
        }

        // ══════════════════════════════════════════════════════════
        //  HEADER — BC-250 + Status + Uhr
        // ══════════════════════════════════════════════════════════
        Item {
            id: header
            width: parent.width; height: 116
            opacity: root._revealStage >= 1 ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }

            PanelBrackets { anchors.fill:parent; bracketColor:root.cBlue; sz:18 }

            // BC-250 Logo links
            Text {
                id: brandText
                anchors.left: parent.left; anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: -6
                text: "BC-250"
                font.family: "DejaVu Sans Mono"; font.pixelSize: 52; font.bold: true
                color: root.cBlue
                style: Text.Outline; styleColor: Qt.rgba(0,0.67,1,0.2)
                SequentialAnimation on opacity {
                    running: true; loops: Animation.Infinite
                    NumberAnimation { to:0.8; duration:3500; easing.type:Easing.InOutSine }
                    NumberAnimation { to:1.0; duration:3500; easing.type:Easing.InOutSine }
                }
            }

            // Uhr rechts
            Column {
                anchors.right: parent.right; anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    anchors.right: parent.right
                    font.family: "DejaVu Sans Mono"; font.pixelSize: 36; font.bold: true
                    color: root.cBlue; style: Text.Outline; styleColor: Qt.rgba(0,0.67,1,0.2)
                    property string hhmm: Qt.formatTime(new Date(), "hh:mm")
                    text: hhmm
                    Timer { interval:1000; running:true; repeat:true; onTriggered: parent.hhmm = Qt.formatTime(new Date(), "hh:mm") }
                }
                Text {
                    anchors.right: parent.right
                    font.family: "DejaVu Sans Mono"; font.pixelSize: 11; font.letterSpacing: 2
                    color: Qt.rgba(0.8,0.5,1,0.55)
                    text: Qt.formatDate(new Date(), "ddd  yyyy.MM.dd")
                }
            }

            // Status-Zeile unten
            Row {
                anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                anchors.left: parent.left; anchors.leftMargin: 16
                spacing: 10
                Rectangle {
                    width: 8; height: 8; radius: 4
                    anchors.verticalCenter: parent.verticalCenter
                    color: hud.connected ? root.cGreen : root.cAmber
                    SequentialAnimation on opacity { running:true; loops:Animation.Infinite
                        NumberAnimation{to:0.3;duration:900} NumberAnimation{to:1.0;duration:900} }
                }
                Text { text: hud.connected ? "ONLINE  " + hud.hostname : "STANDBY  " + hud.hostname
                       font.family:"DejaVu Sans Mono"; font.pixelSize:11; font.letterSpacing:2
                       color: hud.connected ? root.cGreen : root.cAmber
                       anchors.verticalCenter: parent.verticalCenter }
            }

            // interner FPS rechts unten
            Text {
                anchors.bottom: parent.bottom; anchors.right: parent.right
                anchors.margins: 6
                text: root.fps + " fps"
                font.family:"DejaVu Sans Mono"; font.pixelSize:9
                color: Qt.rgba(0,1,0.53,0.3)
            }
        }

        // ── Separator ─────────────────────────────────────────────
        HSep { width: parent.width }
        Item { width: parent.width; height: 6 }

        // ══════════════════════════════════════════════════════════
        //  CPU PANEL — Targeting Reticle
        // ══════════════════════════════════════════════════════════
        Item {
            id: panelCPU
            width: parent.width; height: 390
            opacity: root._revealStage >= 2 ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }

            PanelBrackets { anchors.fill:parent; bracketColor:root.cBlue; sz:18 }

            readonly property real cx: width/2
            readonly property real cy: 195

            // Label oben
            Text { anchors.top:parent.top; anchors.topMargin:8; anchors.horizontalCenter:parent.horizontalCenter
                   text:"PROCESSOR"; font.family:"DejaVu Sans Mono"; font.pixelSize:9; font.letterSpacing:5
                   color:Qt.rgba(0,0.67,1,0.45) }

            // LOCK-Indikator
            Rectangle {
                anchors.top:parent.top; anchors.topMargin:6; anchors.right:parent.right; anchors.rightMargin:16
                width:54; height:16; radius:2; color:Qt.rgba(0,0.67,1,0.08)
                Rectangle { anchors.fill:parent; radius:2; color:Qt.rgba(0,0.67,1,0.15); visible:hud.connected }
                Text { anchors.centerIn:parent; text:hud.connected?"■ LOCK":"□ SCAN"
                       font.family:"DejaVu Sans Mono"; font.pixelSize:9; font.letterSpacing:2
                       color:hud.connected?root.cBlue:Qt.rgba(0,0.67,1,0.35) }
            }

            // ── Rotierender Außen-Ring 1 (3 Bögen, r=175, 25s CW)
            Item {
                x:panelCPU.cx-panelCPU.cx; y:0; width:parent.width; height:panelCPU.cy*2
                RotationAnimation on rotation { running:true; loops:Animation.Infinite; duration:25000; from:0; to:360; direction:RotationAnimation.Clockwise }
                Shape { anchors.fill:parent
                    ShapePath { strokeColor:Qt.rgba(0,0.67,1,0.28); strokeWidth:1.5; fillColor:"transparent"
                        startX:panelCPU.cx+175*Math.cos(-25*Math.PI/180); startY:panelCPU.cy+175*Math.sin(-25*Math.PI/180)
                        PathArc{x:panelCPU.cx+175*Math.cos(65*Math.PI/180);y:panelCPU.cy+175*Math.sin(65*Math.PI/180);radiusX:175;radiusY:175;direction:PathArc.Clockwise} }
                    ShapePath { strokeColor:Qt.rgba(0,0.67,1,0.28); strokeWidth:1.5; fillColor:"transparent"
                        startX:panelCPU.cx+175*Math.cos(95*Math.PI/180); startY:panelCPU.cy+175*Math.sin(95*Math.PI/180)
                        PathArc{x:panelCPU.cx+175*Math.cos(185*Math.PI/180);y:panelCPU.cy+175*Math.sin(185*Math.PI/180);radiusX:175;radiusY:175;direction:PathArc.Clockwise} }
                    ShapePath { strokeColor:Qt.rgba(0,0.67,1,0.28); strokeWidth:1.5; fillColor:"transparent"
                        startX:panelCPU.cx+175*Math.cos(215*Math.PI/180); startY:panelCPU.cy+175*Math.sin(215*Math.PI/180)
                        PathArc{x:panelCPU.cx+175*Math.cos(305*Math.PI/180);y:panelCPU.cy+175*Math.sin(305*Math.PI/180);radiusX:175;radiusY:175;direction:PathArc.Clockwise} }
                }
            }

            // ── Rotierender Ring 2 (4 Bögen, r=155, 38s CCW)
            Item {
                x:0; y:0; width:parent.width; height:panelCPU.cy*2
                RotationAnimation on rotation { running:true; loops:Animation.Infinite; duration:38000; from:0; to:-360; direction:RotationAnimation.Counterclockwise }
                Shape { anchors.fill:parent
                    ShapePath { strokeColor:Qt.rgba(0.6,0.2,1,0.2); strokeWidth:1; fillColor:"transparent"
                        startX:panelCPU.cx+155*Math.cos(10*Math.PI/180);startY:panelCPU.cy+155*Math.sin(10*Math.PI/180)
                        PathArc{x:panelCPU.cx+155*Math.cos(60*Math.PI/180);y:panelCPU.cy+155*Math.sin(60*Math.PI/180);radiusX:155;radiusY:155;direction:PathArc.Clockwise} }
                    ShapePath { strokeColor:Qt.rgba(0.6,0.2,1,0.2); strokeWidth:1; fillColor:"transparent"
                        startX:panelCPU.cx+155*Math.cos(100*Math.PI/180);startY:panelCPU.cy+155*Math.sin(100*Math.PI/180)
                        PathArc{x:panelCPU.cx+155*Math.cos(165*Math.PI/180);y:panelCPU.cy+155*Math.sin(165*Math.PI/180);radiusX:155;radiusY:155;direction:PathArc.Clockwise} }
                    ShapePath { strokeColor:Qt.rgba(0.6,0.2,1,0.2); strokeWidth:1; fillColor:"transparent"
                        startX:panelCPU.cx+155*Math.cos(200*Math.PI/180);startY:panelCPU.cy+155*Math.sin(200*Math.PI/180)
                        PathArc{x:panelCPU.cx+155*Math.cos(255*Math.PI/180);y:panelCPU.cy+155*Math.sin(255*Math.PI/180);radiusX:155;radiusY:155;direction:PathArc.Clockwise} }
                    ShapePath { strokeColor:Qt.rgba(0.6,0.2,1,0.2); strokeWidth:1; fillColor:"transparent"
                        startX:panelCPU.cx+155*Math.cos(290*Math.PI/180);startY:panelCPU.cy+155*Math.sin(290*Math.PI/180)
                        PathArc{x:panelCPU.cx+155*Math.cos(345*Math.PI/180);y:panelCPU.cy+155*Math.sin(345*Math.PI/180);radiusX:155;radiusY:155;direction:PathArc.Clockwise} }
                }
            }

            // ── Crosshair ─────────────────────────────────────────
            Rectangle { x:panelCPU.cx-140; y:panelCPU.cy; width:280; height:1; color:Qt.rgba(0,0.67,1,0.18) }
            Rectangle { x:panelCPU.cx;     y:panelCPU.cy-140; width:1; height:280; color:Qt.rgba(0,0.67,1,0.18) }
            Rectangle { x:panelCPU.cx-10;  y:panelCPU.cy; width:20; height:1; color:Qt.rgba(0,0.67,1,0.7) }
            Rectangle { x:panelCPU.cx;     y:panelCPU.cy-10; width:1; height:20; color:Qt.rgba(0,0.67,1,0.7) }

            // ── CPU Arc (Wert) ─────────────────────────────────────
            property real _cpuV: 0
            Behavior on _cpuV { NumberAnimation { duration:80; easing.type:Easing.OutCubic } }
            Connections { target:hud; function onChanged() { panelCPU._cpuV = hud.cpu } }

            readonly property real arcStart: -225*Math.PI/180
            readonly property real arcSpan:   270*Math.PI/180
            readonly property real arcEnd:    arcStart + arcSpan * Math.max(0.002, _cpuV/100)

            // Glow
            Shape { anchors.left:parent.left; anchors.top:parent.top; width:parent.width; height:panelCPU.cy*2; visible:panelCPU._cpuV>1
                ShapePath { strokeColor:Qt.rgba(0,0.67,1,0.18); strokeWidth:22; fillColor:"transparent"; capStyle:ShapePath.RoundCap
                    startX:panelCPU.cx+140*Math.cos(panelCPU.arcStart); startY:panelCPU.cy+140*Math.sin(panelCPU.arcStart)
                    PathArc{x:panelCPU.cx+140*Math.cos(panelCPU.arcEnd);y:panelCPU.cy+140*Math.sin(panelCPU.arcEnd);radiusX:140;radiusY:140;useLargeArc:panelCPU._cpuV>66.67;direction:PathArc.Clockwise} }
            }
            // Haupt-Arc
            Shape { anchors.left:parent.left; anchors.top:parent.top; width:parent.width; height:panelCPU.cy*2; visible:panelCPU._cpuV>1
                ShapePath { strokeColor:root.cBlue; strokeWidth:8; fillColor:"transparent"; capStyle:ShapePath.RoundCap
                    startX:panelCPU.cx+140*Math.cos(panelCPU.arcStart); startY:panelCPU.cy+140*Math.sin(panelCPU.arcStart)
                    PathArc{x:panelCPU.cx+140*Math.cos(panelCPU.arcEnd);y:panelCPU.cy+140*Math.sin(panelCPU.arcEnd);radiusX:140;radiusY:140;useLargeArc:panelCPU._cpuV>66.67;direction:PathArc.Clockwise} }
            }

            // ── Graduierung (Canvas, einmalig) ────────────────────
            Canvas {
                x:0; y:0; width:parent.width; height:panelCPU.cy*2
                onPaint: {
                    var ctx=getContext("2d"); ctx.clearRect(0,0,width,height)
                    var cx=panelCPU.cx, cy=panelCPU.cy
                    var startDeg=135, spanDeg=270
                    for(var i=0;i<=10;i++){
                        var deg=(startDeg+spanDeg*i/10)*Math.PI/180
                        var r1=i%5===0?126:132
                        ctx.beginPath(); ctx.moveTo(cx+r1*Math.cos(deg),cy+r1*Math.sin(deg))
                        ctx.lineTo(cx+148*Math.cos(deg),cy+148*Math.sin(deg))
                        ctx.strokeStyle=i%5===0?"rgba(0,170,255,0.8)":"rgba(0,170,255,0.3)"
                        ctx.lineWidth=i%5===0?2:1; ctx.stroke()
                    }
                    ctx.fillStyle="rgba(0,170,255,0.45)"; ctx.font="9px 'DejaVu Sans Mono'"; ctx.textAlign="center"
                    var labels=[0,25,50,75,100]
                    for(var j=0;j<5;j++){
                        var d2=(startDeg+spanDeg*j/4)*Math.PI/180
                        ctx.fillText(labels[j],cx+118*Math.cos(d2),cy+118*Math.sin(d2)+4)
                    }
                }
                Component.onCompleted: requestPaint()
            }

            // ── Zentraler Wert ────────────────────────────────────
            Text { x:panelCPU.cx-60; y:panelCPU.cy-44; width:120; horizontalAlignment:Text.AlignHCenter
                   text:Math.round(panelCPU._cpuV)+"%"
                   font.family:"DejaVu Sans Mono"; font.pixelSize:52; font.bold:true; color:root.cBlue
                   style:Text.Outline; styleColor:Qt.rgba(0,0.67,1,0.28) }
            Text { x:panelCPU.cx-60; y:panelCPU.cy+18; width:120; horizontalAlignment:Text.AlignHCenter
                   text:"PROCESSOR"
                   font.family:"DejaVu Sans Mono"; font.pixelSize:10; font.letterSpacing:4
                   color:Qt.rgba(0,0.67,1,0.45) }

            // ── Temperatur + Freq + Power ──────────────────────────
            Row {
                anchors.bottom: parent.bottom; anchors.bottomMargin:10
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 22
                Text { text:"TEMP  "+Math.round(hud.cpuTemp)+"°C"
                       font.family:"DejaVu Sans Mono"; font.pixelSize:12
                       color:hud.cpuTemp<70?root.cGreen:hud.cpuTemp<85?root.cAmber:root.cRed }
                Text { text:Math.round(hud.cpuFreqMhz)+" MHz"
                       font.family:"DejaVu Sans Mono"; font.pixelSize:12; color:Qt.rgba(0,0.67,1,0.5) }
                Text { text:"SOC  "+hud.cpuPackageW.toFixed(1)+"W"
                       font.family:"DejaVu Sans Mono"; font.pixelSize:12; color:Qt.rgba(0.8,0.5,1,0.6) }
            }
        }

        // ── CPU Cores ─────────────────────────────────────────────
        Item {
            id: panelCores
            width: parent.width; height: 96
            opacity: root._revealStage >= 2 ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }

            PanelBrackets { anchors.fill:parent; bracketColor:root.cBlue2; sz:14 }

            Text { anchors.top:parent.top; anchors.left:parent.left; anchors.leftMargin:16
                   text:"CORES"; font.family:"DejaVu Sans Mono"; font.pixelSize:8; font.letterSpacing:4
                   color:Qt.rgba(0,0.67,1,0.4) }

            Row {
                anchors.bottom: parent.bottom; anchors.bottomMargin:4
                anchors.left: parent.left; anchors.right: parent.right
                anchors.leftMargin: 10; anchors.rightMargin: 10
                spacing: 6

                Repeater {
                    model: 6
                    Item {
                        width: (parent.width - 5*6) / 6; height: 70

                        readonly property real coreVal: {
                            var c=hud.cpuCorePct; return (c && index<c.length) ? c[index] : 0
                        }

                        // Label
                        Text { anchors.top:parent.top; anchors.horizontalCenter:parent.horizontalCenter
                               text:"C"+index; font.family:"DejaVu Sans Mono"; font.pixelSize:8
                               color:Qt.rgba(0,0.67,1,0.4) }
                        // Bar — Behavior direkt auf barVal-Property des Rectangle
                        Rectangle {
                            anchors.bottom: parent.bottom; anchors.horizontalCenter:parent.horizontalCenter
                            width: parent.width; radius:2
                            property real barVal: parent.coreVal
                            Behavior on barVal { NumberAnimation { duration:80 } }
                            height: Math.max(3, (parent.height-14) * barVal/100)
                            color: barVal>80 ? root.cRed : barVal>60 ? root.cAmber : root.cBlue
                            opacity: 0.75 + 0.25*(barVal/100)
                        }
                    }
                }
            }
        }

        Item { width: parent.width; height: 4 }
        HSep { width: parent.width }
        Item { width: parent.width; height: 6 }

        // ══════════════════════════════════════════════════════════
        //  GPU PANEL — RDNA2 Reticle
        // ══════════════════════════════════════════════════════════
        Item {
            id: panelGPU
            width: parent.width; height: 296
            opacity: root._revealStage >= 3 ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }

            PanelBrackets { anchors.fill:parent; bracketColor:root.cVio; sz:16 }

            readonly property real cx: width/2
            readonly property real cy: 148

            Text { anchors.top:parent.top; anchors.topMargin:8; anchors.horizontalCenter:parent.horizontalCenter
                   text:"APU TEMP"; font.family:"DejaVu Sans Mono"; font.pixelSize:9; font.letterSpacing:5
                   color:Qt.rgba(0.8,0.5,1,0.45) }

            // Hintergrund-Track
            Shape { anchors.left:parent.left; anchors.top:parent.top; width:parent.width; height:panelGPU.cy*2
                ShapePath { strokeColor:Qt.rgba(0.4,0.1,0.6,0.4); strokeWidth:11; fillColor:"transparent"
                    startX:panelGPU.cx+120*Math.cos(135*Math.PI/180); startY:panelGPU.cy+120*Math.sin(135*Math.PI/180)
                    PathArc{x:panelGPU.cx+120*Math.cos((135+270-0.01)*Math.PI/180);y:panelGPU.cy+120*Math.sin((135+270-0.01)*Math.PI/180);radiusX:120;radiusY:120;useLargeArc:true;direction:PathArc.Clockwise} }
            }

            // APU-Temperatur: 30°C = 0%, 100°C = 100%
            property real _gpuV: 0
            Behavior on _gpuV { NumberAnimation{duration:80} }
            Connections { target:hud; function onChanged(){ panelGPU._gpuV = Math.max(0, Math.min(100, (hud.cpuTemp - 30) / 70 * 100)) } }

            readonly property real gStart: 135*Math.PI/180
            readonly property real gSpan:  270*Math.PI/180
            readonly property real gEnd:   gStart + gSpan * Math.max(0.002, _gpuV/100)

            // Detail-Ring innen (rotierend, r=70)
            Item { anchors.left:parent.left; anchors.top:parent.top; width:parent.width; height:panelGPU.cy*2
                RotationAnimation on rotation { running:true; loops:Animation.Infinite; duration:8000; from:0; to:-360; direction:RotationAnimation.Counterclockwise }
                Shape { anchors.fill:parent
                    ShapePath { strokeColor:Qt.rgba(0.6,0.2,1,0.3); strokeWidth:1; fillColor:"transparent"
                        startX:panelGPU.cx+70*Math.cos(0);startY:panelGPU.cy+70*Math.sin(0)
                        PathArc{x:panelGPU.cx+70*Math.cos(50*Math.PI/180);y:panelGPU.cy+70*Math.sin(50*Math.PI/180);radiusX:70;radiusY:70;direction:PathArc.Clockwise} }
                    ShapePath { strokeColor:Qt.rgba(0.6,0.2,1,0.3); strokeWidth:1; fillColor:"transparent"
                        startX:panelGPU.cx+70*Math.cos(120*Math.PI/180);startY:panelGPU.cy+70*Math.sin(120*Math.PI/180)
                        PathArc{x:panelGPU.cx+70*Math.cos(175*Math.PI/180);y:panelGPU.cy+70*Math.sin(175*Math.PI/180);radiusX:70;radiusY:70;direction:PathArc.Clockwise} }
                    ShapePath { strokeColor:Qt.rgba(0.6,0.2,1,0.3); strokeWidth:1; fillColor:"transparent"
                        startX:panelGPU.cx+70*Math.cos(240*Math.PI/180);startY:panelGPU.cy+70*Math.sin(240*Math.PI/180)
                        PathArc{x:panelGPU.cx+70*Math.cos(295*Math.PI/180);y:panelGPU.cy+70*Math.sin(295*Math.PI/180);radiusX:70;radiusY:70;direction:PathArc.Clockwise} }
                }
            }

            // Glow — Farbe abhängig von Temperatur (kühl=violett, heiß=rot)
            Shape { anchors.left:parent.left; anchors.top:parent.top; width:parent.width; height:panelGPU.cy*2; visible:panelGPU._gpuV>1
                ShapePath { strokeColor:panelGPU._gpuV>85?Qt.rgba(1,0.2,0.3,0.2):Qt.rgba(0.6,0.2,1,0.2)
                             strokeWidth:24; fillColor:"transparent"; capStyle:ShapePath.RoundCap
                    startX:panelGPU.cx+120*Math.cos(panelGPU.gStart); startY:panelGPU.cy+120*Math.sin(panelGPU.gStart)
                    PathArc{x:panelGPU.cx+120*Math.cos(panelGPU.gEnd);y:panelGPU.cy+120*Math.sin(panelGPU.gEnd);radiusX:120;radiusY:120;useLargeArc:panelGPU._gpuV>66.67;direction:PathArc.Clockwise} }
            }
            // Haupt-Arc
            Shape { anchors.left:parent.left; anchors.top:parent.top; width:parent.width; height:panelGPU.cy*2; visible:panelGPU._gpuV>1
                ShapePath { strokeColor:panelGPU._gpuV>85?root.cRed:root.cVio2
                             strokeWidth:9; fillColor:"transparent"; capStyle:ShapePath.RoundCap
                    startX:panelGPU.cx+120*Math.cos(panelGPU.gStart); startY:panelGPU.cy+120*Math.sin(panelGPU.gStart)
                    PathArc{x:panelGPU.cx+120*Math.cos(panelGPU.gEnd);y:panelGPU.cy+120*Math.sin(panelGPU.gEnd);radiusX:120;radiusY:120;useLargeArc:panelGPU._gpuV>66.67;direction:PathArc.Clockwise} }
            }

            // APU-Temperatur (°C)
            Text { x:panelGPU.cx-52; y:panelGPU.cy-38; width:104; horizontalAlignment:Text.AlignHCenter
                   text:Math.round(hud.cpuTemp)+"°C"
                   font.family:"DejaVu Sans Mono"; font.pixelSize:48; font.bold:true
                   color:panelGPU._gpuV>85?root.cRed:root.cVio2 }
            Text { x:panelGPU.cx-52; y:panelGPU.cy+20; width:104; horizontalAlignment:Text.AlignHCenter
                   text:"30 — 100°C"
                   font.family:"DejaVu Sans Mono"; font.pixelSize:11; color:Qt.rgba(0.8,0.5,1,0.5) }

            // Freq + Power unten
            Row {
                anchors.bottom:parent.bottom; anchors.bottomMargin:10
                anchors.horizontalCenter:parent.horizontalCenter
                spacing:28
                Text { text:Math.round(hud.gpuFreqMhz)+" MHz"
                       font.family:"DejaVu Sans Mono"; font.pixelSize:12; color:Qt.rgba(0.8,0.5,1,0.5) }
                Text { text:"SOC  "+hud.gpuPowerW.toFixed(1)+"W"
                       font.family:"DejaVu Sans Mono"; font.pixelSize:12; color:Qt.rgba(0.8,0.5,1,0.6) }
            }
        }

        // ── VRAM-Leiste ───────────────────────────────────────────
        Item {
            id: panelVRAM
            width: parent.width; height: 40
            opacity: root._revealStage >= 3 ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }
            PanelBrackets { anchors.fill:parent; bracketColor:Qt.rgba(0.6,0.2,1,0.35); sz:10 }
            HBar { anchors.verticalCenter:parent.verticalCenter; anchors.left:parent.left; anchors.right:parent.right
                   anchors.leftMargin:12; anchors.rightMargin:12
                   value:hud.gpuAvailable?(hud.vramUsedGb/Math.max(0.1,hud.vramTotalGb)*100):0
                   col:root.cVio; label:"GPU MEM"
                   showGb:true; usedGb:hud.vramUsedGb; totalGb:hud.vramTotalGb }
        }

        Item { width: parent.width; height: 4 }
        HSep { width: parent.width }
        Item { width: parent.width; height: 6 }

        // ══════════════════════════════════════════════════════════
        //  MEMORY — RAM Hex-Grid + Swap
        // ══════════════════════════════════════════════════════════
        Item {
            id: panelMem
            width: parent.width; height: 180
            opacity: root._revealStage >= 4 ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }

            PanelBrackets { anchors.fill:parent; bracketColor:root.cGreen; sz:14 }

            // RAM Header
            Text { id: ramLbl
                   anchors.top:parent.top; anchors.topMargin:4; anchors.left:parent.left; anchors.leftMargin:14
                   text:"MEMORY"; font.family:"DejaVu Sans Mono"; font.pixelSize:9; font.letterSpacing:4
                   color:Qt.rgba(0,1,0.53,0.45) }
            Text { anchors.top:parent.top; anchors.topMargin:4; anchors.right:parent.right; anchors.rightMargin:14
                   font.family:"DejaVu Sans Mono"; font.pixelSize:12; color:root.cGreen
                   text:Math.round(hud.ram)+"%" }

            // RAM Hex-Grid
            Canvas {
                id: ramHexCanvas
                anchors.top: ramLbl.bottom; anchors.topMargin:3
                anchors.left: parent.left; anchors.right: parent.right
                anchors.leftMargin:6; anchors.rightMargin:6
                height: 118
                clip: true
                SequentialAnimation on opacity { running:true; loops:Animation.Infinite
                    NumberAnimation{to:0.65;duration:2200;easing.type:Easing.InOutSine}
                    NumberAnimation{to:1.0; duration:2200;easing.type:Easing.InOutSine} }
                Timer { interval:500; repeat:true; running:true; onTriggered: ramHexCanvas.requestPaint() }
                onPaint: {
                    var ctx=getContext("2d"); ctx.clearRect(0,0,width,height)
                    var s=13, ri=s-2, h=s*0.866, pts=[]
                    var cos60=Math.cos(Math.PI/180*60), sin60=Math.sin(Math.PI/180*60)
                    var cos120=Math.cos(Math.PI/180*120), sin120=Math.sin(Math.PI/180*120)
                    var cos180=-1, sin180=0
                    var cos240=Math.cos(Math.PI/180*240), sin240=Math.sin(Math.PI/180*240)
                    var cos300=Math.cos(Math.PI/180*300), sin300=Math.sin(Math.PI/180*300)
                    for(var col=0;;col++){
                        var hx=col*s*1.5+s; if(hx>width+s) break
                        for(var row=0;;row++){
                            var hy=row*h*2+(col%2===0?h:2*h); if(hy>height+h) break
                            if(hx>=s&&hx<=width-s&&hy>=h&&hy<=height-h) pts.push([hx,hy])
                        }
                    }
                    var filled=Math.round(pts.length*hud.ram/100)
                    // Batch 1: unlit fills
                    ctx.beginPath()
                    for(var i=filled;i<pts.length;i++){
                        var px=pts[i][0], py=pts[i][1]
                        ctx.moveTo(px+ri,py)
                        ctx.lineTo(px+ri*cos60, py+ri*sin60)
                        ctx.lineTo(px+ri*cos120,py+ri*sin120)
                        ctx.lineTo(px+ri*cos180,py)
                        ctx.lineTo(px+ri*cos240,py+ri*sin240)
                        ctx.lineTo(px+ri*cos300,py+ri*sin300)
                        ctx.closePath()
                    }
                    ctx.fillStyle="rgba(0,255,136,0.04)"; ctx.fill()
                    // Batch 2: lit fills
                    ctx.beginPath()
                    for(var i=0;i<filled;i++){
                        var px=pts[i][0], py=pts[i][1]
                        ctx.moveTo(px+ri,py)
                        ctx.lineTo(px+ri*cos60, py+ri*sin60)
                        ctx.lineTo(px+ri*cos120,py+ri*sin120)
                        ctx.lineTo(px+ri*cos180,py)
                        ctx.lineTo(px+ri*cos240,py+ri*sin240)
                        ctx.lineTo(px+ri*cos300,py+ri*sin300)
                        ctx.closePath()
                    }
                    ctx.fillStyle="rgba(0,255,136,0.22)"; ctx.fill()
                    // Batch 3: unlit strokes
                    ctx.beginPath()
                    for(var i=filled;i<pts.length;i++){
                        var px=pts[i][0], py=pts[i][1]
                        ctx.moveTo(px+ri,py)
                        ctx.lineTo(px+ri*cos60, py+ri*sin60)
                        ctx.lineTo(px+ri*cos120,py+ri*sin120)
                        ctx.lineTo(px+ri*cos180,py)
                        ctx.lineTo(px+ri*cos240,py+ri*sin240)
                        ctx.lineTo(px+ri*cos300,py+ri*sin300)
                        ctx.closePath()
                    }
                    ctx.strokeStyle="rgba(0,255,136,0.13)"; ctx.lineWidth=1; ctx.stroke()
                    // Batch 4: lit strokes
                    ctx.beginPath()
                    for(var i=0;i<filled;i++){
                        var px=pts[i][0], py=pts[i][1]
                        ctx.moveTo(px+ri,py)
                        ctx.lineTo(px+ri*cos60, py+ri*sin60)
                        ctx.lineTo(px+ri*cos120,py+ri*sin120)
                        ctx.lineTo(px+ri*cos180,py)
                        ctx.lineTo(px+ri*cos240,py+ri*sin240)
                        ctx.lineTo(px+ri*cos300,py+ri*sin300)
                        ctx.closePath()
                    }
                    ctx.strokeStyle="rgba(0,255,136,0.82)"; ctx.stroke()
                }
            }

            // RAM GB-Info
            Text { anchors.bottom:parent.bottom; anchors.bottomMargin:4; anchors.left:parent.left; anchors.leftMargin:14
                   font.family:"DejaVu Sans Mono"; font.pixelSize:10
                   color:Qt.rgba(0,1,0.53,0.4)
                   text:hud.ramUsedGb.toFixed(1)+" / "+hud.ramTotalGb.toFixed(1)+" GB" }

            // Swap-Info rechts
            Text { anchors.bottom:parent.bottom; anchors.bottomMargin:4; anchors.right:parent.right; anchors.rightMargin:14
                   font.family:"DejaVu Sans Mono"; font.pixelSize:10
                   color:Qt.rgba(0,1,0.53,0.35)
                   text:"SWAP  "+Math.round(hud.swapPercent)+"%  "+hud.swapUsedGb.toFixed(1)+"G" }
        }

        Item { width: parent.width; height: 4 }
        HSep { width: parent.width }
        Item { width: parent.width; height: 6 }

        // ══════════════════════════════════════════════════════════
        //  LOAD HISTORY
        // ══════════════════════════════════════════════════════════
        Item {
            id: panelLoad
            width: parent.width; height: 138
            opacity: root._revealStage >= 4 ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }

            PanelBrackets { anchors.fill:parent; bracketColor:Qt.rgba(0,0.67,1,0.35); sz:14 }

            Text { id: loadLbl2
                   anchors.top:parent.top; anchors.left:parent.left; anchors.leftMargin:12
                   text:"LOAD HISTORY"; font.family:"DejaVu Sans Mono"; font.pixelSize:9; font.letterSpacing:3
                   color:Qt.rgba(0,1,0.53,0.38) }

            Canvas {
                id: loadCanvas
                anchors.top:loadLbl2.bottom; anchors.topMargin:4
                anchors.bottom:parent.bottom; anchors.bottomMargin:4
                anchors.left:parent.left; anchors.right:parent.right
                anchors.leftMargin:4; anchors.rightMargin:4
                Timer { interval:500; repeat:true; running:true; onTriggered: loadCanvas.requestPaint() }
                onPaint: {
                    var ctx=getContext("2d"); ctx.clearRect(0,0,width,height)
                    var hist=hud.loadHistory; if(!hist||hist.length<1) return
                    var bW=Math.max(4,width/60-1)
                    for(var i=0;i<hist.length;i++){
                        var v=hist[i], bh=(v/100)*(height-4), bx=i*(width/60)
                        var ag=0.15+0.75*(i/hist.length)
                        ctx.fillStyle=v>80?"rgba(255,34,68,"+ag+")":v>60?"rgba(255,170,0,"+ag+")":v>30?"rgba(0,170,255,"+ag+")":"rgba(0,255,136,"+ag+")"
                        ctx.fillRect(bx,height-4-bh,bW,bh)
                    }
                    ctx.fillStyle="rgba(0,170,255,0.12)"; ctx.fillRect(0,height-4,width,2)
                }
            }
        }

        Item { width: parent.width; height: 4 }
        HSep { width: parent.width }
        Item { width: parent.width; height: 6 }

        // ══════════════════════════════════════════════════════════
        //  STORAGE + DISK I/O + NETWORK (fade-out im Gaming-Modus)
        // ══════════════════════════════════════════════════════════
        Item {
            id: panelIO
            width: parent.width
            height: gamingPanel.show ? 0 : 240
            clip: true
            opacity: (gamingPanel.show ? 0.0 : 1.0) * (root._revealStage >= 5 ? 1.0 : 0.0)
            visible: height > 2
            Behavior on height  { NumberAnimation { duration:450; easing.type:Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration:300 } }

            PanelBrackets { anchors.fill:parent; bracketColor:Qt.rgba(0,1,0.53,0.45); sz:14 }

            Column {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 5

                // Storage-Leiste
                HBar { width:parent.width
                       value:hud.storage; col:root.cAmber; label:"STORAGE"
                       showGb:true; usedGb:hud.storageUsedGb; totalGb:hud.storageTotalGb }

                // Disk I/O
                MetricRow { width:parent.width
                            labelA:"DISK R"; valA:hud.diskReadMbps.toFixed(1)+" MB/s";  colA:root.cBlue
                            labelB:"DISK W"; valB:hud.diskWriteMbps.toFixed(1)+" MB/s"; colB:root.cVio2 }

                // IP-Zeile
                Row { spacing:8
                    Text { text:"IP"; font.family:"DejaVu Sans Mono"; font.pixelSize:10
                           color:Qt.rgba(0,1,0.53,0.45); anchors.verticalCenter:parent.verticalCenter }
                    Text { text:hud.netLocalIp; font.family:"DejaVu Sans Mono"; font.pixelSize:13; color:root.cGreen }
                }

                // NET RX Graph
                Item {
                    width: parent.width; height: 48
                    Text { text:"NET RX"; font.family:"DejaVu Sans Mono"; font.pixelSize:8; font.letterSpacing:3
                           color:Qt.rgba(0,1,0.53,0.4); anchors.top:parent.top; anchors.left:parent.left }
                    Text { text:hud.netRxMbps.toFixed(2)+" MB/s"; font.family:"DejaVu Sans Mono"; font.pixelSize:11; color:root.cGreen
                           anchors.top:parent.top; anchors.right:parent.right }
                    Canvas {
                        id: netRxCanvas
                        anchors.top:parent.top; anchors.topMargin:16
                        anchors.bottom:parent.bottom; anchors.left:parent.left; anchors.right:parent.right
                        onPaint: {
                            var ctx=getContext("2d"); ctx.clearRect(0,0,width,height)
                            var hist=root.netRxHistory; if(!hist||hist.length<2) return
                            var peak=root.netPeak
                            ctx.strokeStyle="rgba(0,255,136,0.75)"; ctx.lineWidth=1.5; ctx.beginPath()
                            for(var i=0;i<hist.length;i++){
                                var px=i*(width/(hist.length-1))
                                var py=height-(hist[i]/peak)*(height-2)-1
                                i===0?ctx.moveTo(px,py):ctx.lineTo(px,py)
                            }
                            ctx.stroke()
                            ctx.lineTo(width,height); ctx.lineTo(0,height); ctx.closePath()
                            ctx.fillStyle="rgba(0,255,136,0.08)"; ctx.fill()
                        }
                    }
                }

                // NET TX Graph
                Item {
                    width: parent.width; height: 48
                    Text { text:"NET TX"; font.family:"DejaVu Sans Mono"; font.pixelSize:8; font.letterSpacing:3
                           color:Qt.rgba(0,0.67,1,0.4); anchors.top:parent.top; anchors.left:parent.left }
                    Text { text:hud.netTxMbps.toFixed(2)+" MB/s"; font.family:"DejaVu Sans Mono"; font.pixelSize:11; color:root.cBlue
                           anchors.top:parent.top; anchors.right:parent.right }
                    Canvas {
                        id: netTxCanvas
                        anchors.top:parent.top; anchors.topMargin:16
                        anchors.bottom:parent.bottom; anchors.left:parent.left; anchors.right:parent.right
                        onPaint: {
                            var ctx=getContext("2d"); ctx.clearRect(0,0,width,height)
                            var hist=root.netTxHistory; if(!hist||hist.length<2) return
                            var peak=root.netPeak
                            ctx.strokeStyle="rgba(0,170,255,0.75)"; ctx.lineWidth=1.5; ctx.beginPath()
                            for(var i=0;i<hist.length;i++){
                                var px=i*(width/(hist.length-1))
                                var py=height-(hist[i]/peak)*(height-2)-1
                                i===0?ctx.moveTo(px,py):ctx.lineTo(px,py)
                            }
                            ctx.stroke()
                            ctx.lineTo(width,height); ctx.lineTo(0,height); ctx.closePath()
                            ctx.fillStyle="rgba(0,170,255,0.08)"; ctx.fill()
                        }
                    }
                }
            }
        }

        Item { width: parent.width; height: gamingPanel.show ? 0 : 4 }
        HSep { width: parent.width; visible: !gamingPanel.show }
        Item { width: parent.width; height: gamingPanel.show ? 0 : 6 }

        // ══════════════════════════════════════════════════════════
        //  GAMING PANEL — volle Variable Zone (541px)
        // ══════════════════════════════════════════════════════════
        Item {
            id: gamingPanel
            width: parent.width
            // Sichtbar wenn MangoHud-Daten da ODER appState="gaming" (ohne MangoHud)
            readonly property bool show: hud.gaming || hud.appState === "gaming"
            height: show ? 540 : 0
            clip: true
            opacity: (show ? 1.0 : 0.0) * (root._revealStage >= 5 ? 1.0 : 0.0)
            Behavior on height  { NumberAnimation { duration:500; easing.type:Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration:350 } }
            visible: height > 2

            PanelBrackets { anchors.fill:parent; bracketColor:root.cBlue; sz:16 }

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 0

                // Spielname (klein, nur wenn Thumbnail sichtbar)
                Text {
                    text: hud.gameName; width: parent.width
                    height: hud.thumbnailB64 !== "" ? 36 : 0
                    visible: hud.thumbnailB64 !== ""
                    font.family:"DejaVu Sans Mono"; font.pixelSize:13; font.letterSpacing:2
                    color: Qt.rgba(1,0.67,0,0.85); elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }

                // Thumbnail — volle Breite
                // asynchronous: Decode läuft im Background-Thread, kein QML-Stutter
                // opacity-Behavior: blendet das Bild ein sobald es render-bereit ist
                // height:0 wenn nicht sichtbar → kein versteckter Platzbedarf in Column
                Image {
                    id: thumbImg
                    width: parent.width
                    height: hud.thumbnailB64 !== "" ? 180 : 0
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    source: hud.thumbnailB64 ? "data:image/jpeg;base64,"+hud.thumbnailB64 : ""
                    visible: hud.thumbnailB64 !== ""
                    opacity: status === Image.Ready ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }
                    Rectangle { anchors.fill:parent; color:"transparent"
                                border.color:Qt.rgba(1,0.67,0,0.3); border.width:1 }
                }

                // Kein Thumbnail → Spieltitel groß zentriert
                // height:0 wenn nicht sichtbar → kein versteckter Platzbedarf in Column
                Item {
                    width: parent.width
                    height: hud.thumbnailB64 === "" ? 180 : 0
                    visible: hud.thumbnailB64 === ""
                    Text {
                        anchors.centerIn: parent
                        width: parent.width
                        text: hud.gameName
                        font.family: "DejaVu Sans Mono"; font.pixelSize: 22; font.bold: true
                        font.letterSpacing: 1
                        color: root.cBlue
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        style: Text.Outline; styleColor: Qt.rgba(1,0.67,0,0.15)
                    }
                }

                Item { width: parent.width; height: 4 }

                // FPS groß (links) + Percentile-Stats (mitte) + Vertikaler Balken (rechts)
                // Alle drei Blöcke beginnen oben auf der gleichen Höhe und sind gleich hoch.
                Row {
                    width: parent.width; height: 80; spacing: 0

                    // Block 1: FPS-Zahl + "FPS" Label + frametime — Oberkante = Row-Oberkante
                    Column {
                        width: 240; height: parent.height
                        Row { spacing: 8; anchors.left: parent.left
                            Text { text: Math.round(hud.fps)
                                   font.family:"DejaVu Sans Mono"; font.pixelSize:62; font.bold:true
                                   color: root.cBlue; style:Text.Outline; styleColor:Qt.rgba(0,0.67,1,0.2) }
                            Column { anchors.verticalCenter: parent.verticalCenter; spacing: 4
                                Text { text:"FPS"; font.family:"DejaVu Sans Mono"; font.pixelSize:12; font.letterSpacing:3; color:Qt.rgba(0,0.67,1,0.55) }
                                Text { text:hud.frametimeMs.toFixed(1)+" ms"; font.family:"DejaVu Sans Mono"; font.pixelSize:14; color:Qt.rgba(0,0.67,1,0.75) }
                            }
                        }
                    }

                    // Block 2: Percentile-Stats — oben bündig
                    Item {
                        width: parent.width - 240 - 36; height: parent.height
                        Column {
                            anchors.top: parent.top
                            anchors.left: parent.left; anchors.leftMargin: 4
                            spacing: 10
                            Column { spacing:3
                                Text { text:"1% LOW"; font.family:"DejaVu Sans Mono"; font.pixelSize:9; font.letterSpacing:2; color:Qt.rgba(0,0.67,1,0.45) }
                                Text { text:Math.round(hud.fps1PctLow)+" fps"; font.family:"DejaVu Sans Mono"; font.pixelSize:18; color:root.cBlue }
                            }
                            Column { spacing:3
                                Text { text:"0.1% LOW"; font.family:"DejaVu Sans Mono"; font.pixelSize:9; font.letterSpacing:2; color:Qt.rgba(0,0.67,1,0.45) }
                                Text { text:Math.round(hud.fpsPoint1PctLow)+" fps"; font.family:"DejaVu Sans Mono"; font.pixelSize:18; color:Qt.rgba(0,0.67,1,0.7) }
                            }
                        }
                    }

                    // Block 3: Vertikaler FPS-Balken — oben bündig, gleiche Höhe wie Row
                    // PanelBrackets rahmt den Balken; 1 Pixel Abstand zwischen Bracket und Track.
                    Item {
                        width: 36; height: parent.height
                        anchors.top: parent.top

                        PanelBrackets { anchors.fill: parent; bracketColor: Qt.rgba(0,0.67,1,0.5); sz: 8 }

                        // Hintergrund-Track (2px Einzug: 1px Bracket-Linie + 1px Abstand)
                        Rectangle {
                            anchors.fill: parent; anchors.margins: 2
                            radius: 3
                            color: Qt.rgba(0,0.67,1,0.09)
                        }

                        // Füllbalken (wächst von unten)
                        Rectangle {
                            property real ratio: Math.min(hud.fps / 60.0, 1.0)
                            Behavior on ratio { NumberAnimation { duration: 80 } }
                            anchors.left: parent.left;   anchors.leftMargin:   3
                            anchors.right: parent.right; anchors.rightMargin:  3
                            anchors.bottom: parent.bottom; anchors.bottomMargin: 3
                            height: Math.max(radius * 2, (parent.height - 4) * ratio)
                            radius: 2
                            color: ratio < 0.50 ? root.cRed :
                                   ratio < 0.84 ? root.cAmber : root.cGreen
                        }
                    }
                }

                // Frametime-Chart — zeitbasiertes Scrolling
                // Jeder Datenpunkt wird mit Timestamp gespeichert.
                // Ein 50 ms-Timer ruft requestPaint auf, onPaint positioniert
                // Punkte nach Alter (now - t) → Chart scrollt kontinuierlich.
                Item {
                    id: frametimeChartItem
                    width: parent.width; height: 120

                    // Timestamp-Puffer: Array von {t: ms, v: frametimeMs}
                    property var  ftData:     []
                    property real ftWindowMs: 7000   // 7 s sichtbares Fenster
                    property bool _wasGaming: false

                    // Neuen Messpunkt mit aktuellem Timestamp eintragen
                    Connections {
                        target: hud
                        function onChanged() {
                            var gaming = hud.gaming
                            if (frametimeChartItem._wasGaming && !gaming) {
                                frametimeChartItem.ftData = []
                                ftCanvas.requestPaint()
                            }
                            frametimeChartItem._wasGaming = gaming
                            if (!gaming || hud.frametimeMs <= 0) return
                            var d = frametimeChartItem.ftData
                            d.push({t: Date.now(), v: hud.frametimeMs})
                            // Array alle ~30 s kürzen (Speicher)
                            if (d.length > 300) {
                                var cut = Date.now() - frametimeChartItem.ftWindowMs - 2000
                                var k = 0
                                while (k < d.length && d[k].t < cut) k++
                                if (k > 0) frametimeChartItem.ftData = d.slice(k)
                            }
                        }
                    }

                    // 20 Hz → sauberes Scrolling; läuft nur im Gaming-Mode
                    Timer {
                        interval: 50; repeat: true; running: hud.gaming
                        onTriggered: { if (frametimeChartItem.ftData.length > 1) ftCanvas.requestPaint() }
                    }

                    // Canvas füllt das gesamte Item; Label liegt darüber (z:1).
                    // Dadurch beginnt der Graph ~4px unterhalb des FPS-Blocks (Spacer = 4px).
                    Canvas {
                        id: ftCanvas
                        anchors.fill: parent

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            var data = frametimeChartItem.ftData
                            var n = data.length
                            if (n < 2) return

                            var now = Date.now()
                            var win = frametimeChartItem.ftWindowMs
                            var maxFt = 50
                            var y60 = height * (1 - 16.7 / maxFt)
                            var y30 = height * (1 - 33.3 / maxFt)

                            // Gitternetz
                            ctx.lineWidth = 1
                            ctx.strokeStyle = "rgba(0,255,136,0.22)"
                            ctx.beginPath(); ctx.moveTo(0,y60); ctx.lineTo(width,y60); ctx.stroke()
                            ctx.strokeStyle = "rgba(255,170,0,0.22)"
                            ctx.beginPath(); ctx.moveTo(0,y30); ctx.lineTo(width,y30); ctx.stroke()
                            ctx.font = "9px monospace"
                            ctx.fillStyle = "rgba(0,255,136,0.45)"; ctx.fillText("60fps", 2, y60 - 2)
                            ctx.fillStyle = "rgba(255,170,0,0.45)"; ctx.fillText("30fps", 2, y30 - 2)

                            // Punkte in x-Position übersetzen:
                            //   x = width * (1 – age/win)  →  neu = rechts, alt = links
                            // Nur Punkte innerhalb des Fensters einsammeln
                            var xs = [], ys = [], j, age, x, y
                            for (j = 0; j < n; j++) {
                                age = now - data[j].t
                                if (age > win) continue
                                xs.push(width * (1.0 - age / win))
                                ys.push(height - Math.min(data[j].v / maxFt, 1.0) * (height - 2))
                            }
                            var m = xs.length
                            if (m < 2) return

                            // Area fill (Gradient)
                            var grad = ctx.createLinearGradient(0, 0, 0, height)
                            grad.addColorStop(0.0,  "rgba(255,34,68,0.70)")
                            grad.addColorStop(0.33, "rgba(255,170,0,0.65)")
                            grad.addColorStop(0.67, "rgba(0,255,136,0.60)")
                            grad.addColorStop(1.0,  "rgba(0,255,136,0.15)")
                            ctx.beginPath()
                            ctx.moveTo(xs[0], height)
                            for (j = 0; j < m; j++) ctx.lineTo(xs[j], ys[j])
                            ctx.lineTo(xs[m - 1], height)
                            ctx.closePath()
                            ctx.fillStyle = grad
                            ctx.fill()

                            // Linie drüber
                            ctx.beginPath()
                            ctx.moveTo(xs[0], ys[0])
                            for (j = 1; j < m; j++) ctx.lineTo(xs[j], ys[j])
                            ctx.strokeStyle = "rgba(0,170,255,0.70)"
                            ctx.lineWidth = 1.5
                            ctx.stroke()

                            // Rand-Ausblendung — versteckt abruptes Erscheinen/Verschwinden von Balken
                            var fadeW = 20
                            var lg = ctx.createLinearGradient(0, 0, fadeW, 0)
                            lg.addColorStop(0.0, "#020B18")
                            lg.addColorStop(1.0, "rgba(2,11,24,0)")
                            ctx.fillStyle = lg
                            ctx.fillRect(0, 0, fadeW, height)
                            var rg = ctx.createLinearGradient(width - fadeW, 0, width, 0)
                            rg.addColorStop(0.0, "rgba(2,11,24,0)")
                            rg.addColorStop(1.0, "#020B18")
                            ctx.fillStyle = rg
                            ctx.fillRect(width - fadeW, 0, fadeW, height)
                        }
                    }

                    // Label über dem Canvas (z:1), damit der Graph die volle Höhe nutzt
                    Text {
                        id: ftChartLabel
                        z: 1
                        text: "FRAMETIME  ms"
                        font.family:"DejaVu Sans Mono"; font.pixelSize:9; font.letterSpacing:3
                        color: Qt.rgba(0,0.67,1,0.45)
                        anchors.top: parent.top; anchors.left: parent.left
                    }
                }
            }
        }

        // ══════════════════════════════════════════════════════════
        //  FAKE TERMINAL LOG
        // ══════════════════════════════════════════════════════════
        Item {
            id: termPanel
            width: parent.width
            height: gamingPanel.show ? 0 : 173
            clip: true
            opacity: (gamingPanel.show ? 0.0 : 1.0) * (root._revealStage >= 5 ? 1.0 : 0.0)
            visible: height > 2
            Behavior on height  { NumberAnimation { duration:450; easing.type:Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration:300 } }

            PanelBrackets { anchors.fill:parent; bracketColor:Qt.rgba(0,1,0.53,0.4); sz:14 }

            // ── Log-Zeilen State ───────────────────────────────────
            property var lines: []

            // Nachrichten-Pool: mischt Live-Daten mit statischen Fake-Events
            function nextMsg() {
                var pool = [
                    "[SYS]  cpu " + Math.round(hud.cpu) + "% · temp " + hud.cpuTemp.toFixed(1) + "°C · " + Math.round(hud.cpuFreqMhz) + " MHz",
                    "[SYS]  soc power draw: " + hud.cpuPackageW.toFixed(1) + "W",
                    "[GPU]  render " + Math.round(hud.gpu) + "% @ " + hud.gpuTemp.toFixed(0) + "°C · " + Math.round(hud.gpuFreqMhz) + " MHz",
                    "[GPU]  vram " + hud.vramUsedGb.toFixed(1) + "/" + hud.vramTotalGb.toFixed(1) + " G · pwr " + hud.gpuPowerW.toFixed(0) + "W",
                    "[MEM]  used " + hud.ramUsedGb.toFixed(1) + "/" + hud.ramTotalGb.toFixed(1) + " GB · swap " + hud.swapPercent.toFixed(0) + "%",
                    "[I/O]  disk r:" + hud.diskReadMbps.toFixed(1) + " w:" + hud.diskWriteMbps.toFixed(1) + " MB/s",
                    "[NET]  rx " + hud.netRxMbps.toFixed(2) + " tx " + hud.netTxMbps.toFixed(2) + " MB/s · " + hud.netLocalIp,
                    "[NET]  link 1GbE — host reachable · ping <2ms",
                    "[HUD]  daemon heartbeat OK · state: " + hud.appState,
                    "[HUD]  display locked 60 Hz · eglfs/kms · atomic",
                    "[SYS]  thermal headroom nominal · throttle: none",
                    "[SYS]  uptime " + (function(){ var s=hud.uptimeSeconds; return Math.floor(s/3600)+"h "+Math.floor((s%3600)/60)+"m" })(),
                    "[HUD]  pigpiod OK · backlight PWM 100%",
                    "[SYS]  load avg stable · no OOM events",
                ]
                return pool[Math.floor(Math.random() * pool.length)]
            }

            function addLine() {
                var d = new Date()
                var ts = ("0"+d.getHours()).slice(-2)+":"+("0"+d.getMinutes()).slice(-2)+":"+("0"+d.getSeconds()).slice(-2)
                var cur = termPanel.lines.slice()
                cur.push(ts + "  " + termPanel.nextMsg())
                if (cur.length > 13) cur.shift()
                termPanel.lines = cur
            }

            // Beim Start 7 Zeilen vorausfüllen
            Component.onCompleted: {
                for (var i = 0; i < 7; i++) addLine()
            }

            // Alle 2.8s eine neue Zeile
            Timer { interval:2800; repeat:true; running:true; onTriggered: termPanel.addLine() }

            // ── Visuals ────────────────────────────────────────────
            // Cursor-Blinker (letzte Zeile)
            property bool _blink: true
            Timer { interval:530; repeat:true; running:true; onTriggered: termPanel._blink = !termPanel._blink }

            // Schwacher oberer Trennstrich
            Rectangle {
                anchors.top: parent.top; width: parent.width; height: 1
                color: Qt.rgba(0,1,0.53,0.15)
            }

            // Label oben rechts
            Text {
                anchors.top: parent.top; anchors.topMargin: 4
                anchors.right: parent.right; anchors.rightMargin: 12
                text: "SYS LOG"; font.family:"DejaVu Sans Mono"; font.pixelSize:8; font.letterSpacing:4
                color: Qt.rgba(0,1,0.53,0.25)
            }

            // Log-Zeilen
            Column {
                anchors.left: parent.left; anchors.right: parent.right
                anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                anchors.leftMargin: 10; anchors.rightMargin: 10
                spacing: 1

                Repeater {
                    model: termPanel.lines
                    Text {
                        width: parent.width
                        readonly property bool isLast: index === termPanel.lines.length - 1
                        text: isLast
                              ? modelData + (termPanel._blink ? "▌" : " ")
                              : modelData
                        font.family: "DejaVu Sans Mono"; font.pixelSize: 10
                        color: isLast
                               ? Qt.rgba(0,1,0.53,0.9)
                               : Qt.rgba(0,1,0.53, 0.28 + 0.25*(index/Math.max(1,termPanel.lines.length-1)))
                        elide: Text.ElideRight
                    }
                }
            }
        }

        // ══════════════════════════════════════════════════════════
        //  SPECTRUM ANALYZER (fade-out im Gaming-Modus)
        // ══════════════════════════════════════════════════════════
        Item {
            id: specPanel
            width: parent.width
            height: gamingPanel.show ? 0 : 106
            clip: true
            opacity: (gamingPanel.show ? 0.0 : 1.0) * (root._revealStage >= 5 ? 1.0 : 0.0)
            visible: height > 2
            Behavior on height  { NumberAnimation { duration:450; easing.type:Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration:300 } }

            PanelBrackets { anchors.fill:parent; bracketColor:Qt.rgba(0,0.67,1,0.35); sz:14 }

            Text { anchors.top:parent.top; anchors.left:parent.left; anchors.leftMargin:12
                   text:"SPECTRUM"; font.family:"DejaVu Sans Mono"; font.pixelSize:8; font.letterSpacing:4
                   color:Qt.rgba(0,1,0.53,0.32) }

            // Spectrum: Canvas statt 44 Rectangles — keine per-Frame property-Bindings
            Canvas {
                id: specCanvas
                anchors.top:parent.top; anchors.topMargin:18
                anchors.bottom:parent.bottom; anchors.bottomMargin:6
                anchors.left:parent.left; anchors.right:parent.right
                anchors.leftMargin:8; anchors.rightMargin:8

                property real phase: 0

                // Nur repainten wenn sichtbar (stoppt in gaming mode automatisch)
                Timer {
                    interval: 50; repeat: true; running: specPanel.height > 2
                    onTriggered: {
                        // 2π in 4200ms → pro 50ms: 2π/84 ≈ 0.07480
                        specCanvas.phase = (specCanvas.phase + 0.07480) % (Math.PI * 2)
                        specCanvas.requestPaint()
                    }
                }

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    var n = 44
                    var bw = Math.max(0.5, (width - n) / n)
                    var ph = phase
                    // 3 Alpha-Batches statt 44 fillStyle-Strings
                    var lo = [], mid = [], hi = []
                    for (var i = 0; i < n; i++) {
                        var baseAmp = 0.25 + 0.75 * Math.abs(Math.sin(i * 0.41 + 0.9))
                        var relH = baseAmp * (0.42 + 0.58 * Math.abs(Math.sin(ph + i * 0.28 + Math.cos(i * 0.19) * 1.8)))
                        var bh = Math.max(3, (height - 2) * relH)
                        var rx = i * (bw + 1), ry = height - bh
                        if      (relH < 0.45) lo.push(rx, ry, bw, bh)
                        else if (relH < 0.75) mid.push(rx, ry, bw, bh)
                        else                  hi.push(rx, ry, bw, bh)
                    }
                    var j
                    ctx.fillStyle = "rgba(0,170,255,0.50)"; ctx.beginPath()
                    for (j = 0; j < lo.length;  j+=4) ctx.rect(lo[j],  lo[j+1],  lo[j+2],  lo[j+3])
                    ctx.fill()
                    ctx.fillStyle = "rgba(0,170,255,0.72)"; ctx.beginPath()
                    for (j = 0; j < mid.length; j+=4) ctx.rect(mid[j], mid[j+1], mid[j+2], mid[j+3])
                    ctx.fill()
                    ctx.fillStyle = "rgba(0,200,255,0.92)"; ctx.beginPath()
                    for (j = 0; j < hi.length;  j+=4) ctx.rect(hi[j],  hi[j+1],  hi[j+2],  hi[j+3])
                    ctx.fill()
                }
            }
        }

        // ══════════════════════════════════════════════════════════
        //  FOOTER — Uptime + Hostname + IP
        // ══════════════════════════════════════════════════════════
        Item { width: parent.width; height: 4 }
        HSep { width: parent.width }
        Item {
            id: footer
            width: parent.width; height: 52
            opacity: root._revealStage >= 6 ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }

            PanelBrackets { anchors.fill:parent; bracketColor:Qt.rgba(0.8,0.5,1,0.3); sz:14 }

            Row {
                anchors.left:parent.left; anchors.leftMargin:12
                anchors.verticalCenter:parent.verticalCenter
                spacing: 18

                Column { spacing:2
                    Text { text:"UPTIME"; font.family:"DejaVu Sans Mono"; font.pixelSize:8; font.letterSpacing:3; color:Qt.rgba(0.8,0.5,1,0.4) }
                    Text { font.family:"DejaVu Sans Mono"; font.pixelSize:13; color:root.cVio2
                           text: {
                               var s=hud.uptimeSeconds
                               return String(Math.floor(s/3600)).padStart(2,"0")+"h "+
                                      String(Math.floor((s%3600)/60)).padStart(2,"0")+"m "+
                                      String(s%60).padStart(2,"0")+"s"
                           } }
                }
                Column { spacing:2
                    Text { text:"HOST"; font.family:"DejaVu Sans Mono"; font.pixelSize:8; font.letterSpacing:3; color:Qt.rgba(0.8,0.5,1,0.4) }
                    Text { text:hud.hostname; font.family:"DejaVu Sans Mono"; font.pixelSize:13; color:root.cVio2 }
                }
            }

            // Regenbogen-Bodenleiste
            Rectangle {
                anchors.bottom:parent.bottom; width:parent.width; height:2
                gradient:Gradient { orientation:Gradient.Horizontal
                    GradientStop{position:0.0;  color:"#0044FF"}
                    GradientStop{position:0.33; color:"#7700CC"}
                    GradientStop{position:0.66; color:"#00AAFF"}
                    GradientStop{position:1.0;  color:"#00FF88"}
                }
                SequentialAnimation on opacity { running:true; loops:Animation.Infinite
                    NumberAnimation{to:0.4;duration:2200} NumberAnimation{to:1.0;duration:2200} }
            }
        }

    } // Column (Haupt-Layout)

    // Keyboard-Escape
    Item { anchors.fill:parent; focus:true; Keys.onEscapePressed: Qt.quit() }

    // ══════════════════════════════════════════════════════════════
    //  CRT-GLOW-LINIE — leuchtendes Phosphor-Residual beim Ausschalten
    // ══════════════════════════════════════════════════════════════
    Rectangle {
        id: crtGlowLine
        z: 997
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter:   parent.verticalCenter
        width:   root.width
        height:  3
        visible: false
        gradient: Gradient { orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: "#FFFFFF" }
            GradientStop { position: 1.0; color: "transparent" }
        }
        // Zweiter Glow-Layer für Bloom-Effekt
        Rectangle {
            anchors.centerIn: parent
            width: parent.width; height: parent.height * 8
            opacity: 0.18
            gradient: Gradient { orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: "#88CCFF" }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    //  WIPE-BARS (Boot-Animation) — z:998, vor bootOverlay
    // ══════════════════════════════════════════════════════════════
    Rectangle {
        id: wipe1; z: 998
        x: -(width); y: 200
        width: root.width + 120; height: 26
        color: "white"; opacity: 0.88; rotation: -2.5
    }
    Rectangle {
        id: wipe2; z: 998
        x: -(width); y: root.height / 2 - 10
        width: root.width + 120; height: 20
        color: "white"; opacity: 0.72; rotation: 3.2
    }
    Rectangle {
        id: wipe3; z: 998
        x: -(width); y: root.height - 230
        width: root.width + 120; height: 22
        color: "white"; opacity: 0.82; rotation: -2.0
    }

    // ══════════════════════════════════════════════════════════════
    //  BOOT OVERLAY — gleiche Logik wie Querformat
    // ══════════════════════════════════════════════════════════════
    Rectangle {
        id: bootOverlay
        anchors.fill: parent
        z: 999
        color: "#000000"
        visible: opacity > 0.001

        opacity: root._bootAlpha

        readonly property color stateColor: {
            if (hud.appState === "standby")      return Qt.rgba(1.0, 0.67, 0.0, 1)
            if (hud.appState === "shutdown")     return Qt.rgba(1.0, 0.13, 0.27, 1)
            if (hud.appState === "initialising") return Qt.rgba(0.0, 1.0, 0.53, 1)
            if (hud.appState === "disconnected") return Qt.rgba(1.0, 0.67, 0.0, 1)
            if (hud.appState === "restarting")   return Qt.rgba(0.0, 0.67, 1.0, 1)
            return Qt.rgba(0.0, 0.67, 1.0, 1)
        }

        // Scan-Sweep (nicht bei disconnected — eigene Optik)
        Rectangle {
            width: parent.width; height: 2
            visible: hud.appState !== "disconnected"
            color: Qt.rgba(0,0.67,1,0.4)
            NumberAnimation on y { running:bootOverlay.visible; loops:Animation.Infinite; from:0; to:bootOverlay.height; duration:3000; easing.type:Easing.Linear }
        }

        // ── DISCONNECTED: Terminal-Anzeige ──────────────────────────
        Item {
            visible: hud.appState === "disconnected"
            anchors.centerIn: parent
            width: 420; height: 220

            // Bernsteinfarbener Hintergrund-Glow
            Rectangle {
                anchors.centerIn: parent
                width: 400; height: 100
                color: "transparent"
                Rectangle {
                    anchors.centerIn: parent
                    width: 380; height: 80; radius: 4
                    color: Qt.rgba(1.0, 0.67, 0.0, 0.04)
                }
            }

            // "DISCONNECTED" — terminal-artig blinkend
            Text {
                id: disconnectedTxt
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top; anchors.topMargin: 40
                text: "DISCONNECTED"
                font.family: "DejaVu Sans Mono"; font.pixelSize: 34; font.bold: true
                font.letterSpacing: 3; color: root.cAmber
                style: Text.Outline
                styleColor: Qt.rgba(1.0, 0.67, 0.0, 0.25)
                SequentialAnimation on opacity {
                    running: hud.appState === "disconnected"; loops: Animation.Infinite
                    NumberAnimation { to: 1.0;  duration: 40  }
                    PauseAnimation  { duration: 700 }
                    NumberAnimation { to: 0.05; duration: 40  }
                    PauseAnimation  { duration: 80  }
                    NumberAnimation { to: 1.0;  duration: 40  }
                    PauseAnimation  { duration: 700 }
                    NumberAnimation { to: 0.05; duration: 40  }
                    PauseAnimation  { duration: 60  }
                    NumberAnimation { to: 0.9;  duration: 30  }
                    PauseAnimation  { duration: 1400 }
                }
            }

            // Terminal-Cursor-Block
            Rectangle {
                anchors.top: disconnectedTxt.bottom; anchors.topMargin: 4
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.horizontalCenterOffset: 14
                width: 16; height: 22; color: root.cAmber; radius: 1
                SequentialAnimation on opacity {
                    running: hud.appState === "disconnected"; loops: Animation.Infinite
                    NumberAnimation { to: 1.0; duration: 60  }
                    PauseAnimation  { duration: 480 }
                    NumberAnimation { to: 0.0; duration: 60  }
                    PauseAnimation  { duration: 480 }
                }
            }

            // Untertitel
            Text {
                anchors.top: disconnectedTxt.bottom; anchors.topMargin: 58
                anchors.horizontalCenter: parent.horizontalCenter
                text: "SIGNAL LOST  //  AWAITING RECONNECT"
                font.family: "DejaVu Sans Mono"; font.pixelSize: 11; font.letterSpacing: 3
                color: Qt.rgba(1.0, 0.67, 0.0, 0.45)
                SequentialAnimation on opacity {
                    running: hud.appState === "disconnected"; loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 2000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0.75; duration: 2000; easing.type: Easing.InOutSine }
                }
            }
        }

        // ── RESTARTING: Pulsierender Restart-Screen ─────────────────
        Item {
            visible: hud.appState === "restarting"
            anchors.centerIn: parent
            width: 400; height: 240

            Text {
                id: restartingTxt
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top; anchors.topMargin: 50
                text: "RESTARTING\nSYSTEM"
                horizontalAlignment: Text.AlignHCenter
                font.family: "DejaVu Sans Mono"; font.pixelSize: 32; font.bold: true
                font.letterSpacing: 3; color: root.cBlue
                style: Text.Outline
                styleColor: Qt.rgba(0.0, 0.67, 1.0, 0.25)
                SequentialAnimation on opacity {
                    running: hud.appState === "restarting"; loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0;  duration: 900; easing.type: Easing.InOutSine }
                }
            }

            // Fortschritts-Dots
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: restartingTxt.bottom; anchors.topMargin: 28
                spacing: 16
                Repeater { model: 3
                    Rectangle {
                        width: 8; height: 8; radius: 4; color: root.cBlue
                        SequentialAnimation on opacity {
                            running: hud.appState === "restarting"; loops: Animation.Infinite
                            PauseAnimation  { duration: index * 280 }
                            NumberAnimation { to: 1.0;  duration: 280 }
                            NumberAnimation { to: 0.12; duration: 280 }
                            PauseAnimation  { duration: (2 - index) * 280 }
                        }
                    }
                }
            }
        }

        // ── STANDARD-BRANDING (booting/initialising/standby/shutdown) ─
        Item {
            visible: hud.appState !== "disconnected" && hud.appState !== "restarting"
            anchors.centerIn: parent
            width: 400; height: 340

            // Äußerer Ring (rotierend)
            Item { anchors.centerIn:parent; width:260; height:260
                RotationAnimation on rotation { running:bootOverlay.visible; loops:Animation.Infinite; duration:18000; direction:RotationAnimation.Clockwise }
                Shape { anchors.fill:parent
                    ShapePath { strokeColor:Qt.rgba(bootOverlay.stateColor.r,bootOverlay.stateColor.g,bootOverlay.stateColor.b,0.25); strokeWidth:1.5; fillColor:"transparent"
                        startX:130+120*Math.cos(-40*Math.PI/180); startY:130+120*Math.sin(-40*Math.PI/180)
                        PathArc{x:130+120*Math.cos(80*Math.PI/180);y:130+120*Math.sin(80*Math.PI/180);radiusX:120;radiusY:120;direction:PathArc.Clockwise} }
                    ShapePath { strokeColor:Qt.rgba(bootOverlay.stateColor.r,bootOverlay.stateColor.g,bootOverlay.stateColor.b,0.25); strokeWidth:1.5; fillColor:"transparent"
                        startX:130+120*Math.cos(110*Math.PI/180); startY:130+120*Math.sin(110*Math.PI/180)
                        PathArc{x:130+120*Math.cos(220*Math.PI/180);y:130+120*Math.sin(220*Math.PI/180);radiusX:120;radiusY:120;direction:PathArc.Clockwise} }
                    ShapePath { strokeColor:Qt.rgba(bootOverlay.stateColor.r,bootOverlay.stateColor.g,bootOverlay.stateColor.b,0.25); strokeWidth:1.5; fillColor:"transparent"
                        startX:130+120*Math.cos(250*Math.PI/180); startY:130+120*Math.sin(250*Math.PI/180)
                        PathArc{x:130+120*Math.cos(330*Math.PI/180);y:130+120*Math.sin(330*Math.PI/180);radiusX:120;radiusY:120;direction:PathArc.Clockwise} }
                }
            }

            // Innerer Ring (gegenläufig)
            Item { anchors.centerIn:parent; width:200; height:200
                RotationAnimation on rotation { running:bootOverlay.visible; loops:Animation.Infinite; duration:12000; direction:RotationAnimation.Counterclockwise }
                Shape { anchors.fill:parent
                    ShapePath { strokeColor:Qt.rgba(0.6,0.2,1,0.3); strokeWidth:1; fillColor:"transparent"
                        startX:100+85*Math.cos(0);startY:100+85*Math.sin(0)
                        PathArc{x:100+85*Math.cos(70*Math.PI/180);y:100+85*Math.sin(70*Math.PI/180);radiusX:85;radiusY:85;direction:PathArc.Clockwise} }
                    ShapePath { strokeColor:Qt.rgba(0.6,0.2,1,0.3); strokeWidth:1; fillColor:"transparent"
                        startX:100+85*Math.cos(100*Math.PI/180);startY:100+85*Math.sin(100*Math.PI/180)
                        PathArc{x:100+85*Math.cos(170*Math.PI/180);y:100+85*Math.sin(170*Math.PI/180);radiusX:85;radiusY:85;direction:PathArc.Clockwise} }
                    ShapePath { strokeColor:Qt.rgba(0.6,0.2,1,0.3); strokeWidth:1; fillColor:"transparent"
                        startX:100+85*Math.cos(200*Math.PI/180);startY:100+85*Math.sin(200*Math.PI/180)
                        PathArc{x:100+85*Math.cos(290*Math.PI/180);y:100+85*Math.sin(290*Math.PI/180);radiusX:85;radiusY:85;direction:PathArc.Clockwise} }
                    ShapePath { strokeColor:Qt.rgba(0.6,0.2,1,0.3); strokeWidth:1; fillColor:"transparent"
                        startX:100+85*Math.cos(310*Math.PI/180);startY:100+85*Math.sin(310*Math.PI/180)
                        PathArc{x:100+85*Math.cos(350*Math.PI/180);y:100+85*Math.sin(350*Math.PI/180);radiusX:85;radiusY:85;direction:PathArc.Clockwise} }
                }
            }

            // Logo
            Text { anchors.centerIn:parent; anchors.verticalCenterOffset:-22
                   text:"BC-250"; font.family:"DejaVu Sans Mono"; font.pixelSize:72; font.bold:true
                   color:bootOverlay.stateColor
                   style:Text.Outline; styleColor:Qt.rgba(bootOverlay.stateColor.r,bootOverlay.stateColor.g,bootOverlay.stateColor.b,0.3)
                   SequentialAnimation on opacity { running:bootOverlay.visible; loops:Animation.Infinite
                       NumberAnimation{to:0.7;duration:1200;easing.type:Easing.InOutSine}
                       NumberAnimation{to:1.0;duration:1200;easing.type:Easing.InOutSine} }
            }

            // Subtitle
            Text { anchors.centerIn:parent; anchors.verticalCenterOffset:46
                   text: hud.appState==="standby"    ? "STANDBY MODE"    :
                         hud.appState==="shutdown"   ? "SYSTEM SHUTDOWN" :
                         hud.appState==="initialising"? "SYSTEM READY"   :
                         hud.appState==="restarting" ? "SYSTEM RESTART"  : "TACTICAL DISPLAY SYSTEM"
                   font.family:"DejaVu Sans Mono"; font.pixelSize:12; font.letterSpacing:5
                   color:Qt.rgba(bootOverlay.stateColor.r,bootOverlay.stateColor.g,bootOverlay.stateColor.b,0.55) }
        }

        // Status-Text (unten)
        Item {
            anchors.bottom:parent.bottom; anchors.bottomMargin:32
            anchors.horizontalCenter:parent.horizontalCenter
            width:400; height:30

            Text { id:bootStatusTxt; anchors.centerIn:parent
                   text: hud.appState==="initialising" ? "POWER OK  ■  BC250 OFFLINE"  :
                         hud.appState==="booting"      ? "AWAITING HOST CONNECTION"     :
                         hud.appState==="standby"      ? "LOW POWER STANDBY"            :
                         hud.appState==="shutdown"     ? "POWERING DOWN"                :
                         hud.appState==="restarting"   ? "PLEASE WAIT..."               : ""
                   font.family:"DejaVu Sans Mono"; font.pixelSize:11; font.letterSpacing:3
                   color:Qt.rgba(bootOverlay.stateColor.r,bootOverlay.stateColor.g,bootOverlay.stateColor.b,0.5) }

            Rectangle { anchors.left:bootStatusTxt.right; anchors.leftMargin:6; anchors.verticalCenter:bootStatusTxt.verticalCenter
                        width:5; height:5; radius:2.5; color:bootOverlay.stateColor
                        visible: hud.appState!=="shutdown" && hud.appState!=="disconnected"
                        SequentialAnimation on opacity {
                            running: bootOverlay.visible && hud.appState!=="shutdown" && hud.appState!=="disconnected"
                            loops: Animation.Infinite
                            NumberAnimation{to:0.1;duration:600} NumberAnimation{to:1.0;duration:600} } }

            Row { anchors.centerIn:parent; spacing:10; visible:hud.appState==="shutdown"
                Repeater { model:3
                    Rectangle { width:6;height:6;radius:3; color:Qt.rgba(1,0.13,0.27,0.8)
                        SequentialAnimation on opacity { running:hud.appState==="shutdown"; loops:Animation.Infinite
                            NumberAnimation{to:0.1;duration:400+index*200} NumberAnimation{to:1.0;duration:400+index*200} } }
                }
            }
        }

        // Eck-Brackets (H enthält Eckpixel, V versetzt um 2px → kein Doppel-Rendering)
        readonly property color _bc: Qt.rgba(stateColor.r, stateColor.g, stateColor.b, 0.4)
        Rectangle{x:14;              y:14;               width:28; height:2;  color:bootOverlay._bc} // TL H
        Rectangle{x:14;              y:16;               width:2;  height:26; color:bootOverlay._bc} // TL V
        Rectangle{x:parent.width-42; y:14;               width:28; height:2;  color:bootOverlay._bc} // TR H
        Rectangle{x:parent.width-16; y:16;               width:2;  height:26; color:bootOverlay._bc} // TR V
        Rectangle{x:14;              y:parent.height-16; width:28; height:2;  color:bootOverlay._bc} // BL H
        Rectangle{x:14;              y:parent.height-42; width:2;  height:26; color:bootOverlay._bc} // BL V
        Rectangle{x:parent.width-42; y:parent.height-16; width:28; height:2;  color:bootOverlay._bc} // BR H
        Rectangle{x:parent.width-16; y:parent.height-42; width:2;  height:26; color:bootOverlay._bc} // BR V
    }

    } // scene

}
