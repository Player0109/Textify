import Foundation
import SwiftUI
import TextifyModels

struct ModelSourceLicensePresentation: Equatable {
    struct SignedFile: Equatable, Identifiable {
        let filename: String
        let relativePath: String?
        let sha256: String
        let sizeBytes: Int64

        var id: String {
            relativePath ?? filename
        }
    }

    struct License: Equatable, Identifiable {
        let scope: String
        let spdxID: String
        let name: String
        let licenseTextURL: String

        var id: String {
            "\(scope)|\(licenseTextURL)"
        }
    }

    let sourceName: String
    let sourceURL: URL?
    let sourceRevision: String
    let sourceFile: String
    let originalModelName: String
    let originalModelURL: URL?
    let files: [SignedFile]
    let licenses: [License]

    init(model: ModelEntry) {
        sourceName = model.provenance.sourceName
        sourceURL = URL(string: model.provenance.sourceUrl)
        sourceRevision = model.provenance.sourceRevision
        sourceFile = model.provenance.sourceFile
        originalModelName = model.provenance.originalModelName
        originalModelURL = URL(string: model.provenance.originalModelUrl)
        files = model.files.map {
            SignedFile(
                filename: $0.filename,
                relativePath: $0.relativePath,
                sha256: $0.sha256,
                sizeBytes: $0.sizeBytes
            )
        }
        licenses = model.licenses.map {
            License(
                scope: $0.scope,
                spdxID: $0.spdxId,
                name: $0.name,
                licenseTextURL: $0.licenseTextUrl
            )
        }
    }
}

enum BundledModelLicenseResourceResolver {
    static let noticeResourceName = "THIRD_PARTY_NOTICES.md"

    private static let resourceNamesByLicenseTextURL: [String: String] = [
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

    static func resourceName(for licenseTextURL: String) -> String? {
        resourceNamesByLicenseTextURL[licenseTextURL]
    }

    static func resourceURL(
        named resourceName: String,
        in bundle: Bundle = .main
    ) -> URL? {
        let filename = resourceName as NSString
        let pathExtension = filename.pathExtension
        let baseName = filename.deletingPathExtension
        return bundle.url(
            forResource: baseName,
            withExtension: pathExtension.isEmpty ? nil : pathExtension
        )
    }
}

struct ModelSourceLicenseButton: View {
    let presentation: ModelSourceLicensePresentation

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Label(
                "View Offline License & Notices",
                systemImage: "doc.text.magnifyingglass"
            )
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .sheet(isPresented: $isPresented) {
            ModelSourceLicenseSheet(presentation: presentation)
        }
    }
}

private struct ModelSourceLicenseSheet: View {
    private struct Document: Identifiable {
        let id: String
        let title: String
        let resourceName: String?
    }

    let presentation: ModelSourceLicensePresentation

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDocumentID: String
    private let documents: [Document]

    init(presentation: ModelSourceLicensePresentation) {
        self.presentation = presentation

        var documents = [
            Document(
                id: BundledModelLicenseResourceResolver.noticeResourceName,
                title: "Third-Party Notices",
                resourceName:
                    BundledModelLicenseResourceResolver.noticeResourceName
            ),
        ]

        for license in presentation.licenses {
            documents.append(
                Document(
                    id: "license|\(license.id)",
                    title: "\(license.spdxID) — \(license.scope)",
                    resourceName:
                        BundledModelLicenseResourceResolver.resourceName(
                            for: license.licenseTextURL
                        )
                )
            )
        }

        self.documents = documents
        _selectedDocumentID = State(initialValue: documents[0].id)
    }

    var body: some View {
        NavigationStack {
            HSplitView {
                ScrollView {
                    sourceAndFiles
                        .padding(20)
                }
                .frame(minWidth: 280, idealWidth: 340, maxWidth: 420)

                VStack(alignment: .leading, spacing: 12) {
                    Picker("Document", selection: $selectedDocumentID) {
                        ForEach(documents) { document in
                            Text(document.title).tag(document.id)
                        }
                    }
                    .pickerStyle(.menu)

                    ScrollView {
                        Text(selectedDocumentText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                }
                .padding(20)
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Source, License & Notices")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 760, minHeight: 560)
    }

    private var sourceAndFiles: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ORIGINAL MODEL")
                    .font(.caption2.bold().monospaced())
                    .foregroundStyle(.secondary)
                Text(presentation.originalModelName)
                    .font(.headline)
                if let originalModelURL = presentation.originalModelURL {
                    Link("Open original model page", destination: originalModelURL)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("PINNED SOURCE")
                    .font(.caption2.bold().monospaced())
                    .foregroundStyle(.secondary)
                Text(presentation.sourceName)
                    .font(.headline)
                Text("Revision \(presentation.sourceRevision)")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Text("Source file: \(presentation.sourceFile)")
                    .font(.caption)
                    .textSelection(.enabled)
                if let sourceURL = presentation.sourceURL {
                    Link("Open upstream source", destination: sourceURL)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("SIGNED FILES")
                    .font(.caption2.bold().monospaced())
                    .foregroundStyle(.secondary)
                ForEach(presentation.files) { file in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.relativePath ?? file.filename)
                            .font(.caption.weight(.semibold))
                            .textSelection(.enabled)
                        Text(
                            ByteCountFormatter.string(
                                fromByteCount: file.sizeBytes,
                                countStyle: .file
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        Text(file.sha256)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("LICENSE SCOPES")
                    .font(.caption2.bold().monospaced())
                    .foregroundStyle(.secondary)
                ForEach(presentation.licenses) { license in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(license.spdxID) — \(license.name)")
                            .font(.caption.weight(.semibold))
                        Text(license.scope)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var selectedDocumentText: String {
        guard let document = documents.first(
            where: { $0.id == selectedDocumentID }
        ),
        let resourceName = document.resourceName,
        let resourceURL = BundledModelLicenseResourceResolver.resourceURL(
            named: resourceName
        ),
        let contents = try? String(contentsOf: resourceURL, encoding: .utf8)
        else {
            return "This bundled legal document is unavailable. Do not install the model from this build."
        }
        return contents
    }
}
