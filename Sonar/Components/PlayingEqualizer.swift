import SwiftUI

struct PlayingEqualizer: View {
    var isAnimating: Bool
    var color: Color

    @Environment(\.sonarReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isAnimating || reduceMotion)) { timeline in
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: 2, height: height(for: index, at: timeline.date))
                }
            }
        }
        .frame(width: 9, height: 11, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private func height(for index: Int, at date: Date) -> CGFloat {
        guard isAnimating, !reduceMotion else { return [5, 10, 7][index] }
        let phase = [0.0, 2.1, 4.2][index]
        let wave = (sin(date.timeIntervalSinceReferenceDate / 0.9 * 2 * .pi + phase) + 1) / 2
        let base = [3.3, 4.0, 3.3][index]
        let range = [7.7, 7.0, 7.7][index]
        return base + range * wave
    }
}
