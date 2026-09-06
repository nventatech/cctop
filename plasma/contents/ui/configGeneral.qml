// cctop - settings page (language, panel display, notifications, donate).
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property string cfg_language
    property string cfg_panelDisplay
    property int cfg_notifyThreshold
    property int cfg_notifyThresholdWeekly
    property int cfg_refreshInterval
    property int cfg_budgetMonthly
    property string cfg_extraSubscriptions
    property bool cfg_followSystemTheme

    property string cfg_languageDefault: ""
    property string cfg_panelDisplayDefault: "session"
    property int cfg_notifyThresholdDefault: 85
    property int cfg_notifyThresholdWeeklyDefault: 85
    property int cfg_refreshIntervalDefault: 60
    property int cfg_budgetMonthlyDefault: 0
    property string cfg_extraSubscriptionsDefault: ""
    property bool cfg_followSystemThemeDefault: false

    readonly property string donateUrl: "https://www.paypal.com/donate/?business=SR28XBBCYSPHE&no_recurring=0&item_name=Help+me+buy+a+coffee.&currency_code=USD"

    Item { implicitHeight: Kirigami.Units.largeSpacing * 2 }

    QQC2.ComboBox {
        Kirigami.FormData.label: "Language:"
        textRole: "text"
        valueRole: "value"
        model: [
            { value: "", text: "System" },
            { value: "en", text: "English" },
            { value: "pt_BR", text: "Português (Brasil)" },
            { value: "es", text: "Español" }
        ]
        onActivated: page.cfg_language = currentValue
        Component.onCompleted: currentIndex = indexOfValue(page.cfg_language)
    }

    QQC2.ComboBox {
        Kirigami.FormData.label: "Panel shows:"
        textRole: "text"
        valueRole: "value"
        model: [
            { value: "session", text: "Session %" },
            { value: "weekly", text: "Weekly % (tightest limit)" },
            { value: "today", text: "Spend today" },
            { value: "subs", text: "Subscriptions total" },
            { value: "reset", text: "Session reset countdown" }
        ]
        onActivated: page.cfg_panelDisplay = currentValue
        Component.onCompleted: currentIndex = indexOfValue(page.cfg_panelDisplay)
    }

    QQC2.SpinBox {
        Kirigami.FormData.label: "Notify at session % (0 = off):"
        from: 0
        to: 100
        stepSize: 5
        value: page.cfg_notifyThreshold
        onValueModified: page.cfg_notifyThreshold = value
    }

    QQC2.SpinBox {
        Kirigami.FormData.label: "Notify at weekly % (0 = off):"
        from: 0
        to: 100
        stepSize: 5
        value: page.cfg_notifyThresholdWeekly
        onValueModified: page.cfg_notifyThresholdWeekly = value
    }

    QQC2.SpinBox {
        Kirigami.FormData.label: "Monthly budget in US$ (0 = off):"
        from: 0
        to: 100000
        stepSize: 10
        value: page.cfg_budgetMonthly
        onValueModified: page.cfg_budgetMonthly = value
    }

    QQC2.SpinBox {
        Kirigami.FormData.label: "Refresh every (seconds):"
        from: 30
        to: 3600
        stepSize: 30
        value: page.cfg_refreshInterval
        onValueModified: page.cfg_refreshInterval = value
    }

    QQC2.CheckBox {
        Kirigami.FormData.label: "Popup colors:"
        text: "Follow the system theme"
        checked: page.cfg_followSystemTheme
        onToggled: page.cfg_followSystemTheme = checked
    }

    QQC2.TextArea {
        Kirigami.FormData.label: "Extra subscriptions:"
        implicitWidth: Kirigami.Units.gridUnit * 14
        implicitHeight: Kirigami.Units.gridUnit * 4
        placeholderText: "One per line, e.g.\nCursor Pro: 20"
        text: page.cfg_extraSubscriptions
        onTextChanged: page.cfg_extraSubscriptions = text
    }

    Kirigami.Separator { Kirigami.FormData.isSection: true }

    QQC2.Button {
        Kirigami.FormData.label: "Enjoying cctop?"
        text: "Donate via PayPal ❤"
        icon.name: "love"
        onClicked: Qt.openUrlExternally(page.donateUrl)
    }

    Image {
        Kirigami.FormData.label: " "
        source: Qt.resolvedUrl("../images/donate-qr.png")
        sourceSize.width: 140
        sourceSize.height: 140
        fillMode: Image.PreserveAspectFit
    }
}
