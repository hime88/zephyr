import XCTest
@testable import ZephyrCore

/// InstallODA download-URL regression net: ODA's guestfiles endpoint
/// serves unversioned filenames (a `_27.1`-style infix returns 404),
/// so pin the shape of every configured URL. Liveness itself is
/// verified manually against the endpoint, not from this suite.
@MainActor
final class InstallODAURLTests: XCTestCase {

    func testFallbackURLsAreUnversionedGuestfilesLinks() throws {
        let expectedExtensions = [
            "windows": "msi",
            "macos_arm64": "dmg",
            "macos_x64": "dmg",
            "linux": "AppImage",
        ]
        XCTAssertEqual(
            Set(InstallODACommand.fallbackURLs.keys),
            Set(expectedExtensions.keys))
        for (key, string) in InstallODACommand.fallbackURLs {
            guard let url = URL(string: string),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            else {
                return XCTFail("\(key): not a parseable URL: \(string)")
            }
            XCTAssertEqual(url.scheme, "https", key)
            XCTAssertEqual(components.host, "www.opendesign.com", key)
            XCTAssertEqual(components.path, "/guestfiles/get", key)
            let filename = components.queryItems?.first {
                $0.name == "filename"
            }?.value ?? ""
            XCTAssertFalse(filename.isEmpty, key)
            XCTAssertNil(
                filename.range(of: "_\\d+\\.\\d+\\.", options: .regularExpression),
                "\(key): versioned filename 404s on guestfiles: \(filename)")
            XCTAssertTrue(
                filename.hasSuffix(".\(expectedExtensions[key]!)"), "\(key): \(filename)")
        }
    }
}
