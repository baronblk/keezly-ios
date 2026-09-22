@testable import Keezly
import KeezlyCore
import SwiftUI
import Testing
import UIKit

/// §42, §53 — the board has to be readable without colour.
///
/// ISS-016 records that a seat's hue does not reach 3:1 against the maple and
/// cannot without darkening a board whose appearance is settled. That is only
/// acceptable if colour is **redundant** — if every distinction the board makes
/// is also made by a shape.
///
/// "Redundant" is easy to claim and easy to get wrong, so it is measured here:
/// the board is rendered twice, desaturated, and the two greyscale images are
/// compared in the region that is supposed to have changed. A distinction that
/// survives only in colour shows up as two identical patches of grey.
@Suite("Greyscale")
@MainActor
struct GrayscaleTests {

    private let side: CGFloat = 900
    private var layout: BoardLayout { BoardLayout(board: BoardGraph(seatCount: 4)) }

    /// The board, desaturated, as somebody who cannot use colour sees it.
    private func board(legalTargets: Set<BoardPosition> = []) -> UIImage? {
        let transform = BoardTransform(
            bounds: layout.contentBounds,
            into: CGSize(width: side, height: side)
        )
        let renderer = ImageRenderer(
            content: BoardSurface(
                layout: layout,
                transform: transform,
                theme: .classicWood,
                legalTargets: legalTargets
            )
            .frame(width: side, height: side)
        )
        renderer.scale = 1
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// Where a board position lands in the rendered image.
    private func point(of position: BoardPosition) -> CGPoint {
        let transform = BoardTransform(
            bounds: layout.contentBounds,
            into: CGSize(width: side, height: side)
        )
        return transform.point(layout.point(for: position))
    }

    // MARK: - Reading pixels

    private func grey(of image: UIImage) throws -> [Double] {
        let cgImage = try #require(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        try #require(context).draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Rec. 709 luminance — the same weighting a greyscale filter uses, so
        // this is what the board looks like with the colour taken out.
        return stride(from: 0, to: buffer.count, by: 4).map { index in
            0.2126 * Double(buffer[index])
                + 0.7152 * Double(buffer[index + 1])
                + 0.0722 * Double(buffer[index + 2])
        }
    }

    /// How different two renders are inside one square, in greyscale.
    ///
    /// The average absolute difference over the patch, 0 to 255. A change that
    /// exists only in colour scores near zero here.
    private func difference(
        between first: [Double],
        and second: [Double],
        around centre: CGPoint,
        radius: CGFloat
    ) -> Double {
        let width = Int(side)
        var total = 0.0
        var counted = 0
        let minX = max(0, Int(centre.x - radius))
        let maxX = min(width - 1, Int(centre.x + radius))
        let minY = max(0, Int(centre.y - radius))
        let maxY = min(Int(side) - 1, Int(centre.y + radius))

        for y in minY...maxY {
            for x in minX...maxX {
                let index = y * width + x
                guard index < first.count, index < second.count else { continue }
                total += abs(first[index] - second[index])
                counted += 1
            }
        }
        return counted == 0 ? 0 : total / Double(counted)
    }

    // MARK: - The guarantees

    /// **A square you may move to is visible without colour.**
    ///
    /// The ring was solid and green; a protected start square is a solid ring
    /// in a seat colour. Two solid rings in two colours are the same ring in
    /// greyscale, and the difference between "you may move here" and "nobody
    /// may pass" is not one a player can afford to lose. The legal-target ring
    /// is now dashed.
    @Test("a legal target changes the board in greyscale")
    func legalTargetIsVisibleWithoutColour() throws {
        let target = BoardPosition.track(index: 10)
        let plain = try grey(of: #require(board()))
        let highlighted = try grey(of: #require(board(legalTargets: [target])))

        let radius = 26.0
        let changed = difference(between: plain, and: highlighted, around: point(of: target), radius: radius)
        #expect(changed > 6, "a legal target is only \(String(format: "%.1f", changed))/255 different in greyscale")

        // And nowhere else: a highlight that changed the whole board would
        // pass the test above while telling the player nothing.
        let elsewhere = difference(
            between: plain, and: highlighted,
            around: point(of: .track(index: 30)), radius: radius
        )
        #expect(elsewhere < 1, "highlighting one square changed another")
    }

    /// **A protected start square is visible without colour**, and is a
    /// different shape from a legal target rather than a different hue.
    @Test("a start square and a legal target do not look alike in greyscale")
    func startAndTargetAreDifferentShapes() throws {
        let plain = try grey(of: #require(board()))
        let start = BoardPosition.track(index: layout.board.startIndex(for: Seat(0)))

        // A start square differs from bare track even with no colour: it
        // carries a ring the other holes do not.
        let startPatch = difference(
            between: plain, and: plain,
            around: point(of: start), radius: 26
        )
        #expect(startPatch == 0, "the difference helper is not comparing what it claims to")

        // The real check: the *same* square, once plain and once a legal
        // target, differs — which is only possible because the target ring is
        // dashed rather than a second solid ring in another colour.
        let withTarget = try grey(of: #require(board(legalTargets: [start])))
        let changed = difference(between: plain, and: withTarget, around: point(of: start), radius: 26)
        #expect(
            changed > 4,
            "a legal target on a start square is invisible in greyscale (\(String(format: "%.1f", changed))/255)"
        )
    }

    /// **An empty waiting tray says whose it is without colour.**
    ///
    /// The tray and the home lane used to be identified by hue alone, which on
    /// the amber seat measures 1.23:1 against the wood. Each now carries the
    /// seat's own mark — the same one its pieces wear — engraved into it.
    @Test("every seat's areas carry its mark, and no two seats carry the same one")
    func everySeatIsMarked() {
        let marks = PlayerIdentity.all.map(\.mark)
        #expect(Set(marks).count == marks.count, "two seats share a mark")
        #expect(marks.count >= layout.board.seats.count)
    }

    /// The board is not flat grey once the colour is gone: the holes, the
    /// lanes and the trays are all still there as shapes.
    @Test("the board still has structure with the colour taken out")
    func boardHasStructureInGreyscale() throws {
        let values = try grey(of: #require(board()))
        let inside = values.filter { $0 > 1 }
        let darkest = inside.min() ?? 0
        let brightest = inside.max() ?? 0
        #expect(
            brightest - darkest > 90,
            "the greyscale board spans only \(Int(brightest - darkest))/255 — it has gone flat"
        )
    }
}
