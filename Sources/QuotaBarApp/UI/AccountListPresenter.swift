import Foundation

struct AccountListPresenter {
    static func visibleAccounts(
        accounts: [Account],
        filter: AccountFilter,
        activeID: UUID?,
        quotaByAccount: [UUID: QuotaSnapshot],
        loadStateByAccount: [UUID: AccountLoadState],
        frozenOrder: [UUID]?
    ) -> [Account] {
        let sortedAccounts = sortedForStableDisplay(
            accounts,
            activeID: activeID,
            quotaByAccount: quotaByAccount,
            loadStateByAccount: loadStateByAccount,
            frozenOrder: frozenOrder
        )

        switch filter {
        case .all:
            return sortedAccounts
        case .available:
            return sortedAccounts.filter { isAccountAvailable($0, quotaByAccount: quotaByAccount) }
        }
    }

    static func availableAccountCount(
        accounts: [Account],
        quotaByAccount: [UUID: QuotaSnapshot]
    ) -> Int {
        accounts.filter { isAccountAvailable($0, quotaByAccount: quotaByAccount) }.count
    }

    static func isAccountAvailable(
        _ account: Account,
        quotaByAccount: [UUID: QuotaSnapshot]
    ) -> Bool {
        guard let quota = quotaByAccount[account.id],
              quota.isQuotaBlocked != true else {
            return false
        }

        let ratios = [quota.primary, quota.secondary, quota.tertiary]
            .compactMap { window -> Double? in
                guard let window, window.limit > 0 else { return nil }
                return min(max(window.remaining / window.limit, 0), 1)
            }
        if !ratios.isEmpty {
            return ratios.allSatisfy { Int(($0 * 100).rounded()) > 0 }
        }

        if account.tool == .claudeCode {
            let note = quota.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !quota.orderedMetrics.isEmpty
                || !note.isEmpty
                || quota.accountIdentifier?.isEmpty == false
        }

        if let remaining = quota.creditsRemaining {
            return remaining > 0
        }

        return false
    }

    private static func sortedForStableDisplay(
        _ accounts: [Account],
        activeID: UUID?,
        quotaByAccount: [UUID: QuotaSnapshot],
        loadStateByAccount: [UUID: AccountLoadState],
        frozenOrder: [UUID]?
    ) -> [Account] {
        let frozenRankByID = Dictionary(
            uniqueKeysWithValues: (frozenOrder ?? []).enumerated().map { ($0.element, $0.offset) }
        )
        let isRefreshing = accounts.contains { account in
            loadStateByAccount[account.id] == .refreshing
                || loadStateByAccount[account.id] == .loadingInitial
        }
        let entries = accounts.map { account in
            SortEntry(
                account: account,
                isActive: account.id == activeID,
                frozenRank: frozenRankByID[account.id],
                isAvailable: isAccountAvailable(account, quotaByAccount: quotaByAccount),
                availabilityRank: availabilityRank(
                    account,
                    quotaByAccount: quotaByAccount,
                    loadStateByAccount: loadStateByAccount
                ),
                bottleneckRatio: bottleneckRemainingRatio(account, quotaByAccount: quotaByAccount),
                earliestReset: earliestResetDate(account, quotaByAccount: quotaByAccount)
            )
        }

        return entries.sorted { lhs, rhs in
            if lhs.isActive, !rhs.isActive {
                return true
            }
            if rhs.isActive, !lhs.isActive {
                return false
            }

            if frozenOrder != nil {
                let lhsRank = lhs.frozenRank ?? Int.max
                let rhsRank = rhs.frozenRank ?? Int.max
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
            }

            if isRefreshing {
                return lhs.account.createdAt < rhs.account.createdAt
            }

            if lhs.isAvailable != rhs.isAvailable {
                return lhs.isAvailable
            }

            if lhs.availabilityRank != rhs.availabilityRank {
                return lhs.availabilityRank < rhs.availabilityRank
            }

            if lhs.isAvailable {
                if lhs.bottleneckRatio != rhs.bottleneckRatio {
                    return lhs.bottleneckRatio > rhs.bottleneckRatio
                }
            } else {
                if lhs.earliestReset != rhs.earliestReset {
                    return lhs.earliestReset < rhs.earliestReset
                }
            }

            return lhs.account.createdAt < rhs.account.createdAt
        }.map(\.account)
    }

    private static func availabilityRank(
        _ account: Account,
        quotaByAccount: [UUID: QuotaSnapshot],
        loadStateByAccount: [UUID: AccountLoadState]
    ) -> AvailabilityRank {
        guard let quota = quotaByAccount[account.id] else {
            return loadStateByAccount[account.id] == .failed ? .failed : .unknown
        }

        if isAccountAvailable(account, quotaByAccount: quotaByAccount) {
            return .available
        }

        if quota.isQuotaBlocked == true {
            return .blocked
        }

        if earliestResetDate(account, quotaByAccount: quotaByAccount) != .distantFuture {
            return .recovering
        }

        if !quota.orderedMetrics.isEmpty {
            return .exhausted
        }

        let loadState = loadStateByAccount[account.id]
        if loadState == .failed || loadState == .stale {
            return .failed
        }
        return .unknown
    }

    private static func bottleneckRemainingRatio(
        _ account: Account,
        quotaByAccount: [UUID: QuotaSnapshot]
    ) -> Double {
        guard let quota = quotaByAccount[account.id] else { return -1 }
        let ratios = quota.orderedMetrics.compactMap(\.ratio)
        return ratios.min() ?? -1
    }

    private static func earliestResetDate(
        _ account: Account,
        quotaByAccount: [UUID: QuotaSnapshot]
    ) -> Date {
        guard let quota = quotaByAccount[account.id] else { return .distantFuture }
        return quota.orderedMetrics.compactMap(\.resetAt).min() ?? .distantFuture
    }

    private struct SortEntry {
        let account: Account
        let isActive: Bool
        let frozenRank: Int?
        let isAvailable: Bool
        let availabilityRank: AvailabilityRank
        let bottleneckRatio: Double
        let earliestReset: Date
    }

    private enum AvailabilityRank: Int, Comparable {
        case available = 0
        case recovering = 1
        case exhausted = 2
        case blocked = 3
        case failed = 4
        case unknown = 5

        static func < (lhs: AvailabilityRank, rhs: AvailabilityRank) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}

enum AccountFilter {
    case all
    case available
}
