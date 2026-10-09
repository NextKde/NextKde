#pragma once
#include "qmlbridge/controllers.h"
#include <QApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQuickWindow>
#include <QScreen>
#include <QSysInfo>
#include <QTimer>
#include <QWidget>
#include <windows.h>
#include <dwmapi.h>
#include <memory>

// Opt-in, disposable-profile regression of the actual HWND and desktop composite.
inline void runWindowCornerRegression(QApplication& app, QQuickWindow* window, QObject* shell,
    listenfree::qmlbridge::SettingsController& settings, const QString& reportPath) {
    struct State {
        int phase{0};
        bool failed{false};
        QJsonArray samples;
        QJsonObject checks;
        DWORD gdiBefore{0};
    };
    auto state = std::make_shared<State>();
    auto* backdrop = new QWidget(nullptr, Qt::Window | Qt::FramelessWindowHint | Qt::WindowDoesNotAcceptFocus);
    backdrop->setAttribute(Qt::WA_ShowWithoutActivating);
    backdrop->setWindowTitle("ListenFree corner regression backdrop");
    backdrop->setStyleSheet("background-color: #17c95b;");
    backdrop->setGeometry(window->screen()->availableGeometry());
    backdrop->show();
    window->hide();
    window->showNormal();
    window->setPosition(window->screen()->availableGeometry().topLeft() + QPoint(55, 50));
    window->raise();
    window->requestActivate();
    shell->setProperty("settingsOpen", true);
    settings.setValue("appearance.mode", "Dark");
    settings.setValue("window.transparencyEnabled", true);
    settings.setValue("tray.enabled", false);
    QDir().mkpath(QFileInfo(reportPath).absolutePath());
    auto* timer = new QTimer(&app);
    timer->setInterval(1100);
    auto capture = [=](const QString& name, bool square = false, bool baseline = false) {
        const HWND hwnd = reinterpret_cast<HWND>(window->winId());
        RECT bounds{};
        GetWindowRect(hwnd, &bounds);
        const int width = bounds.right - bounds.left;
        const int height = bounds.bottom - bounds.top;
        HRGN region = CreateRectRgn(0, 0, 0, 0);
        const int kind = GetWindowRgn(hwnd, region);
        bool outside = true;
        for (const QPoint point : {QPoint(1, 1), QPoint(width-2, 1), QPoint(1, height-2), QPoint(width-2, height-2)})
            outside = outside && !PtInRegion(region, point.x(), point.y());
        const bool center = kind != ERROR && PtInRegion(region, width/2, height/2);
        DeleteObject(region);
        const bool geometryOk = baseline ? kind == ERROR : square ? kind == ERROR : kind != ERROR && outside && center;
        const bool radiusOk = window->property("cornerRadius").toDouble() == (square ? 0.0 : 32.0);
        state->checks[name + "/nativeBoundary"] = geometryOk;
        state->checks[name + "/qmlRadius"] = radiusOk;
        state->failed = state->failed || !geometryOk || !radiusOk;
        const QImage qml = window->grabWindow();
        HDESK input = OpenInputDesktop(0, FALSE, DESKTOP_READOBJECTS);
        WCHAR desktopName[128]{};
        DWORD needed{};
        const bool desktopAccessible = input && GetUserObjectInformationW(input, UOI_NAME, desktopName, sizeof(desktopName), &needed) &&
            QString::fromWCharArray(desktopName) == QStringLiteral("Default");
        if (input) CloseDesktop(input);
        const QImage desktop = desktopAccessible ? window->screen()->grabWindow(0, window->x(), window->y(), window->width(), window->height()).toImage() : QImage{};
        qml.save(reportPath + "." + name + ".qml.png");
        desktop.save(reportPath + "." + name + ".desktop.png");
        QJsonObject sample{{"stage", name}, {"nativeWidth", width}, {"nativeHeight", height},
            {"dpr", window->devicePixelRatio()}, {"qmlRadius", window->property("cornerRadius").toDouble()},
            {"nativeRegionKind", kind}, {"desktopAccessible", desktopAccessible},
            {"desktopTransparencyActive", shell->property("desktopTransparencyActive").toBool()}};
        if (!qml.isNull()) sample["qmlTopLeftAlpha"] = qml.pixelColor(1, 1).alpha();
        if (!desktop.isNull() && !square) {
            const QColor corner = desktop.pixelColor(1, 1);
            sample["desktopTopLeft"] = corner.name();
            const QColor expected("#17c95b");
            const bool exposesBackdrop = qAbs(corner.red()-expected.red()) < 4 &&
                qAbs(corner.green()-expected.green()) < 4 && qAbs(corner.blue()-expected.blue()) < 4;
            state->checks[name + "/desktopCorner"] = baseline ? !exposesBackdrop : exposesBackdrop;
            state->failed = state->failed || (baseline ? exposesBackdrop : !exposesBackdrop);
        } else if (!square) {
            sample["desktopCaptureSkipped"] = QStringLiteral("Desktop locked or capture unavailable");
        }
        state->samples.append(sample);
    };
    QObject::connect(timer, &QTimer::timeout, &app, [=, &app, &settings] {
        switch (state->phase++) {
        case 0:
            capture("dark-transparent");
            // Controlled reproduction of the released HWND configuration with the same QML scene.
            {
                const HWND hwnd = reinterpret_cast<HWND>(window->winId());
                const int backdropType = 3;
                const MARGINS margins{-1,-1,-1,-1};
                DwmSetWindowAttribute(hwnd,38,&backdropType,sizeof(backdropType));
                DwmExtendFrameIntoClientArea(hwnd,&margins);
            }
            SetWindowRgn(reinterpret_cast<HWND>(window->winId()), nullptr, TRUE);
            break;
        case 1:
            capture("released-boundary-reproduction", false, true);
            settings.setValue("window.transparencyEnabled", false);
            settings.setValue("window.transparencyEnabled", true);
            window->resize(window->width()+20, window->height()+10);
            break;
        case 2:
            capture("resized");
            settings.setValue("window.transparencyEnabled", false);
            break;
        case 3:
            capture("dark-opaque");
            settings.setValue("appearance.mode", "Light");
            settings.setValue("window.transparencyEnabled", true);
            break;
        case 4:
            capture("light-transparent");
            window->showMaximized();
            break;
        case 5:
            capture("maximized", true);
            window->showNormal();
            break;
        case 6:
            capture("restored-maximized");
            window->showFullScreen();
            break;
        case 7:
            capture("fullscreen", true);
            window->showNormal();
            break;
        case 8:
            capture("restored-fullscreen");
            window->hide();
            window->show();
            window->raise();
            break;
        case 9:
            capture("reshown");
            window->hide();
            window->destroy();
            window->showNormal();
            window->raise();
            break;
        case 10:
            capture("recreated");
            state->gdiBefore = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
            break;
        default:
            if (state->phase < 112) {
                window->resize(1060 + (state->phase%2)*20, 719 + (state->phase%2)*10);
                timer->setInterval(20);
                return;
            }
            capture("resize-stress");
            const DWORD after = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
            state->checks["resizeStress/noGdiLeak"] = after <= state->gdiBefore + 2;
            state->failed = state->failed || after > state->gdiBefore + 2;
            QJsonObject report{{"checks", state->checks}, {"samples", state->samples},
                {"gdiBefore", static_cast<int>(state->gdiBefore)}, {"gdiAfter", static_cast<int>(after)},
                {"passed", !state->failed}, {"qtVersion", qVersion()}, {"osVersion", QSysInfo::kernelVersion()}};
            QFile file(reportPath);
            const bool saved = file.open(QIODevice::WriteOnly) && file.write(QJsonDocument(report).toJson()) > 0;
            timer->stop();
            backdrop->hide();
            backdrop->deleteLater();
            app.exit(saved && !state->failed ? 0 : 5);
            break;
        }
    });
    timer->start();
}
