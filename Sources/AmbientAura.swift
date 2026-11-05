import SwiftUI

/// What the assistant is doing, as far as the background is concerned.
enum AuraMode: Equatable {
    case idle
    case thinking
    case writing
    case listening
}

/// The living background: three soft lights drifting behind the transcript, drawn on a
/// Canvas so the cost stays flat no matter how long the conversation gets. The lights
/// answer the state of the app — they speed up while an answer is being written and go
/// cyan while the microphone is open. With Reduce Motion on, it is a still gradient.
struct AmbientAura: View {
    var mode: AuraMode = .idle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// Egyszer legyártott szemcse. A lágy gradiensek sávosodnak a kijelzőn; egy 3%-os
    /// zajréteg eltünteti, és mivel statikus kép, nem kerül semmibe.
    private static let grain: Image? = {
        let side = 128
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let v = UInt8.random(in: 0...255)
            pixels[i] = v; pixels[i + 1] = v; pixels[i + 2] = v
            pixels[i + 3] = UInt8.random(in: 0...26)
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cg = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false,
                               intent: .defaultIntent) else { return nil }
        return Image(decorative: cg, scale: 1)
    }()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if reduceMotion || lowPower || scenePhase != .active {
                    // Nem látszik senkinek, nem mozog, nem fogyaszt: állókép, ugyanaz a hangulat.
                    still(size: geo.size)
                } else {
                    // 20 kép/másodperc elég a lassú fényekhez (24 helyett), és a Canvas csak
                    // akkor rajzol, amikor tényleg a képernyőn van a beszélgetés.
                    TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                        Canvas { context, size in
                            paint(&context, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
                        }
                    }
                }
                if let grain = Self.grain {
                    grain
                        .resizable(resizingMode: .tile)
                        .opacity(0.5)
                        .blendMode(.overlay)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Palette

    private var palette: [Color] {
        switch mode {
        case .idle: return [Theme.violet, Theme.cyan, Theme.magenta]
        case .thinking: return [Theme.violet, Theme.magenta, Theme.violetSoft]
        case .writing: return [Theme.cyan, Theme.violet, Theme.violetSoft]
        case .listening: return [Theme.cyan, Theme.success, Theme.cyan]
        }
    }

    private var speed: Double {
        switch mode {
        case .idle: return 0.16
        case .thinking: return 0.34
        case .writing: return 0.26
        case .listening: return 0.5
        }
    }

    private var strength: Double {
        switch mode {
        case .idle: return 0.30
        case .thinking: return 0.42
        case .writing: return 0.38
        case .listening: return 0.44
        }
    }

    // MARK: Drawing

    private func paint(_ context: inout GraphicsContext, size: CGSize, time: Double) {
        let t = time * speed
        let colors = palette
        context.blendMode = .plusLighter

        let blobs: [(x: Double, y: Double, r: Double)] = [
            (0.28 + 0.16 * sin(t), 0.20 + 0.10 * cos(t * 1.3), 0.62),
            (0.78 + 0.12 * cos(t * 0.9), 0.42 + 0.14 * sin(t * 1.1), 0.52),
            (0.46 + 0.20 * sin(t * 0.7 + 1.2), 0.86 + 0.08 * cos(t * 0.8), 0.58)
        ]

        for (index, blob) in blobs.enumerated() {
            let color = colors[index % colors.count]
            let center = CGPoint(x: blob.x * size.width, y: blob.y * size.height)
            let radius = blob.r * min(size.width, size.height) * (0.9 + 0.06 * sin(t + Double(index)))

            // Két réteg: a széles, halvány fény adja a mélységet, a szűk, erős a magot.
            // Egyetlen gradiensnél a fény „korongnak" látszik; így olvad.
            for layer in 0..<2 {
                let r = layer == 0 ? radius * 1.45 : radius * 0.72
                let alpha = layer == 0 ? strength * 0.42 : strength
                let gradient = Gradient(stops: [
                    .init(color: color.opacity(alpha), location: 0),
                    .init(color: color.opacity(alpha * 0.42), location: 0.5),
                    .init(color: color.opacity(0), location: 1)
                ])
                let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                context.fill(
                    Path(ellipseIn: rect),
                    with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: r)
                )
            }
        }
    }

    private func still(size: CGSize) -> some View {
        ZStack {
            RadialGradient(colors: [Theme.violet.opacity(0.22), .clear], center: .topLeading, startRadius: 0, endRadius: size.width * 0.9)
            RadialGradient(colors: [Theme.cyan.opacity(0.14), .clear], center: .bottomTrailing, startRadius: 0, endRadius: size.width * 0.8)
        }
        .ignoresSafeArea()
    }
}
