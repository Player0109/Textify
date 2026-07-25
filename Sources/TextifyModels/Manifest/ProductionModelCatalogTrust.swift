import Foundation

public enum ProductionModelCatalogTrust {
    public static let bundleIdentifier = "io.github.Player0109.Textify"

    public static let manifestURL = URL(
        string:
            "https://player0109.github.io/Textify/models/manifest.json"
    )!
    public static let manifestSignatureURL = URL(
        string:
            "https://player0109.github.io/Textify/models/manifest.json.sig"
    )!
    public static let revocationURL = URL(
        string:
            "https://player0109.github.io/Textify/models/revocations.json"
    )!
    public static let revocationSignatureURL = URL(
        string:
            "https://player0109.github.io/Textify/models/revocations.json.sig"
    )!

    public static let trustedKeys = [
        TrustedModelManifestKey(
            keyId: "textify-model-manifest-2026-primary",
            publicKeyBase64:
                "mLO7nEpXKrM6LkuQrMrpXtGDaJFEQWQivS9Hxm8RWY0="
        ),
        TrustedModelManifestKey(
            keyId: "textify-model-manifest-2026-reserve",
            publicKeyBase64:
                "4U2qV+TakjtL2HleKRPAhpd9LTTIfhGEmvZR4Opc1ZM="
        ),
        TrustedModelManifestKey(
            keyId: "textify-model-manifest-2026-huggingface",
            publicKeyBase64:
                "eg6XVGVQ4Kqh1dtN3B8JcFTtK0RSxkxd79W5tfIlfos="
        ),
    ]

    public static var trustedKeyIDs: Set<String> {
        Set(trustedKeys.map(\.keyId))
    }
}
