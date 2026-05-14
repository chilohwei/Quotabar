import AppKit
import SwiftUI

struct AccountCardView: View {
    let account: Account
    let language: AppLanguage
    let isActive: Bool
    let isRefreshing: Bool
    let loadState: AccountLoadState
    let quota: QuotaSnapshot?
    let errorMessage: String?
    let canActivate: Bool
    let refreshCycleID: Int
    let onActivate: () -> Void
    let onDelete: () -> Void

    @State private var isConfirmingDelete = false
    @State private var isHovering = false
    @State private var showFullDisplayName = false
    @State private var refreshFeedback: CardRefreshFeedback = .idle
    @State private var activeRefreshCycleID: Int = 0
    @State private var wasRefreshingInActiveCycle = false
    @State private var hideRefreshFeedbackTask: Task<Void, Never>?

    private let cardCornerRadius: CGFloat = 16

    private var text: AppText { AppText(language: language) }

    private var resolvedAccountName: String {
        let trimmed = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "\(account.tool.displayName) Account" : trimmed
    }

    private var compactedDisplayName: String {
        compactDisplayName(resolvedAccountName)
    }

    private var displayName: String {
        if showFullDisplayName {
            return resolvedAccountName
        }
        return compactedDisplayName
    }

    private var canToggleDisplayName: Bool {
        compactedDisplayName != resolvedAccountName
    }

    private func compactDisplayName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let atIndex = trimmed.firstIndex(of: "@"), trimmed.count > 22 {
            let localPart = String(trimmed[..<atIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let domainPart = String(trimmed[trimmed.index(after: atIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !localPart.isEmpty {
                let domainPrefix = domainPart.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
                if !domainPrefix.isEmpty {
                    let localWithDomain = "\(localPart)@\(domainPrefix)"
                    if localWithDomain.count <= 26 {
                        return localWithDomain
                    }
                }
                if localPart.count <= 26 {
                    return localPart
                }
                return String(localPart.prefix(26))
            }
        }
        if trimmed.count <= 26 {
            return trimmed
        }
        return String(trimmed.prefix(26))
    }

    private enum SubscriptionType: Equatable {
        case apiKey
        case free
        case plus
        case pro
        case proPlus
        case ultra
        case max
        case team
        case enterprise
        case unlimited
        case claudeFirstParty
        case claudeProvider(String)
        case unknown(String)

        var label: String {
            switch self {
            case .apiKey: return "API"
            case .free: return "Free"
            case .plus: return "Plus"
            case .pro: return "Pro"
            case .proPlus: return "Pro+"
            case .ultra: return "Ultra"
            case .max: return "Max"
            case .team: return "Team"
            case .enterprise: return "Enterprise"
            case .unlimited: return "Unlimited"
            case .claudeFirstParty: return "Claude.ai"
            case .claudeProvider(let provider): return provider
            case .unknown(let raw): return raw
            }
        }

        var tint: Color {
            switch self {
            case .free:
                return Branding.inkMuted
            case .apiKey, .plus, .team:
                return Branding.accentBlueDark
            case .pro, .claudeFirstParty:
                return Branding.success
            case .proPlus, .ultra, .max, .unlimited, .claudeProvider:
                return Branding.warning
            case .enterprise:
                return Branding.inkStrong
            case .unknown:
                return Branding.accentBlueDark
            }
        }

        var background: Color {
            switch self {
            case .free:
                return Branding.chipSurface
            case .apiKey, .plus:
                return Branding.accentBlueSoft
            case .team:
                return Branding.activeChipSurface
            case .pro, .claudeFirstParty:
                return Branding.successSoft
            case .proPlus, .ultra, .max, .unlimited, .claudeProvider:
                return Branding.warningSoft
            case .enterprise:
                return Branding.metricSurface
            case .unknown:
                return Branding.accentBlueSoft
            }
        }

        var isPaid: Bool {
            switch self {
            case .plus, .pro, .proPlus, .ultra, .max, .team, .enterprise, .unlimited:
                return true
            case .claudeFirstParty, .claudeProvider:
                return true
            case .apiKey, .free, .unknown:
                return false
            }
        }
    }

    private var planBadgeItems: [(text: String, tint: Color, background: Color)] {
        guard let rawPlan = quota?.planName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPlan.isEmpty else {
            return []
        }

        let type = subscriptionType(from: rawPlan, tool: account.tool)
        var items: [(text: String, tint: Color, background: Color)] = [
            (type.label, type.tint, type.background)
        ]

        if account.tool != .claudeCode,
           let cycle = actualBillingCycle(from: rawPlan.lowercased()) {
            items.append((text.billingCycle(cycle), Branding.warning, Branding.warningSoft))
        }

        return items
    }

    private func subscriptionType(from rawPlan: String, tool: ToolKind) -> SubscriptionType {
        let lower = rawPlan.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return .unknown(rawPlan) }

        switch tool {
        case .cursor:
            if lower.contains("free") || lower.contains("hobby") { return .free }
            if lower.contains("enterprise") { return .enterprise }
            if lower.contains("team") || lower.contains("business") { return .team }
            if lower.contains("ultra") { return .ultra }
            if lower.contains("pro+") || lower.contains("pro plus") || lower.contains("pro_plus") { return .proPlus }
            if lower.contains("pro") { return .pro }
            return .unknown(rawPlan)
        case .codex:
            if lower.contains("api key") || lower == "api" { return .apiKey }
            if lower.contains("free") || lower.contains("hobby") { return .free }
            if lower.contains("enterprise") { return .enterprise }
            if lower.contains("team") || lower.contains("business") { return .team }
            if lower.contains("unlimited") { return .unlimited }
            if lower.contains("ultra") { return .ultra }
            if lower.contains("max") { return .max }
            if lower.contains("pro+") || lower.contains("pro plus") || lower.contains("pro_plus") { return .proPlus }
            if lower.contains("pro") { return .pro }
            if lower.contains("plus") { return .plus }
            return .unknown(rawPlan)
        case .claudeCode:
            if lower == "claude.ai" || lower.contains("claude.ai") {
                return .claudeFirstParty
            }
            if lower.contains("api key") || lower == "api" {
                return .apiKey
            }
            return .claudeProvider(rawPlan)
        }
    }

    private var subscriptionDateText: String? {
        guard let quota,
              let date = quota.accountValidUntil,
              shouldShowSubscriptionDate(for: quota) else {
            return nil
        }

        if quota.subscriptionWillRenew == true {
            return text.renewsOn(date)
        }
        return text.expiresOn(date)
    }

    private func shouldShowSubscriptionDate(for quota: QuotaSnapshot) -> Bool {
        switch account.tool {
        case .codex:
            guard let rawPlan = quota.planName else { return false }
            return subscriptionType(from: rawPlan, tool: .codex).isPaid
        case .cursor:
            guard let plan = quota.planName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !plan.isEmpty else {
                return true
            }
            return subscriptionType(from: plan, tool: .cursor) != .free
        case .claudeCode:
            return true
        }
    }

    private var remainingRatio: Double? {
        quotaLimitingMetrics.compactMap(\.ratio).min()
    }

    private var remainingRatios: [Double] {
        quotaLimitingMetrics.compactMap(\.ratio)
    }

    private var metrics: [QuotaDisplayMetric] {
        quota?.orderedMetrics ?? []
    }

    private var visibleMetrics: [QuotaDisplayMetric] {
        Array(metrics.prefix(3))
    }

    private var quotaLimitingMetrics: [QuotaDisplayMetric] {
        guard account.tool == .claudeCode else { return metrics }
        var items: [QuotaDisplayMetric] = []
        if let primary = quota?.primary {
            items.append(.window(primary))
        }
        if let secondary = quota?.secondary {
            items.append(.window(secondary))
        }
        if let remaining = quota?.creditsRemaining,
           let total = quota?.creditsTotal,
           total > 0 {
            items.append(.credits(remaining: remaining, total: total, periodEnd: quota?.periodEnd))
        }
        return items
    }

    private var useRingMetricLayout: Bool {
        account.tool == .cursor
    }

    private var hasAnyQuotaRemaining: Bool {
        if remainingRatios.contains(where: { $0 > 0.001 }) {
            return true
        }
        return false
    }

    private var hasExhaustedQuotaWindow: Bool {
        remainingRatios.contains { $0 <= 0.001 }
    }

    private func actualBillingCycle(from lowercasedPlan: String) -> BillingCycle? {
        if lowercasedPlan.contains("annual")
            || lowercasedPlan.contains("yearly")
            || lowercasedPlan.contains("year")
            || lowercasedPlan.contains("年度") {
            return .annual
        }

        if lowercasedPlan.contains("monthly")
            || lowercasedPlan.contains("month")
            || lowercasedPlan.contains("月度") {
            return .monthly
        }

        return nil
    }

    private var status: AccountVisualStatus {
        if errorMessage != nil, quota != nil { return .stale }
        if errorMessage != nil { return .error }
        if isRefreshing || loadState == .refreshing || loadState == .loadingInitial { return .refreshing }
        guard let quota else { return .pending }
        if quota.isQuotaBlocked == true { return .exhausted }
        if metrics.isEmpty {
            if account.tool == .claudeCode {
                return .healthy
            }
            return .noQuota
        }
        if hasExhaustedQuotaWindow { return .exhausted }
        if account.tool == .claudeCode, quotaLimitingMetrics.isEmpty, !metrics.isEmpty {
            return .healthy
        }
        if hasAnyQuotaRemaining {
            guard let remainingRatio else { return .healthy }
            return remainingRatio <= 0.20 ? .warning : .healthy
        }
        guard let remainingRatio else { return .noQuota }
        if remainingRatio <= 0.001 { return .exhausted }
        if remainingRatio <= 0.20 { return .warning }
        return .healthy
    }

    private var shouldShowStatusBadge: Bool {
        if shouldHideRefreshingStatusBadge {
            return false
        }
        if useRingMetricLayout, status == .noQuota {
            // Cursor ring tiles already communicate zero quota via 0%,
            // so suppress the duplicate "No Quota" badge.
            return false
        }

        switch status {
        case .healthy, .warning, .exhausted:
            return false
        case .refreshing, .pending, .noQuota, .stale, .error:
            return true
        }
    }

    private var shouldHideRefreshingStatusBadge: Bool {
        guard refreshBadge != nil else { return false }
        if case .refreshing = status {
            return true
        }
        return false
    }

    private var cardFill: Color {
        if isActive { return Branding.activeCardSurface }
        if isHovering { return Branding.hoverCardSurface }
        return Branding.cardSurface
    }

    private var cardStroke: Color {
        isActive ? Branding.borderSelected : Branding.cardStroke
    }

    private var shouldShowActions: Bool {
        isHovering || isActive
    }

    private var footerMessage: (message: String, color: Color)? {
        if let errorMessage {
            if quota != nil {
                return (text.staleQuotaMessage(errorMessage), Branding.warning)
            }
            return (errorMessage, Branding.danger)
        }
        if let note = quota?.note?.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty {
            return (note, Branding.inkSubtle)
        }
        return nil
    }

    private var hasFooterContent: Bool {
        footerMessage != nil
    }

    private var secondaryPanelTitle: String {
        quota?.secondaryPanelTitle ?? "Weekly"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(displayName)
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Branding.inkStrong)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(canToggleDisplayName ? account.name : "")
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard canToggleDisplayName else { return }
                        showFullDisplayName.toggle()
                    }

                HStack(spacing: 7) {
                    ForEach(Array(planBadgeItems.enumerated()), id: \.offset) { _, item in
                        Badge(text: item.text, tint: item.tint, background: item.background)
                    }

                    if isActive {
                        Badge(text: text.string(.current), tint: Branding.accentBlueDark, background: Branding.accentBlueSoft)
                    }

                    if shouldShowStatusBadge {
                        Badge(text: status.title(text), tint: status.tint, background: status.background)
                    }

                    if let refreshBadge {
                        Badge(text: refreshBadge.text, tint: refreshBadge.tint, background: refreshBadge.background)
                    }

                    if let subscriptionDateText {
                        Text(subscriptionDateText)
                            .font(.system(size: 10.5, weight: .regular))
                            .foregroundStyle(Branding.inkSubtle)
                            .lineLimit(1)
                    }
                }
                .fixedSize()

                Spacer(minLength: 8)

                actionZone
                    .fixedSize()
            }

            if useRingMetricLayout {
                CursorMetricRingStrip(
                    primary: quota?.primaryPanelMetric,
                    secondary: quota?.secondaryPanelMetric,
                    tertiary: quota?.tertiaryPanelMetric,
                    fallbackResetAt: quota?.periodEnd,
                    language: language
                )
            } else {
                HStack(spacing: 10) {
                    if visibleMetrics.isEmpty {
                        QuotaPanel(title: quota?.primary?.label ?? "5h", metric: quota?.primaryPanelMetric, language: language, compact: false)
                        QuotaPanel(title: secondaryPanelTitle, metric: quota?.secondaryPanelMetric, language: language, compact: false)
                    } else {
                        ForEach(Array(visibleMetrics.enumerated()), id: \.offset) { _, metric in
                            QuotaPanel(title: metric.title, metric: metric, language: language, compact: false)
                        }
                    }
                }
            }

            footer
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 13)
        .frame(minHeight: hasFooterContent ? 138 : 118)
        .background(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        )
        .shadow(
            color: isActive ? Branding.shadowPopover : (isHovering ? Branding.hoverCardShadow : Branding.cardShadow),
            radius: isActive ? 9 : (isHovering ? 7 : 4),
            y: isActive ? 2.5 : 1.5
        )
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .animation(.easeOut(duration: 0.14), value: isActive)
        .onChange(of: refreshCycleID) { _ in
            handleRefreshCycleChange()
        }
        .onChange(of: isRefreshing) { refreshing in
            handleRefreshStateChange(isRefreshing: refreshing)
        }
        .onDisappear {
            hideRefreshFeedbackTask?.cancel()
            hideRefreshFeedbackTask = nil
        }
        .confirmationDialog(text.string(.deletePromptTitle), isPresented: $isConfirmingDelete) {
            Button(text.deleteAccountTitle(displayName), role: .destructive, action: onDelete)
            Button(text.string(.cancel), role: .cancel) {}
        } message: {
            Text(text.string(.deleteLocalOnly))
        }
    }

    private var actionZone: some View {
        HStack(spacing: 9) {
            if canActivate {
                Button(text.string(.switchAccount), action: onActivate)
                    .disabled(isActive)
                    .foregroundStyle(isActive ? Branding.inkSubtle : Branding.accentBlueDark)
            }
            Button {
                isConfirmingDelete = true
            } label: {
                if canActivate {
                    Text(text.string(.delete))
                } else {
                    Image(systemName: "trash")
                        .font(.system(size: 10.5, weight: .semibold))
                }
            }
            .foregroundStyle(Branding.danger)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Branding.inkMuted)
        .buttonStyle(.plain)
        .opacity(shouldShowActions ? 1 : 0)
        .allowsHitTesting(shouldShowActions)
        .accessibilityHidden(!shouldShowActions)
        .animation(.easeOut(duration: 0.12), value: shouldShowActions)
    }

    @ViewBuilder
    private var footer: some View {
        if hasFooterContent {
            VStack(alignment: .leading, spacing: 4) {
                if let footerMessage {
                    Text(footerMessage.message)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(footerMessage.color)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(footerMessage.message)
                }
            }
        }
    }

    private var refreshBadge: (text: String, tint: Color, background: Color)? {
        switch refreshFeedback {
        case .idle:
            return nil
        case .refreshing:
            return (
                refreshText(.refreshing),
                Branding.accentBlueDark,
                Branding.accentBlueSoft
            )
        case .success:
            return (
                refreshText(.success),
                Branding.success,
                Branding.successSoft
            )
        }
    }

    private func refreshText(_ state: CardRefreshFeedback) -> String {
        switch language {
        case .english:
            switch state {
            case .refreshing: return "Refreshing..."
            case .success: return "Updated"
            case .idle: return ""
            }
        case .simplifiedChinese:
            switch state {
            case .refreshing: return "刷新中..."
            case .success: return "已更新"
            case .idle: return ""
            }
        case .traditionalChinese:
            switch state {
            case .refreshing: return "刷新中..."
            case .success: return "已更新"
            case .idle: return ""
            }
        }
    }

    private func handleRefreshCycleChange() {
        guard refreshCycleID != activeRefreshCycleID else { return }
        activeRefreshCycleID = refreshCycleID
        wasRefreshingInActiveCycle = false
        refreshFeedback = .idle
        hideRefreshFeedbackTask?.cancel()
        hideRefreshFeedbackTask = nil
    }

    private func handleRefreshStateChange(isRefreshing: Bool) {
        if isRefreshing {
            if refreshCycleID > 0 {
                hideRefreshFeedbackTask?.cancel()
                hideRefreshFeedbackTask = nil
                refreshFeedback = .refreshing
                wasRefreshingInActiveCycle = true
            }
            return
        }

        guard wasRefreshingInActiveCycle else { return }
        wasRefreshingInActiveCycle = false

        if case .refreshing = refreshFeedback, errorMessage == nil {
            refreshFeedback = .success
            let completedCycleID = activeRefreshCycleID
            hideRefreshFeedbackTask?.cancel()
            hideRefreshFeedbackTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                if refreshFeedback == .success, activeRefreshCycleID == completedCycleID {
                    refreshFeedback = .idle
                    hideRefreshFeedbackTask = nil
                }
            }
        } else {
            refreshFeedback = .idle
            hideRefreshFeedbackTask?.cancel()
            hideRefreshFeedbackTask = nil
        }
    }
}

private enum CardRefreshFeedback: Equatable {
    case idle
    case refreshing
    case success
}

private enum AccountVisualStatus {
    case healthy
    case refreshing
    case pending
    case noQuota
    case stale
    case warning
    case exhausted
    case error

    func title(_ text: AppText) -> String {
        switch self {
        case .healthy: return text.string(.normal)
        case .refreshing: return text.string(.refreshing)
        case .pending: return text.string(.pendingRefresh)
        case .noQuota: return text.string(.noQuota)
        case .stale: return text.string(.staleData)
        case .warning: return text.string(.nearLimit)
        case .exhausted: return text.string(.exhausted)
        case .error: return text.string(.error)
        }
    }

    var tint: Color {
        switch self {
        case .healthy: return Branding.success
        case .refreshing: return Branding.accentBlue
        case .pending, .noQuota: return Branding.inkMuted
        case .stale: return Branding.warning
        case .warning: return Branding.warning
        case .exhausted, .error: return Branding.danger
        }
    }

    var background: Color {
        switch self {
        case .healthy: return Branding.successSoft
        case .refreshing: return Branding.accentBlueSoft
        case .pending, .noQuota: return Branding.chipSurface
        case .stale: return Branding.warningSoft
        case .warning: return Branding.warningSoft
        case .exhausted, .error: return Branding.dangerSoft
        }
    }
}

struct ToolLogoIcon: View {
    let tool: ToolKind
    let size: CGFloat

    private var fallbackSymbol: String {
        switch tool {
        case .codex:
            return "terminal.fill"
        case .cursor:
            return "square.grid.2x2.fill"
        case .claudeCode:
            return "asterisk"
        }
    }

    private var resourceName: String {
        switch tool {
        case .codex:
            return "codex"
        case .cursor:
            return "cursor"
        case .claudeCode:
            return "claude"
        }
    }

    private var preparedImage: NSImage? {
        ToolIconImageCache.image(named: resourceName, size: size)
    }

    var body: some View {
        if let icon = preparedImage {
            Image(nsImage: icon)
                .interpolation(.high)
                .antialiased(true)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: fallbackSymbol)
                .font(.system(size: size * 0.78, weight: .semibold))
                .foregroundStyle(Branding.inkStrong)
                .frame(width: size, height: size)
        }
    }
}

@MainActor
private enum ToolIconImageCache {
    private static var cache: [String: NSImage] = [:]

    static func image(named name: String, size: CGFloat) -> NSImage? {
        let key = "\(name)-\(size)"
        if let cached = cache[key] {
            return cached
        }
        guard let url = bundledResourceURL(name: name, extension: "png"),
              let loaded = NSImage(contentsOf: url) else {
            return nil
        }
        let icon = (loaded.copy() as? NSImage) ?? loaded
        icon.size = NSSize(width: size, height: size)
        cache[key] = icon
        return icon
    }

    private static func bundledResourceURL(name: String, extension resourceExtension: String) -> URL? {
        let bundleName = "QuotaBar_QuotaBarApp.bundle"
        let fileName = "\(name).\(resourceExtension)"
        let fileManager = FileManager.default
        let candidates = [
            Bundle.main.url(forResource: name, withExtension: resourceExtension),
            Bundle.main.resourceURL?
                .appendingPathComponent(bundleName, isDirectory: true)
                .appendingPathComponent(fileName),
            Bundle.main.executableURL?
                .deletingLastPathComponent()
                .appendingPathComponent(bundleName, isDirectory: true)
                .appendingPathComponent(fileName),
            Bundle.main.bundleURL
                .appendingPathComponent(bundleName, isDirectory: true)
                .appendingPathComponent(fileName)
        ]

        return candidates.compactMap { $0 }.first { fileManager.fileExists(atPath: $0.path) }
    }
}

private struct Badge: View {
    let text: String
    let tint: Color
    let background: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(background, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Branding.borderSubtle, lineWidth: 0.5)
            )
            .lineLimit(1)
    }
}

private struct CursorMetricRingStrip: View {
    let primary: QuotaDisplayMetric?
    let secondary: QuotaDisplayMetric?
    let tertiary: QuotaDisplayMetric?
    let fallbackResetAt: Date?
    let language: AppLanguage

    private var tiles: [(title: String, metric: QuotaDisplayMetric?)] {
        [
            ("Total", primary),
            ("Auto", secondary),
            ("API", tertiary)
        ]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                CursorMetricRingTile(
                    title: tile.title,
                    metric: tile.metric,
                    fallbackResetAt: fallbackResetAt,
                    language: language
                )
            }
        }
    }
}

private struct CursorMetricRingTile: View {
    let title: String
    let metric: QuotaDisplayMetric?
    let fallbackResetAt: Date?
    let language: AppLanguage

    private var text: AppText { AppText(language: language) }

    private var ratio: Double {
        min(max(metric?.ratio ?? 0, 0), 1)
    }

    private var isKnown: Bool {
        metric?.ratio != nil
    }

    private var tint: Color {
        guard isKnown else { return Branding.inkSubtle }
        if ratio <= 0.001 { return Branding.danger }
        if ratio <= 0.20 { return Branding.warning }
        return Branding.success
    }

    var body: some View {
        VStack(alignment: .center, spacing: 5) {
            Text(text.quotaLabel(title))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Branding.inkMuted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)

            ZStack {
                MetricRing(value: ratio, tint: tint)
                    .frame(width: 44, height: 44)

                Text("\(Int((ratio * 100).rounded()))%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(isKnown ? Branding.inkStrong : Branding.inkSubtle)
                    .monospacedDigit()
            }

            if let resetAt = metric?.resetAt ?? fallbackResetAt {
                Text(text.formatCompactDateTime(resetAt))
                    .font(.system(size: 9.8, weight: .regular))
                    .foregroundStyle(Branding.inkSubtle)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .top)
    }
}

private struct MetricRing: View {
    let value: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Branding.track, lineWidth: 3.6)
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: 3.6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.55), value: value)
        }
    }
}

private struct QuotaPanel: View {
    let title: String
    let metric: QuotaDisplayMetric?
    let language: AppLanguage
    let compact: Bool

    private var text: AppText { AppText(language: language) }

    private var state: (ratio: Double, resetAt: Date?, isKnown: Bool) {
        guard let metric,
              let ratio = metric.ratio else {
            return (0, nil, false)
        }
        return (ratio, metric.resetAt, true)
    }

    private var tint: Color {
        guard state.isKnown else { return Branding.inkSubtle }
        if state.ratio <= 0.001 { return Branding.danger }
        if state.ratio <= 0.20 { return Branding.warning }
        return Branding.success
    }

    var body: some View {
        let resolved = state

        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.quotaLabel(title))
                        .font(.system(size: compact ? 11 : 12, weight: .semibold))
                        .foregroundStyle(Branding.inkMuted)
                        .lineLimit(1)
                    Text(language == .english ? "Remaining" : (language == .traditionalChinese ? "剩餘" : "剩余"))
                        .font(.system(size: compact ? 10 : 10.5, weight: .regular))
                        .foregroundStyle(Branding.inkSubtle)
                }

                Spacer(minLength: 8)

                Text(resolved.isKnown ? "\(Int((resolved.ratio * 100).rounded()))%" : "--")
                    .font(.system(size: compact ? 14.5 : 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(resolved.isKnown ? Branding.inkStrong : Branding.inkSubtle)
                    .monospacedDigit()
            }

            RatioBar(value: resolved.isKnown ? resolved.ratio : 0, tint: tint)

            if resolved.isKnown, let resetAt = resolved.resetAt {
                Text(text.formatCompactDateTime(resetAt))
                    .font(.system(size: compact ? 10 : 10.5, weight: .regular))
                    .foregroundStyle(Branding.inkSubtle)
                    .lineLimit(1)
            } else if !resolved.isKnown {
                Text(text.string(.waitingData))
                    .font(.system(size: compact ? 10 : 10.5, weight: .regular))
                    .foregroundStyle(Branding.inkSubtle)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 64 : 70, alignment: .leading)
    }
}

private struct RatioBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Branding.track)
                    .overlay(
                        Capsule()
                            .stroke(Branding.iconHighlight, lineWidth: 0.5)
                    )
                Capsule()
                    .fill(tint)
                    .frame(width: max(proxy.size.width * value, value > 0 ? 7 : 0))
                    .animation(.easeOut(duration: 0.55), value: value)
            }
        }
        .frame(height: 7)
    }
}
