/*
    SPDX-FileCopyrightText: 2026 kilo
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "unifiedtasksmodel.h"

#include <QQmlEngine>
#include <QQmlExtensionPlugin>

class KiloTasksPlugin : public QQmlExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)

public:
    void registerTypes(const char *uri) override
    {
        Q_ASSERT(QLatin1String(uri) == QLatin1String("org.kilo.kilotasks"));
        qmlRegisterType<UnifiedTasksModel>(uri, 1, 0, "UnifiedTasksModel");
    }
};

#include "plugin.moc"
