import KeezlyCore
import SwiftUI

/// How the playing screen arranges itself, and the pieces it arranges.
///
/// Split from `GameScreen` because the two halves answer different questions:
/// that file decides what the player may do, this one decides where it goes.
/// The arithmetic behind the three-column layout lives in `PlayLayout`, where
/// a test can add it up (§5, §35).
extension GameScreen {

    // MARK: - Layouts

    /// Below this height there is no room to put a hand under a board and keep
    /// the board worth looking at. A phone in landscape is the case.
    static let shortHeightThreshold: CGFloat = 520

    /// How much height the fanned hand takes below the board.
    var handHeight: CGFloat { handCardWidth * 1.45 + handCardWidth * 0.3 }

    static func describe(_ focus: PlayFocus?) -> String {
        switch focus {
        case .none: "focus:none"
        case .screen: "focus:screen"
        case .fold: "focus:fold"
        case .card(let card): "focus:card:\(card.rank.shorthand)"
        case .pawn(let pawn): "focus:pawn:\(pawn.seat.index).\(pawn.slot)"
        case .target(let position): "focus:target:\(position)"
        }
    }

    /// Phone-shaped: the board leads, the hand sits under it within thumb reach,
    /// and the opponents are a single compact row (§5).
    func compactLayout(size: CGSize) -> some View {
        // The board is square, so on a tall phone its size is set by the
        // width and there is height left over. It goes to the cards rather
        // than to empty table: a card that can be read is worth more than a
        // gap (§45).
        // A portrait iPad reaches this layout too, and an eight-point margin
        // that suits a phone leaves a thirteen-inch board touching the glass.
        // The arithmetic lives in `StackedLayout`, where a test can sweep it
        // across every width between a third of an iPad and the whole of one
        // rather than the handful a device list happens to name.
        let layout = StackedLayout(size: size, chromeHeight: chromeHeight)
        let margin = layout.margin

        return VStack(spacing: Keezly.Spacing.small) {
            opponentStrip
            // The slack goes here, in one piece, rather than being split above
            // and below the board by a greedy frame. A phone screen is taller
            // than a square board and a hand need, and the spare height is
            // better spent lifting the board away from the opponents than
            // opening gaps inside the group the board belongs to — the hand
            // stays where a thumb is (§5, §53).
            //
            // Above the tray rather than below it: on a two-seat table the
            // tray *is* the board's middle, moved outside because there is no
            // room for it inside (ISS-013). A gap between the two would read
            // as a second, smaller board sitting above the real one.
            Spacer(minLength: 0)
            tableTray(axis: .horizontal)
            board
                .frame(maxWidth: layout.boardSide, maxHeight: layout.boardSide)
            boardStatus(boardSide: layout.boardSide)
            sevenProgress
            hintLine
            hand(availableWidth: layout.handWidth, cardWidth: layout.cardWidth)
        }
        .frame(maxHeight: .infinity)
        .padding(margin)
        // Nothing inside may push the layout wider than the screen: that is
        // what clipped the board on a six-player phone table.
        .frame(width: size.width)
        .clipped()
    }

    /// Short and wide — a phone in landscape. The board takes the whole
    /// height, and the hand moves beside it rather than under it, because
    /// height is the scarce dimension here and the board is what needs it (§5).
    func shortLayout(size: CGSize) -> some View {
        let boardSide = max(200, size.height - Keezly.Spacing.regular)
        let sideWidth = max(160, size.width - boardSide - Keezly.Spacing.medium * 2)

        return HStack(spacing: Keezly.Spacing.medium) {
            board
                .frame(width: boardSide, height: boardSide)

            VStack(spacing: Keezly.Spacing.small) {
                opponentStrip
                tableTray(axis: .horizontal)
                Spacer(minLength: 0)
                boardStatus(boardSide: boardSide)
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
    func wideLayout(size: CGSize) -> some View {
        // The board is square, so in landscape its size is set by the height
        // left after the hand. Whatever width that leaves goes to the seat
        // panels rather than sitting empty either side of a centred board.
        // The arithmetic lives in `PlayLayout`, where it can be added up by a
        // test rather than by looking at a screenshot.
        let layout = PlayLayout(size: size, handHeight: handHeight)
        let boardSide = layout.boardSide
        let sideWidth = layout.sideWidth
        let opponents = session.state.configuration.seats.filter { $0 != viewpoint }
        let split = (opponents.count + 1) / 2

        return HStack(alignment: .center, spacing: Keezly.Spacing.large) {
            SeatColumn(
                seats: Array(opponents.prefix(split)),
                state: session.state, roles: session.roles, localSeat: viewpoint
            )
            .frame(width: sideWidth)

            VStack(spacing: Keezly.Spacing.medium) {
                board.frame(maxHeight: .infinity)
                boardStatus(boardSide: boardSide)
                sevenProgress
                hintLine
                hand(availableWidth: boardSide)
            }
            // Given explicitly so the three columns add up. Left to itself the
            // middle took whatever the seat columns did not, which on a
            // two-player table — one opponent, so one empty column — pushed
            // the board well off centre.
            .frame(width: boardSide)

            // On a two-seat table the far column is empty — one opponent, one
            // column — so the table's own cards go there: the deck opposite
            // the other player, with the board between them (ISS-013).
            ZStack {
                SeatColumn(
                    seats: Array(opponents.suffix(from: split)),
                    state: session.state, roles: session.roles, localSeat: viewpoint
                )
                tableTray(axis: .vertical)
            }
            .frame(width: sideWidth)
        }
        .padding(Keezly.Spacing.regular)
    }

    /// Opponents on a phone: fixed-size chips that cannot push the layout
    /// wider than the screen. Five of them across a phone was what clipped the
    /// board before.
    var opponentStrip: some View {
        HStack(spacing: Keezly.Spacing.tight) {
            ForEach(session.state.configuration.seats.filter { $0 != viewpoint }, id: \.self) { seat in
                SeatChip(
                    seat: seat,
                    cardCount: session.state.hand(of: seat).count,
                    pawnsHome: session.state.pawns(of: seat).count(where: \.isHome),
                    isDealer: session.state.dealer == seat,
                    isOnTurn: session.state.currentSeat == seat,
                    isPartner: viewpoint.map {
                        session.state.configuration.areAllied($0, seat) && $0 != seat
                    } ?? false
                )
            }
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Whose turn it is and which round, for a board too small to say so
    /// itself.
    ///
    /// Empty whenever the middle is carrying them, which is every board from
    /// about a tablet upwards. It sits directly under the board rather than in
    /// a bar of its own: it is the same information in the same reading order,
    /// moved down by however much it takes to stop covering the pieces.
    @ViewBuilder
    func boardStatus(boardSide: CGFloat) -> some View {
        let fit = BoardCentreView.fitted(in: layout, boardSide: boardSide)
        if layout.centrePlacement == .inside, fit.content == .piles {
            BoardCentreView(
                state: session.state,
                roles: session.roles,
                width: BoardCentreView.detachedWidth,
                content: .labels
            )
            .accessibilityIdentifier("board.status")
        }
    }

    @ViewBuilder
    var sevenProgress: some View {
        if let remaining = planner.remainingSevenSteps, remaining > 0 {
            SevenProgress(remaining: remaining, isCompact: isCompact)
        }
    }

    /// The suggestion, once there is one.
    ///
    /// Worded as an opinion rather than an instruction, because that is what
    /// it is: one competent player's move, worked out from exactly what the
    /// person holding the device can see.
    @ViewBuilder
    var hintLine: some View {
        if let hint {
            HStack(alignment: .firstTextBaseline, spacing: Keezly.Spacing.small) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 13))
                    .accessibilityHidden(true)
                Text("hint.suggestion \(hint.spoken)")
                    .font(Keezly.Typography.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(.white.opacity(0.82))
            .padding(.horizontal, Keezly.Spacing.medium)
            .padding(.vertical, Keezly.Spacing.small)
            .frame(maxWidth: 520)
            .background(Capsule().fill(Color.black.opacity(0.32)))
            .onTapGesture { clearHint() }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("hint.text")
        }
    }

    @ViewBuilder
    var lessonBanner: some View {
        if let tutorial, tutorial.progress == .open {
            LessonBanner(
                lesson: tutorial.lesson,
                number: tutorial.index + 1,
                total: Tutorial.lessons.count,
                onSkip: { tutorial.skip() },
                onRead: { tutorial.acknowledge() }
            )
            .padding(.horizontal, Keezly.Spacing.regular)
            .padding(.bottom, Keezly.Spacing.small)
        }
    }

    @ViewBuilder
    var lessonOverlay: some View {
        if let tutorial, tutorial.progress != .open {
                LessonOutcomeCard(
                    lesson: tutorial.lesson,
                    progress: tutorial.progress,
                    isLast: tutorial.isLast,
                    onContinue: { tutorial.advance() },
                    onRestart: { tutorial.restartLesson() },
                    onFinish: onLeave
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.35).ignoresSafeArea())
                .transition(.opacity)
                .zIndex(550)
        }
    }

    /// The two things that must be reachable from any position: the way out,
    /// and the rules.
    ///
    /// Small and in the corner rather than in a bar of its own — the board is
    /// what the screen is for — but never behind a gesture. A match a player
    /// cannot leave is a match they have to force-quit, and a rule argument
    /// mid-turn is exactly when the rulebook is wanted.
    @ViewBuilder
    var matchControls: some View {
        if session.result == nil, !awaitingHandover {
            HStack(spacing: Keezly.Spacing.small) {
                Button(action: onLeave) {
                    Label("play.leave", systemImage: "chevron.backward")
                        .labelStyle(.iconOnly)
                        .frame(width: Keezly.Target.minimum, height: Keezly.Target.minimum)
                }
                .accessibilityLabel("play.leave")
                .accessibilityHint("play.leave.hint")
                .accessibilityIdentifier("play.leave")

                Spacer()

                Button {
                    showsRules = true
                } label: {
                    Label("play.rules", systemImage: "book")
                        .labelStyle(.iconOnly)
                        .frame(width: Keezly.Target.minimum, height: Keezly.Target.minimum)
                }
                .accessibilityLabel("play.rules")
                .accessibilityIdentifier("play.rules")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.7))
            .pointerEffect(.highlight)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, Keezly.Spacing.small)
            .zIndex(400)
            .sheet(isPresented: $showsRules) {
                RulebookView(rules: session.state.configuration.ruleSet)
            }
        }
    }

    /// The way in to the second complete input method (§53).
    ///
    /// Not hidden behind an accessibility setting. Somebody who finds the
    /// board fiddly — a small phone, a shaking hand, a bright pavement — is
    /// served by the same list, and a route that only appears for VoiceOver
    /// users is a route nobody else can discover.
    @ViewBuilder
    var actionListButton: some View {
        if session.isAwaitingHuman, !awaitingHandover, session.seatOnTurn != nil {
            HStack(spacing: Keezly.Spacing.small) {
                Button {
                    showsActionList = true
                } label: {
                    Label("a11y.actions.open", systemImage: "list.bullet")
                        .font(Keezly.Typography.caption.weight(.medium))
                        .padding(.horizontal, Keezly.Spacing.medium)
                        .padding(.vertical, Keezly.Spacing.small)
                }
                .accessibilityHint("a11y.actions.hint")
                .accessibilityIdentifier("actions.open")

                if session.allowsHints {
                    Button(action: toggleHint) {
                        Label(hint == nil ? "hint.ask" : "hint.dismiss", systemImage: "lightbulb")
                            .font(Keezly.Typography.caption.weight(.medium))
                            .padding(.horizontal, Keezly.Spacing.medium)
                            .padding(.vertical, Keezly.Spacing.small)
                    }
                    .accessibilityHint("hint.hint")
                    .accessibilityIdentifier("hint.ask")
                }
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .pointerEffect(.automatic)
        }
    }

    // MARK: - Pieces

    var board: some View {
        ZStack {
            BoardView(
                layout: layout,
                // The board draws what the presenter is showing, which during
                // an animation is behind the state on purpose.
                pawns: presenter.displayedPawns,
                legalTargets: planner.highlightedTargets,
                legTargets: planner.legTargets,
                selectablePawns: planner.selectablePawns,
                selectedPawn: selectedPawn,
                emphasised: presenter.emphasised,
                onSelectPawn: select(pawn:),
                onSelectTarget: tap(target:),
                focus: $focus,
                // The planner's own observation, so what is spoken and what is
                // playable come from one source (DEC-014).
                narration: planner.observation
            )

            if layout.centrePlacement == .inside {
                GeometryReader { proxy in
                    let side = min(proxy.size.width, proxy.size.height)
                    let fit = BoardCentreView.fitted(in: layout, boardSide: side)
                    BoardCentreView(
                        state: session.state,
                        roles: session.roles,
                        width: fit.width,
                        content: fit.content
                    )
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
                .allowsHitTesting(false)
            }
        }
        .animation(Keezly.Motion.step(reduceMotion: reduceMotion), value: session.state.revision)
    }

    @ViewBuilder
    func hand(availableWidth: CGFloat, cardWidth: CGFloat? = nil) -> some View {
        VStack(spacing: Keezly.Spacing.small) {
            actionListButton

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
                .keyboardFocusRing(focus == .fold, cornerRadius: Keezly.Radius.card)
                .pointerEffect(.automatic)
                .keyboardFocus($focus, equals: .fold)
                .accessibilityHint("action.fold.hint")
            }

            // Drawn only for the person who has said they are holding the
            // device. Checked here as well as behind the cover, so a hand
            // cannot appear even if the cover failed to draw (§34).
            if let seat = viewpoint, !awaitingHandover {
                HandView(
                    cards: session.state.hand(of: seat).cards,
                    playable: planner.playableCards,
                    selected: selectedCard,
                    cardWidth: cardWidth ?? (availableWidth < 300 ? shortHandCardWidth : handCardWidth),
                    availableWidth: availableWidth,
                    focus: $focus,
                    onSelect: select(card:),
                    onExplain: { explaining = CardHelp(rank: $0.rank) }
                )
                .disabled(!session.isAwaitingHuman)
                .opacity(session.isAwaitingHuman ? 1 : 0.55)
            }
        }
    }
}
