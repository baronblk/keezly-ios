import SwiftUI

/// What the lesson is asking, while it is being asked.
///
/// A bar rather than a dialogue: the point of the tutorial is that the board
/// underneath is the real game, and a box over it that has to be dismissed
/// before every move would make it something else.
struct LessonBanner: View {
    @Environment(\.boardTheme) private var theme
    @ScaledMetric(relativeTo: .subheadline) private var labelSize: CGFloat = 15

    let lesson: Lesson
    let number: Int
    let total: Int
    /// Leaves this lesson for the next one without doing it.
    var onSkip: () -> Void
    /// Finishes a lesson that only asked to be read.
    var onRead: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Keezly.Spacing.tight) {
            HStack(alignment: .firstTextBaseline, spacing: Keezly.Spacing.small) {
                Text(verbatim: lesson.title)
                    .font(.system(size: labelSize * 1.05, weight: .semibold, design: .rounded))
                Spacer(minLength: Keezly.Spacing.small)
                Text("lesson.counter \(number) \(total)")
                    .font(.system(size: labelSize * 0.8, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .monospacedDigit()
            }

            Text(verbatim: lesson.body)
                .font(.system(size: labelSize * 0.92, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            if let task = lesson.task {
                HStack(alignment: .firstTextBaseline, spacing: Keezly.Spacing.small) {
                    Text(verbatim: task)
                        .font(.system(size: labelSize * 0.95, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Keezly.Spacing.small)
                    Button("lesson.skip", action: onSkip)
                        .font(.system(size: labelSize * 0.85, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("lesson.skip")
                }
            } else {
                // A lesson with nothing to play still has to end somewhere,
                // and the player decides when they have finished looking.
                Button("lesson.read", action: onRead)
                    .font(.system(size: labelSize * 0.95, weight: .semibold, design: .rounded))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, Keezly.Spacing.tight)
                    .accessibilityIdentifier("lesson.read")
            }
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, Keezly.Spacing.regular)
        .padding(.vertical, Keezly.Spacing.medium)
        .frame(maxWidth: 620)
        .background {
            // The dark table, not the board's wood: the text here is light,
            // and light text on light wood is the sort of contrast failure
            // that only shows up on a real screen in real daylight (§53).
            let shape = RoundedRectangle(cornerRadius: Keezly.Radius.panel, style: .continuous)
            shape
                .fill(theme.table.opacity(0.96))
                .overlay(shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lesson")
    }
}

/// What happens when a lesson stops being open: it was done, it became
/// impossible, or it could not be set up at all.
///
/// A card over the board, because each of these ends the lesson and the next
/// thing to do is a decision rather than a move.
struct LessonOutcomeCard: View {
    @Environment(\.boardTheme) private var theme
    @ScaledMetric(relativeTo: .title3) private var titleSize: CGFloat = 21
    @ScaledMetric(relativeTo: .subheadline) private var labelSize: CGFloat = 15

    let lesson: Lesson
    let progress: LessonProgress
    let isLast: Bool
    var onContinue: () -> Void
    var onRestart: () -> Void
    var onFinish: () -> Void

    private var headline: LocalizedStringKey {
        switch progress {
        case .met: "lesson.done"
        case .impossible: "lesson.impossible"
        case .unavailable: "lesson.unavailable"
        case .open: ""
        }
    }

    private var detail: LocalizedStringKey? {
        switch progress {
        case .met: nil
        // Said plainly rather than dressed up as encouragement: the board
        // moved on, nobody did anything wrong, and the lesson can be set up
        // again.
        case .impossible: "lesson.impossible.detail"
        case .unavailable: "lesson.unavailable.detail"
        case .open: nil
        }
    }

    var body: some View {
        VStack(spacing: Keezly.Spacing.large) {
            VStack(spacing: Keezly.Spacing.small) {
                Text(headline)
                    .font(.system(size: titleSize, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("lesson.outcome")
                if let detail {
                    Text(detail)
                        .font(.system(size: labelSize, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
            .foregroundStyle(.white.opacity(0.95))
            .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: Keezly.Spacing.small) {
                if progress != .met {
                    Button("lesson.again", action: onRestart)
                        .buttonStyle(.bordered)
                        .tint(.white)
                        .accessibilityIdentifier("lesson.again")
                }

                Button(isLast && progress == .met ? "lesson.finish" : "lesson.next") {
                    if isLast { onFinish() } else { onContinue() }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("lesson.next")
            }
            .controlSize(.large)
        }
        .padding(Keezly.Spacing.large)
        .frame(maxWidth: 420)
        .background {
            let shape = RoundedRectangle(cornerRadius: Keezly.Radius.panel, style: .continuous)
            shape
                .fill(theme.table.opacity(0.97))
                .overlay(shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 22, y: 8)
        }
        .padding(Keezly.Spacing.large)
    }
}
