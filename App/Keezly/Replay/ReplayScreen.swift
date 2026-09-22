import KeezlyCore
import SwiftUI

/// A match, watched back.
///
/// The same board the match was played on, driven by `ReplayRun` instead of by
/// a player. There is no hand and nothing to tap on the board: a replay is
/// something to watch, and offering a move that cannot be made would be a
/// worse kind of dead control than a greyed-out button (§36).
struct ReplayScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var labelSize: CGFloat = 15

    private let theme = BoardTheme.classicWood

    @State private var replay: ReplayRun
    @State private var presenter: BoardPresenter
    @State private var presentation: Task<Void, Never>?
    var onLeave: () -> Void

    init(replay: ReplayRun, onLeave: @escaping () -> Void = {}) {
        _replay = State(initialValue: replay)
        _presenter = State(initialValue: BoardPresenter(pawns: replay.state.pawns))
        self.onLeave = onLeave
    }

    private var layout: BoardLayout { BoardLayout(board: replay.state.board) }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ZStack {
                    theme.table.ignoresSafeArea()

                    VStack(spacing: Keezly.Spacing.small) {
                        header
                        ZStack {
                            BoardView(
                                layout: layout,
                                pawns: presenter.displayedPawns,
                                emphasised: presenter.emphasised,
                                narration: PlayerObservation(of: replay.state, for: replay.state.currentSeat)
                            )

                            // The card that was played is most of what makes a
                            // replay legible: without it the pieces move for
                            // no visible reason.
                            if layout.centrePlacement == .inside {
                                GeometryReader { board in
                                    let side = min(board.size.width, board.size.height)
                                    let fit = BoardCentreView.fitted(in: layout, boardSide: side)
                                    BoardCentreView(
                                        state: replay.state,
                                        roles: replay.roles,
                                        isReplay: true,
                                        width: fit.width,
                                        content: fit.content
                                    )
                                    .position(x: board.size.width / 2, y: board.size.height / 2)
                                }
                                .allowsHitTesting(false)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(Keezly.Spacing.regular)
                    .frame(width: proxy.size.width)
                }
            }

            transport
        }
        .background(theme.table.ignoresSafeArea())
        .environment(\.boardTheme, theme)
        .onChange(of: replay.step) { _, _ in show() }
        .onDisappear { presentation?.cancel() }
        // One clock, owned by the view. The model has no timer to leak.
        .task(id: replay.isPlaying) {
            while replay.isPlaying, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(replay.speed.interval))
                guard !Task.isCancelled else { return }
                replay.tick()
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: Keezly.Spacing.medium) {
            Button(action: onLeave) {
                Label("play.leave", systemImage: "chevron.backward")
                    .labelStyle(.iconOnly)
                    .frame(width: Keezly.Target.minimum, height: Keezly.Target.minimum)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("play.leave")
            .accessibilityIdentifier("replay.leave")

            Spacer()

            Text("replay.position \(replay.step) \(replay.stepCount)")
                .font(.system(size: labelSize, design: .rounded))
                .monospacedDigit()
                .accessibilityIdentifier("replay.position")

            Spacer()

            Picker("replay.speed", selection: $replay.speed) {
                ForEach(ReplaySpeed.allCases) { speed in
                    Text(verbatim: speed.label).tag(speed)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityIdentifier("replay.speed")
        }
        .foregroundStyle(.white.opacity(0.8))
    }

    private var transport: some View {
        VStack(spacing: Keezly.Spacing.small) {
            Slider(
                value: Binding(
                    get: { Double(replay.step) },
                    set: { replay.goTo(step: Int($0.rounded())) }
                ),
                in: 0...Double(max(1, replay.stepCount)),
                step: 1
            )
            .tint(.white.opacity(0.7))
            // The unfilled part of the track is nearly invisible on the dark
            // table, which left the slider looking like a stray white pill at
            // the far left rather than a control with a length.
            .background(
                Capsule()
                    .fill(.white.opacity(0.14))
                    .frame(height: 4)
            )
            .disabled(replay.stepCount == 0)
            .accessibilityLabel("replay.scrub")
            .accessibilityIdentifier("replay.scrub")

            HStack(spacing: Keezly.Spacing.large) {
                control("backward.end", systemImage: "backward.end.fill") { replay.restart() }
                    .disabled(replay.isAtStart)
                control("replay.previous", systemImage: "backward.frame.fill") { replay.previous() }
                    .disabled(replay.isAtStart)
                control(
                    replay.isPlaying ? "replay.pause" : "replay.play",
                    systemImage: replay.isPlaying ? "pause.fill" : "play.fill"
                ) { replay.togglePlaying() }
                    .disabled(replay.isAtEnd)
                control("replay.next", systemImage: "forward.frame.fill") { replay.next() }
                    .disabled(replay.isAtEnd)
                control("replay.end", systemImage: "forward.end.fill") { replay.end() }
                    .disabled(replay.isAtEnd)
            }
            .font(.system(size: labelSize * 1.3))
            .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, Keezly.Spacing.large)
        .padding(.vertical, Keezly.Spacing.medium)
        .accessibilityIdentifier("replay.transport")
    }

    private func control(
        _ label: LocalizedStringKey,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: Keezly.Target.minimum, height: Keezly.Target.minimum)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Shows the step the replay has moved to.
    ///
    /// The same presenter the game uses, so a capture is animated in the same
    /// order it was when the match was played. A jump — scrubbing, or a step
    /// back — has no events and snaps.
    private func show() {
        presentation?.cancel()
        let events = replay.lastEvents
        let pawns = replay.state.pawns
        guard !events.isEmpty, !reduceMotion else {
            presenter.snap(to: pawns)
            return
        }
        presentation = Task { @MainActor in
            presenter.updateTiming(.standard)
            await presenter.present(events, finalPawns: pawns)
        }
    }
}
