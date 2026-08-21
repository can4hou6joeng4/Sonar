import SwiftUI

struct PlayingEqualizer: View {
    var isAnimating: Bool
    var color: Color

    @Environment(\.sonarReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isAnimating || reduceMotion)) { timeline in
            HStack(alignment: .bottom, spacing: 2.2) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: 2.6, height: height(for: index, at: timeline.date))
                }
            }
        }
        .frame(width: 14, height: 16, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private func height(for index: Int, at date: Date) -> CGFloat {
        guard isAnimating, !reduceMotion else { return [7, 13, 9][index] }
        let phase = [0.0, 2.1, 4.2][index]
        let wave = (sin(date.timeIntervalSinceReferenceDate / 0.92 * 2 * .pi + phase) + 1) / 2
        let base = [6.0, 7.0, 5.0][index]
        let range = [5.0, 7.0, 6.0][index]
        return base + range * wave
    }
}
