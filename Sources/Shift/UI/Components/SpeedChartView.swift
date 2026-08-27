import SwiftUI

public struct SpeedChartView: View {
    public let history: [DownloadSpeedSample]
    public let currentSpeed: Int64
    public let height: CGFloat

    public init(history: [DownloadSpeedSample], currentSpeed: Int64, height: CGFloat = 100) {
        self.history = history
        self.currentSpeed = currentSpeed
        self.height = height
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Live Speed Graph", systemImage: "waveform.path.ecg")
                    .font(.footnote)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Spacer()

                Text(ByteCountFormatter.formatSpeed(bytesPerSecond: currentSpeed))
                    .font(.system(.footnote, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }

            GeometryReader { geometry in
                let width = max(1, geometry.size.width)
                let height = max(1, geometry.size.height)
                let samples = Array(history.suffix(30))
                let maxSpeed = max(1024 * 100, samples.map { $0.bytesPerSecond }.max() ?? 1024 * 100)

                if samples.count < 2 {
                    // Empty state line
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: height - 2))
                        path.addLine(to: CGPoint(x: width, y: height - 2))
                    }
                    .stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                } else {
                    let count = CGFloat(samples.count)
                    let points: [CGPoint] = samples.enumerated().map { index, sample in
                        let x = width * (CGFloat(index) / max(1.0, count - 1.0))
                        let yFraction = min(1.0, max(0.0, CGFloat(sample.bytesPerSecond) / CGFloat(maxSpeed)))
                        let y = height - (height * yFraction)
                        return CGPoint(x: x, y: max(4, min(height - 4, y)))
                    }

                    // Background Gradient Fill
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: height))
                        for point in points {
                            path.addLine(to: point)
                        }
                        path.addLine(to: CGPoint(x: width, y: height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.25), Color.blue.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // Foreground Line
                    Path { path in
                        guard let first = points.first else { return }
                        path.move(to: first)
                        for i in 1..<points.count {
                            let p0 = points[i - 1]
                            let p1 = points[i]
                            let midPoint = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
                            path.addQuadCurve(to: p1, control: midPoint)
                        }
                    }
                    .stroke(
                        LinearGradient(
                            colors: [Color.blue, Color.cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 2.0
                    )
                }
            }
            .frame(height: height)
        }
        .padding(12)
        .background(Color.secondaryGroupedBg)
        .cornerRadius(10)
    }
}
