// WeOS 安装器幻灯片
import QtQuick 2.15
import calamares.slideshow 1.0

Presentation {
    id: presentation

    Timer {
        interval: 8000
        running: true
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#0b1026"
        }
        Column {
            anchors.centerIn: parent
            spacing: 22
            Image {
                source: "welcome.png"
                width: 560
                height: 280
                fillMode: Image.PreserveAspectFit
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                text: "欢迎使用 WeOS"
                color: "#f0f4ff"
                font.pixelSize: 26
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                text: "XanMod 内核 · UKUI 桌面 · NVIDIA 专有驱动 · Wine / Proton"
                color: "#9fb0d0"
                font.pixelSize: 15
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#0b1026"
        }
        Column {
            anchors.centerIn: parent
            spacing: 18
            Text {
                text: "为游戏与创作优化"
                color: "#f0f4ff"
                font.pixelSize: 26
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                text: "XanMod 7.x 内核（BBR3 / sched_ext / 低延迟调度）"
                color: "#9fb0d0"
                font.pixelSize: 15
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                text: "内置 GE-Proton 与 umu-launcher，开箱即玩"
                color: "#9fb0d0"
                font.pixelSize: 15
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                text: "安装过程约需 5-10 分钟，请保持通电"
                color: "#6f7f9e"
                font.pixelSize: 13
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
