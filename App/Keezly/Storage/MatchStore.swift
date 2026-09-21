import Foundation
import KeezlyCore

/// Where unfinished matches live between launches.
///
/// One file per match, written whole or not at all. The alternative — an index
/// alongside the matches — would need two files to agree, and a crash between
/// the two writes would leave them disagreeing.
///
/// Saving happens *after* the engine has accepted an action and before the
/// board animates it (§57). That ordering is the point: an interrupted
/// animation can never leave half a move on disk, because the move was written
/// before the animation began.
struct MatchStore: Sendable {
    /// Where the matches are kept. Injectable so a test writes to its own
    /// directory rather than the one the app is using.
    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory
    }

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Matches", isDirectory: true)
    }

    private var quarantine: URL { directory.appendingPathComponent("Unreadable", isDirectory: true) }

    private func file(for matchID: String) -> URL {
        directory.appendingPathComponent("\(matchID).keezly", isDirectory: false)
    }

    // MARK: - Writing

    /// Writes a match, whole.
    ///
    /// `Data.write(options: .atomic)` writes a temporary file beside the target
    /// and renames it into place. A rename within one volume either happens or
    /// does not, so a process killed mid-write leaves the previous save intact
    /// — never a half file.
    func save(record: MatchRecord, state: GameState, roles: [SeatRole]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let summary = MatchSummary(record: record, state: state, roles: roles)
        let envelope = try SavedMatchEnvelope(
            summary: summary,
            record: MatchRecordEnvelope.encode(record, finalState: state)
        )
        let data = try GameStateCoding.makeEncoder().encode(envelope)
        try data.write(to: file(for: record.matchID), options: .atomic)
    }

    func delete(matchID: String) {
        try? FileManager.default.removeItem(at: file(for: matchID))
    }

    // MARK: - Reading

    /// Every match on disk that can be listed, newest first.
    ///
    /// Listing decodes but does not replay: a summary is written from the
    /// validated state, so it can be read back without playing the match out
    /// again. A file that will not decode is skipped here and reported when it
    /// is opened — a broken save must not stop the others being listed.
    func list() -> [MatchSummary] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []

        return files
            .filter { $0.pathExtension == "keezly" }
            .compactMap { url -> MatchSummary? in
                guard let data = try? Data(contentsOf: url),
                      let envelope = try? GameStateCoding.makeDecoder()
                          .decode(SavedMatchEnvelope.self, from: data),
                      let verified = try? envelope.verified()
                else { return nil }
                return verified.summary
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// The match a player would expect "continue" to open: the most recently
    /// touched one that is still being played.
    func mostRecentActive() -> MatchSummary? {
        list().first { $0.status == .active }
    }

    /// Opens a match, or refuses.
    ///
    /// Nothing is returned until the actions have been replayed through the
    /// real engine and the result matches the position that was saved. A
    /// partly-restored match is never handed back to be played on (§57).
    func restore(matchID: String) throws -> RestoredMatch {
        let data: Data
        do {
            data = try Data(contentsOf: file(for: matchID))
        } catch {
            throw MatchStoreError.unreadable(reason: String(describing: error))
        }

        let envelope: SavedMatchEnvelope
        do {
            envelope = try GameStateCoding.makeDecoder().decode(SavedMatchEnvelope.self, from: data)
        } catch {
            throw MatchStoreError.unreadable(reason: String(describing: error))
        }
        let verified = try envelope.verified()

        let roles = try verified.summary.roles.map { persisted -> SeatRole in
            guard let role = persisted.role else {
                if case .computer(let strength) = persisted {
                    throw MatchStoreError.unknownOpponent(strength: strength)
                }
                throw MatchStoreError.unreadable(reason: "a seat has no player")
            }
            return role
        }

        let restoration: MatchRestoration
        do {
            restoration = try MatchRecordEnvelope.restore(verified.record)
        } catch let error as MatchRestoreError {
            throw MatchStoreError.engineRefused(error)
        }

        guard roles.count == restoration.state.configuration.seatCount else {
            throw MatchStoreError.seatCountMismatch(
                seats: restoration.state.configuration.seatCount,
                roles: roles.count
            )
        }

        return RestoredMatch(
            record: restoration.record,
            state: restoration.state,
            roles: roles,
            summary: verified.summary
        )
    }

    /// Moves a file that could not be opened out of the way, keeping it.
    ///
    /// Not deleted: a save that failed to restore is the only evidence of why,
    /// and throwing it away would make the fault impossible to investigate. It
    /// stops being offered as a match to continue, which is all that is needed.
    @discardableResult
    func quarantine(matchID: String) -> URL? {
        let source = file(for: matchID)
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }
        do {
            try FileManager.default.createDirectory(at: quarantine, withIntermediateDirectories: true)
            let destination = quarantine.appendingPathComponent("\(matchID)-\(Clock.now()).keezly")
            try FileManager.default.moveItem(at: source, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}
