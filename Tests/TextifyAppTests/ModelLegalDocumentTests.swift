@testable import Textify
import CryptoKit
import Foundation
import TextifyModels
import XCTest

final class ModelLegalDocumentTests: XCTestCase {
    func testEveryProductionCatalogLicenseMapsToPinnedBundledText() throws {
        let manifest = try ModelManifest.decode(
            Data(
                contentsOf:
                    repositoryRoot.appendingPathComponent("models/manifest.json")
            )
        )
        let catalogLicenseURLs = Set(
            manifest.models.flatMap(\.licenses).map(\.licenseTextUrl)
        )

        XCTAssertEqual(catalogLicenseURLs, Set(expectedResourcesByLicenseURL.keys))

        for model in manifest.models {
            for license in model.licenses {
                let resourceName = try XCTUnwrap(
                    BundledModelLicenseResourceResolver.resourceName(
                        for: license.licenseTextUrl
                    ),
                    "\(model.id) has no bundled text for \(license.licenseTextUrl)"
                )
                XCTAssertEqual(
                    resourceName,
                    expectedResourcesByLicenseURL[license.licenseTextUrl],
                    "\(model.id) resolved the wrong bundled legal document"
                )
            }
        }

        for (resourceName, expectedSHA256) in expectedSHA256ByResource {
            let data = try Data(contentsOf: repositoryURL(for: resourceName))
            let actualSHA256 = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
            XCTAssertEqual(
                actualSHA256,
                expectedSHA256,
                "\(resourceName) does not match its reviewed source bytes"
            )
        }
    }

    func testUnknownLicenseURLFailsClosed() {
        XCTAssertNil(
            BundledModelLicenseResourceResolver.resourceName(
                for: "https://example.com/mutable-license"
            )
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func repositoryURL(for resourceName: String) -> URL {
        resourceName == "LICENSE"
            ? repositoryRoot.appendingPathComponent(resourceName)
            : repositoryRoot
                .appendingPathComponent("THIRD_PARTY_LICENSES")
                .appendingPathComponent(resourceName)
    }

    private var expectedResourcesByLicenseURL: [String: String] {
        [
            "https://github.com/Player0109/Textify/releases/download/models-v1/ggml-small.en-q5_1.LICENSES.txt":
                "ggml-small.en-q5_1.LICENSES.txt",
            "https://raw.githubusercontent.com/openai/whisper/04f449b8a437f1bbd3dba5c9f826aca972e7709a/LICENSE":
                "OpenAI-Whisper.txt",
            "https://raw.githubusercontent.com/ggerganov/whisper.cpp/a8d002cfd879315632a579e73f0148d06959de36/LICENSE":
                "whisper.cpp.txt",
            "https://raw.githubusercontent.com/Blaizzy/mlx-audio-swift/d302a5c6080d2bb97bae38c7418f82abb76013b6/LICENSE":
                "MLXAudioSwift.txt",
            "https://raw.githubusercontent.com/ml-explore/mlx-swift/61b9e011e09a62b489f6bd647958f1555bdf2896/LICENSE":
                "MLXSwift.txt",
            "https://raw.githubusercontent.com/microsoft/onnxruntime/v1.24.4/LICENSE":
                "ONNX_Runtime.txt",
            "https://raw.githubusercontent.com/handy-computer/transcribe.cpp/5a5a49664a8ea1f0e5b3be1dfc544730d1b62561/LICENSE":
                "transcribe.cpp.txt",
            "https://www.apache.org/licenses/LICENSE-2.0.txt":
                "LICENSE",
            "https://raw.githubusercontent.com/FluidInference/FluidAudio/19600a485baa4998812e4654b70d2bab8f2c9949/LICENSE":
                "FluidAudio.txt",
            "https://raw.githubusercontent.com/k2-fsa/sherpa-onnx/13d0ae6c539d2809d32f5eaa3ef1db0c459d0b24/LICENSE":
                "sherpa-onnx.txt",
            "https://creativecommons.org/licenses/by/4.0/legalcode":
                "CC-BY-4.0.txt",
            "https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/":
                "NVIDIA_Open_Model_License.txt",
            "https://openmdw.ai/license/1-1/":
                "OpenMDW-1.1.txt",
            "https://raw.githubusercontent.com/modelscope/FunASR/38e421b0c49963a6f46ae2ebbaa24bc5168cc707/MODEL_LICENSE":
                "FunASR_Model_License_1.1.txt",
        ]
    }

    private var expectedSHA256ByResource: [String: String] {
        [
            "LICENSE":
                "c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4",
            "CC-BY-4.0.txt":
                "9ba9550ad48438d0836ddab3da480b3b69ffa0aac7b7878b5a0039e7ab429411",
            "FluidAudio.txt":
                "c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4",
            "FunASR_Model_License_1.1.txt":
                "7dba975a2069691db4992b0592d70828b330d2f8a30a71450f4e152a554e84f8",
            "MLXAudioSwift.txt":
                "fd330bb5d9adf9e65bfe4d8f6f90c808a4196ef5c98aad018a3344256fcb2374",
            "MLXSwift.txt":
                "44326a4ea062241ae6fc26ee2ec90bdc81af7eb7b9d3966181b733fa69d42057",
            "NVIDIA_Open_Model_License.txt":
                "1e62abdfd004da72038581ea98b9dd3a94b7b859d66efa6b13e2992a523ef5cd",
            "ONNX_Runtime.txt":
                "2f07c72751aed99790b8a4869cf2311df85a860b22ded05fa22803587a48922c",
            "OpenAI-Whisper.txt":
                "b5d65a59060e68c4ff940e1eddfa6f94b2d68fdf58ed7f4dd57721c997e35e9d",
            "OpenMDW-1.1.txt":
                "46f043dbe040e781acdf5fd0cfbbdc1662eec4a23a08d0646b061511b2e7f97b",
            "ggml-small.en-q5_1.LICENSES.txt":
                "5745650da468d88786f6805e04b3458f69f5d884d9aa82fe39a00bb41b59cd1e",
            "sherpa-onnx.txt":
                "cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30",
            "transcribe.cpp.txt":
                "86a53633b56f6b029d3cb42158bcc7aac0cdff898aceb13e83b93e368bbc4ac6",
            "whisper.cpp.txt":
                "e562a2ddfaf8280537795ac5ecd34e3012b6582a147ef69ba6a6a5c08c84757d",
        ]
    }
}
