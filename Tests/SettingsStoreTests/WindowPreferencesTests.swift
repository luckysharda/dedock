import Foundation
import Testing
@testable import SettingsStore

/// T37b: Window appearance and Window material (design.md §7.2).
@Suite struct WindowPreferencesTests {
    @Test func defaultsAreSystemAndFrosted() {
        #expect(AppPreferences().windowAppearance == .system)
        #expect(AppPreferences().windowMaterial == .frosted)
        // A file from before T37b has neither key.
        let old = AppPreferences(object: ["showStatusItem": .bool(true)])
        #expect(old.windowAppearance == .system && old.windowMaterial == .frosted)
    }

    @Test func valuesRoundTrip() {
        for a in AppPreferences.WindowAppearance.allCases {
            for m in AppPreferences.WindowMaterial.allCases {
                let p = AppPreferences(windowAppearance: a, windowMaterial: m)
                let back = AppPreferences(object: p.knownObject)
                #expect(back == p)
            }
        }
        #expect(AppPreferences().knownObject["windowMaterial"] == .string("frosted"))
    }

    @Test func unknownValuesFallBackToTheDefaults() {
        let p = AppPreferences(object: ["windowAppearance": .string("sepia"), "windowMaterial": .number(3)])
        #expect(p.windowAppearance == .system && p.windowMaterial == .frosted)
        #expect(p.unknown.isEmpty)       // known keys with bad values are not kept as unknown
    }
}
