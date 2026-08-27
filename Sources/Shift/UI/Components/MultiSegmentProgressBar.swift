import SwiftUI

public struct MultiSegmentProgressBar: View {
    public let segments: [DownloadSegment]
    public let height: CGFloat
    public let isAnimated: Bool

    public init(segments: [DownloadSegment], height: CGFloat = 8, isAnimated: Bool = true) {
        self.segments = segments
        self.height = height
        self.isAnimated = isAnimated
    }

    public var body: some View {
        GeometryReader { proxy in
            let totalWidth = proxy.size.width
            let totalFileBytes = segments.reduce(0) { max($0, $1.endOffset + 1) }

            HStack(spacing: 2) {
                if segments.isEmpty || totalFileBytes <= 0 {
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(Color.tertiarySystemFillColor)
                } else {
                    ForEach(segments) { segment in
                        let segFraction = totalFileBytes > 0 ? CGFloat(segment.totalBytes) / CGFloat(totalFileBytes) : 1.0 / CGFloat(segments.count)
                        let segWidth = max(2, (totalWidth - CGFloat(segments.count - 1) * 2) * segFraction)

                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.tertiarySystemFillColor)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(segmentFillColor(for: segment))
                                .frame(width: max(0, segWidth * CGFloat(segment.progress)))
                        }
                        .frame(width: segWidth, height: height)
                    }
                }
            }
        }
        .frame(height: height)
    }

    private func segmentFillColor(for segment: DownloadSegment) -> Color {
        switch segment.status {
        case .completed:
            return .green
        case .downloading:
            return .blue
        case .connecting:
            return .orange
        case .paused:
            return .secondary
        case .failed:
            return .red
        case .pending:
            return Color.systemFillColor
        }
    }
}

public struct DetailedSegmentGridView: View {
    public let segments: [DownloadSegment]

    public init(segments: [DownloadSegment]) {
        self.segments = segments
    }

    private let columns = [
        GridItem(.adaptive(minimum: 76), spacing: 8)
    ]

    public var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(segments) { seg in
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(seg.status == .completed ? Color.green : (seg.status == .downloading ? Color.blue : Color.secondary))
                            .frame(width: 6, height: 6)
                        Text("T\(seg.index + 1)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(Int(seg.progress * 100))%")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    ProgressView(value: seg.progress)
                        .progressViewStyle(.linear)
                        .tint(seg.status == .completed ? .green : .blue)
                        .scaleEffect(x: 1, y: 0.8, anchor: .center)
                }
                .padding(8)
                .background(Color.secondaryGroupedBg)
                .cornerRadius(8)
            }
        }
    }
}
