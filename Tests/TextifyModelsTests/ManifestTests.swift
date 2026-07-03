import TextifyModels
import XCTest

final class ManifestTests: XCTestCase {
    private static func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name,
                withExtension: nil,
                subdirectory: "Fixtures/Models"
            )
        )
        return try Data(contentsOf: url)
    }

    private static var validManifestData: Data {
        get throws {
            try fixtureData("manifest.json")
        }
    }

    private static var validManifestJSONWithUnknownField: String {
        get throws {
            String(decoding: try fixtureData("manifest_unknown_field.json"), as: UTF8.self)
        }
    }

    func testManifestParsesInitialCuratedModelShape() throws {
        let manifest = try ModelManifest.decode(try Self.validManifestData)
        XCTAssertEqual(manifest.manifestVersion, 1)
        XCTAssertEqual(manifest.models.first?.id, ProductionModelPolicy.requiredModelID)
        XCTAssertEqual(manifest.models.first?.runtimeParameters.language, "en")
        XCTAssertEqual(manifest.models.first?.runtimeParameters.temperatureFallback, [])
    }

    func testUnknownFieldsAreRejected() throws {
        let data = Data((try Self.validManifestJSONWithUnknownField).utf8)
        XCTAssertThrowsError(try ModelManifest.decode(data))
    }
}
