/*
    SPDX-FileCopyrightText: 2026 kilo
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QAbstractListModel>
#include <QHash>
#include <QPersistentModelIndex>
#include <QPointer>
#include <QString>
#include <QStringList>
#include <QUrl>
#include <QVector>

/*
 * Single-list model combining manual slots and unpinned running tasks (strays).
 *
 * Items intermix by user-controlled order, so pinning a running window is a
 * Stray -> Slot conversion IN PLACE (position preserved), and drag-reorder works
 * uniformly across both kinds.
 *
 * Bound slots forward role reads to the source tasksModel (QIcon etc. survive
 * natively). Empty slots synthesize launcher-like role values. Strays also
 * forward to source.
 */
class UnifiedTasksModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(QAbstractItemModel *sourceModel READ sourceModel WRITE setSourceModel NOTIFY sourceModelChanged)
    Q_PROPERTY(QStringList slotsConfig READ slotsConfig WRITE setSlotsConfig NOTIFY slotsConfigChanged)

public:
    enum ExtraRole {
        SlotIdxRole = Qt::UserRole + 20000,   // slot index in the SLOTS-ONLY enumeration (-1 for strays)
        TaskIdxRole,                          // source row index, or -1 for empty slot
        IsEmptySlotRole,                      // true if slot exists but has no live bound task
        SlotLauncherUrlRole,
        SlotAppIdRole,
        SlotBgColorRole,                      // per-slot background tint "#aarrggbb" (empty = none)
        SlotBarColorRole,                     // per-slot top-bar colour override "#rrggbb" (empty = use global)
    };
    Q_ENUM(ExtraRole)

    explicit UnifiedTasksModel(QObject *parent = nullptr);
    ~UnifiedTasksModel() override;

    QAbstractItemModel *sourceModel() const;
    void setSourceModel(QAbstractItemModel *model);

    QStringList slotsConfig() const;
    void setSlotsConfig(const QStringList &json);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    // Source row lookup for stock tasksModel.requestXxx() callsites in QML.
    Q_INVOKABLE QModelIndex sourceIndex(int unifiedRow, int child = -1) const;

    // Slot ops (unifiedRow is the visible row in this model).
    Q_INVOKABLE void addSlotFromSourceRow(int sourceRow);
    Q_INVOKABLE void addSlot(const QString &launcherUrl, const QString &iconName,
                             const QString &appId, const QString &appName);
    Q_INVOKABLE void removeSlotAt(int unifiedRow);
    Q_INVOKABLE void duplicateSlotAt(int unifiedRow);
    Q_INVOKABLE void activateOrSpawnSlotAt(int unifiedRow);

    // Per-slot command override. Empty string means "use the .desktop file's Exec".
    Q_INVOKABLE QString slotCommandAt(int unifiedRow) const;
    Q_INVOKABLE void setSlotCommandAt(int unifiedRow, const QString &command);
    Q_INVOKABLE QString defaultCommandForAppId(const QString &appId) const;

    // Per-slot background tint ("#aarrggbb"; empty string = no tint).
    Q_INVOKABLE QString slotBgColorAt(int unifiedRow) const;
    Q_INVOKABLE void setSlotBgColorAt(int unifiedRow, const QString &color);

    // Per-slot top-bar (stateBar) colour override ("#rrggbb"; empty string = default).
    Q_INVOKABLE QString slotBarColorAt(int unifiedRow) const;
    Q_INVOKABLE void setSlotBarColorAt(int unifiedRow, const QString &color);

    // Drag reorder: move item [from] to [to] within this model's order.
    Q_INVOKABLE bool moveItem(int from, int to);

    // Drop-to-bind: drag a stray onto a matching empty slot. The slot takes over the
    // stray's running task (boundTask = stray.strayTask) and the stray row is removed.
    Q_INVOKABLE bool bindStrayToSlot(int slotRow, int strayRow);

Q_SIGNALS:
    void sourceModelChanged();
    void slotsConfigChanged();

private Q_SLOTS:
    void onSourceRowsInserted(const QModelIndex &parent, int first, int last);
    void onSourceRowsRemoved(const QModelIndex &parent, int first, int last);
    void onSourceRowsMoved(const QModelIndex &parent, int start, int end,
                           const QModelIndex &destination, int row);
    void onSourceDataChanged(const QModelIndex &topLeft, const QModelIndex &bottomRight,
                             const QVector<int> &roles);
    void onSourceModelReset();
    void onSourceLayoutChanged();
    void reconcileStrays();

private:
    enum class Kind { Slot, Stray };

    struct Item {
        Kind kind = Kind::Stray;

        // Slot fields (valid only when kind == Slot):
        QString launcherUrl;
        QString iconName;
        QString appId;
        QString appName;
        QString customCommand;               // empty = use .desktop Exec
        QString bgColor;                     // "#aarrggbb" or empty
        QString barColor;                    // "#rrggbb" override for the top stateBar, empty = default
        QPersistentModelIndex boundTask;     // invalid means empty slot

        // Stray field (valid only when kind == Stray):
        QPersistentModelIndex strayTask;     // points to sourceModel row
    };

    struct PendingSpawn {
        int unifiedRow;     // row of the slot that spawned
        qint64 pid;         // child PID captured at spawn time; primary match key
        QString appId;      // fallback match for apps that daemonize (Firefox etc.)
        qint64 ts;          // enqueue epoch (ms) for TTL
    };

    void connectSource();
    void disconnectSource();
    QString appIdFromSource(const QModelIndex &si) const;
    QString iconNameFromSource(const QModelIndex &si) const;
    bool shouldTrackSource(const QModelIndex &si) const;
    int findStrayRow(const QModelIndex &sourceIdx) const;           // unified row holding this source row as stray
    int findBoundSlot(const QModelIndex &sourceIdx) const;          // unified row holding this source row as bound slot
    void tryBindPendingSpawns(int first, int last);
    void expirePendingSpawns();

    QPointer<QAbstractItemModel> m_source;
    QVector<Item> m_items;
    QVector<PendingSpawn> m_pending;

    QHash<QByteArray, int> m_sourceRoleByName;
    mutable QHash<int, QByteArray> m_roleNames;
};
