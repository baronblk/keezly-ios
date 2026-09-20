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
    @State private var presenter: BoardPresenter
    @State private var presentation: Task<Void, Never>?
    @State private var selectedCard: Card?
    @State private var selectedPawn: PawnID?
    @State private var committedLegs: [SplitStep] = []

    @Environment(\.scenePhase) private var scenePhase

    init(session: MatchSession) {
        _session = State(initialValue: session)
        _presenter = State(initialValue: BoardPresenter(pawns: session.state.pawns))
    }

    private var isCompact: Bool { horizontalSizeClass == .compact }
    /// Cards are larger on iPad: the big display is the point, not a bonus (§4).
    /// A square board on a tall phone screen is limited by width, which leaves
    /// height to spare. It goes to the cards, because a card that can be read
    /// is worth more than empty table (§45).
    private var handCardWidth: CGFloat { isCompact ? 92 : 112 }

    /// Cards in the short landscape layout, where they share the width with the
    /// board rather than having a band of their own.
    private var shortHandCardWidth: CGFloat { 74 }
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

                // Chosen by the space actually available, not by size class
                // alone. A phone in landscape reports a regular width on some
                // models, and stacking a board above a hand there left the
                // board the size of a postage stamp.
                if proxy.size.height < Self.shortHeightThreshold {
                    shortLayout(size: proxy.size)
                } else if isCompact {
                    compactLayout(size: proxy.size)
                } else {
                    wideLayout(size: proxy.size)
                }
            }
        }
        .environment(\.boardTheme, theme)
        .onAppear { session.begin() }
        .onChange(of: session.pendingEvents.count) { _, _ in playOutEvents() }
        .onDisappear { abandonPresentation() }
        .onChange(of: scenePhase) { _, phase in
            // Leaving the foreground mid-animation must not strand the board
            // in a half-played position.
            if phase != .active { abandonPresentation() }
        }
    }

    // MARK: - Layouts

    /// Below this height there is no room to put a hand under a board and keep
    /// the board worth looking at. A phone in landscape is the case.
    static let shortHeightThreshold: CGFloat = 520

    /// Phone-shaped: the board leads, the hand sits under it within thumb reach,
    /// and the opponents are a single compact row (§5).
    private func compactLayout(size: CGSize) -> some View {
        VStack(spacing: Keezly.Spacing.small) {
            opponentStrip
            board
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            sevenProgress
            hand(availableWidth: size.width - Keezly.Spacing.regular * 2)
        }
        .padding(Keezly.Spacing.small)
        // Nothing inside may push the layout wider than the screen: that is
        // what clipped the board on a six-player phone table.
        .frame(width: size.width)
        .clipped()
    }

    /// Short and wide — a phone in landscape. The board takes the whole
    /// height, and the hand moves beside it rather than under it, because
    /// height is the scarce dimension here and the board is what needs it (§5).
    private func shortLayout(size: CGSize) -> some View {
        let boardSide = max(200, size.height - Keezly.Spacing.regular)
        let sideWidth = max(160, size.width - boardSide - Keezly.Spacing.medium * 2)

        return HStack(spacing: Keezly.Spacing.medium) {
            board
                .frame(width: boardSide, height: boardSide)

            VStack(spacing: Keezly.Spacing.small) {
                opponentStrip
                Spacer(minLength: 0)
                sevenProgress
                hand(availableWidth: sideWidth)
                Spacer(minLength: 0)
            }
            .frame(width: sideWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Keezly.Spacing.small)
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
        // Never let the board shrink below most of the smaller screen edge: a
        // board that has been squeezed out of the way is no longer a board.
        let floor = min(size.width, size.height) * 0.8
        let boardSide = max(floor, size.height - handHeight - Keezly.Spacing.section)
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

    /// Opponents on a phone: fixed-size chips that cannot push the layout
    /// wider than the screen. Five of them across a phone was what clipped the
    /// board before.
    private var opponentStrip: some View {
        HStack(spacing: Keezly.Spacing.tight) {
            ForEach(session.state.configuration.seats.filter { $0 != session.localSeat }, id: \.self) { seat in
                SeatChip(
                    seat: seat,
                    cardCount: session.state.hand(of: seat).count,
                    pawnsHome: session.state.pawns(of: seat).count(where: \.isHome),
                    isDealer: session.state.dealer == seat,
                    isOnTurn: session.state.currentSeat == seat,
                    isPartner: session.localSeat.map {
                        session.state.configuration.areAllied($0, seat) && $0 != seat
                    } ?? false
                )
            }
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
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
                // The board draws what the presenter is showing, which during
                // an animation is behind the state on purpose.
                pawns: presenter.displayedPawns,
                legalTargets: planner.highlightedTargets,
                selectablePawns: planner.selectablePawns,
                selectedPawn: selectedPawn,
                emphasised: presenter.emphasised,
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
                    cardWidth: availableWidth < 300 ? shortHandCardWidth : handCardWidth,
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

    /// Plays the events of the last action, then reopens input.
    ///
    /// The state was already final before this ran; the presenter only shows
    /// how the board got there (§39). Input stays closed for the duration,
    /// which is what stops a second tap landing on a board that has not caught
    /// up (§63).
    private func playOutEvents() {
        let events = session.pendingEvents
        guard !events.isEmpty else { return }

        let pawns = session.state.pawns
        presentation?.cancel()
        presentation = Task { @MainActor in
            presenter.updateTiming(reduceMotion ? .instant : .standard)
            await presenter.present(events, finalPawns: pawns)
            guard !Task.isCancelled else { return }
            session.animationsFinished()
        }
    }

    /// Stops an animation in flight and shows the true position.
    ///
    /// Called when the view goes away or the app leaves the foreground: an
    /// animation that was interrupted must never leave the board showing
    /// something that is not the state.
    private func abandonPresentation() {
        presentation?.cancel()
        presentation = nil
        presenter.snap(to: session.state.pawns)
        if session.isBusy { session.animationsFinished() }
    }
}

/// How much of a Seven is left to spend (§38).
private struct SevenProgress: View {
    @ScaledMetric(relativeTo: .subheadline) private var textScale: CGFloat = 1

    let remaining: Int
    let isCompact: Bool

    var body: some View {
        HStack(spacing: Keezly.Spacing.small) {
            Text("seven.remaining \(remaining)")
                .font(.system(size: (isCompact ? 14 : 17) * textScale, weight: .semibold, design: .rounded))
                .lineLimit(1)
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
