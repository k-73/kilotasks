cmake_minimum_required(VERSION 3.16)
project(kilotasks LANGUAGES CXX)

set(QT_MIN_VERSION 5.15.0)
set(KF5_MIN_VERSION 5.102.0)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(ECM ${KF5_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

find_package(Qt5 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core Qml Quick)
find_package(KF5 ${KF5_MIN_VERSION} REQUIRED COMPONENTS Service)

add_subdirectory(src)
