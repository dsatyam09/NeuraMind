import AppKit
import QuartzCore

// Ported from hocus-pocus (https://github.com/saturday-club/hocus-pocus)
// Custom NSVisualEffectView that applies a configurable Gaussian blur radius
// to the layer tree — the system's default blur radius is fixed and too shallow.
final class BlurView: NSVisualEffectView {

    private var customBlurRadius: CGFloat = 30.0
    private var isObservingLayers = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    private func configure() {
        blendingMode = .behindWindow
        material = .hudWindow
        state = .active
        autoresizingMask = [.width, .height]
    }

    func updateIntensity(_ amount: Double) {
        updateAppearance(amount: amount, opacity: nil)
    }

    func updateAppearance(amount: Double, opacity: Double?) {
        let clamped = CGFloat(min(max(amount, 0), 1))
        customBlurRadius = 15.0 + clamped * 35.0

        if let opacity {
            alphaValue = CGFloat(min(max(opacity, 0), 1))
        } else {
            alphaValue = 0.7 + clamped * 0.3
        }
        applyCustomBlurRadius()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.applyCustomBlurRadius()
            self?.startObservingLayers()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.applyCustomBlurRadius()
        }
    }

    private func applyCustomBlurRadius() {
        guard let rootLayer = layer else { return }
        applyBlurToLayerTree(rootLayer)
    }

    private func applyBlurToLayerTree(_ layer: CALayer) {
        if let filters = layer.filters {
            for case let filter as NSObject in filters {
                applyRadiusIfBlurFilter(filter)
            }
        }
        if let bgFilters = layer.backgroundFilters {
            for case let filter as NSObject in bgFilters {
                applyRadiusIfBlurFilter(filter)
            }
        }
        for sublayer in layer.sublayers ?? [] {
            applyBlurToLayerTree(sublayer)
        }
    }

    private func applyRadiusIfBlurFilter(_ filter: NSObject) {
        let sel = NSSelectorFromString("setValue:forKey:")
        guard filter.responds(to: sel) else { return }
        if filter.responds(to: NSSelectorFromString("inputRadius"))
            || filter.responds(to: NSSelectorFromString("valueForKey:"))
        {
            if (filter as AnyObject).value(forKey: "inputRadius") as? NSNumber != nil {
                filter.setValue(NSNumber(value: Float(customBlurRadius)), forKey: "inputRadius")
            } else {
                filter.setValue(NSNumber(value: Float(customBlurRadius)), forKey: "inputRadius")
            }
        }
    }

    private func startObservingLayers() {
        guard !isObservingLayers, let rootLayer = layer else { return }
        isObservingLayers = true
        rootLayer.addObserver(self, forKeyPath: "sublayers", options: [.new], context: nil)
    }

    // swiftlint:disable:next block_based_kvo
    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if keyPath == "sublayers" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.applyCustomBlurRadius()
            }
        }
    }
}
