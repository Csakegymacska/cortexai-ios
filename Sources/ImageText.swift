import Foundation
import UIKit
import Vision

/// Szöveg olvasása fényképről, a készüléken.
///
/// A kép nem hagyja el a telefont: a Vision a helyi szövegfelismerést futtatja, és a
/// kiolvasott szöveg kerül a beviteli mezőbe. Így egy képernyőkép, egy könyvlap vagy egy
/// idegen nyelvű felirat is bekerülhet a beszélgetésbe anélkül, hogy bármit feltöltenénk.
enum ImageText {
    /// A kép szövege, soronként. Üres, ha nincs benne olvasható szöveg.
    static func recognize(in data: Data) async -> String {
        // A Data Sendable, a UIImage nem — ezért a dekódolás már a háttérfeladaton belül történik.
        return await Task.detached(priority: .userInitiated) { () -> String in
            guard let image = UIImage(data: data), let cg = image.cgImage else { return "" }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["hu-HU", "en-US"]
            do {
                try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
            } catch {
                return ""
            }
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: "\n")
        }.value
    }
}
