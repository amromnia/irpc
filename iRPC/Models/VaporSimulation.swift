import Foundation

/// The same density-advection/pressure solver used by the motion preview.
/// One worker owns each instance; no audio or background execution is involved.
final class VaporSimulation {
    static let width = 80
    static let height = 152
    private let width = VaporSimulation.width
    private let height = VaporSimulation.height
    private var u = [Float](repeating: 0, count: VaporSimulation.width * VaporSimulation.height)
    private var v = [Float](repeating: 0, count: VaporSimulation.width * VaporSimulation.height)
    private var density = [Float](repeating: 0, count: VaporSimulation.width * VaporSimulation.height)
    private var nextU = [Float](repeating: 0, count: VaporSimulation.width * VaporSimulation.height)
    private var nextV = [Float](repeating: 0, count: VaporSimulation.width * VaporSimulation.height)
    private var nextDensity = [Float](repeating: 0, count: VaporSimulation.width * VaporSimulation.height)
    private var pressure = [Float](repeating: 0, count: VaporSimulation.width * VaporSimulation.height)
    private var nextPressure = [Float](repeating: 0, count: VaporSimulation.width * VaporSimulation.height)
    private var divergence = [Float](repeating: 0, count: VaporSimulation.width * VaporSimulation.height)
    private var curl = [Float](repeating: 0, count: VaporSimulation.width * VaporSimulation.height)
    private var time: Float = 0
    let style: String

    init(style: String) { self.style = style }

    @inline(__always)
    private func sample(_ field: [Float], _ x: Float, _ y: Float) -> Float {
        let x = max(0.5, min(Float(width) - 1.5, x))
        let y = max(0.5, min(Float(height) - 1.5, y))
        let ix = Int(x), iy = Int(y), fx = x - Float(ix), fy = y - Float(iy)
        let k = iy * width + ix
        return (field[k] * (1 - fx) + field[k + 1] * fx) * (1 - fy)
            + (field[k + width] * (1 - fx) + field[k + width + 1] * fx) * fy
    }

    private func source(x: Float, y: Float, radius: Float, amount: Float, dx: Float, dy: Float, dt: Float) {
        let minY = max(1, Int(y - radius * 3)), maxY = min(height - 1, Int(ceil(y + radius * 3)))
        let minX = max(1, Int(x - radius * 3)), maxX = min(width - 1, Int(ceil(x + radius * 3)))
        for j in minY..<maxY {
            for i in minX..<maxX {
                let k = j * width + i
                let ax = Float(i) - x, ay = Float(j) - y
                let g = exp(-(ax * ax + ay * ay) / (2 * radius * radius)) * dt
                density[k] = min(2, density[k] + amount * g)
                u[k] += dx * g
                v[k] += dy * g
            }
        }
    }

    func step(_ delta: Float) {
        guard delta.isFinite, delta > 0 else { return }
        let dt = min(delta, 0.05)
        time += dt
        let thin = style == "wisps", vortex = style == "vortex"
        let radius: Float = thin ? 2.3 : 4.5
        source(x: Float(width) * (0.18 + 0.06 * sin(time * 0.7)), y: Float(height) * 0.94,
               radius: radius, amount: 1.5, dx: 12 * sin(time * 1.1), dy: -65, dt: dt)
        source(x: Float(width) * (0.84 + 0.04 * cos(time * 0.6)), y: Float(height) * 0.81,
               radius: radius, amount: 1.2, dx: -15 * cos(time * 0.8), dy: -55, dt: dt)
        source(x: Float(width) * 0.08, y: Float(height) * (0.55 + 0.05 * sin(time * 0.5)),
               radius: radius * 0.8, amount: 0.65, dx: 14, dy: -22, dt: dt)
        for y in 1..<height - 1 {
            for x in 1..<width - 1 {
                let k = y * width + x
                v[k] -= dt * (thin ? 19 : 12) * density[k]
                u[k] += dt * 5 * sin(Float(y) * 0.12 + time * 0.9) * cos(Float(x) * 0.1 - time * 0.4)
                v[k] += dt * 3 * cos(Float(y) * 0.12 + time * 0.9) * sin(Float(x) * 0.1 - time * 0.4)
                if vortex {
                    let dx = (Float(x) - Float(width) * 0.5) / Float(width)
                    let dy = (Float(y) - Float(height) * 0.6) / Float(width)
                    let distance = (hypot(dx, dy) - 0.27) / 0.18
                    let ring = exp(-distance * distance)
                    u[k] -= dt * dy * ring * 140
                    v[k] += dt * dx * ring * 140
                }
                curl[k] = (v[k + 1] - v[k - 1] - u[k + width] + u[k - width]) * 0.5
            }
        }
        for y in 2..<height - 2 {
            for x in 2..<width - 2 {
                let k = y * width + x
                let gx = (abs(curl[k + 1]) - abs(curl[k - 1])) * 0.5
                let gy = (abs(curl[k + width]) - abs(curl[k - width])) * 0.5
                let norm = hypot(gx, gy) + 0.0001
                let force = (thin ? Float(9) : 6) * curl[k] * dt
                u[k] += gy / norm * force
                v[k] -= gx / norm * force
            }
        }
        for y in 1..<height - 1 {
            for x in 1..<width - 1 {
                let k = y * width + x
                let px = Float(x) - dt * u[k], py = Float(y) - dt * v[k]
                nextU[k] = sample(u, px, py) * 0.997
                nextV[k] = sample(v, px, py) * 0.997
            }
        }
        swap(&u, &nextU)
        swap(&v, &nextV)
        pressure.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
        for y in 1..<height - 1 {
            for x in 1..<width - 1 {
                let k = y * width + x
                divergence[k] = (u[k + 1] - u[k - 1] + v[k + width] - v[k - width]) * 0.5
            }
        }
        for _ in 0..<12 {
            for y in 1..<height - 1 {
                for x in 1..<width - 1 {
                    let k = y * width + x
                    nextPressure[k] = (pressure[k - 1] + pressure[k + 1] + pressure[k - width]
                        + pressure[k + width] - divergence[k]) * 0.25
                }
            }
            swap(&pressure, &nextPressure)
        }
        let decay = exp(-dt * (thin ? Float(0.22) : 0.16))
        for y in 1..<height - 1 {
            for x in 1..<width - 1 {
                let k = y * width + x
                u[k] -= (pressure[k + 1] - pressure[k - 1]) * 0.5
                v[k] -= (pressure[k + width] - pressure[k - width]) * 0.5
                nextDensity[k] = sample(density, Float(x) - dt * u[k], Float(y) - dt * v[k]) * decay
            }
        }
        swap(&density, &nextDensity)
    }

    func rgba(red: Float, green: Float, blue: Float, opacity: Float) -> [UInt8] {
        let channels = [red, green, blue].map { $0.isFinite ? max(0, min(1, $0)) : 0 }
        let opacity = opacity.isFinite ? max(0, min(1, opacity)) : 0
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for k in density.indices {
            let shade = 0.72 + 0.28 * min(1, abs(curl[k]) * 0.036)
            let alpha = max(0, min(1, (1 - exp(-max(0, density[k]) * 2.8)) * opacity))
            // Premultiplied alpha; tint is darkened, never mixed with white.
            for channel in 0..<3 { pixels[k * 4 + channel] = UInt8(channels[channel] * shade * alpha * 255) }
            pixels[k * 4 + 3] = UInt8(alpha * 255)
        }
        return pixels
    }
}
