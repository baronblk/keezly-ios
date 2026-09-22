import KeezlyCore
import SwiftUI

/// The board, the hand and everything needed to take a turn.
///
/// Layout adapts by size class rather than by device: on a regular width the
/// board dominates with the hand beneath it and room to breathe; on a compact
/// width the board still leads, but the hand sits closer and the cards shrink
/// to stay reachable with one thumb (§4, §5).
///
/// Its layout half lives in `GameScreen+Layout.swift`. Members are internal
/// rather than private only because Swift gives an extension in another file
/// no access to a private one — nothing outside this screen uses them.
struct GameScreen: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    /// Classic Wood is the material for 1.0.0 (DEC-018).
    let theme = BoardTheme.classicWood

    /// Called when the player leaves the match for the menu.
    var onLeave: () -> Void = {}
    /// The lesson being taught on this board, when the match is a lesson.
    ///
    /// The tutorial plays on the ordinary screen rather than a copy of it —
    /// the board, the hand, the rules and the refusals are all the real ones,
    /// and this only watches what the player does with them (§52).
    var tutorial: TutorialRun?
    /// Sound and haptics, as the player has asked for them.
    var preferences: Preferences

    @State var session: MatchSession
    @State var presenter: BoardPresenter
    @State var presentation: Task<Void, Never>?
    @State var selectedCard: Card?
    @State var selectedPawn: PawnID?
    @State var committedLegs: [SplitStep] = []
    /// Where the keyboard is. Shared by the hand and the board, so focus can
    /// cross between them (§46).
    @FocusState var focus: PlayFocus?
    /// The seat whose cards may be shown.
    ///
    /// Not simply "the seat on turn". On a pass-and-play table the device goes
    /// round, and a hand must not appear until the person it belongs to has
    /// said they are holding it — otherwise the cards are on screen at exactly
    /// the moment the device is being passed (§34).
    @State var seatInHand: Seat?
    /// Whether the list of legal moves is open (§53).
    @State var showsActionList = false
    /// Whether the rulebook is open.
    @State var showsRules = false
    /// The card whose rule the player asked about.
    @State var explaining: CardHelp?
    /// The suggestion on screen, when one has been asked for.
    @State var hint: Hint?
    /// The running request for one.
    @State var hintSearch: Task<Void, Never>?

    @Environment(\.scenePhase) var scenePhase
    /// Roughly what the opponent strip, the buttons and the spacings take
    /// above and below the board. Scaled, because all of it is text and all of
    /// it grows with the reader's setting.
    @ScaledMetric(relativeTo: .body) var chromeHeight: CGFloat = 132

    init(
        session: MatchSession,
        onLeave: @escaping () -> Void = {},
        tutorial: TutorialRun? = nil,
        preferences: Preferences = Preferences()
    ) {
        self.onLeave = onLeave
        self.tutorial = tutorial
        self.preferences = preferences
        _session = State(initialValue: session)
        _presenter = State(initialValue: BoardPresenter(pawns: session.state.pawns))
    }

    var isCompact: Bool { horizontalSizeClass == .compact }
    /// Cards are larger on iPad: the big display is the point, not a bonus (§4).
    /// A square board on a tall phone screen is limited by width, which leaves
    /// height to spare. It goes to the cards, because a card that can be read
    /// is worth more than empty table (§45).
    var handCardWidth: CGFloat { isCompact ? 92 : 112 }

    /// Cards in the short landscape layout, where they share the width with the
    /// board rather than having a band of their own.
    var shortHandCardWidth: CGFloat { 74 }
    var layout: BoardLayout { BoardLayout(board: session.state.board) }

    /// The table's own cards, when the board has no middle to hold them.
    ///
    /// Only a two-seat board reaches this: there the home lanes run almost to
    /// the centre, leaving a quiet field of a little over one square pitch —
    /// not the three a pile and a played card need (ISS-013). The same information is shown as a tray beside the board —
    /// a deck on the table next to a small board — rather than shrunk past
    /// reading. The board and the rules are identical either way.
    @ViewBuilder
    func tableTray(axis: Axis) -> some View {
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

    /// Whether the device is waiting to be handed to somebody else.
    ///
    /// The whole of the privacy rule is this one condition: a person's turn
    /// has come and the cards on screen are not theirs yet.
    var awaitingHandover: Bool {
        guard session.isPassAndPlay, let seat = session.seatOnTurn else { return false }
        return seatInHand != seat
    }

    /// The seat whose point of view the screen is taking.
    var viewpoint: Seat? { seatInHand ?? session.localSeat }

    /// The interaction state, rebuilt from the session every render so it can
    /// never disagree with the board.
    var planner: PlayPlanner {
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
    var ring: FocusRing {
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
        VStack(spacing: 0) {
            GeometryReader { proxy in
            ZStack {
                theme.table.ignoresSafeArea()

                // Chosen by the space actually available, not by size class
                // alone. A phone in landscape reports a regular width on some
                // models, and stacking a board above a hand there left the
                // board the size of a postage stamp.
                matchControls
                lessonOverlay

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

            // Below the board rather than over it. A lesson that covers the
            // hand is a lesson that cannot be played.
            lessonBanner
        }
        // The table runs behind the banner as well as behind the board.
        // Without this the strip the banner sits in showed the system
        // background, which in light mode is white.
        .background(theme.table.ignoresSafeArea())
        .environment(\.boardTheme, theme)
        // Built when it opens, from the planner's own observation — so the
        // list is a view of the same position the board is drawing, never a
        // second answer about what is legal (DEC-004).
        .sheet(item: $explaining) { CardHelpView(help: $0) }
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
            Feedback(preferences: preferences).prepare()
            if !session.isPassAndPlay { seatInHand = session.localSeat }
            session.persistOpening()
            session.begin()
        }
        // Not on appear: at that point the computers may still be opening, so
        // there is nothing a human could focus yet.
        .onChange(of: session.isAwaitingHuman) { _, awaiting in
            turnBegan(awaiting)
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

    // MARK: - Interaction

    func select(card: Card) {
        guard session.isAwaitingHuman else { return }
        // The one cue that does not come from an event: picking a card up
        // changes nothing on the board, and is exactly the moment a player
        // wants confirming.
        Feedback(preferences: preferences).play(.select)
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

    func select(pawn: PawnID) {
        guard session.isAwaitingHuman, planner.selectablePawns.contains(pawn) else { return }
        selectedPawn = selectedPawn == pawn ? nil : pawn
    }

    func tap(target: BoardPosition) {
        guard let action = planner.targets[target] else { return }
        switch action {
        case .play(let move):
            submit(.play(move))
        case .commitLeg(let leg):
            committedLegs.append(leg)
            selectedPawn = nil
        }
    }

    /// Everything that happens when the board comes back to the player.
    func turnBegan(_ awaiting: Bool) {
        announceTurn(awaiting)
        // Once the opponents have replied a lesson may no longer be possible:
        // the pawn it was about can have been knocked out by somebody else.
        if awaiting { tutorial?.boardSettled() }
        guard awaiting, ScreenshotMode.forcesInitialFocus, focus == .screen || focus == nil else { return }
        focus = ring.first ?? .screen
    }

    /// Says whose turn it is, once, when it becomes a person's turn.
    ///
    /// A sighted player sees the board settle and their cards light up. A
    /// listener gets nothing at all unless something says so — and the
    /// computers' turns go past in silence, so the first they would otherwise
    /// know is when they went looking (§53).
    ///
    /// A no-op when VoiceOver is not running, so there is nothing to gate on.
    func announceTurn(_ awaiting: Bool) {
        guard awaiting, !awaitingHandover, session.seatOnTurn != nil else { return }
        AccessibilityNotification
            .Announcement(MoveNarrator.turnSummary(for: planner.observation))
            .post()
    }

    /// Asks for a suggestion, or puts the one on screen away.
    ///
    /// Cancellable and cancelled: the request runs off the main actor, and a
    /// board that has moved on must not be given advice about the board it was.
    func toggleHint() {
        hintSearch?.cancel()
        guard hint == nil else {
            hint = nil
            return
        }
        let observation = planner.observation
        let asked = session.state.revision
        hintSearch = Task { @MainActor in
            let found = await HintProvider.hint(for: observation)
            guard !Task.isCancelled, session.state.revision == asked else { return }
            hint = found
        }
    }

    func clearHint() {
        hintSearch?.cancel()
        hintSearch = nil
        hint = nil
    }

    func submit(_ action: PlayerAction) {
        clearHint()
        let before = session.state
        let outcome = session.submit(action, atRevision: session.state.revision)
        guard case .success = outcome else { return }
        clearSelection()
        // Reported from the board the player saw to the board their move made,
        // so a lesson judges what happened rather than what was tapped.
        tutorial?.record(action, before: before, after: session.state)
    }

    func clearSelection() {
        selectedCard = nil
        selectedPawn = nil
        committedLegs = []
    }

    // MARK: - Keyboard

    /// Applies a key press. The decision itself lives in `PlayKeyboard`, which
    /// is pure and therefore testable without a hardware keyboard.
    func handle(_ key: PlayKey) -> KeyPress.Result {
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

    func activate(_ item: PlayFocus) {
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
    func settleFocus() {
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
    func playOutEvents() {
        let events = session.pendingEvents
        guard !events.isEmpty else { return }

        // Felt and heard as the board begins to show it, from the events the
        // engine produced rather than from the tap that caused them: a move a
        // computer opponent made lands the same way as one the player made,
        // and a tap the engine refused produces nothing at all (§43).
        Feedback(preferences: preferences).play(FeedbackCue.cues(for: events))

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
    func abandonPresentation() {
        presentation?.cancel()
        presentation = nil
        presenter.snap(to: session.state.pawns)
        if session.isBusy { session.animationsFinished() }
    }
}

/// How much of a Seven is left to spend (§38).
struct SevenProgress: View {
    @ScaledMetric(relativeTo: .subheadline) var textScale: CGFloat = 1

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
