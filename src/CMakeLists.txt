add_library(kilotasksplugin SHARED
    unifiedtasksmodel.cpp
    unifiedtasksmodel.h
    plugin.cpp
)

target_link_libraries(kilotasksplugin
    Qt5::Core
    Qt5::Qml
    Qt5::Quick
    KF5::Service
)

# Install to the system-wide Qt5 QML import path so `import org.kilo.kilotasks 1.0` resolves.
# Query qmake at configure time to stay distro-portable (Ubuntu uses multiarch path).
execute_process(
    COMMAND /usr/lib/qt5/bin/qmake -query QT_INSTALL_QML
    OUTPUT_VARIABLE QT_INSTALL_QML
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

set(QML_DEST "${QT_INSTALL_QML}/org/kilo/kilotasks")

install(TARGETS kilotasksplugin
    LIBRARY DESTINATION "${QML_DEST}"
)

install(FILES qmldir
    DESTINATION "${QML_DEST}"
)
