import AppKit
import Foundation
import XCTest

@testable import Textify

final class ModelCatalogCheckpointStringCatalogTests: XCTestCase {
    func testCheckpointFirstCriticalLabelsShipInTheEnglishStringCatalog()
        throws
    {
        let strings = try catalogStrings()
        let criticalLabels = [
            "%lld versions",
            "%@ does not support %@. Change Dictation Language to %@ and continue?",
            "Action %@",
            "Browse All Languages",
            "Checkpoint",
            "Change Dictation Language?",
            "Choose the version Textify should use.",
            "Close",
            "Compare Versions",
            "Dictation Language",
            "Download Size",
            "Download and Enable",
            "Downloading %@. Textify will verify it before activation.",
            "Downloading the selected version. Textify will verify it, then make it active.",
            "Does not support %@",
            "Enable Voice Cleaning",
            "Finish Current Dictation before changing models.",
            "In Use",
            "Install Only",
            "Installed Files",
            "Installed Models",
            "Model Details",
            "No action",
            "Not Comparable",
            "Not installed",
            "Recommended",
            "Remove",
            "Revoked",
            "Search all models",
            "Select",
            "Technical Details",
            "Textify could not start this download. Check Downloads and try again.",
            "Textify could not verify the model list included with this app. Reinstall or update Textify. Existing local dictation may continue with an already loaded model; no catalog actions are available.",
            "The current model does not support %@. Choose a compatible model to use this dictation language.",
            "The selected version was not installed, so the current model is unchanged.",
            "The selected version was revoked and was not activated.",
            "Use",
            "Use %@",
            "Use Language Filter",
            "Use Selected Version",
            "Version",
            "Versions",
            "Voice cleaning is off.",
            "Wait for the current dictation to finish, then try again.",
        ]

        for label in criticalLabels {
            let entry = try XCTUnwrap(
                strings[label] as? [String: Any],
                "Missing checkpoint-first localization key \(label)"
            )
            let localizations = try XCTUnwrap(
                entry["localizations"] as? [String: Any]
            )
            XCTAssertEqual(Set(localizations.keys), ["en"])
        }
    }

    func testSharedLayoutPolicyIsExercisedWithPseudoExpandedAndRTLLabels()
        throws
    {
        let values = try englishValues()
        let base = measuredMetrics(replacements: values)
        let pseudo = measuredMetrics(
            replacements: values.mapValues {
                "［\($0.flatMap { "\($0)\($0)" })］"
            }
        )
        let rtl = measuredMetrics(
            replacements: values.mapValues {
                "\u{2067}\($0)\u{2069}"
            }
        )

        XCTAssertGreaterThan(
            ModelCheckpointLayoutPolicy(metrics: pseudo).requiredWideWidth,
            ModelCheckpointLayoutPolicy(metrics: base).requiredWideWidth
        )
        XCTAssertEqual(
            ModelCheckpointLayoutPolicy(metrics: rtl).mode(
                availableWidth:
                    ModelCheckpointLayoutPolicy(metrics: rtl)
                    .requiredWideWidth,
                previous: .wide
            ),
            .wide
        )
    }

    func testSecurityFailureOffersNoCatalogAction() {
        XCTAssertNil(
            ModelCatalogEmptyPresentation
                .securityFailure(.transcription)
                .actionTitle
        )
    }

    private func catalogStrings() throws -> [String: Any] {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Localizable.xcstrings")
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: catalogURL)
            ) as? [String: Any]
        )
        return try XCTUnwrap(object["strings"] as? [String: Any])
    }

    private func englishValues() throws -> [String: String] {
        try catalogStrings().reduce(into: [:]) { result, entry in
            guard
                let value =
                    ((entry.value as? [String: Any])?[
                        "localizations"
                    ] as? [String: Any])?["en"] as? [String: Any],
                let stringUnit = value["stringUnit"] as? [String: Any],
                let text = stringUnit["value"] as? String
            else {
                return
            }
            result[entry.key] = text
        }
    }

    private func measuredMetrics(
        replacements: [String: String]
    ) -> ModelCheckpointLayoutMetrics {
        ModelCheckpointLayoutMetrics.measured { source in
            let text = replacements[source] ?? source
            return ceil(
                (text as NSString).size(
                    withAttributes: [
                        .font: NSFont.systemFont(
                            ofSize: NSFont.smallSystemFontSize
                        )
                    ]
                ).width
            )
        }
    }
}
