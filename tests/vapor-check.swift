import Foundation

@main
struct VaporCheck {
    static func main() {
        let start = Date()
        var outputs: [[UInt8]] = []
        for style in ["vapor", "vortex", "wisps"] {
            let simulation = VaporSimulation(style: style)
            for _ in 0..<105 { simulation.step(1 / 30) }
            let first = simulation.rgba(red: 0.59, green: 0.106, blue: 0.169, opacity: 0.4)
            for _ in 0..<60 { simulation.step(1 / 30) }
            let second = simulation.rgba(red: 0.59, green: 0.106, blue: 0.169, opacity: 0.4)
            precondition(first != second, "Vapor must evolve rather than repeat a still image")
            precondition(second.count == 80 * 152 * 4)
            precondition(second.enumerated().contains { $0.offset % 4 == 3 && $0.element > 0 })
            for k in stride(from: 0, to: second.count, by: 4) {
                let alpha = second[k + 3]
                precondition(alpha <= 102)
                precondition(second[k] <= alpha && second[k + 1] <= alpha && second[k + 2] <= alpha,
                             "CGImage expects premultiplied alpha")
                precondition(second[k + 1] <= 11 && second[k + 2] <= 18, "No white highlights")
            }
            simulation.step(.nan)
            simulation.step(0)
            precondition(second == simulation.rgba(red: 0.59, green: 0.106, blue: 0.169, opacity: 0.4))
            let clear = simulation.rgba(red: 1, green: 1, blue: 1, opacity: 0)
            precondition(clear.allSatisfy { $0 == 0 })
            for _ in 0..<1200 { simulation.step(0.05) }
            let steady = simulation.rgba(red: 0.59, green: 0.106, blue: 0.169, opacity: 0.4)
            precondition(steady != second, "The flow must continue evolving after a minute")
            precondition(steady.enumerated().contains { $0.offset % 4 == 3 && $0.element > 0 })
            outputs.append(steady)
        }
        precondition(outputs[0] != outputs[1] && outputs[1] != outputs[2])
        print("PASS: three evolving fluids, pause, alpha, dark tint, and zero opacity (\(Date().timeIntervalSince(start))s)")
    }
}
