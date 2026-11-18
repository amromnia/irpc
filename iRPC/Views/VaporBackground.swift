import SwiftUI
import UIKit

struct VaporBackground: UIViewRepresentable {
    let style: String
    let color: Color
    let opacity: Double
    let speed: Double
    let moving: Bool

    func makeUIView(context: Context) -> VaporCanvas { VaporCanvas() }
    func updateUIView(_ view: VaporCanvas, context: Context) {
        view.configure(style: style, color: UIColor(color), opacity: opacity, speed: speed, moving: moving)
    }
    static func dismantleUIView(_ view: VaporCanvas, coordinator: ()) { view.stop() }
}

/// Serial ownership keeps the fluid solver and image creation off the UI thread.
private final class VaporWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "afterglow.vapor", qos: .utility)
    private var simulation: VaporSimulation?
    func render(style: String, delta: Float, rgba: SIMD4<Float>, completion: @escaping @Sendable (CGImage?) -> Void) {
        queue.async {
            if self.simulation?.style != style {
                self.simulation = VaporSimulation(style: style)
                for _ in 0..<105 { self.simulation?.step(1 / 30) }
            }
            guard let simulation = self.simulation else { completion(nil); return }
            simulation.step(delta)
            let pixels = simulation.rgba(red: rgba.x, green: rgba.y, blue: rgba.z, opacity: rgba.w)
            let data = Data(pixels) as CFData
            let provider = CGDataProvider(data: data)
            let image = provider.flatMap {
                CGImage(width: VaporSimulation.width, height: VaporSimulation.height, bitsPerComponent: 8,
                        bitsPerPixel: 32, bytesPerRow: VaporSimulation.width * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                        provider: $0, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
            }
            completion(image)
        }
    }
}

final class VaporCanvas: UIView {
    private let worker = VaporWorker()
    private var link: CADisplayLink?
    private var busy = false
    private var style = "wisps"
    private var rgba = SIMD4<Float>(0.59, 0.106, 0.169, 0.4)
    private var speed: Float = 1 / 1.3
    private var moving = true
    private var dirty = true
    private var lastTime: CFTimeInterval = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        layer.contentsGravity = .resize
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    func configure(style: String, color: UIColor, opacity: Double, speed: Double, moving: Bool) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let rgba = SIMD4<Float>(Float(r), Float(g), Float(b), Float(max(0, min(0.65, opacity))))
        dirty = dirty || self.style != style || self.rgba != rgba
        self.style = style
        self.rgba = rgba
        self.speed = Float(max(0.25, min(1.5, speed)))
        self.moving = moving
        link?.preferredFramesPerSecond = ProcessInfo.processInfo.isLowPowerModeEnabled ? 8 : 24
        link?.isPaused = !moving && !dirty
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() }
        else if link == nil {
            let link = CADisplayLink(target: self, selector: #selector(drawFrame(_:)))
            link.preferredFramesPerSecond = ProcessInfo.processInfo.isLowPowerModeEnabled ? 8 : 24
            link.add(to: .main, forMode: .common)
            self.link = link
        }
    }

    func stop() { link?.invalidate(); link = nil; lastTime = 0 }

    @objc private func drawFrame(_ displayLink: CADisplayLink) {
        guard !busy else { return }
        guard moving || dirty else { displayLink.isPaused = true; return }
        busy = true
        dirty = false
        let elapsed = lastTime == 0 ? 1.0 / 24 : min(0.075, displayLink.timestamp - lastTime)
        lastTime = displayLink.timestamp
        let requestedStyle = style
        worker.render(style: style, delta: moving ? Float(elapsed) * speed : 0, rgba: rgba) { [weak self] image in
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                guard self.window != nil, self.style == requestedStyle else { return }
                self.layer.contents = image
            }
        }
    }
}
