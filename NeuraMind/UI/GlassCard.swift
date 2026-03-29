import AppKit
import SwiftUI

// Ported from hocus-pocus (https://github.com/saturday-club/hocus-pocus)

// MARK: - Glass Card

/// Glass-morphism card container. Pre-macOS 26: Gaussian backdrop blur + gradient border.
/// macOS 26+: native .glassEffect API with reflective border and sheen.
struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let baseFillOpacity: Double
    let hoverFillOpacity: Double
    let baseSheenOpacity: Double
    let hoverSheenOpacity: Double
    @ViewBuilder let content: Content
    @State private var isHovered = false

    init(
        cornerRadius: CGFloat = 22,
        baseFillOpacity: Double = 0.006,
        hoverFillOpacity: Double = 0.014,
        baseSheenOpacity: Double = 0.02,
        hoverSheenOpacity: Double = 0.045,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.baseFillOpacity = baseFillOpacity
        self.hoverFillOpacity = hoverFillOpacity
        self.baseSheenOpacity = baseSheenOpacity
        self.hoverSheenOpacity = hoverSheenOpacity
        self.content = content()
    }

    var body: some View {
        Group {
            if #available(macOS 26, *) {
                content
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.white.opacity(isHovered ? hoverFillOpacity : baseFillOpacity))
                    )
                    .overlay { reflectiveGlassBorder }
                    .overlay(alignment: .top) { clearGlassSheen }
                    .shadow(
                        color: .black.opacity(isHovered ? 0.12 : 0.08),
                        radius: isHovered ? 18 : 14,
                        y: 4
                    )
                    .glassEffect(
                        .clear.interactive(),
                        in: .rect(cornerRadius: cornerRadius)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                content
                    .background { cardBackdrop }
                    .overlay { cardOutline }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var cardBackdrop: some View {
        ZStack {
            GaussianBackdropBlur(
                material: .popover,
                blendingMode: .behindWindow,
                intensity: isHovered ? 0.55 : 0.46
            )
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.white.opacity(isHovered ? 0.035 : 0.018))
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var cardOutline: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        .white.opacity(isHovered ? 0.22 : 0.14),
                        .white.opacity(0.05),
                        .white.opacity(isHovered ? 0.14 : 0.1),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.75
            )
    }

    private var clearGlassSheen: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        .white.opacity(isHovered ? hoverSheenOpacity : baseSheenOpacity),
                        .white.opacity(0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: 16)
            .blur(radius: 6)
            .mask(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var reflectiveGlassBorder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        .white.opacity(isHovered ? 0.34 : 0.22),
                        .white.opacity(0.08),
                        .white.opacity(isHovered ? 0.18 : 0.12),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.85
            )
    }
}

// MARK: - Visual Effect Blur

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Gaussian Backdrop Blur

struct GaussianBackdropBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let intensity: Double

    func makeNSView(context: Context) -> BlurView {
        let view = BlurView(frame: .zero)
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = false
        view.updateIntensity(intensity)
        return view
    }

    func updateNSView(_ nsView: BlurView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.updateIntensity(intensity)
    }
}

// MARK: - Custom Strip Blur

struct CustomStripBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let intensity: Double
    let opacity: Double

    func makeNSView(context: Context) -> BlurView {
        let view = BlurView(frame: .zero)
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = false
        view.updateAppearance(amount: intensity, opacity: opacity)
        return view
    }

    func updateNSView(_ nsView: BlurView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.updateAppearance(amount: intensity, opacity: opacity)
    }
}
