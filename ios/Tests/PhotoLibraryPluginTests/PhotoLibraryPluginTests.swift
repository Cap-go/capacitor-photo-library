import XCTest
@testable import PhotoLibraryPlugin

class PhotoLibraryPickPresentationTests: XCTestCase {
    func testResolvePickMediaFullScreen_prefersCallValueOverPluginConfig() {
        XCTAssertTrue(PhotoLibraryPickPresentation.resolvePickMediaFullScreen(callValue: true, pluginConfigValue: false))
        XCTAssertFalse(PhotoLibraryPickPresentation.resolvePickMediaFullScreen(callValue: false, pluginConfigValue: true))
    }

    func testResolvePickMediaFullScreen_usesPluginConfigWhenCallOmitted() {
        XCTAssertTrue(PhotoLibraryPickPresentation.resolvePickMediaFullScreen(callValue: nil, pluginConfigValue: true))
        XCTAssertFalse(PhotoLibraryPickPresentation.resolvePickMediaFullScreen(callValue: nil, pluginConfigValue: false))
    }
}