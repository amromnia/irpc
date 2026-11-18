import Foundation

@main struct Benchmark {
    static func main() {
        for style in ["vapor", "vortex", "wisps"] {
            let simulation = VaporSimulation(style: style)
            for _ in 0..<105 { simulation.step(1 / 30) }
            var samples: [Double] = []
            var checksum = 0
            for _ in 0..<300 {
                let start = DispatchTime.now().uptimeNanoseconds
                simulation.step(1 / 60)
                let pixels = simulation.rgba(red: 0.59, green: 0.106, blue: 0.169, opacity: 0.4)
                checksum += Int(pixels[1000])
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            }
            samples.sort()
            print("\(style): median \(samples[150]) ms, p95 \(samples[285]) ms, checksum \(checksum)")
        }
    }
}
