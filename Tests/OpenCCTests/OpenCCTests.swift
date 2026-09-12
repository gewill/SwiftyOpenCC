import Foundation
import XCTest
import copencc
@testable import OpenCC

private let officialOptions: [String: ChineseConverter.Options] = [
    "s2t": [.traditionalize], "t2s": [.simplify],
    "s2hk": [.traditionalize, .hkStandard], "hk2s": [.simplify, .hkStandard],
    "s2tw": [.traditionalize, .twStandard], "tw2s": [.simplify, .twStandard],
    "s2twp": [.traditionalize, .twStandard, .twIdiom],
    "tw2sp": [.simplify, .twStandard, .twIdiom],
    "t2hk": [.hkStandard], "t2tw": [.twStandard]
]

private struct Fixture: Decodable {
    let id: String
    let input: String
    let expected: [String: String]
}
private struct Fixtures: Decodable { let cases: [Fixture] }

final class OpenCCTests: XCTestCase {
    func testOfficialConversionFixtures() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "testcases", withExtension: "json", subdirectory: "testcases"))
        let fixtures = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
        let converters = try officialOptions.mapValues { try ChineseConverter(options: $0) }
        // These official modes cannot be expressed by the existing public Options.
        // In particular, tw2t must never be mislabeled as .traditionalize (s2t).
        let unsupported: Set<String> = ["hk2t", "tw2t", "jp2t", "t2jp", "s2hkp", "hk2sp"]
        var coverage: [String: Int] = [:]
        for fixture in fixtures.cases {
            for (mode, expected) in fixture.expected {
                guard let converter = converters[mode] else {
                    XCTAssertTrue(unsupported.contains(mode), "Unclassified upstream fixture mode: \(mode)")
                    continue
                }
                XCTAssertEqual(converter.convert(fixture.input), expected, "\(fixture.id): \(mode)")
                coverage[mode, default: 0] += 1
            }
        }
        XCTAssertEqual(Set(coverage.keys), Set(officialOptions.keys), "Every supported official mode needs fixtures")
        XCTAssertGreaterThan(coverage.values.reduce(0, +), 100)
        print("Official fixture coverage: \(coverage.sorted { $0.key < $1.key })")
    }

    func testAllOptionCombinationsAndPrecedence() throws {
        let flags: [ChineseConverter.Options] = [.traditionalize, .simplify, .twStandard, .hkStandard, .twIdiom]
        let expectedNames = [
            "s2t", "s2t", "t2s", "s2t", "t2tw", "s2tw", "tw2s", "s2tw",
            "t2hk", "s2hk", "hk2s", "s2hk", "t2hk", "s2hk", "hk2s", "s2hk",
            "s2t", "legacy-s2t-tw-idiom", "legacy-t2s-tw-idiom", "legacy-s2t-tw-idiom",
            "t2tw", "s2twp", "tw2sp", "s2twp", "t2hk", "legacy-s2hk-tw-idiom",
            "legacy-hk2s-tw-idiom", "legacy-s2hk-tw-idiom", "t2hk", "legacy-s2hk-tw-idiom",
            "legacy-hk2s-tw-idiom", "legacy-s2hk-tw-idiom"
        ]
        var outputs: [String: String] = [:]
        for mask in 0..<32 {
            var options: ChineseConverter.Options = []
            for index in 0..<5 where mask & (1 << index) != 0 { options.formUnion(flags[index]) }
            let converter = try ChineseConverter(options: options)
            XCTAssertEqual(converter.configurationName, expectedNames[mask], "mask \(mask)")
            let output = converter.convert("鼠标里面的硅二极管坏了，台湾滑鼠裡面的矽二極體壞了。")
            if let existing = outputs[expectedNames[mask]] { XCTAssertEqual(output, existing) }
            outputs[expectedNames[mask]] = output
            let unknownBits = ChineseConverter.Options(rawValue: options.rawValue | (1 << 20))
            XCTAssertEqual(unknownBits.configurationName, expectedNames[mask])
        }
        XCTAssertEqual(outputs.count, 14)
    }

    func testLegacyConfigurations() throws {
        let cases: [(ChineseConverter.Options, String, String)] = [
            ([.traditionalize, .twIdiom], "鼠标里面的硅二极管", "滑鼠裏面的矽二極體"),
            ([.traditionalize, .hkStandard, .twIdiom], "鼠标里面的硅二极管", "滑鼠裏面的矽二極體"),
            ([.simplify, .twIdiom], "滑鼠裡面的矽二極體", "鼠标里面的硅二极管"),
            ([.simplify, .hkStandard, .twIdiom], "滑鼠裏面的矽二極體", "鼠标里面的硅二极管")
        ]
        for (options, input, expected) in cases {
            XCTAssertEqual(try ChineseConverter(options: options).convert(input), expected)
        }
    }

    func testEmbeddedNullsAndUnicodeBoundaries() throws {
        let options = Array(officialOptions.values) + [
            [.traditionalize, .twIdiom], [.traditionalize, .hkStandard, .twIdiom],
            [.simplify, .twIdiom], [.simplify, .hkStandard, .twIdiom]
        ]
        let fixtures = ["", "\0", "\0\0", "鼠标\0汉字", "\0鼠标\0\0汉字\0",
                        "\r\n👨‍👩‍👧‍👦e\u{301}台湾\t\u{2028}\r\n", String(repeating: "a", count: 3999) + "鼠标"]
        for option in options {
            let converter = try ChineseConverter(options: option)
            for input in fixtures {
                let expected = input.split(separator: "\0", omittingEmptySubsequences: false)
                    .map { converter.convert(String($0)) }.joined(separator: "\0")
                XCTAssertEqual(converter.convert(input), expected, "\(converter.configurationName): \(input.debugDescription)")
            }
            XCTAssertEqual(converter.convert("\r\n👨‍👩‍👧‍👦e\u{301}\t\u{2028}\r\n"), "\r\n👨‍👩‍👧‍👦e\u{301}\t\u{2028}\r\n")
        }
        XCTAssertEqual(try ChineseConverter(options: [.traditionalize, .twIdiom]).convert("\0鼠标\0\0汉字\0"), "\0滑鼠\0\0漢字\0")
    }

    func testNativeHandleLifetime() throws {
        let convertersBefore = CCConverterGetLiveHandleCount()
        let stringsBefore = STLStringGetLiveHandleCount()
        for _ in 0..<100 {
            try autoreleasepool {
                let converter = try ChineseConverter(options: [.traditionalize, .twStandard, .twIdiom])
                XCTAssertEqual(CCConverterGetLiveHandleCount(), convertersBefore + 1)
                XCTAssertEqual(converter.convert("鼠标"), "滑鼠")
                XCTAssertEqual(STLStringGetLiveHandleCount(), stringsBefore)
            }
        }
        XCTAssertEqual(CCConverterGetLiveHandleCount(), convertersBefore)
        XCTAssertEqual(STLStringGetLiveHandleCount(), stringsBefore)
    }

    func testConcurrentCreationAndSharedConversion() throws {
        let shared = try ChineseConverter(options: [.traditionalize, .twStandard, .twIdiom])
        let lock = NSLock()
        var failures: [String] = []
        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            do {
                let local = try ChineseConverter(options: [.traditionalize, .twStandard, .twIdiom])
                if local.convert("鼠标\0汉字") != "滑鼠\0漢字" || shared.convert("鼠标\0汉字") != "滑鼠\0漢字" {
                    lock.lock(); failures.append("Wrong concurrent result"); lock.unlock()
                }
            } catch {
                lock.lock(); failures.append(String(describing: error)); lock.unlock()
            }
        }
        XCTAssertEqual(failures, [])
    }

    func testMissingConfigurationErrorDoesNotCreateNativeHandle() {
        let count = CCConverterGetLiveHandleCount()
        XCTAssertThrowsError(try ChineseConverter(configurationName: "missing",
            configurationURL: URL(fileURLWithPath: "/__swiftyopencc_missing__/missing.json"),
            dictionaryDirectory: URL(fileURLWithPath: "/__swiftyopencc_missing__"))) { error in
            guard case ConversionError.fileNotFound = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(CCConverterGetLiveHandleCount(), count)
    }
}
