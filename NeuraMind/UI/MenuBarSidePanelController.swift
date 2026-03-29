import AppKit
import SwiftUI
import Combine

// MARK: - Menu Bar Side Panel Controller
// Architecture ported from hocus-pocus (https://github.com/saturday-club/hocus-pocus)
// Transparent NSPanel — each GlassCard provides its own backdrop blur.

@MainActor
final class MenuBarSidePanelController: NSObject {

    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var clickMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    var isVisible: Bool { panel?.isVisible ?? false }

    // MARK: - Setup

    func setup() {
        createStatusItem()
        observeCaptureEngine()
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = statusImage(name: "eye.slash")
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    // MARK: - Observe Capture Engine (icon sync)

    private func observeCaptureEngine() {
        guard let engine = ServiceContainer.shared.captureEngine else { return }
        Publishers.CombineLatest3(engine.$state, engine.$isRunning, engine.$isWinking)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state, isRunning, isWinking in
                self?.updateIcon(state: state, isRunning: isRunning, isWinking: isWinking)
            }
            .store(in: &cancellables)
    }

    private func updateIcon(state: CaptureState, isRunning: Bool, isWinking: Bool) {
        let focusSnapshot = FocusStateStore.currentSnapshot(
            storageManager: ServiceContainer.shared.storageManager
        )
        let name: String
        if focusSnapshot.current != nil, focusSnapshot.drift?.level == "drifting" {
            name = "exclamationmark.circle"
        } else if !isRunning {
            name = "eye.slash"
        } else if isWinking {
            name = "eye"
        } else {
            switch state {
            case .recording:     name = "eye.fill"
            case .paused:        name = "eye.slash"
            case .privacyPaused: name = "lock.shield"
            case .sleeping:      name = "moon.fill"
            }
        }
        statusItem?.button?.image = statusImage(name: name)
    }

    private func statusImage(name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: "NeuraMind")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
    }

    // MARK: - Toggle

    @objc nonisolated func handleClick(_ sender: AnyObject?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
            if isRightClick {
                self.showContextMenu()
            } else {
                self.toggle()
            }
        }
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    // MARK: - Show / Hide (hocus-pocus fade approach)

    func show() {
        if panel == nil { createPanel() }
        guard let panel, let screen = NSScreen.main else { return }

        let width: CGFloat = 360
        let margin: CGFloat = 10
        let visible = screen.visibleFrame

        let x = visible.maxX - width - margin
        let y = visible.minY + margin
        let h = visible.height - margin * 2

        panel.setFrame(NSRect(x: x, y: y, width: width, height: h), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }

        setupClickOutsideMonitor()
    }

    func hide() {
        teardownClickOutsideMonitor()
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                panel.alphaValue = 1.0
            }
        })
    }

    // MARK: - Panel Creation

    private func createPanel() {
        let p = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.animationBehavior = .utilityWindow

        // Transparent panel — each GlassCard provides its own backdrop blur
        let content = ScrollView(.vertical, showsIndicators: false) {
            NeuraMindMenuBarPanel()
                .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        let hostingView = NSHostingView(rootView: content)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        p.contentView = hostingView
        self.panel = p
    }

    // MARK: - Click Outside

    private func setupClickOutsideMonitor() {
        teardownClickOutsideMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                if !panel.frame.contains(NSEvent.mouseLocation) {
                    self.hide()
                }
            }
        }
    }

    private func teardownClickOutsideMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    // MARK: - Right-click Context Menu (debug access)

    private func showContextMenu() {
        guard let button = statusItem?.button else { return }
        let menu = NSMenu()

        if let engine = ServiceContainer.shared.captureEngine {
            let item = NSMenuItem(
                title: engine.isRunning ? "Pause Capture" : "Resume Capture",
                action: #selector(toggleCapture),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let enrichItem = NSMenuItem(title: "Enrich Prompt…", action: #selector(openEnrichment), keyEquivalent: "")
        enrichItem.target = self
        menu.addItem(enrichItem)

        let assistantItem = NSMenuItem(title: "Daily Assistant…", action: #selector(openDailyAssistant), keyEquivalent: "")
        assistantItem.target = self
        menu.addItem(assistantItem)

        let debugItem = NSMenuItem(title: "Database Debug…", action: #selector(openDebug), keyEquivalent: "")
        debugItem.target = self
        menu.addItem(debugItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit NeuraMind", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc nonisolated private func toggleCapture() {
        Task { @MainActor in
            guard let engine = ServiceContainer.shared.captureEngine else { return }
            if engine.isRunning { engine.stop() } else { engine.start() }
        }
    }

    @objc nonisolated private func openEnrichment() {
        Task { @MainActor in ServiceContainer.shared.panelController?.toggle() }
    }

    @objc nonisolated private func openDailyAssistant() {
        Task { @MainActor in ServiceContainer.shared.neuraMindController?.toggle() }
    }

    @objc nonisolated private func openDebug() {
        Task { @MainActor in ServiceContainer.shared.debugController?.toggle() }
    }

    @objc nonisolated private func openSettings() {
        Task { @MainActor in NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
    }

    // MARK: - Screen Change

    func handleScreenChange() {
        guard isVisible else { return }
        hide()
    }
}

// MARK: - Panel Card
//
// Uses `.hudWindow` material — always renders dark regardless of system
// appearance or wallpaper, giving consistent contrast for white text.
// Transparent: the desktop blurs through. Inspired by hocus-pocus GlassCard
// but tuned for a menu-bar panel that must be legible in any context.

struct PanelCard<Content: View>: View {
    var cornerRadius: CGFloat = 16
    @ViewBuilder var content: () -> Content
    @State private var isHovered = false

    var body: some View {
        Group {
            if #available(macOS 26, *) {
                content()
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.white.opacity(isHovered ? 0.014 : 0.006))
                    )
                    .shadow(
                        color: .black.opacity(isHovered ? 0.16 : 0.10),
                        radius: isHovered ? 16 : 10, y: 4
                    )
                    .glassEffect(
                        .regular.interactive(),
                        in: .rect(cornerRadius: cornerRadius)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                content()
                    .background(cardBackdrop)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            }
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { isHovered = h } }
    }

    private var cardBackdrop: some View {
        ZStack {
            // Deep behind-window blur — .hudWindow is dark in both light & dark mode
            GaussianBackdropBlur(
                material: .hudWindow,
                blendingMode: .behindWindow,
                intensity: isHovered ? 0.58 : 0.48
            )
            // Subtle lightening tint so the card isn't pitch black
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.white.opacity(isHovered ? 0.06 : 0.035))
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - NeuraMind Menu Bar Panel

struct NeuraMindMenuBarPanel: View {
    private var services: ServiceContainer { .shared }

    @State private var captureCount: Int = 0
    @State private var summaryCount: Int = 0
    @State private var focusScore: FocusScore?
    @State private var currentTask: String?

    var body: some View {
        VStack(spacing: 10) {
            topRow
            actionsCard
            statsCard
            footerRow
        }
        .padding(14)
        .frame(width: 340)
        .onAppear { refresh() }
    }

    // MARK: Top — capture status (wide) + focus ring (square)

    private var topRow: some View {
        HStack(spacing: 10) {
            if let engine = services.captureEngine {
                PanelCard(cornerRadius: 18) {
                    CaptureStatusTile(engine: engine)
                }
            } else {
                PanelCard(cornerRadius: 18) {
                    Text("No capture engine")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(16)
                }
            }

            PanelCard(cornerRadius: 18) {
                FocusRingTile(score: focusScore)
                    .frame(width: 90)
            }
        }
    }

    // MARK: Actions

    private var actionsCard: some View {
        PanelCard(cornerRadius: 18) {
            VStack(spacing: 0) {
                let running = services.captureEngine?.isRunning == true
                PanelRow(
                    icon: running ? "pause.fill" : "play.fill",
                    label: running ? "Pause Capture" : "Resume Capture"
                ) {
                    guard let e = services.captureEngine else { return }
                    if e.isRunning { e.stop() } else { e.start() }
                }

                CardDivider()

                PanelRow(icon: "sparkle.magnifyingglass", label: "Enrich Prompt") {
                    services.panelController?.toggle(); dismissPanel()
                }

                CardDivider()

                PanelRow(icon: "brain.head.profile", label: "Daily Assistant") {
                    services.neuraMindController?.toggle(); dismissPanel()
                }

                CardDivider()

                PanelRow(icon: "ladybug", label: "Database") {
                    services.debugController?.toggle(); dismissPanel()
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: Stats

    private var statsCard: some View {
        PanelCard(cornerRadius: 18) {
            HStack(spacing: 0) {
                StatBlock(value: captureCount, label: "Captures")

                Rectangle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 0.5, height: 36)

                StatBlock(value: summaryCount, label: "Summaries")
            }
            .padding(.vertical, 16)
        }
    }

    // MARK: Footer — Settings / Quit

    private var footerRow: some View {
        HStack(spacing: 10) {
            PanelCard(cornerRadius: 16) {
                FooterButton(icon: "gearshape.fill", label: "Settings") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    dismissPanel()
                }
            }
            PanelCard(cornerRadius: 16) {
                FooterButton(icon: "power", label: "Quit", isDestructive: true) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    // MARK: Helpers

    private func refresh() {
        focusScore = services.focusScoreEngine?.currentScore
        let snap = FocusStateStore.currentSnapshot(storageManager: services.storageManager)
        currentTask = snap.current?.task
        captureCount = (try? services.storageManager?.captureCount24h()) ?? 0
        summaryCount = (try? services.storageManager?.summaryCount24h()) ?? 0
    }

    private func dismissPanel() {
        Task { @MainActor in
            (NSApp.delegate as? AppDelegate)?.menuBarController?.hide()
        }
    }
}

// MARK: - Capture Status Tile

struct CaptureStatusTile: View {
    @ObservedObject var engine: CaptureEngine

    var body: some View {
        HStack(spacing: 14) {
            // Icon — no animation on the Image itself to prevent flicker.
            // Only the background circle pulses gently when recording.
            ZStack {
                Circle()
                    .fill(stateColor.opacity(0.2))
                    .frame(width: 40, height: 40)

                Image(systemName: iconName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(stateColor)
                    // Lock the symbol's identity so SwiftUI doesn't
                    // cross-fade when the name changes mid-render.
                    .contentTransition(.identity)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("NeuraMind")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)

                HStack(spacing: 5) {
                    Circle()
                        .fill(stateColor)
                        .frame(width: 6, height: 6)
                    Text(statusLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture {
            if engine.isRunning { engine.stop() } else { engine.start() }
        }
    }

    private var stateColor: Color {
        guard engine.isRunning else { return .gray }
        switch engine.state {
        case .recording:     return .green
        case .paused:        return .gray
        case .privacyPaused: return .orange
        case .sleeping:      return .cyan
        }
    }

    private var iconName: String {
        guard engine.isRunning else { return "eye.slash" }
        switch engine.state {
        case .recording:     return "eye.fill"
        case .paused:        return "eye.slash"
        case .privacyPaused: return "lock.shield.fill"
        case .sleeping:      return "moon.fill"
        }
    }

    private var statusLabel: String {
        guard engine.isRunning else { return "Paused" }
        switch engine.state {
        case .recording:     return "Recording"
        case .paused:        return "Paused"
        case .privacyPaused: return "Privacy"
        case .sleeping:      return "Sleeping"
        }
    }
}

// MARK: - Focus Ring Tile

struct FocusRingTile: View {
    let score: FocusScore?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 4)
                    .frame(width: 40, height: 40)

                if let score {
                    Circle()
                        .trim(from: 0, to: CGFloat(score.value))
                        .stroke(
                            ringColor(for: score),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 40, height: 40)
                        .rotationEffect(.degrees(-90))

                    Text("\(Int(score.value * 100))")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "brain")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            Text("Focus")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(0.3)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }

    private func ringColor(for score: FocusScore) -> Color {
        if score.value >= 0.7 { return .green }
        if score.value >= 0.4 { return .yellow }
        return .orange
    }
}

// MARK: - Panel Row

struct PanelRow: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(isHovered ? 0.95 : 0.55))
                    .frame(width: 20, alignment: .center)

                Text(label)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(isHovered ? 1.0 : 0.85))

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.25))
                    .opacity(isHovered ? 1 : 0)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(isHovered ? 0.08 : 0))
                    .padding(.horizontal, 4)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { isHovered = h } }
    }
}

// MARK: - Card Divider

struct CardDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }
}

// MARK: - Stat Block

struct StatBlock: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Footer Button

struct FooterButton: View {
    let icon: String
    let label: String
    var isDestructive: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(
                isDestructive
                    ? (isHovered ? Color.red : .white.opacity(0.5))
                    : (isHovered ? Color.white : .white.opacity(0.5))
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { isHovered = h } }
    }
}
