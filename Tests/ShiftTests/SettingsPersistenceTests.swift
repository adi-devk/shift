import XCTest
@testable import Shift

final class SettingsPersistenceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: AppSettings.storageKey)
    }

    func testSearchEnginePersistence() {
        var settings = AppSettings.load()
        XCTAssertEqual(settings.defaultSearchEngine, .duckDuckGo)

        // Switch to Google and save
        settings.defaultSearchEngine = .google
        settings.save()

        // Reload fresh from disk
        let reloaded = AppSettings.load()
        XCTAssertEqual(reloaded.defaultSearchEngine, .google, "Search engine setting must persist to Google across restarts")
    }

    func testEngineAutoSavesSettingsOnMutation() async {
        let engine = await MainActor.run {
            ShiftDownloadEngine()
        }

        await MainActor.run {
            engine.settings.defaultSearchEngine = .google
        }

        let reloaded = AppSettings.load()
        XCTAssertEqual(reloaded.defaultSearchEngine, .google, "Engine didSet must automatically persist mutated settings to UserDefaults")
    }

    func testLogFilesNeverAppearInUserFilesList() {
        let storage = FileStorageService.shared
        let files = storage.listFiles()
        for file in files {
            XCTAssertFalse(file.name.hasSuffix(".log"), "User files list must never contain internal .log files")
            XCTAssertFalse(file.name.hasPrefix("."), "User files list must never contain hidden dotfiles")
        }
    }
}
