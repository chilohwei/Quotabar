import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var appState: AppState
    @State private var accountFilter: AccountFilter = .all
    @State private var refreshCycleID: Int = 0
    @State private var isToolMenuPresented: Bool = false
    @State private var isFilterMenuPresented: Bool = false
    @State private var frozenAccountOrderByTool: [ToolKind: [UUID]] = [:]
    @State private var lastVisibleAccountOrderByTool: [ToolKind: [UUID]] = [:]

    private var text: AppText { appState.text }

    private var toolAccounts: [Account] {
        appState.accounts(for: appState.selectedTool)
    }

    private var visibleAccounts: [Account] {
        let sortedAccounts = AccountListPresenter.visibleAccounts(
            accounts: toolAccounts,
            filter: accountFilter,
            activeID: appState.activeAccountByTool[appState.selectedTool],
            quotaByAccount: appState.quotaByAccount,
            loadStateByAccount: appState.loadStateByAccount,
            frozenOrder: effectiveFrozenOrder
        )
        guard isRefreshingSelectedTool,
              let frozenOrder = effectiveFrozenOrder,
              !frozenOrder.isEmpty else {
            return sortedAccounts
        }

        let accountByID = Dictionary(uniqueKeysWithValues: toolAccounts.map { ($0.id, $0) })
        let frozenAccounts = frozenOrder.compactMap { accountByID[$0] }
        return frozenAccounts.isEmpty ? sortedAccounts : frozenAccounts
    }

    private var visibleAccountIDs: [UUID] {
        visibleAccounts.map(\.id)
    }

    private var activeName: String {
        appState.activeAccount(for: appState.selectedTool)?.name ?? "--"
    }

    private var isRefreshingSelectedTool: Bool {
        toolAccounts.contains { account in
            appState.loadStateByAccount[account.id] == .refreshing
                || appState.loadStateByAccount[account.id] == .loadingInitial
        }
    }

    private var availableAccountCount: Int {
        AccountListPresenter.availableAccountCount(
            accounts: toolAccounts,
            quotaByAccount: appState.quotaByAccount
        )
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            if shouldShowUpdateNotice {
                updateNoticeBar
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            accountList
                .frame(maxHeight: .infinity)
            footerBar
        }
        .padding(.top, 8)
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
        .frame(width: 430, height: 552, alignment: .top)
        .background(Branding.pageBackground)
        .foregroundStyle(Branding.ink)
        .alert(text.string(.restartRequiredTitle), isPresented: restartRequiredAlertBinding) {
            Button(text.string(.ok)) {
                appState.dismissRestartRequiredMessage()
            }
        } message: {
            Text(appState.restartRequiredMessage ?? "")
        }
        .alert(text.string(.addAccountFailedTitle), isPresented: addAccountErrorAlertBinding) {
            Button(text.string(.ok)) {
                appState.dismissAddAccountError()
            }
        } message: {
            Text(appState.addAccountErrorMessage ?? "")
        }
        .onChange(of: isRefreshingSelectedTool) { refreshing in
            if refreshing {
                if frozenAccountOrderByTool[appState.selectedTool] == nil {
                    frozenAccountOrderByTool[appState.selectedTool] = preferredFrozenOrderForSelectedTool()
                }
            } else {
                withTransaction(Transaction(animation: nil)) {
                    frozenAccountOrderByTool[appState.selectedTool] = nil
                    rememberVisibleOrderForSelectedTool(visibleAccountIDs)
                }
            }
        }
        .onChange(of: visibleAccountIDs) { ids in
            guard !isRefreshingSelectedTool else { return }
            rememberVisibleOrderForSelectedTool(ids)
        }
        .onChange(of: appState.selectedTool) { _ in
            rememberVisibleOrderForSelectedTool(visibleAccountIDs)
        }
        .onAppear {
            rememberVisibleOrderForSelectedTool(visibleAccountIDs)
        }
    }

    private func freezeCurrentAccountOrder() {
        let ids = visibleAccountIDs
        frozenAccountOrderByTool[appState.selectedTool] = ids
        rememberVisibleOrderForSelectedTool(ids)
    }

    private var effectiveFrozenOrder: [UUID]? {
        let tool = appState.selectedTool
        if let frozen = frozenAccountOrderByTool[tool] {
            return frozen
        }
        if isRefreshingSelectedTool,
           let remembered = lastVisibleAccountOrderByTool[tool],
           !remembered.isEmpty {
            return remembered
        }
        return nil
    }

    private func preferredFrozenOrderForSelectedTool() -> [UUID] {
        let tool = appState.selectedTool
        if let remembered = lastVisibleAccountOrderByTool[tool], !remembered.isEmpty {
            return remembered
        }
        return visibleAccountIDs
    }

    private func rememberVisibleOrderForSelectedTool(_ ids: [UUID]) {
        lastVisibleAccountOrderByTool[appState.selectedTool] = ids
    }

    private func accountLoadState(_ account: Account) -> AccountLoadState {
        appState.loadStateByAccount[account.id] ?? .idle
    }

    private func isAccountRefreshing(_ account: Account) -> Bool {
        let state = accountLoadState(account)
        return state == .refreshing || state == .loadingInitial
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 8) {
                HStack(alignment: .center, spacing: 6) {
                    toolSwitchMenu
                    Text(text.usageHeadline)
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(Branding.inkStrong)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                headerActions
            }

            Text(text.subtitle(count: toolAccounts.count, activeName: activeName))
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(Branding.inkSubtle.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var headerActions: some View {
        HStack(spacing: 9) {
            Button {
                freezeCurrentAccountOrder()
                refreshCycleID += 1
                appState.refreshSelectedTool()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .rotationEffect(.degrees(isRefreshingSelectedTool ? 360 : 0))
                    .animation(
                        isRefreshingSelectedTool
                            ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                            : .easeOut(duration: 0.2),
                        value: isRefreshingSelectedTool
                    )
                .frame(width: 42, height: 34)
                .foregroundStyle(isRefreshingSelectedTool || toolAccounts.isEmpty ? Branding.inkSubtle : Branding.inkMuted)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Branding.controlSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Branding.controlStroke, lineWidth: 1)
                )
            }
            .disabled(isRefreshingSelectedTool || toolAccounts.isEmpty)
            .buttonStyle(.plain)
            .help(text.string(.refresh))

            Button {
                if appState.isAddingAccount {
                    appState.cancelAddAccount()
                } else {
                    appState.quickAddAccount(tool: appState.selectedTool)
                }
            } label: {
                HStack(spacing: 6) {
                    if appState.isAddingAccount {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Branding.warning)
                    }

                    Text(appState.isAddingAccount ? text.string(.cancelAdding) : text.string(.addAccount))
                        .font(.system(size: 13, weight: .medium))
                }
                .frame(height: 34)
                .padding(.horizontal, 15)
                .foregroundStyle(appState.isAddingAccount ? Branding.warning : Branding.primaryActionText)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(appState.isAddingAccount ? Branding.warningSoft : Branding.accentBlue)
                )
                .shadow(
                    color: appState.isAddingAccount ? Branding.warning.opacity(0.12) : Branding.accentBlue.opacity(0.14),
                    radius: 7,
                    y: 2
                )
            }
            .buttonStyle(.plain)
        }
        .fixedSize()
    }

    private var toolSwitchMenu: some View {
        Button {
            isToolMenuPresented.toggle()
        } label: {
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(toolBackground(appState.selectedTool))
                    ToolLogoIcon(tool: appState.selectedTool, size: 11.5)
                }
                .frame(width: 18, height: 18)

                Text(appState.selectedTool.displayName)
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Branding.inkSubtle)
            }
            .foregroundStyle(Branding.inkStrong)
            .padding(.horizontal, 10)
            .frame(height: 31)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Branding.controlSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Branding.controlStroke, lineWidth: 1)
            )
        }
        .popover(isPresented: $isToolMenuPresented, arrowEdge: .top) {
            VStack(spacing: 4) {
                ForEach(ToolKind.allCases) { tool in
                    Button {
                        appState.selectTool(tool)
                        isToolMenuPresented = false
                    } label: {
                        HStack(spacing: 9) {
                            ZStack {
                                Circle()
                                    .fill(toolBackground(tool))
                                ToolLogoIcon(tool: tool, size: 11)
                            }
                            .frame(width: 18, height: 18)

                            Text(tool.displayName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Branding.inkStrong)
                                .lineLimit(1)
                                .layoutPriority(1)

                            Spacer(minLength: 6)

                            if appState.selectedTool == tool {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(toolTint(tool))
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 31)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(appState.selectedTool == tool ? Branding.menuItemSelectedSurface : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .frame(width: 178)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Branding.menuSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Branding.borderSubtle, lineWidth: 1)
            )
            .shadow(color: Branding.shadowPopover, radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private func toolTint(_ tool: ToolKind) -> Color {
        switch tool {
        case .codex:
            return Branding.accentBlueDark
        case .cursor:
            return Branding.success
        case .claudeCode:
            return Branding.warning
        }
    }

    private func toolBackground(_ tool: ToolKind) -> Color {
        switch tool {
        case .codex:
            return Branding.accentBlueSoft.opacity(0.72)
        case .cursor:
            return Branding.successSoft.opacity(0.70)
        case .claudeCode:
            return Branding.warningSoft.opacity(0.72)
        }
    }

    @ViewBuilder
    private var accountList: some View {
        let accounts = visibleAccounts
        let accountIDs = accounts.map(\.id)

        ScrollView(.vertical, showsIndicators: false) {
            if toolAccounts.isEmpty {
                emptyState
            } else if accounts.isEmpty {
                filteredEmptyState
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(accounts) { account in
                        AccountCardView(
                            account: account,
                            language: appState.language,
                            isActive: appState.activeAccountByTool[appState.selectedTool] == account.id,
                            isRefreshing: isAccountRefreshing(account),
                            loadState: accountLoadState(account),
                            quota: appState.quotaByAccount[account.id],
                            errorMessage: appState.errorByAccount[account.id],
                            canActivate: true,
                            refreshCycleID: refreshCycleID,
                            onActivate: { appState.activateAccount(account) },
                            onDelete: { appState.deleteAccount(account) }
                        )
                        .transaction { transaction in
                            if isRefreshingSelectedTool {
                                transaction.animation = nil
                            }
                        }
                    }
                }
                .padding(.top, 2)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .top)
                .animation(isRefreshingSelectedTool ? nil : .easeInOut(duration: 0.16), value: accountIDs)
            }
        }
        .background(ScrollIndicatorHider())
        .scrollIndicators(.hidden)
        .clipped()
        .frame(maxWidth: .infinity)
    }

    private var restartRequiredAlertBinding: Binding<Bool> {
        Binding {
            appState.restartRequiredMessage != nil
        } set: { isPresented in
            if !isPresented {
                appState.dismissRestartRequiredMessage()
            }
        }
    }

    private var addAccountErrorAlertBinding: Binding<Bool> {
        Binding {
            appState.addAccountErrorMessage != nil
        } set: { isPresented in
            if !isPresented {
                appState.dismissAddAccountError()
            }
        }
    }

    private var footerBar: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                isFilterMenuPresented.toggle()
            } label: {
                HStack(spacing: 7) {
                    Text(text.string(.show))
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(Branding.inkSubtle)

                    Circle()
                        .fill(Branding.separatorDot)
                        .frame(width: 3, height: 3)

                    Text(currentFilterTitle)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(Branding.inkMuted)
                        .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Branding.inkSubtle)
                }
                .padding(.leading, 9)
                .padding(.trailing, 8)
                .frame(height: 23)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Branding.controlSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Branding.controlStroke, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .fixedSize()
            .popover(isPresented: $isFilterMenuPresented, arrowEdge: .bottom) {
                VStack(spacing: 4) {
                    footerFilterOption(
                        title: text.accountFilterAll(count: toolAccounts.count),
                        isSelected: accountFilter == .all
                    ) {
                        accountFilter = .all
                        isFilterMenuPresented = false
                    }

                    footerFilterOption(
                        title: text.accountFilterAvailable(count: availableAccountCount),
                        isSelected: accountFilter == .available
                    ) {
                        accountFilter = .available
                        isFilterMenuPresented = false
                    }
                }
                .padding(8)
                .frame(width: 160)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Branding.menuSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Branding.borderSubtle, lineWidth: 1)
                )
                .shadow(color: Branding.shadowPopover, radius: 18, y: 8)
            }

            Spacer(minLength: 6)

            Button(text.string(.quit)) {
                NSApp.terminate(nil)
            }
            .font(.system(size: 11.5, weight: .regular))
            .foregroundStyle(Branding.inkMuted.opacity(0.92))
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            .frame(height: 23)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .frame(height: 28)
    }

    private var shouldShowUpdateNotice: Bool {
        if case .idle = appState.updateBannerState {
            return false
        }
        return true
    }

    private var updateNoticeBar: some View {
        Button {
            appState.installAvailableUpdateFromDashboard()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: updateNoticeIconName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(width: 16)

                Text(updateNoticeTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .monospacedDigit()

                Spacer(minLength: 8)

                if let action = updateNoticeActionLabel {
                    Text(action)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(height: 23)
                        .foregroundStyle(Branding.primaryActionText)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Branding.accentBlue)
                        )
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, updateNoticeActionLabel == nil ? 12 : 6)
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .foregroundStyle(updateNoticeTint)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(updateNoticeBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(updateNoticeTint.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isUpdateNoticeEnabled)
        .opacity(isUpdateNoticeEnabled ? 1 : 0.94)
    }

    private var isUpdateNoticeEnabled: Bool {
        if case .available = appState.updateBannerState {
            return true
        }
        return false
    }

    private var updateNoticeIconName: String {
        switch appState.updateBannerState {
        case .available:
            return "arrow.down.circle.fill"
        case .checking:
            return "magnifyingglass"
        case .downloading:
            return "arrow.down.circle"
        case .installing:
            return "gearshape.2.fill"
        case .idle:
            return "arrow.down.circle"
        }
    }

    private var updateNoticeTitle: String {
        switch appState.updateBannerState {
        case .available(let version):
            switch appState.language {
            case .english:
                return "New version \(version) available"
            case .simplifiedChinese:
                return "新版本 \(version) 可用"
            case .traditionalChinese:
                return "新版本 \(version) 可用"
            }
        case .checking:
            switch appState.language {
            case .english:
                return "Checking..."
            case .simplifiedChinese:
                return "检查中..."
            case .traditionalChinese:
                return "檢查中..."
            }
        case .downloading(let progress):
            if let progress {
                let percent = Int((progress * 100).rounded())
                switch appState.language {
                case .english:
                    return "Downloading \(percent)%"
                case .simplifiedChinese:
                    return "下载 \(percent)%"
                case .traditionalChinese:
                    return "下載 \(percent)%"
                }
            }
            switch appState.language {
            case .english:
                return "Downloading..."
            case .simplifiedChinese:
                return "下载中..."
            case .traditionalChinese:
                return "下載中..."
            }
        case .installing:
            switch appState.language {
            case .english:
                return "Installing..."
            case .simplifiedChinese:
                return "安装中..."
            case .traditionalChinese:
                return "安裝中..."
            }
        case .idle:
            return ""
        }
    }

    private var updateNoticeActionLabel: String? {
        guard case .available = appState.updateBannerState else { return nil }
        switch appState.language {
        case .english:
            return "Update"
        case .simplifiedChinese:
            return "更新"
        case .traditionalChinese:
            return "更新"
        }
    }

    private var updateNoticeTint: Color {
        switch appState.updateBannerState {
        case .available:
            return Branding.accentBlueDark
        case .checking, .downloading:
            return Branding.warning
        case .installing:
            return Branding.success
        case .idle:
            return Branding.inkMuted
        }
    }

    private var updateNoticeBackground: Color {
        switch appState.updateBannerState {
        case .available:
            return Branding.accentBlueSoft
        case .checking, .downloading:
            return Branding.warningSoft
        case .installing:
            return Branding.successSoft
        case .idle:
            return Branding.chipSurface
        }
    }

    private var currentFilterTitle: String {
        accountFilter == .all
            ? text.accountFilterAll(count: toolAccounts.count)
            : text.accountFilterAvailable(count: availableAccountCount)
    }

    private func footerFilterOption(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Branding.inkStrong)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Branding.accentBlueDark)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Branding.menuItemSelectedSurface : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text(text.string(.emptyAccountsTitle))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Branding.ink)

            Text(text.string(.emptyAccountsDescription))
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Branding.inkMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 58)
    }

    private var filteredEmptyState: some View {
        VStack(spacing: 8) {
            Text(text.string(.emptyAvailableAccountsTitle))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Branding.inkMuted)

            Text(text.string(.emptyAvailableAccountsDescription))
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(Branding.inkSubtle)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 58)
    }

}

private struct ScrollIndicatorHider: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let view = ScrollIndicatorHidingView()
        view.configureWhenReady()
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        (nsView as? ScrollIndicatorHidingView)?.configureWhenReady()
    }

    private final class ScrollIndicatorHidingView: NSView {
        private weak var configuredScrollView: NSScrollView?
        private var isConfigureScheduled = false

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            configureWhenReady()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWhenReady()
        }

        override func layout() {
            super.layout()
            if configuredScrollView == nil {
                configureWhenReady()
            }
        }

        func configureWhenReady() {
            guard configuredScrollView == nil, !isConfigureScheduled else { return }
            isConfigureScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.configureNearestScrollView()
            }
        }

        private func configureNearestScrollView() {
            isConfigureScheduled = false
            if let scrollView = configuredScrollView {
                configure(scrollView)
                return
            }
            var root: NSView? = self
            while let superview = root?.superview {
                root = superview
            }
            guard let scrollView = findFirstScrollView(in: root ?? self) else {
                return
            }
            configure(scrollView)
            configuredScrollView = scrollView
        }

        private func configure(_ scrollView: NSScrollView) {
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.verticalScroller?.isHidden = true
            scrollView.horizontalScroller?.isHidden = true
            scrollView.verticalScroller = nil
            scrollView.horizontalScroller = nil
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true
            scrollView.drawsBackground = false
            scrollView.backgroundColor = .clear
            scrollView.borderType = .noBorder
            scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
            scrollView.contentView.drawsBackground = false
            scrollView.contentView.backgroundColor = .clear
        }

        private func findFirstScrollView(in view: NSView) -> NSScrollView? {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }
            for subview in view.subviews {
                if let scrollView = findFirstScrollView(in: subview) {
                    return scrollView
                }
            }
            return nil
        }
    }
}
