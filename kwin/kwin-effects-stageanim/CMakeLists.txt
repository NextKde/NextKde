cmake_minimum_required(VERSION 3.16.0)

project(kwin-stageanim)
set(PROJECT_VERSION "1.0.0")

set(KF_MIN_VERSION "5.240.0")
set(QT_MIN_VERSION "6.6.0")
set(QT_MAJOR_VERSION 6)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Choose Release or Debug" FORCE)
endif()

find_package(ECM REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${ECM_MODULE_PATH} ${ECM_KDE_MODULE_DIR})

include(FeatureSummary)
include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

find_package(Qt6 ${QT_MIN_VERSION} CONFIG REQUIRED COMPONENTS
    Core
    Gui
    Widgets
    DBus
)

find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS
    Config
)

# Same capability check philosophy as the glass vendor: the imported target
# as a whole is the capability test.
find_package(KWin QUIET COMPONENTS kwineffects)
if(NOT KWin_FOUND OR NOT TARGET KWin::kwin)
    message(FATAL_ERROR "KWin development dependencies unavailable")
endif()

add_subdirectory(src)

feature_summary(WHAT ALL FATAL_ON_MISSING_REQUIRED_PACKAGES)
