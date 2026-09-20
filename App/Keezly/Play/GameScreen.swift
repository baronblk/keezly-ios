import KeezlyCore
import SwiftUI

/// The board, the hand and everything needed to take a turn.
///
/// Layout adapts by size class rather than by device: on a regular width the
/// board dominates with the hand beneath it and room to breathe; on a compact
/// width the board still leads, but the hand sits closer and the cards shrink
/// to stay reachable with one thumb (§4, §5).
struct GameScreen: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var session: MatchSession
    @State private var selectedCard: Card?
    @State private var selectedPawn: PawnID?
    @State private var committedLegs: [SplitStep] = []

    init(session: MatchSession) {
        _session = State(initialValue: session)
    }

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var layout: BoardLayout { BoardLayout(board: session.state.board) }

    /// The interaction state, rebuilt from the session every render so it can
    /// never disagree with the board.
    private var planner: PlayPlanner {
        guard let seat = session.localSeat, session.isAwaitingHuman else {
            return PlayPlanner(observation: PlayerObservation(of: session.state, for: session.state.currentSeat))
        }
        return PlayPlanner(
            observation: PlayerObservation(of: session.state, for: seat),
            card: selectedCard,
            committedLegs: committedLegs,
            pawn: selectedPawn
        )
    }

    var body: some View {
        ZStack {
            Keezly.Palette.table.ignoresSafeArea()

            VStack(spacing: isCompact ? Keezly.Spacing.medium : Keezly.Spacing.large) {
                board
                    .frame(maxHeight: .infinity)

                if let remaining = planner.remainingSevenSteps, remaining > 0 {
                    SevenProgress(remaining: remaining, isCompact: isCompact)
                }

                hand
            }
            .padding(isCompact ? Keezly.Spacing.small : Keezly.Spacing.large)
        }
        .onAppear { session.begin() }
        .onChange(of: session.pendingEvents.count) { _, _ in playOutEvents() }
    }

    // MARK: - Pieces

    private var board: some View {
        ZStack {
            BoardView(
                layout: layout,
                pawns: session.state.pawns,
                legalTargets: planner.highlightedTargets,
                selectablePawns: planner.selectablePawns,
                selectedPawn: selectedPawn,
                onSelectPawn: select(pawn:),
                onSelectTarget: tap(target:)
            )

            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                BoardCentreView(
                    state: session.state,
                    roles: session.roles,
                    width: side * 0.26
                )
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            .allowsHitTesting(false)
        }
        .animation(Keezly.Motion.step(reduceMotion: reduceMotion), value: session.state.revision)
    }

    @ViewBuilder
    private var hand: some View {
        VStack(spacing: Keezly.Spacing.small) {
            if session.mustFold {
                Button {
                    submit(.foldHand(seat: session.state.currentSeat))
                } label: {
                    Text("action.fold")
                        .font(Keezly.Typography.body.weight(.semibold))
                        .padding(.horizontal, Keezly.Spacing.large)
                        .padding(.vertical, Keezly.Spacing.medium)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("action.fold.hint")
            }

            if let seat = session.localSeat {
                HandView(
                    cards: session.state.hand(of: seat).cards,
                    playable: planner.playableCards,
                    selected: selectedCard,
                    cardWidth: isCompact ? 58 : 84,
                    onSelect: select(card:)
                )
                .disabled(!session.isAwaitingHuman)
                .opacity(session.isAwaitingHuman ? 1 : 0.55)
            }
        }
    }

    // MARK: - Interaction

    private func select(card: Card) {
        guard session.isAwaitingHuman else { return }
        // Tapping the selected card again clears it: cancelling before the move
        // is final must always be possible (§37).
        if selectedCard == card, committedLegs.isEmpty {
            clearSelection()
        } else {
            selectedCard = card
            selectedPawn = nil
            committedLegs = []
        }
    }

    private func select(pawn: PawnID) {
        guard session.isAwaitingHuman, planner.selectablePawns.contains(pawn) else { return }
        selectedPawn = selectedPawn == pawn ? nil : pawn
    }

    private func tap(target: BoardPosition) {
        guard let action = planner.targets[target] else { return }
        switch action {
        case .play(let move):
            submit(.play(move))
        case .commitLeg(let leg):
            committedLegs.append(leg)
            selectedPawn = nil
        }
    }

    private func submit(_ action: PlayerAction) {
        let outcome = session.submit(action, atRevision: session.state.revision)
        if case .success = outcome { clearSelection() }
    }

    private func clearSelection() {
        selectedCard = nil
        selectedPawn = nil
        committedLegs = []
    }

    // MARK: - Animation

    /// Lets the board catch up, then reopens input.
    ///
    /// The state is already final; this only paces the visuals and holds the
    /// input lock while they play (§39, §63). A fuller event-by-event pipeline
    /// arrives with the rest of M4.6; the duration here is derived from the
    /// events so a long journey already reads as longer than a short one.
    private func playOutEvents() {
        let events = session.pendingEvents
        guard !events.isEmpty else { return }

        let duration = Self.duration(of: events, reduceMotion: reduceMotion)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            session.animationsFinished()
        }
    }

    static func duration(of events: [GameEvent], reduceMotion: Bool) -> Double {
        var total = 0.0
        for event in events {
            switch event {
            case .pawnMoved(_, _, _, let path, _):
                total += Double(path.count) * Keezly.Motion.stepDuration
            case .pawnsSwapped:
                total += Keezly.Motion.swapDuration
            case .pawnCaptured:
                total += Keezly.Motion.captureDuration
            case .pawnEntered, .cardPlayed:
                total += Keezly.Motion.cardPlayDuration
            default:
                break
            }
        }
        let capped = min(total, 2.2)
        return reduceMotion ? min(capped, 0.35) : capped
    }
}

/// How much of a Seven is left to spend (§38).
private struct SevenProgress: View {
    let remaining: Int
    let isCompact: Bool

    var body: some View {
        HStack(spacing: Keezly.Spacing.small) {
            Text("seven.remaining \(remaining)")
                .font(.system(size: isCompact ? 14 : 17, weight: .semibold, design: .rounded))
            HStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { index in
                    Capsule()
                        .fill(index < remaining ? Keezly.Palette.legalTarget : Keezly.Palette.rim)
                        .frame(width: isCompact ? 8 : 12, height: 5)
                }
            }
        }
        .padding(.horizontal, Keezly.Spacing.regular)
        .padding(.vertical, Keezly.Spacing.small)
        .background(Capsule().fill(Keezly.Palette.legalTarget.opacity(0.14)))
        .accessibilityElement(children: .combine)
    }
}
