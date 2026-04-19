/*
    SPDX-FileCopyrightText: 2026 kilo
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "unifiedtasksmodel.h"

#include <QByteArray>
#include <QDateTime>
#include <QDebug>
#include <QDesktopServices>
#include <QIcon>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QRegularExpression>
#include <QUrl>
#include <QVariant>

#include <KService>

#include <algorithm>

static constexpr qint64 PENDING_SPAWN_TTL_MS = 30000;

UnifiedTasksModel::UnifiedTasksModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

UnifiedTasksModel::~UnifiedTasksModel() = default;

QAbstractItemModel *UnifiedTasksModel::sourceModel() const
{
    return m_source.data();
}

void UnifiedTasksModel::setSourceModel(QAbstractItemModel *model)
{
    if (m_source.data() == model) return;

    beginResetModel();
    disconnectSource();
    m_source = model;
    m_sourceRoleByName.clear();
    m_roleNames.clear();

    // Remove all strays; slots stay but drop bound tasks.
    m_items.erase(std::remove_if(m_items.begin(), m_items.end(),
                                 [](const Item &it) { return it.kind == Kind::Stray; }),
                  m_items.end());
    for (auto &it : m_items) {
        if (it.kind == Kind::Slot) it.boundTask = QPersistentModelIndex();
    }

    if (m_source) {
        const QHash<int, QByteArray> names = m_source->roleNames();
        for (auto it = names.cbegin(); it != names.cend(); ++it) {
            m_sourceRoleByName.insert(it.value(), it.key());
        }
        connectSource();

        // Seed strays for every existing source row we want to track.
        const int n = m_source->rowCount();
        for (int r = 0; r < n; ++r) {
            const QModelIndex si = m_source->index(r, 0);
            if (!shouldTrackSource(si)) continue;
            Item it;
            it.kind = Kind::Stray;
            it.strayTask = QPersistentModelIndex(si);
            m_items.append(it);
        }
    }

    endResetModel();
    Q_EMIT sourceModelChanged();
}

void UnifiedTasksModel::connectSource()
{
    if (!m_source) return;
    connect(m_source.data(), &QAbstractItemModel::rowsInserted,
            this, &UnifiedTasksModel::onSourceRowsInserted);
    connect(m_source.data(), &QAbstractItemModel::rowsRemoved,
            this, &UnifiedTasksModel::onSourceRowsRemoved);
    connect(m_source.data(), &QAbstractItemModel::rowsMoved,
            this, &UnifiedTasksModel::onSourceRowsMoved);
    connect(m_source.data(), &QAbstractItemModel::dataChanged,
            this, &UnifiedTasksModel::onSourceDataChanged);
    connect(m_source.data(), &QAbstractItemModel::modelReset,
            this, &UnifiedTasksModel::onSourceModelReset);
    // QSortFilterProxyModel (used by TasksModel internally) emits layoutChanged
    // on invalidateFilter(), not rowsInserted/Removed. Handle it to re-seed strays.
    connect(m_source.data(), &QAbstractItemModel::layoutChanged,
            this, &UnifiedTasksModel::onSourceLayoutChanged);
}

void UnifiedTasksModel::disconnectSource()
{
    if (!m_source) return;
    disconnect(m_source.data(), nullptr, this, nullptr);
}

QStringList UnifiedTasksModel::slotsConfig() const
{
    QStringList out;
    for (const auto &it : m_items) {
        if (it.kind != Kind::Slot) continue;
        QJsonObject obj;
        obj.insert(QStringLiteral("u"), it.launcherUrl);
        obj.insert(QStringLiteral("i"), it.iconName);
        obj.insert(QStringLiteral("a"), it.appId);
        obj.insert(QStringLiteral("n"), it.appName);
        if (!it.customCommand.isEmpty()) {
            obj.insert(QStringLiteral("c"), it.customCommand);
        }
        if (!it.bgColor.isEmpty()) {
            obj.insert(QStringLiteral("b"), it.bgColor);
        }
        if (!it.barColor.isEmpty()) {
            obj.insert(QStringLiteral("r"), it.barColor);
        }
        // Persist the unified row index of the slot so ordering (slots+strays) can be
        // approximately restored; strays are ephemeral so we only anchor on slot order.
        out.append(QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact)));
    }
    return out;
}

void UnifiedTasksModel::setSlotsConfig(const QStringList &json)
{
    beginResetModel();

    // Strays survive. Wipe slots, then rebuild from config.
    m_items.erase(std::remove_if(m_items.begin(), m_items.end(),
                                 [](const Item &it) { return it.kind == Kind::Slot; }),
                  m_items.end());

    QVector<Item> slots;
    for (const QString &entry : json) {
        const QJsonDocument doc = QJsonDocument::fromJson(entry.toUtf8());
        if (!doc.isObject()) continue;
        const QJsonObject obj = doc.object();
        Item it;
        it.kind = Kind::Slot;
        it.launcherUrl = obj.value(QStringLiteral("u")).toString();
        it.iconName = obj.value(QStringLiteral("i")).toString();
        it.appId = obj.value(QStringLiteral("a")).toString();
        it.appName = obj.value(QStringLiteral("n")).toString();
        it.customCommand = obj.value(QStringLiteral("c")).toString();
        it.bgColor = obj.value(QStringLiteral("b")).toString();
        it.barColor = obj.value(QStringLiteral("r")).toString();
        if (it.appId.isEmpty() && !it.launcherUrl.isEmpty()) {
            const QRegularExpression re(QStringLiteral("applications:(.+?)(?:\\.desktop)?$"));
            const auto m = re.match(it.launcherUrl);
            if (m.hasMatch()) it.appId = m.captured(1);
        }
        // Reject entries with no AppId: nothing to spawn, nothing to bind against; these
        // are usually stale legacy migrations (e.g. preferred://browser) that render
        // as ghost icons with spurious audio overlays. Dropping them auto-persists
        // a cleaned config via slotsConfigChanged below.
        if (it.appId.isEmpty()) {
            qDebug() << "kilotasks: dropping invalid slot (no appId) url=" << it.launcherUrl;
            continue;
        }
        slots.append(it);
    }

    m_items = slots + m_items;

    endResetModel();
    Q_EMIT slotsConfigChanged();
}

int UnifiedTasksModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_items.size();
}

QModelIndex UnifiedTasksModel::sourceIndex(int unifiedRow, int child) const
{
    if (!m_source) return {};
    if (unifiedRow < 0 || unifiedRow >= m_items.size()) return {};

    const Item &it = m_items[unifiedRow];
    QModelIndex base;
    if (it.kind == Kind::Slot) {
        if (!it.boundTask.isValid()) return {};
        base = QModelIndex(it.boundTask);
    } else {
        if (!it.strayTask.isValid()) return {};
        base = QModelIndex(it.strayTask);
    }
    if (child < 0) return base;
    return m_source->index(child, 0, base);
}

QVariant UnifiedTasksModel::data(const QModelIndex &idx, int role) const
{
    if (!idx.isValid() || idx.row() < 0 || idx.row() >= m_items.size()) return {};

    const int row = idx.row();
    const Item &it = m_items[row];
    const bool isSlot = it.kind == Kind::Slot;
    const bool isEmpty = isSlot && !it.boundTask.isValid();

    // Extra roles first.
    switch (role) {
    case SlotIdxRole:
        return isSlot ? row : -1;
    case TaskIdxRole: {
        const QModelIndex si = sourceIndex(row);
        return si.isValid() ? si.row() : -1;
    }
    case IsEmptySlotRole:
        return isEmpty;
    case SlotLauncherUrlRole:
        return isSlot ? it.launcherUrl : QString();
    case SlotAppIdRole:
        return isSlot ? it.appId : QString();
    case SlotBgColorRole:
        return isSlot ? it.bgColor : QString();
    case SlotBarColorRole:
        return isSlot ? it.barColor : QString();
    default:
        break;
    }

    // Bound slot or stray → forward to source.
    const QModelIndex si = sourceIndex(row);
    if (si.isValid() && m_source) {
        return m_source->data(si, role);
    }

    // Empty slot — synthesize launcher-like data.
    if (!isSlot) return {};

    const QByteArray roleName = m_sourceRoleByName.key(role);

    const auto iconFallback = [&]() -> QVariant {
        if (!it.iconName.isEmpty()) return it.iconName;
        if (!it.appId.isEmpty()) return it.appId;
        return QStringLiteral("application-x-executable");
    };
    const auto displayFallback = [&]() -> QVariant {
        if (!it.appName.isEmpty()) return it.appName;
        if (!it.appId.isEmpty()) return it.appId;
        return QString();
    };

    if (role == Qt::DecorationRole) return iconFallback();
    if (role == Qt::DisplayRole) return displayFallback();

    if (roleName == QByteArrayLiteral("decoration")) return iconFallback();
    if (roleName == QByteArrayLiteral("display")) return displayFallback();
    if (roleName == QByteArrayLiteral("AppId"))
        return QVariant(it.appId + QLatin1String(".desktop"));
    if (roleName == QByteArrayLiteral("AppName"))
        return it.appName.isEmpty() ? it.appId : it.appName;
    if (roleName == QByteArrayLiteral("AppPid")) return 0;
    if (roleName == QByteArrayLiteral("LauncherUrl")) return QUrl(it.launcherUrl);
    if (roleName == QByteArrayLiteral("LauncherUrlWithoutIcon")) return QUrl(it.launcherUrl);
    if (roleName == QByteArrayLiteral("GenericName")) return QString();
    if (roleName == QByteArrayLiteral("MimeType")) return QString();
    if (roleName == QByteArrayLiteral("MimeData")) return QByteArray();
    if (roleName == QByteArrayLiteral("StackingOrder")) return 0;
    if (roleName == QByteArrayLiteral("LastActivated")) return 0;
    if (roleName == QByteArrayLiteral("ApplicationMenuServiceName")) return QString();
    if (roleName == QByteArrayLiteral("ApplicationMenuObjectPath")) return QString();
    if (roleName == QByteArrayLiteral("IsWindow")) return false;
    if (roleName == QByteArrayLiteral("IsLauncher")) return true;
    if (roleName == QByteArrayLiteral("IsStartup")) return false;
    if (roleName == QByteArrayLiteral("IsActive")) return false;
    if (roleName == QByteArrayLiteral("IsMinimized")) return false;
    if (roleName == QByteArrayLiteral("IsGroupParent")) return false;
    if (roleName == QByteArrayLiteral("HasLauncher")) return true;
    if (roleName == QByteArrayLiteral("ChildCount")) return 0;
    if (roleName == QByteArrayLiteral("WinIdList")) return QVariantList();
    if (roleName == QByteArrayLiteral("VirtualDesktops")) return QVariantList();
    if (roleName == QByteArrayLiteral("IsOnAllVirtualDesktops")) return true;
    if (roleName == QByteArrayLiteral("Activities")) return QVariantList();
    if (roleName == QByteArrayLiteral("SkipTaskbar")) return false;
    if (roleName == QByteArrayLiteral("IsDemandingAttention")) return false;
    if (roleName == QByteArrayLiteral("CanLaunchNewInstance")) return true;
    if (roleName == QByteArrayLiteral("IsClosable")) return false;
    if (roleName == QByteArrayLiteral("IsMovable")) return false;
    if (roleName == QByteArrayLiteral("IsResizable")) return false;
    if (roleName == QByteArrayLiteral("IsMaximizable")) return false;
    if (roleName == QByteArrayLiteral("IsMaximized")) return false;
    if (roleName == QByteArrayLiteral("IsMinimizable")) return false;
    if (roleName == QByteArrayLiteral("IsKeepAbove")) return false;
    if (roleName == QByteArrayLiteral("IsKeepBelow")) return false;
    if (roleName == QByteArrayLiteral("IsFullScreenable")) return false;
    if (roleName == QByteArrayLiteral("IsFullScreen")) return false;
    if (roleName == QByteArrayLiteral("IsShadeable")) return false;
    if (roleName == QByteArrayLiteral("IsShaded")) return false;
    if (roleName == QByteArrayLiteral("IsHidden")) return false;
    if (roleName == QByteArrayLiteral("HasNoBorder")) return false;
    if (roleName == QByteArrayLiteral("CanSetNoBorder")) return false;
    if (roleName == QByteArrayLiteral("IsVirtualDesktopsChangeable")) return false;
    if (roleName == QByteArrayLiteral("IsGroupable")) return false;

    return {};
}

QHash<int, QByteArray> UnifiedTasksModel::roleNames() const
{
    if (!m_roleNames.isEmpty()) return m_roleNames;

    QHash<int, QByteArray> h;
    if (m_source) {
        h = m_source->roleNames();
    } else {
        h.insert(Qt::DisplayRole, QByteArrayLiteral("display"));
        h.insert(Qt::DecorationRole, QByteArrayLiteral("decoration"));
    }
    h.insert(SlotIdxRole, QByteArrayLiteral("slotIdx"));
    h.insert(TaskIdxRole, QByteArrayLiteral("taskIdx"));
    h.insert(IsEmptySlotRole, QByteArrayLiteral("isEmptySlot"));
    h.insert(SlotLauncherUrlRole, QByteArrayLiteral("slotLauncherUrl"));
    h.insert(SlotAppIdRole, QByteArrayLiteral("slotAppId"));
    h.insert(SlotBgColorRole, QByteArrayLiteral("slotBgColor"));
    h.insert(SlotBarColorRole, QByteArrayLiteral("slotBarColor"));
    m_roleNames = h;
    return h;
}

QString UnifiedTasksModel::appIdFromSource(const QModelIndex &si) const
{
    if (!m_source || !si.isValid()) return {};
    const int roleId = m_sourceRoleByName.value(QByteArrayLiteral("AppId"), -1);
    if (roleId < 0) return {};
    QString s = m_source->data(si, roleId).toString();
    if (s.endsWith(QLatin1String(".desktop"))) s.chop(QLatin1String(".desktop").size());
    return s;
}

// Filter out phantom rows. Requires, cumulatively:
//   - Not SkipTaskbar (canonical "don't show in taskbar" flag)
//   - Non-empty AppId
//   - At least one WinId (prevents lingering startup rows and helper processes)
//   - Renderable decoration (non-null QIcon OR non-empty string name)
// IsHidden is intentionally NOT filtered: on X11 Plasma sets NET_WM_STATE_HIDDEN
// for minimized windows, so keying on it would hide minimized strays. SkipTaskbar
// already covers windows that explicitly opt out of the taskbar.
bool UnifiedTasksModel::shouldTrackSource(const QModelIndex &si) const
{
    if (!m_source || !si.isValid()) return false;

    const int skipRole = m_sourceRoleByName.value(QByteArrayLiteral("SkipTaskbar"), -1);
    if (skipRole >= 0 && m_source->data(si, skipRole).toBool()) return false;

    if (appIdFromSource(si).isEmpty()) return false;

    const int winIdRole = m_sourceRoleByName.value(QByteArrayLiteral("WinIdList"), -1);
    if (winIdRole >= 0) {
        const QVariantList wids = m_source->data(si, winIdRole).toList();
        if (wids.isEmpty()) return false;
    }

    const QVariant dec = m_source->data(si, Qt::DecorationRole);
    if (!dec.isValid()) return false;
    if (dec.canConvert<QIcon>()) {
        const QIcon ic = dec.value<QIcon>();
        return !ic.isNull() || !ic.name().isEmpty();
    }
    if (dec.canConvert<QString>()) return !dec.toString().isEmpty();
    return false;
}

QString UnifiedTasksModel::iconNameFromSource(const QModelIndex &si) const
{
    if (!m_source || !si.isValid()) return {};
    const QVariant v = m_source->data(si, Qt::DecorationRole);
    if (v.canConvert<QIcon>()) {
        const QIcon icon = v.value<QIcon>();
        const QString name = icon.name();
        if (!name.isEmpty()) return name;
    }
    return {};
}

int UnifiedTasksModel::findStrayRow(const QModelIndex &sourceIdx) const
{
    if (!sourceIdx.isValid()) return -1;
    for (int i = 0; i < m_items.size(); ++i) {
        if (m_items[i].kind == Kind::Stray && m_items[i].strayTask == sourceIdx) return i;
    }
    return -1;
}

int UnifiedTasksModel::findBoundSlot(const QModelIndex &sourceIdx) const
{
    if (!sourceIdx.isValid()) return -1;
    for (int i = 0; i < m_items.size(); ++i) {
        if (m_items[i].kind == Kind::Slot && m_items[i].boundTask == sourceIdx) return i;
    }
    return -1;
}

// Pick the first empty slot whose identity matches (appId + launcherUrl). Used by
// the pending-spawn binder so row shifts (moveItem, reconcileStrays, duplicate,
// unbind) between the spawn click and the window's arrival are transparent: the
// binder does not hold a raw m_items index — it holds the slot's logical key.
//
// `hintRow` is a NON-AUTHORITATIVE preference: when the user has multiple empty
// slots of the same app (duplicates), the hint keeps the bind on the slot the
// user actually clicked instead of always landing on the first one in order.
// The hint is only honoured when it still points to a valid empty slot with
// matching identity — otherwise we transparently fall back to first-matching.
int UnifiedTasksModel::findEmptySlotMatching(const QString &appId, const QString &launcherUrl, int hintRow) const
{
    if (appId.isEmpty()) return -1;

    auto slotMatches = [&](int i) {
        if (i < 0 || i >= m_items.size()) return false;
        const Item &it = m_items[i];
        if (it.kind != Kind::Slot) return false;
        if (it.boundTask.isValid()) return false;
        if (it.appId != appId) return false;
        if (!launcherUrl.isEmpty() && !it.launcherUrl.isEmpty()
            && it.launcherUrl != launcherUrl) return false;
        return true;
    };

    if (hintRow >= 0 && slotMatches(hintRow)) return hintRow;
    for (int i = 0; i < m_items.size(); ++i) {
        if (slotMatches(i)) return i;
    }
    return -1;
}

void UnifiedTasksModel::expirePendingSpawns()
{
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    auto it = std::remove_if(m_pending.begin(), m_pending.end(),
                             [now](const PendingSpawn &p) { return now - p.ts > PENDING_SPAWN_TTL_MS; });
    m_pending.erase(it, m_pending.end());
}

void UnifiedTasksModel::tryBindPendingSpawns(int first, int last)
{
    if (m_pending.isEmpty() || !m_source) return;
    expirePendingSpawns();
    const int pidRole = m_sourceRoleByName.value(QByteArrayLiteral("AppPid"), -1);
    const qint64 now = QDateTime::currentMSecsSinceEpoch();

    auto applyBind = [&](int pendingIdx, const QModelIndex &si) {
        const QString pendAppId   = m_pending[pendingIdx].appId;
        const QString pendLauncher = m_pending[pendingIdx].slotLauncherUrl;
        const int     pendHint     = m_pending[pendingIdx].hintRow;
        m_pending.remove(pendingIdx);

        // Late lookup of the target slot. Survives any number of
        // moveItem/removeSlotAt/duplicateSlotAt calls between click and bind.
        // The hint is the original click row — honoured if still valid.
        const int unifiedRow = findEmptySlotMatching(pendAppId, pendLauncher, pendHint);
        if (unifiedRow < 0) return; // no matching empty slot left — window becomes a stray via the regular insert path

        Item &it = m_items[unifiedRow];
        it.boundTask = QPersistentModelIndex(si);
        const QModelIndex i = index(unifiedRow);
        Q_EMIT dataChanged(i, i);
        if (it.iconName.isEmpty()) {
            const QString name = iconNameFromSource(si);
            if (!name.isEmpty()) {
                it.iconName = name;
                Q_EMIT slotsConfigChanged();
            }
        }
    };

    for (int r = first; r <= last; ++r) {
        const QModelIndex si = m_source->index(r, 0);
        if (!si.isValid()) continue;

        // Skip source rows we already own as stray or bound slot: a late-arriving
        // layoutChanged-driven rebind must not re-bind a row that's already tracked.
        if (findStrayRow(si) >= 0) continue;
        if (findBoundSlot(si) >= 0) continue;

        const qint64 windowPid = (pidRole >= 0) ? m_source->data(si, pidRole).toLongLong() : 0;
        const QString windowAppId = appIdFromSource(si);

        int matchIdx = -1;

        // Pass 1: exact PID match (authoritative for simple apps).
        if (windowPid > 0) {
            for (int p = 0; p < m_pending.size(); ++p) {
                if (m_pending[p].pid == windowPid) { matchIdx = p; break; }
            }
        }

        // Pass 2: AppId match within a tight TTL (covers double-fork / daemonizing apps
        // like Firefox/Thunderbird/VSCode whose window PID differs from the spawned PID).
        // Limited to 10s so that external launches well after the click are treated as strays.
        if (matchIdx < 0 && !windowAppId.isEmpty()) {
            for (int p = 0; p < m_pending.size(); ++p) {
                if (m_pending[p].appId == windowAppId && now - m_pending[p].ts <= 10000) {
                    matchIdx = p;
                    break;
                }
            }
        }

        if (matchIdx >= 0) applyBind(matchIdx, si);
    }
}

// Parse a raw Exec-style command line (with Desktop Entry field codes stripped) and
// spawn it detached via QProcess, capturing the child PID. Returns 0 on failure.
static qint64 spawnCommandPid(const QString &cmdLine)
{
    if (cmdLine.trimmed().isEmpty()) return 0;

    QString clean = cmdLine;
    static const QRegularExpression re(QStringLiteral("%[uUfFckiv]"));
    clean.replace(re, QString());
    clean.replace(QLatin1String("%%"), QLatin1String("%"));
    clean = clean.simplified();
    if (clean.isEmpty()) return 0;

    const QStringList parts = QProcess::splitCommand(clean);
    if (parts.isEmpty()) return 0;

    qint64 pid = 0;
    if (!QProcess::startDetached(parts.first(), parts.mid(1), QString(), &pid)) return 0;
    return pid;
}

// Resolve the .desktop Exec line for an appId, with or without the .desktop suffix.
static QString execLineForAppId(const QString &appId)
{
    if (appId.isEmpty()) return {};

    QString storageId = appId;
    if (!storageId.endsWith(QLatin1String(".desktop"))) storageId += QLatin1String(".desktop");

    KService::Ptr service = KService::serviceByStorageId(storageId);
    if (!service) {
        QString bare = appId;
        if (bare.endsWith(QLatin1String(".desktop"))) bare.chop(8);
        service = KService::serviceByDesktopName(bare);
    }
    return service ? service->exec() : QString();
}

// Resolve a .desktop service and spawn it via QProcess to capture the child PID,
// which is the authoritative reservation key for slot binding. Returns 0 on failure.
static qint64 spawnServicePid(const QString &appId)
{
    return spawnCommandPid(execLineForAppId(appId));
}

void UnifiedTasksModel::onSourceRowsInserted(const QModelIndex &parent, int first, int last)
{
    Q_UNUSED(parent);
    if (!m_source) return;

    // First, attempt to bind pending spawns on the new source rows.
    tryBindPendingSpawns(first, last);

    // Collect newly-trackable rows and append them as strays in a single batched insertion.
    QVector<Item> pending;
    for (int r = first; r <= last; ++r) {
        const QModelIndex si = m_source->index(r, 0);
        if (!si.isValid()) continue;
        if (!shouldTrackSource(si)) continue;
        if (findStrayRow(si) >= 0 || findBoundSlot(si) >= 0) continue;
        Item it;
        it.kind = Kind::Stray;
        it.strayTask = QPersistentModelIndex(si);
        pending.append(it);
    }
    if (!pending.isEmpty()) {
        const int insertAt = m_items.size();
        beginInsertRows(QModelIndex(), insertAt, insertAt + pending.size() - 1);
        m_items.append(pending);
        endInsertRows();
    }

    // Source insertion before the row of any existing persistent index shifts
    // that index by +1. Notify all surviving items so their cached TaskIdxRole
    // value refreshes in QML (symmetrical with onSourceRowsRemoved).
    if (!m_items.isEmpty()) {
        Q_EMIT dataChanged(index(0), index(m_items.size() - 1),
                           QVector<int>{TaskIdxRole});
    }
}

void UnifiedTasksModel::onSourceRowsRemoved(const QModelIndex &parent, int first, int last)
{
    Q_UNUSED(parent);
    Q_UNUSED(first);
    Q_UNUSED(last);
    // Any stray whose persistent index became invalid should be removed from our list.
    // Bound slots with invalidated indices become empty slots (visible, no task).
    for (int i = m_items.size() - 1; i >= 0; --i) {
        Item &it = m_items[i];
        if (it.kind == Kind::Stray && !it.strayTask.isValid()) {
            beginRemoveRows(QModelIndex(), i, i);
            m_items.remove(i);
            endRemoveRows();
        } else if (it.kind == Kind::Slot && !it.boundTask.isValid()) {
            const QModelIndex idx = index(i);
            Q_EMIT dataChanged(idx, idx);
        }
    }

    // Row removal in the source model shifts the row() of every persistent index
    // that was positioned AFTER the removed range. QPersistentModelIndex tracks
    // this internally, but our forwarded TaskIdxRole reads are cached by QML
    // delegates — if we don't announce the change, a click on a surviving slot
    // still hits the stale source-row index (or a vanished one), and the
    // activation request targets nothing. Re-emit for every remaining item so
    // the delegate refreshes its `taskIdx` before the next user interaction.
    if (!m_items.isEmpty()) {
        Q_EMIT dataChanged(index(0), index(m_items.size() - 1),
                           QVector<int>{TaskIdxRole});
    }
}

void UnifiedTasksModel::onSourceRowsMoved(const QModelIndex &parent, int start, int end,
                                          const QModelIndex &destination, int row)
{
    Q_UNUSED(parent);
    Q_UNUSED(start);
    Q_UNUSED(end);
    Q_UNUSED(destination);
    Q_UNUSED(row);
    // Persistent indices follow moves automatically. Data values may change; re-emit dataChanged.
    if (m_items.isEmpty()) return;
    Q_EMIT dataChanged(index(0), index(m_items.size() - 1));
}

void UnifiedTasksModel::onSourceDataChanged(const QModelIndex &topLeft, const QModelIndex &bottomRight,
                                            const QVector<int> &roles)
{
    // Split into two passes:
    //   Pass 1 (safe): emit our own dataChanged for rows where tracking state doesn't change.
    //   Pass 2 (structural): any row where the filter result flipped needs add/remove — not
    //   legal to do inside a source dataChanged handler, so we defer to the next tick.
    bool needsReconcile = false;

    for (int r = topLeft.row(); r <= bottomRight.row(); ++r) {
        const QModelIndex si = m_source ? m_source->index(r, 0) : QModelIndex();
        if (!si.isValid()) continue;

        const int boundRow = findBoundSlot(si);
        const int strayRow = findStrayRow(si);
        const bool shouldTrack = shouldTrackSource(si);

        if (boundRow >= 0) {
            const QModelIndex i = index(boundRow);
            Q_EMIT dataChanged(i, i, roles);
            continue;
        }

        if (strayRow >= 0) {
            if (shouldTrack) {
                const QModelIndex i = index(strayRow);
                Q_EMIT dataChanged(i, i, roles);
            } else {
                needsReconcile = true; // structural removal — defer
            }
            continue;
        }

        if (shouldTrack) {
            needsReconcile = true; // structural insertion — defer
        }
    }

    if (needsReconcile) {
        QMetaObject::invokeMethod(this, "reconcileStrays", Qt::QueuedConnection);
    }
}

void UnifiedTasksModel::onSourceModelReset()
{
    beginResetModel();
    // Drop all strays; slots stay (bound references become invalid automatically).
    m_items.erase(std::remove_if(m_items.begin(), m_items.end(),
                                 [](const Item &it) { return it.kind == Kind::Stray; }),
                  m_items.end());
    // Re-seed strays for whatever the source currently exposes (filtered).
    if (m_source) {
        const int n = m_source->rowCount();
        for (int r = 0; r < n; ++r) {
            const QModelIndex si = m_source->index(r, 0);
            if (!shouldTrackSource(si)) continue;
            Item it;
            it.kind = Kind::Stray;
            it.strayTask = QPersistentModelIndex(si);
            m_items.append(it);
        }
    }
    endResetModel();
}

void UnifiedTasksModel::onSourceLayoutChanged()
{
    // Qt's model/view contract forbids mutating row count inside a layoutChanged
    // handler. Defer the reconcile to the next event-loop tick via QueuedConnection.
    QMetaObject::invokeMethod(this, "reconcileStrays", Qt::QueuedConnection);
}

// Bring m_items into sync with the current source rows without a full reset.
// Removes strays whose persistent index went invalid and appends strays for any
// source row not already tracked as stray or bound slot. Preserves delegate state.
void UnifiedTasksModel::reconcileStrays()
{
    if (!m_source) return;

    // Drop strays whose source row was filtered out or removed.
    for (int i = m_items.size() - 1; i >= 0; --i) {
        if (m_items[i].kind == Kind::Stray && !m_items[i].strayTask.isValid()) {
            beginRemoveRows(QModelIndex(), i, i);
            m_items.remove(i);
            endRemoveRows();
        }
    }

    const int n = m_source->rowCount();

    // Retry pending-spawn binding across the whole visible source range BEFORE
    // appending strays. Plasma's TasksModel emits layoutChanged on filter
    // reshuffles (screen, virtual-desktop, activity); rows that were filtered
    // out when the user clicked Spawn can reappear here, and we want them to
    // bind to the click's pending slot instead of becoming a fresh stray.
    if (!m_pending.isEmpty() && n > 0) {
        tryBindPendingSpawns(0, n - 1);
    }

    // Add strays for source rows not yet covered by any item.
    for (int r = 0; r < n; ++r) {
        const QModelIndex si = m_source->index(r, 0);
        if (!si.isValid()) continue;
        if (!shouldTrackSource(si)) continue;
        if (findStrayRow(si) >= 0 || findBoundSlot(si) >= 0) continue;
        const int insertAt = m_items.size();
        beginInsertRows(QModelIndex(), insertAt, insertAt);
        Item it;
        it.kind = Kind::Stray;
        it.strayTask = QPersistentModelIndex(si);
        m_items.append(it);
        endInsertRows();
    }

    // Refresh role values (filter changes may flip things like IsActive,
    // TaskIdxRole after QPersistentModelIndex shifts, etc.).
    if (!m_items.isEmpty()) {
        Q_EMIT dataChanged(index(0), index(m_items.size() - 1));
    }
}

void UnifiedTasksModel::addSlotFromSourceRow(int sourceRow)
{
    if (!m_source) return;
    if (sourceRow < 0 || sourceRow >= m_source->rowCount()) return;

    const QModelIndex si = m_source->index(sourceRow, 0);
    if (!si.isValid()) return;

    const int strayRow = findStrayRow(si);
    const QString appId = appIdFromSource(si);
    const int urlRole = m_sourceRoleByName.value(QByteArrayLiteral("LauncherUrlWithoutIcon"), -1);
    const int nameRole = m_sourceRoleByName.value(QByteArrayLiteral("AppName"), -1);
    const QString url = urlRole >= 0 ? m_source->data(si, urlRole).toUrl().toString() : QString();
    const QString name = nameRole >= 0 ? m_source->data(si, nameRole).toString() : QString();
    const QString icon = iconNameFromSource(si);

    if (url.isEmpty() && appId.isEmpty()) return;

    if (strayRow >= 0) {
        // Convert Stray -> Slot in place. Position preserved.
        Item &it = m_items[strayRow];
        it.kind = Kind::Slot;
        it.launcherUrl = url;
        it.iconName = icon.isEmpty() ? appId : icon;
        it.appId = appId;
        it.appName = name;
        it.boundTask = QPersistentModelIndex(si);
        it.strayTask = QPersistentModelIndex();
        const QModelIndex idx = index(strayRow);
        Q_EMIT dataChanged(idx, idx);
        Q_EMIT slotsConfigChanged();
        return;
    }

    // No matching stray (rare): append new bound slot.
    const int insertAt = m_items.size();
    beginInsertRows(QModelIndex(), insertAt, insertAt);
    Item it;
    it.kind = Kind::Slot;
    it.launcherUrl = url;
    it.iconName = icon.isEmpty() ? appId : icon;
    it.appId = appId;
    it.appName = name;
    it.boundTask = QPersistentModelIndex(si);
    m_items.append(it);
    endInsertRows();
    Q_EMIT slotsConfigChanged();
}

void UnifiedTasksModel::addSlot(const QString &launcherUrl, const QString &iconName,
                                const QString &appId, const QString &appName)
{
    Item it;
    it.kind = Kind::Slot;
    it.launcherUrl = launcherUrl;
    it.iconName = iconName;
    it.appId = appId;
    if (it.appId.isEmpty() && !launcherUrl.isEmpty()) {
        const QRegularExpression re(QStringLiteral("applications:(.+?)(?:\\.desktop)?$"));
        const auto m = re.match(launcherUrl);
        if (m.hasMatch()) it.appId = m.captured(1);
    }
    it.appName = appName;

    if (it.appId.isEmpty()) {
        qDebug() << "kilotasks: refusing to add slot with no appId, url=" << launcherUrl;
        return;
    }

    const int insertAt = m_items.size();
    beginInsertRows(QModelIndex(), insertAt, insertAt);
    m_items.append(it);
    endInsertRows();
    Q_EMIT slotsConfigChanged();
}

void UnifiedTasksModel::removeSlotAt(int unifiedRow)
{
    if (unifiedRow < 0 || unifiedRow >= m_items.size()) return;
    if (m_items[unifiedRow].kind != Kind::Slot) return;

    // If the slot has a bound task, convert it back to a Stray so the window stays visible.
    if (m_items[unifiedRow].boundTask.isValid()) {
        Item &it = m_items[unifiedRow];
        it.kind = Kind::Stray;
        it.strayTask = it.boundTask;
        it.boundTask = QPersistentModelIndex();
        it.launcherUrl.clear();
        it.iconName.clear();
        it.appId.clear();
        it.appName.clear();
        const QModelIndex idx = index(unifiedRow);
        // Slot -> Stray conversion flips IsEmptySlotRole / SlotIdxRole (Stray gets -1).
        Q_EMIT dataChanged(idx, idx,
                           QVector<int>{SlotIdxRole, IsEmptySlotRole,
                                        SlotLauncherUrlRole, SlotAppIdRole,
                                        SlotBgColorRole, SlotBarColorRole});
    } else {
        beginRemoveRows(QModelIndex(), unifiedRow, unifiedRow);
        m_items.remove(unifiedRow);
        endRemoveRows();
        // Everything AFTER the removed row has SlotIdxRole = row() decremented.
        if (unifiedRow < m_items.size()) {
            Q_EMIT dataChanged(index(unifiedRow), index(m_items.size() - 1),
                               QVector<int>{SlotIdxRole});
        }
    }
    Q_EMIT slotsConfigChanged();
}

void UnifiedTasksModel::duplicateSlotAt(int unifiedRow)
{
    if (unifiedRow < 0 || unifiedRow >= m_items.size()) return;
    if (m_items[unifiedRow].kind != Kind::Slot) return;

    Item copy = m_items[unifiedRow];
    copy.boundTask = QPersistentModelIndex();
    copy.strayTask = QPersistentModelIndex();

    const int insertAt = unifiedRow + 1;
    beginInsertRows(QModelIndex(), insertAt, insertAt);
    m_items.insert(insertAt, copy);
    endInsertRows();

    // SlotIdxRole for every item AFTER the insertion shifted by +1. Refresh QML.
    if (insertAt + 1 < m_items.size()) {
        Q_EMIT dataChanged(index(insertAt + 1), index(m_items.size() - 1),
                           QVector<int>{SlotIdxRole});
    }
    Q_EMIT slotsConfigChanged();
}

void UnifiedTasksModel::activateOrSpawnSlotAt(int unifiedRow)
{
    if (unifiedRow < 0 || unifiedRow >= m_items.size()) return;
    const Item &it = m_items[unifiedRow];
    if (it.kind != Kind::Slot) return;
    if (it.boundTask.isValid()) return; // bound path uses stock activate in QML

    const qint64 pid = it.customCommand.isEmpty()
        ? spawnServicePid(it.appId)
        : spawnCommandPid(it.customCommand);
    if (pid <= 0) {
        qWarning() << "kilotasks: failed to spawn slot" << it.appId
                   << "cmd" << (it.customCommand.isEmpty() ? QStringLiteral("<desktop>") : it.customCommand);
        return;
    }

    expirePendingSpawns();
    PendingSpawn p;
    p.pid = pid;
    p.appId = it.appId;
    p.slotLauncherUrl = it.launcherUrl;
    p.hintRow = unifiedRow;
    p.ts = QDateTime::currentMSecsSinceEpoch();
    m_pending.append(p);
}

bool UnifiedTasksModel::bindStrayToSlot(int slotRow, int strayRow)
{
    if (slotRow < 0 || slotRow >= m_items.size()) return false;
    if (strayRow < 0 || strayRow >= m_items.size()) return false;
    if (slotRow == strayRow) return false;

    Item &slot = m_items[slotRow];
    Item &stray = m_items[strayRow];
    if (slot.kind != Kind::Slot || stray.kind != Kind::Stray) return false;
    if (slot.boundTask.isValid()) return false;
    if (!stray.strayTask.isValid()) return false;

    // Transfer running task ownership.
    slot.boundTask = stray.strayTask;
    if (slot.iconName.isEmpty()) {
        const QString name = iconNameFromSource(QModelIndex(stray.strayTask));
        if (!name.isEmpty()) slot.iconName = name;
    }

    // Remove the stray entry. Slot row index may shift if the stray was before it.
    beginRemoveRows(QModelIndex(), strayRow, strayRow);
    m_items.remove(strayRow);
    endRemoveRows();

    const int newSlotRow = (strayRow < slotRow) ? slotRow - 1 : slotRow;

    // All items from strayRow onwards had their row() (and therefore
    // SlotIdxRole) decremented by the removal. Additionally the slot itself
    // just transitioned empty -> bound, so its IsEmptySlotRole flipped too.
    if (strayRow < m_items.size()) {
        Q_EMIT dataChanged(index(strayRow), index(m_items.size() - 1),
                           QVector<int>{SlotIdxRole});
    }
    const QModelIndex si = index(newSlotRow);
    Q_EMIT dataChanged(si, si, QVector<int>{IsEmptySlotRole, TaskIdxRole});
    Q_EMIT slotsConfigChanged();
    return true;
}

QString UnifiedTasksModel::slotCommandAt(int unifiedRow) const
{
    if (unifiedRow < 0 || unifiedRow >= m_items.size()) return {};
    if (m_items[unifiedRow].kind != Kind::Slot) return {};
    return m_items[unifiedRow].customCommand;
}

void UnifiedTasksModel::setSlotCommandAt(int unifiedRow, const QString &command)
{
    if (unifiedRow < 0 || unifiedRow >= m_items.size()) return;
    if (m_items[unifiedRow].kind != Kind::Slot) return;
    const QString trimmed = command.trimmed();
    if (m_items[unifiedRow].customCommand == trimmed) return;
    m_items[unifiedRow].customCommand = trimmed;
    Q_EMIT slotsConfigChanged();
}

QString UnifiedTasksModel::defaultCommandForAppId(const QString &appId) const
{
    return execLineForAppId(appId);
}

QString UnifiedTasksModel::slotBgColorAt(int unifiedRow) const
{
    if (unifiedRow < 0 || unifiedRow >= m_items.size()) return {};
    if (m_items[unifiedRow].kind != Kind::Slot) return {};
    return m_items[unifiedRow].bgColor;
}

void UnifiedTasksModel::setSlotBgColorAt(int unifiedRow, const QString &color)
{
    if (unifiedRow < 0 || unifiedRow >= m_items.size()) return;
    if (m_items[unifiedRow].kind != Kind::Slot) return;
    const QString trimmed = color.trimmed();
    if (m_items[unifiedRow].bgColor == trimmed) return;
    m_items[unifiedRow].bgColor = trimmed;
    const QModelIndex i = index(unifiedRow);
    Q_EMIT dataChanged(i, i, QVector<int>{SlotBgColorRole});
    Q_EMIT slotsConfigChanged();
}

QString UnifiedTasksModel::slotBarColorAt(int unifiedRow) const
{
    if (unifiedRow < 0 || unifiedRow >= m_items.size()) return {};
    if (m_items[unifiedRow].kind != Kind::Slot) return {};
    return m_items[unifiedRow].barColor;
}

void UnifiedTasksModel::setSlotBarColorAt(int unifiedRow, const QString &color)
{
    if (unifiedRow < 0 || unifiedRow >= m_items.size()) return;
    if (m_items[unifiedRow].kind != Kind::Slot) return;
    const QString trimmed = color.trimmed();
    if (m_items[unifiedRow].barColor == trimmed) return;
    m_items[unifiedRow].barColor = trimmed;
    const QModelIndex i = index(unifiedRow);
    Q_EMIT dataChanged(i, i, QVector<int>{SlotBarColorRole});
    Q_EMIT slotsConfigChanged();
}

bool UnifiedTasksModel::moveItem(int from, int to)
{
    if (from == to) return false;
    if (from < 0 || from >= m_items.size()) return false;
    if (to < 0 || to >= m_items.size()) return false;

    // Qt's beginMoveRows requires destination index AFTER the removed range semantics;
    // so when moving forward, dest = to + 1.
    const int destIndex = (to > from) ? to + 1 : to;
    if (!beginMoveRows(QModelIndex(), from, from, QModelIndex(), destIndex)) return false;
    m_items.move(from, to);
    endMoveRows();

    // SlotIdxRole and TaskIdxRole for items between from/to have shifted. QML
    // caches role data across rowsMoved (Qt only repositions delegates), so we
    // must explicitly notify or a click on a moved empty slot spawns into the
    // wrong row. Emit for the whole range — cheap with <20 tasks.
    if (!m_items.isEmpty()) {
        Q_EMIT dataChanged(index(0), index(m_items.size() - 1),
                           QVector<int>{SlotIdxRole, TaskIdxRole});
    }
    Q_EMIT slotsConfigChanged();
    return true;
}
