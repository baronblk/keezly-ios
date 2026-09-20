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

    /// Classic Wood is the material for 1.0.0 (DEC-018).
    private let theme = BoardTheme.classicWood

    @State private var session: MatchSession
    @State private var selectedCard: Card?
    @State private var selectedPawn: PawnID?
    @State private var committedLegs: [SplitStep] = []

    init(session: MatchSession) {
        _session = State(initialValue: session)
    }

    private var isCompact: Bool { horizontalSizeClass == .compact }
    /// Cards are larger on iPad: the big display is the point, not a bonus (§4).
    private var handCardWidth: CGFloat { isCompact ? 72 : 112 }
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
        GeometryReader { proxy in
            ZStack {
                theme.table.ignoresSafeArea()

                if isCompact {
                    compactLayout(size: proxy.size)
                } else {
                    wideLayout(size: proxy.size)
                }
            }
        }
        .environment(\.boardTheme, theme)
        .onAppear { session.begin() }
        .onChange(of: session.pendingEvents.count) { _, _ in playOutEvents() }
    }

    // MARK: - Layouts

    /// Phone-shaped: the board leads, the hand sits under it within thumb reach,
    /// and the opponents are a single compact row (§5).
    private func compactLayout(size: CGSize) -> some View {
        VStack(spacing: Keezly.Spacing.small) {
            opponentStrip
            board.frame(maxHeight: .infinity)
            sevenProgress
            hand(availableWidth: size.width - Keezly.Spacing.regular * 2)
        }
        .padding(Keezly.Spacing.small)
    }

    /// iPad-shaped, and especially landscape: the board takes the height it can
    /// get, the hand sits beneath it, and the width left over carries the seat
    /// status — rather than being left empty because the board happens to be
    /// square (§4).
    private func wideLayout(size: CGSize) -> some View {
        // The board is square, so in landscape its size is set by the height
        // left after the hand. Whatever width that leaves goes to the seat
        // panels rather than sitting empty either side of a centred board.
        let handHeight = handCardWidth * 1.45 + handCardWidth * 0.3
        let boardSide = max(240, size.height - handHeight - Keezly.Spacing.section)
        let sideWidth = max(210, (size.width - boardSide) / 2 - Keezly.Spacing.large)
        let opponents = session.state.configuration.seats.filter { $0 != session.localSeat }
        let split = (opponents.count + 1) / 2

        return HStack(alignment: .center, spacing: Keezly.Spacing.large) {
            SeatColumn(
                seats: Array(opponents.prefix(split)),
                state: session.state, roles: session.roles, localSeat: session.localSeat
            )
            .frame(width: sideWidth)

            VStack(spacing: Keezly.Spacing.medium) {
                board.frame(maxHeight: .infinity)
                sevenProgress
                hand(availableWidth: boardSide)
            }

            SeatColumn(
                seats: Array(opponents.suffix(from: split)),
                state: session.state, roles: session.roles, localSeat: session.localSeat
            )
            .frame(width: sideWidth)
        }
        .padding(Keezly.Spacing.regular)
    }

    private var opponentStrip: some View {
        HStack(spacing: Keezly.Spacing.tight) {
            ForEach(session.state.configuration.seats.filter { $0 != session.localSeat }, id: \.self) { seat in
                SeatStatusView(
                    seat: seat,
                    role: session.roles[seat.index],
                    cardCount: session.state.hand(of: seat).count,
                    pawnsHome: session.state.pawns(of: seat).count(where: \.isHome),
                    isDealer: session.state.dealer == seat,
                    isOnTurn: session.state.currentSeat == seat,
                    isPartner: session.localSeat.map {
                        session.state.configuration.areAllied($0, seat) && $0 != seat
                    } ?? false,
                    compact: true
                )
            }
        }
    }

    @ViewBuilder
    private var sevenProgress: some View {
        if let remaining = planner.remainingSevenSteps, remaining > 0 {
            SevenProgress(remaining: remaining, isCompact: isCompact)
        }
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
    private func hand(availableWidth: CGFloat) -> some View {
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
                    cardWidth: handCardWidth,
                    availableWidth: availableWidth,
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
