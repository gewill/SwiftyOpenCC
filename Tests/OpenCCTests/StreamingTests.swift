import Foundation
import XCTest
import copencc
@testable import OpenCC

final class StreamingTests: XCTestCase {
    private let modes: [ChineseConverter.Options] = [
        [.traditionalize], [.simplify], [.traditionalize, .hkStandard],
        [.simplify, .hkStandard], [.traditionalize, .twStandard], [.simplify, .twStandard],
        [.traditionalize, .twStandard, .twIdiom], [.simplify, .twStandard, .twIdiom],
        [.hkStandard], [.twStandard], [.traditionalize, .twIdiom],
        [.traditionalize, .hkStandard, .twIdiom], [.simplify, .twIdiom], [.simplify, .hkStandard, .twIdiom]
    ]

    private func streamed(_ data: Data, converter: ChineseConverter, chunkSize: Int) throws -> Data {
        let stream = try converter.makeStream()
        var output = Data()
        for start in stride(from: 0, to: data.count, by: chunkSize) {
            output.append(try stream.append(data.subdata(in: start..<min(start + chunkSize, data.count))))
            XCTAssertLessThan(stream.pendingByteCount, 4096, "\(converter.configurationName) retains too much input")
        }
        output.append(try stream.finish())
        XCTAssertEqual(stream.pendingByteCount, 0)
        return output
    }

    func testEveryByteCutAcrossAllPublicModes() throws {
        let text = "头发干杯，鼠标里面的硅二极管坏了。軟體滑鼠裡面的矽二極體。\u{FEFF}\r\n👨‍👩‍👧‍👦e\u{301}\0神⿰木发\0\r\n"
        let bytes = Data(text.utf8)
        for options in modes {
            let converter = try ChineseConverter(options: options)
            let expected = Data(converter.convert(text).utf8)
            for split in 0...bytes.count {
                let stream = try converter.makeStream()
                var output = try stream.append(bytes.subdata(in: 0..<split))
                output.append(try stream.append(bytes.subdata(in: split..<bytes.count)))
                output.append(try stream.finish())
                XCTAssertEqual(output, expected, "\(converter.configurationName), split \(split)")
            }
            for size in [1, 2, 3, 4, 7, 16, 31, 256] {
                XCTAssertEqual(try streamed(bytes, converter: converter, chunkSize: size), expected,
                               "\(converter.configurationName), chunks \(size)")
            }
        }
    }

    func testOfficialFixturesDifferential() throws {
        struct Fixtures: Decodable { struct Fixture: Decodable { let input: String }; let cases: [Fixture] }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "testcases", withExtension: "json", subdirectory: "testcases"))
        let fixtures = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
        // Joined input adds phrase interactions across fixture boundaries as well
        // as exercising every bundled configuration and normalization stage.
        let text = fixtures.cases.map(\.input).joined(separator: "\r\n")
        for options in modes {
            let converter = try ChineseConverter(options: options)
            let expected = Data(converter.convert(text).utf8)
            for size in [1, 13, 256, 1024] {
                XCTAssertEqual(try streamed(Data(text.utf8), converter: converter, chunkSize: size), expected,
                               "\(converter.configurationName), fixture chunks \(size)")
            }
        }
    }

    func testEveryPartitionOfPhraseRegression() throws {
        for options in modes {
            let converter = try ChineseConverter(options: options)
            for text in ["头发", "干杯"] {
                let bytes = Data(text.utf8)
                let expected = Data(converter.convert(text).utf8)
                for mask in 0..<(1 << (bytes.count - 1)) {
                    let stream = try converter.makeStream()
                    var output = Data()
                    var start = 0
                    for end in 1...bytes.count where end == bytes.count || mask & (1 << (end - 1)) != 0 {
                        output.append(try stream.append(bytes.subdata(in: start..<end)))
                        start = end
                    }
                    output.append(try stream.finish())
                    XCTAssertEqual(output, expected, "\(converter.configurationName), \(text), partition \(mask)")
                }
            }
        }
    }

    func testDeterministicMixedCorpusWithIrregularChunks() throws {
        var seed: UInt64 = 0x52_1_4_2
        func next() -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int(seed >> 33)
        }
        let fragments = ["头发", "干杯", "发", "明", "发展", "干", "头", "鼠标", "硅二极管", "矽二極體",
                         "理髮", "頭髮", "神", "⿰木", "发", "⿾", "𠀀", "e\u{301}", "\0", "\r\n", "\u{FEFF}", "👩🏽‍💻", "a"]
        let text = (0..<2048).map { _ in fragments[next() % fragments.count] }.joined()
        let input = Data(text.utf8)
        for options in modes {
            let converter = try ChineseConverter(options: options)
            let stream = try converter.makeStream()
            var output = Data()
            var offset = 0
            while offset < input.count {
                let end = min(offset + 1 + next() % 97, input.count)
                output.append(try stream.append(input.subdata(in: offset..<end)))
                offset = end
            }
            output.append(try stream.finish())
            XCTAssertEqual(output, Data(converter.convert(text).utf8), converter.configurationName)
        }
    }

    func testPhraseAtOldKeepTailBoundaryAndMovedBoundaries() throws {
        let converter = try ChineseConverter(options: [.traditionalize])
        for padding in 0..<48 {
            let input = String(repeating: "甲", count: padding) + "头发干杯" + String(repeating: "乙", count: 80)
            for chunk in [17, 31, 48, 49, 50, 64, 256] {
                XCTAssertEqual(try streamed(Data(input.utf8), converter: converter, chunkSize: chunk),
                               Data(converter.convert(input).utf8), "padding \(padding), chunks \(chunk)")
            }
        }
    }

    func testUnmatchedSegmentAndLengthChangingChainBoundaries() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let dictionaries = [
            "normalize.txt": "c\tab\n",
            "segment.txt": "q\tq\n",
            "first.txt": "a\tX\nb\tY\nq\tY\n",
            "second.txt": "XX\tR\nXY\tZ\nYY\tW\n"
        ]
        for (name, text) in dictionaries {
            try text.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let json = """
        {
          "name": "streaming segment regression",
          "normalization": [{"dict":{"type":"text","file":"normalize.txt"}}],
          "segmentation": {"type":"mmseg","dict":{"type":"text","file":"segment.txt"}},
          "conversion_chain": [
            {"dict":{"type":"text","file":"first.txt"}},
            {"dict":{"type":"text","file":"second.txt"}}
          ]
        }
        """
        let configuration = directory.appendingPathComponent("test.json")
        try json.write(to: configuration, atomically: true, encoding: .utf8)
        let converter = try ChineseConverter(configurationName: "test", configurationURL: configuration,
                                             dictionaryDirectory: directory)
        // Unmatched a+b must interact after stage one, while two adjacent mmseg
        // q matches are distinct segments and must not become the YY -> W pair.
        XCTAssertEqual(converter.convert("abqqc"), "ZYYZ")
        for input in ["abqqc", "a\0b", String(repeating: "a", count: 10001) + "bqqc"] {
            for size in [1, 2, 3, 7, 13, 256] {
                XCTAssertEqual(try streamed(Data(input.utf8), converter: converter, chunkSize: size),
                               Data(converter.convert(input).utf8), "length-changing chain, chunks \(size)")
            }
        }
    }

    func testIDSDepthAndScalarLimits() throws {
        func tree(_ depth: Int) -> String {
            if depth == 0 { return "发" }
            return "⿲" + tree(depth - 1) + tree(depth - 1) + tree(depth - 1)
        }
        let ids58 = "⿲" + tree(3) + tree(2) + tree(1)
        let ids64 = String(repeating: "⿾", count: 6) + ids58
        let ids65 = String(repeating: "⿾", count: 7) + ids58
        XCTAssertEqual(ids64.unicodeScalars.count, 64)
        XCTAssertEqual(ids65.unicodeScalars.count, 65)
        let fixtures = [
            "⿰木发", "⿰", "⿰木", tree(3), ids64, ids65,
            String(repeating: "⿾", count: 15) + "发",
            String(repeating: "⿾", count: 16) + "发",
            String(repeating: "⿰", count: 15) + "发" + String(repeating: "木", count: 15),
            // Complete/incomplete trees around the 64-scalar parser bound.
            "⿲" + tree(3) + "⿲" + tree(2) + tree(2) + "发" + "木",
            "⿲" + tree(3) + tree(3) + "发",
            String(repeating: "⿰", count: 64) + String(repeating: "发", count: 65)
        ]
        for options in modes {
            let converter = try ChineseConverter(options: options)
            for fixture in fixtures {
                let input = fixture + "头发\0" + fixture + "干杯"
                for chunk in [1, 5, 17, 63, 64, 65, 256] {
                    XCTAssertEqual(try streamed(Data(input.utf8), converter: converter, chunkSize: chunk),
                                   Data(converter.convert(input).utf8), "\(converter.configurationName), IDS chunks \(chunk)")
                }
            }
        }
    }

    func testBoundedPendingForLongUnmatchedAndChineseRuns() throws {
        for options in modes {
            let converter = try ChineseConverter(options: options)
            for unit in ["a", "发", "⿾"] {
                let chunk = Data(String(repeating: unit, count: 8192).utf8)
                let stream = try converter.makeStream()
                var outputBytes = 0
                for _ in 0..<32 {
                    outputBytes += try stream.append(chunk).count
                    XCTAssertLessThan(stream.pendingByteCount, 4096)
                }
                outputBytes += try stream.finish().count
                XCTAssertGreaterThan(outputBytes, 0)
                XCTAssertEqual(stream.pendingByteCount, 0)
            }
        }
    }

    func testInvalidUTF8AndTerminalState() throws {
        let converter = try ChineseConverter(options: [.traditionalize])
        let invalid: [[UInt8]] = [
            [0x80], [0xc0, 0x80], [0xc1, 0xbf], [0xe0, 0x80, 0x80],
            [0xed, 0xa0, 0x80], [0xf0, 0x80, 0x80, 0x80], [0xf4, 0x90, 0x80, 0x80],
            [0xf5, 0x80, 0x80, 0x80], [0xff], [0xe4, 0x41], [0xe4, 0xb8, 0x00]
        ]
        for bytes in invalid {
            for split in 0...bytes.count {
                let stream = try converter.makeStream()
                XCTAssertThrowsError(try {
                    _ = try stream.append(Data(bytes.prefix(split)))
                    _ = try stream.append(Data(bytes.dropFirst(split)))
                    _ = try stream.finish()
                }()) { error in
                    guard case ConversionError.invalidUTF8 = error else { return XCTFail("Unexpected \(error), \(bytes)") }
                }
                XCTAssertThrowsError(try stream.append(Data())) { error in
                    guard case ConversionError.streamClosed = error else { return XCTFail("Unexpected \(error)") }
                }
            }
        }
        for bytes: [UInt8] in [[0xc2], [0xe4, 0xb8], [0xf0, 0x90, 0x80]] {
            let stream = try converter.makeStream()
            _ = try stream.append(Data(bytes))
            XCTAssertThrowsError(try stream.finish()) { error in
                guard case ConversionError.invalidUTF8 = error else { return XCTFail("Unexpected \(error)") }
            }
        }
        let stream = try converter.makeStream()
        XCTAssertEqual(try stream.append(Data()), Data())
        XCTAssertEqual(try stream.finish(), Data())
        XCTAssertThrowsError(try stream.finish()) { error in
            guard case ConversionError.streamClosed = error else { return XCTFail("Unexpected \(error)") }
        }
    }

    func testStreamOutlivesConverterAndReleasesHandles() throws {
        let initialStreams = CCStreamGetLiveHandleCount()
        let initialStrings = STLStringGetLiveHandleCount()
        let initialConverters = CCConverterGetLiveHandleCount()
        for _ in 0..<20 {
            try autoreleasepool {
                var converter: ChineseConverter? = try ChineseConverter(options: [.traditionalize, .twStandard, .twIdiom])
                let stream = try XCTUnwrap(converter).makeStream()
                converter = nil
                XCTAssertEqual(CCConverterGetLiveHandleCount(), initialConverters)
                var output = try stream.append(Data("头发鼠标\0干杯".utf8))
                output.append(try stream.finish())
                XCTAssertEqual(String(decoding: output, as: UTF8.self), "頭髮滑鼠\0乾杯")
                XCTAssertEqual(STLStringGetLiveHandleCount(), initialStrings)
                XCTAssertEqual(CCStreamGetLiveHandleCount(), initialStreams + 1)
            }
        }
        XCTAssertEqual(CCStreamGetLiveHandleCount(), initialStreams)
    }
}
