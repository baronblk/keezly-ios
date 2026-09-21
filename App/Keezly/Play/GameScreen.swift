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

    /// Called when the player leaves the match for the menu.
    var onLeave: () -> Void = {}

    @State private var session: MatchSession
    @State private var presenter: BoardPresenter
    @State private var presentation: Task<Void, Never>?
    @State private var selectedCard: Card?
    @State private var selectedPawn: PawnID?
    @State private var committedLegs: [SplitStep] = []
    /// Where the keyboard is. Shared by the hand and the board, so focus can
    /// cross between them (§46).
    @FocusState private var focus: PlayFocus?
    /// The seat whose cards may be shown.
    ///
    /// Not simply "the seat on turn". On a pass-and-play table the device goes
    /// round, and a hand must not appear until the person it belongs to has
    /// said they are holding it — otherwise the cards are on screen at exactly
    /// the moment the device is being passed (§34).
    @State private var seatInHand: Seat?
    /// Whether the list of legal moves is open (§53).
    @State private var showsActionList = false
    /// Whether the rulebook is open.
    @State private var showsRules = false

    @Environment(\.scenePhase) private var scenePhase

    init(session: MatchSession, onLeave: @escaping () -> Void = {}) {
        self.onLeave = onLeave
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

    /// How big the cards in the middle may be, as a fraction of the board.
    ///
    /// Proportioned to the board's quiet middle rather than to the view. A
    /// fixed fraction suits the classic four-player board and is far too much
    /// for two seats, where the home lanes run almost to the centre and the
    /// draw pile ends up sitting across them (ISS-008). Never larger than the
    /// four-player value, so the board it was designed on is unchanged.
    private var centreScale: CGFloat {
        let reference = BoardLayout.classicInnerFieldFraction
        guard reference > 0 else { return Self.classicCentreScale }
        let scaled = Self.classicCentreScale * layout.innerFieldFraction / reference
        // Floored as well as capped. Two seats leave so little middle that the
        // honest proportion would shrink the draw pile past reading, and an
        // illegible count is worse than a crowded one (ISS-013).
        return min(Self.classicCentreScale, max(Self.minimumCentreScale, scaled))
    }

    /// The table's own cards, when the board has no middle to hold them.
    ///
    /// Only a two-seat board reaches this: there the home lanes run almost to
    /// the centre, leaving a quiet field of about a quarter of one square
    /// (ISS-013). The same information is shown as a tray beside the board —
    /// a deck on the table next to a small board — rather than shrunk past
    /// reading. The board and the rules are identical either way.
    @ViewBuilder
    private func tableTray(axis: Axis) -> some View {
        if layout.centrePlacement == .beside {
            BoardCentreView(
                state: session.state,
                roles: session.roles,
                width: isCompact ? 84 : 128,
                axis: axis
            )
            .padding(.horizontal, Keezly.Spacing.regular)
            .padding(.vertical, Keezly.Spacing.regular)
            // The same wood as the seat panels, so the tray reads as part of
            // the table rather than as a floating panel of app chrome.
            .background {
                let shape = RoundedRectangle(cornerRadius: Keezly.Radius.panel, style: .continuous)
                shape
                    .fill(theme.surfaceMid.opacity(0.92))
                    .overlay(shape.strokeBorder(theme.edge.opacity(0.45), lineWidth: 1))
                    .overlay(shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 1).padding(1))
                    .shadow(color: .black.opacity(0.24), radius: 5, y: 2)
            }
            .accessibilityIdentifier("table.tray")
        }
    }

    /// The share of the board the middle takes on a four-player table.
    static let classicCentreScale: CGFloat = 0.26
    /// Below this the cards in the middle stop being readable.
    static let minimumCentreScale: CGFloat = 0.19

    /// Whether the device is waiting to be handed to somebody else.
    ///
    /// The whole of the privacy rule is this one condition: a person's turn
    /// has come and the cards on screen are not theirs yet.
    private var awaitingHandover: Bool {
        guard session.isPassAndPlay, let seat = session.seatOnTurn else { return false }
        return seatInHand != seat
    }

    /// The seat whose point of view the screen is taking.
    private var viewpoint: Seat? { seatInHand ?? session.localSeat }

    /// The interaction state, rebuilt from the session every render so it can
    /// never disagree with the board.
    private var planner: PlayPlanner {
        guard let seat = session.seatOnTurn, session.isAwaitingHuman, !awaitingHandover else {
            return PlayPlanner(observation: PlayerObservation(of: session.state, for: session.state.currentSeat))
        }
        return PlayPlanner(
            observation: PlayerObservation(of: session.state, for: seat),
            card: selectedCard,
            committedLegs: committedLegs,
            pawn: selectedPawn
        )
    }

    /// Everything the keyboard can reach right now, rebuilt from the session
    /// on every render exactly as the planner is — so focus can never point at
    /// something the engine would refuse.
    private var ring: FocusRing {
        guard session.isAwaitingHuman, !awaitingHandover else { return FocusRing(mustFold: false) }
        guard !session.mustFold else { return FocusRing(mustFold: true) }
        let planner = planner
        return FocusRing(
            mustFold: false,
            hand: session.seatOnTurn.map { session.state.hand(of: $0).cards } ?? [],
            playable: planner.playableCards,
            selectablePawns: planner.selectablePawns,
            targets: planner.highlightedTargets
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
                matchControls

                if ScreenshotMode.showsFocusProbe {
                    // A probe, not a feature: it exists only under the test
                    // launch argument and reports where focus actually is, so
                    // a capture can answer "did the key arrive" rather than
                    // leaving it to inference.
                    Text(Self.describe(focus))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.black)
                        .accessibilityIdentifier("debug.focus")
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .allowsHitTesting(false)
                        .zIndex(999)
                }

                if let result = session.result {
                    MatchEndView(result: result, localSeat: session.localSeat, onLeave: onLeave)
                        .transition(.opacity)
                        .zIndex(600)
                } else if awaitingHandover, let seat = session.seatOnTurn {
                    HandoverView(seat: seat) { seatInHand = seat }
                        .transition(.opacity)
                        .zIndex(500)
                } else if proxy.size.height < Self.shortHeightThreshold {
                    shortLayout(size: proxy.size)
                } else if isCompact || !PlayLayout.prefersColumns(size: proxy.size, handHeight: handHeight) {
                    compactLayout(size: proxy.size)
                } else {
                    wideLayout(size: proxy.size)
                }
            }
        }
        .environment(\.boardTheme, theme)
        // Built when it opens, from the planner's own observation — so the
        // list is a view of the same position the board is drawing, never a
        // second answer about what is legal (DEC-004).
        .sheet(isPresented: $showsActionList) {
            ActionListView(
                list: ActionList(observation: planner.observation),
                mustFold: session.mustFold,
                onPlay: { submit(.play($0)) },
                onFold: { submit(.foldHand(seat: session.state.currentSeat)) }
            )
            .environment(\.boardTheme, theme)
        }
        // The screen itself takes focus so that a key press arrives even
        // before the player has focused anything — otherwise the first arrow
        // key on a fresh board would go nowhere. Its own focus ring is
        // suppressed: the container is a route for keys, not a destination.
        .focusable()
        .focusEffectDisabled()
        .keyboardFocus($focus, equals: .screen)
        .defaultFocus($focus, .screen)
        .onAppear {
            // A table with one person at it never hands over, so their cards
            // are theirs from the first deal. A pass-and-play table leaves
            // this unset — including one just restored from disk, where a hand
            // may have been on screen when the app was last closed. Safety
            // before convenience: the device is assumed to have changed hands
            // (§34).
            if !session.isPassAndPlay { seatInHand = session.localSeat }
            session.persistOpening()
            session.begin()
        }
        // Not on appear: at that point the computers may still be opening, so
        // there is nothing a human could focus yet.
        .onChange(of: session.isAwaitingHuman) { _, awaiting in
            announceTurn(awaiting)
            guard awaiting, ScreenshotMode.forcesInitialFocus, focus == .screen || focus == nil else { return }
            focus = ring.first ?? .screen
        }
        .onChange(of: session.pendingEvents.count) { _, _ in playOutEvents() }
        .onDisappear { abandonPresentation() }
        .onChange(of: scenePhase) { _, phase in
            // Leaving the foreground mid-animation must not strand the board
            // in a half-played position.
            if phase != .active { abandonPresentation() }
        }
        // Arrows walk the current band, up and down cross between hand, pieces
        // and squares. Bound here rather than on each element so a key press
        // works wherever focus happens to be (§46).
        .onKeyPress(.leftArrow) { handle(.left) }
        .onKeyPress(.rightArrow) { handle(.right) }
        .onKeyPress(.upArrow) { handle(.up) }
        .onKeyPress(.downArrow) { handle(.down) }
        .onKeyPress(.return) { handle(.activate) }
        .onKeyPress(.space) { handle(.activate) }
        .onKeyPress(.escape) { handle(.cancel) }
        // The keyboard must never be left pointing at a card that has been
        // played or a square that is no longer legal.
        .onChange(of: session.state.revision) { _, _ in
            settleFocus()
            // The list describes one position. Once the board has moved on it
            // is describing a board that no longer exists, so it closes rather
            // than offering moves nobody can make.
            showsActionList = false
        }
    }

    // MARK: - Layouts

    /// Below this height there is no room to put a hand under a board and keep
    /// the board worth looking at. A phone in landscape is the case.
    static let shortHeightThreshold: CGFloat = 520

    /// Roughly what the opponent strip and the spacings take on a phone,
    /// before the hand gets what is left.
    static let phoneChromeHeight: CGFloat = 104

    /// How much height the fanned hand takes below the board.
    private var handHeight: CGFloat { handCardWidth * 1.45 + handCardWidth * 0.3 }

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
    private func compactLayout(size: CGSize) -> some View {
        // The board is square, so on a tall phone its size is set by the
        // width and there is height left over. It goes to the cards rather
        // than to empty table: a card that can be read is worth more than a
        // gap (§45).
        // A portrait iPad reaches this layout too, and an eight-point margin
        // that suits a phone leaves a thirteen-inch board touching the glass.
        let margin = isCompact ? Keezly.Spacing.small : Keezly.Spacing.large
        let boardSide = size.width - margin * 2
        let spare = max(0, size.height - boardSide - Self.phoneChromeHeight)
        // Capped: the fan tilts its outer cards, so its drawn width is a
        // little more than the frame it is given. Letting the cards grow to
        // fill the height exactly pushed the outermost two off the screen.
        // The cap is the card's own readable maximum, which is larger on the
        // bigger screen for the same reason the board is.
        let cardWidth = min(isCompact ? 110 : 150, max(handCardWidth, spare / 1.95))

        return VStack(spacing: Keezly.Spacing.small) {
            opponentStrip
            tableTray(axis: .horizontal)
            board
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            sevenProgress
            // Narrower than the screen by more than the padding: a fanned
            // card is rotated about its foot, so it reaches further sideways
            // than the frame the fan is given. Two of them did so far enough
            // to be cut off at the edges.
            hand(availableWidth: size.width - Keezly.Spacing.section, cardWidth: cardWidth)
        }
        .padding(margin)
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
                tableTray(axis: .horizontal)
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
                sevenProgress
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
    private var opponentStrip: some View {
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

    @ViewBuilder
    private var sevenProgress: some View {
        if let remaining = planner.remainingSevenSteps, remaining > 0 {
            SevenProgress(remaining: remaining, isCompact: isCompact)
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
    private var matchControls: some View {
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
    private var actionListButton: some View {
        if session.isAwaitingHuman, !awaitingHandover, session.seatOnTurn != nil {
            Button {
                showsActionList = true
            } label: {
                Label("a11y.actions.open", systemImage: "list.bullet")
                    .font(Keezly.Typography.caption.weight(.medium))
                    .padding(.horizontal, Keezly.Spacing.medium)
                    .padding(.vertical, Keezly.Spacing.small)
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .pointerEffect(.automatic)
            .accessibilityHint("a11y.actions.hint")
            .accessibilityIdentifier("actions.open")
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
                    BoardCentreView(
                        state: session.state,
                        roles: session.roles,
                        width: side * centreScale
                    )
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
                .allowsHitTesting(false)
            }
        }
        .animation(Keezly.Motion.step(reduceMotion: reduceMotion), value: session.state.revision)
    }

    @ViewBuilder
    private func hand(availableWidth: CGFloat, cardWidth: CGFloat? = nil) -> some View {
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

    /// Says whose turn it is, once, when it becomes a person's turn.
    ///
    /// A sighted player sees the board settle and their cards light up. A
    /// listener gets nothing at all unless something says so — and the
    /// computers' turns go past in silence, so the first they would otherwise
    /// know is when they went looking (§53).
    ///
    /// A no-op when VoiceOver is not running, so there is nothing to gate on.
    private func announceTurn(_ awaiting: Bool) {
        guard awaiting, !awaitingHandover, session.seatOnTurn != nil else { return }
        AccessibilityNotification
            .Announcement(MoveNarrator.turnSummary(for: planner.observation))
            .post()
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

    // MARK: - Keyboard

    /// Applies a key press. The decision itself lives in `PlayKeyboard`, which
    /// is pure and therefore testable without a hardware keyboard.
    private func handle(_ key: PlayKey) -> KeyPress.Result {
        switch PlayKeyboard.intent(for: key, focus: focus, ring: ring) {
        case .moveFocus(let next):
            focus = next
            return .handled
        case .activate(let item):
            activate(item)
            return .handled
        case .cancel:
            clearSelection()
            // Back to the hand, which is where a cancelled move leaves the
            // player: nothing chosen, everything still available.
            focus = ring.first ?? .screen
            return .handled
        case .ignored:
            return .ignored
        }
    }

    private func activate(_ item: PlayFocus) {
        switch item {
        // The screen itself is a route for keys, not something to act on.
        case .screen: return
        case .fold: submit(.foldHand(seat: session.state.currentSeat))
        case .card(let card): select(card: card)
        case .pawn(let pawn): select(pawn: pawn)
        case .target(let position): tap(target: position)
        }
        // Acting changes what is reachable, so the keyboard moves on to
        // whatever the player would reach for next: from a card to the pieces
        // it can move, from a piece to its squares, and from a square — the
        // move now made — back to the hand.
        Task { @MainActor in
            focus = ring.jump(from: item, by: 1) ?? ring.first
        }
    }

    /// Puts focus back on something real after the board has moved on.
    ///
    /// Deliberately does nothing while focus is still on the screen itself: a
    /// player using touch has not asked for a focus ring, and pulling one onto
    /// the board every time a computer opponent moved would be noise on a
    /// device that may have no keyboard at all.
    private func settleFocus() {
        guard let current = focus, current != .screen else { return }
        if ring.contains(current) { return }
        focus = ring.first ?? .screen
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
        .accessibilityIdentifier("seven.progress")
    }
}
