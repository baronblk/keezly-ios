@testable import Keezly
import SwiftUI
import Testing
import UIKit

/// §79 — the icon is compared before it is chosen, and checked at the size it
/// is actually seen at.
///
/// Rendering every concept at every size is also how the comparison sheet is
/// produced: the pictures a decision is made from come out of the same code
/// that ships, so there is no drawing-program original to drift away from.
///
/// The run also writes the sheet into the host app's Documents directory
/// inside the simulator, where `scripts/icon-sheet.sh` collects it. That is a
/// throwaway sandbox, not the repository, so there is nothing to clean up and
/// nothing to remember to switch on.
@Suite("App icon")
@MainActor
struct AppIconTests {

    /// The sizes an iOS icon is actually drawn at, in points at 1× — the App
    /// Store master, the home screen, Spotlight, Settings and notifications.
    static let sizes: [CGFloat] = [1024, 180, 120, 60, 40, 29]

    private func render(
        _ concept: IconConcept,
        side: CGFloat,
        mask: Bool = false,
        appearance: ColorScheme = .light
    ) -> UIImage? {
        let renderer = ImageRenderer(
            content: AppIconArtwork(concept: concept, side: side, isMask: mask)
                .environment(\.colorScheme, appearance)
        )
        renderer.scale = 1
        renderer.isOpaque = true
        return renderer.uiImage
    }

    // MARK: - Every concept renders, at every size

    @Test("every concept renders at every size an icon is drawn at", arguments: IconConcept.allCases)
    func conceptsRender(concept: IconConcept) throws {
        for side in Self.sizes {
            let image = try #require(render(concept, side: side), "\(concept.rawValue) at \(side) produced nothing")
            #expect(image.size.width == side)
            #expect(image.size.height == side, "an icon must be square")
        }
    }

    /// **The icon has to survive being shrunk to 29 points.**
    ///
    /// A concept that turns to mush at Settings size has failed, however well
    /// it reads at 1024. Measured as the spread of pixel values: a 29-point
    /// render that has collapsed towards one flat colour has lost its subject.
    @Test("every concept still has a subject at 29 points", arguments: IconConcept.allCases)
    func conceptsSurviveShrinking(concept: IconConcept) throws {
        let small = try #require(render(concept, side: 29))
        let spread = try contrastSpread(of: small)
        #expect(spread > 0.2, "\(concept.rawValue) is nearly flat at 29 points (spread \(spread))")
    }

    /// The tinted appearance is a mask: iOS supplies the colour, so the
    /// artwork must carry its shape in luminance alone.
    @Test("every concept works as a tinted mask", arguments: IconConcept.allCases)
    func conceptsWorkAsMasks(concept: IconConcept) throws {
        let mask = try #require(render(concept, side: 180, mask: true))
        let spread = try contrastSpread(of: mask)
        #expect(spread > 0.25, "\(concept.rawValue) has no shape without its colour")
    }

    /// Three genuinely different pictures, not one picture three ways.
    @Test("the concepts are actually different from each other")
    func conceptsDiffer() throws {
        var renders: [String: [UInt8]] = [:]
        for concept in IconConcept.allCases {
            renders[concept.rawValue] = try pixels(of: #require(render(concept, side: 120)))
        }
        let names = Array(renders.keys).sorted()
        for (index, one) in names.enumerated() {
            for other in names[(index + 1)...] {
                let first = try #require(renders[one])
                let second = try #require(renders[other])
                let differing = zip(first, second).count { abs(Int($0) - Int($1)) > 8 }
                let share = Double(differing) / Double(first.count)
                #expect(share > 0.15, "\(one) and \(other) are \(Int((1 - share) * 100))% the same picture")
            }
        }
    }

    @Test("each concept says what it is arguing for")
    func conceptsCarryTheirArgument() {
        for concept in IconConcept.allCases {
            #expect(concept.argument.count > 30, "\(concept.rawValue) has no argument recorded")
        }
        #expect(IconConcept.allCases.count >= 3, "a choice needs something to choose between")
    }

    // MARK: - The comparison sheet

    /// Writes every concept at every size, plus the masks, for a decision to be
    /// made from.
    @Test("the comparison sheet is produced")
    func writesTheSheet() throws {
        // Inside the simulator's own container: the test runs on the device,
        // so a path from the Mac would not exist here.
        let documents = try #require(
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        )
        let folder = documents.appending(path: "icons")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        for concept in IconConcept.allCases {
            for side in Self.sizes {
                let image = try #require(render(concept, side: side))
                let data = try #require(image.pngData())
                try data.write(to: folder.appending(path: "\(concept.rawValue)-\(Int(side)).png"))
            }
            let mask = try #require(render(concept, side: 180, mask: true))
            try #require(mask.pngData()).write(to: folder.appending(path: "\(concept.rawValue)-mask.png"))
        }

        // The three 1024 renders the asset catalogue wants, from the chosen
        // concept: the default appearance, the dark one, and the grayscale
        // mask iOS tints for itself.
        let shipping: [(String, UIImage?)] = [
            ("AppIcon-1024", render(IconConcept.chosen, side: 1024)),
            ("AppIcon-dark-1024", render(IconConcept.chosen, side: 1024, appearance: .dark)),
            ("AppIcon-tinted-1024", render(IconConcept.chosen, side: 1024, mask: true)),
        ]
        for (name, image) in shipping {
            let rendered = try #require(image, "\(name) produced nothing")
            let data = try #require(rendered.pngData())
            try data.write(to: folder.appending(path: "\(name).png"))
        }
    }

    // MARK: - Reading pixels

    private func pixels(of image: UIImage) throws -> [UInt8] {
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
        return buffer
    }

    /// How far the brightest and darkest parts of an image are apart, 0 to 1.
    private func contrastSpread(of image: UIImage) throws -> Double {
        let buffer = try pixels(of: image)
        var darkest = 255.0
        var brightest = 0.0
        for index in stride(from: 0, to: buffer.count, by: 4) {
            let alpha = Double(buffer[index + 3]) / 255
            guard alpha > 0.5 else { continue }
            let value = (Double(buffer[index]) + Double(buffer[index + 1]) + Double(buffer[index + 2])) / 3
            darkest = min(darkest, value)
            brightest = max(brightest, value)
        }
        guard brightest >= darkest else { return 0 }
        return (brightest - darkest) / 255
    }
}
