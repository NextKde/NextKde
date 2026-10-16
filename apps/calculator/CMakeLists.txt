kos_add_application(kos-calculator
    URI Kos.Apps.Calculator
    DISPLAY_NAME "KOS Calculator"
    DESKTOP_FILE ${CMAKE_CURRENT_SOURCE_DIR}/data/kos-calculator.desktop.in
    ICON_FILE ${CMAKE_CURRENT_SOURCE_DIR}/data/kos-calculator.svg
    METAINFO_FILE ${CMAKE_CURRENT_SOURCE_DIR}/data/org.nextkde.Kos.Calculator.metainfo.xml
    SOURCES
        src/main.cpp
    QML_FILES
        qml/Main.qml
        qml/CalculatorPalette.qml
        qml/CalculatorEngine.qml
        qml/HistoryStore.qml
        qml/CalculatorButton.qml
        qml/CalculatorChromeButton.qml
        qml/CalculatorGlassPanel.qml
        qml/CalculatorIcon.qml
        qml/CalculatorMenu.qml
        qml/CalculatorMenuItem.qml
        qml/CalculatorMenuSeparator.qml
        qml/CalculatorPill.qml
        qml/ConvertDisplay.qml
        qml/ConvertStore.qml
        qml/ConvertUnitChip.qml
        qml/HistoryPane.qml
        qml/Keypad.qml
        qml/UnitPicker.qml
        qml/CalculatorKeys.js
        qml/UnitTable.js
)
