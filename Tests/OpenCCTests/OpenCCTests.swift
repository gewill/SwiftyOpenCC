import XCTest
@testable import OpenCC

let testCases: [(String, ChineseConverter.Options)] = [
    ("s2t", [.traditionalize]),
    ("t2s", [.simplify]),
    ("s2hk", [.traditionalize, .hkStandard]),
    ("hk2s", [.simplify, .hkStandard]),
    ("s2tw", [.traditionalize, .twStandard]),
    ("tw2s", [.simplify, .twStandard]),
    ("s2twp", [.traditionalize, .twStandard, .twIdiom]),
    ("tw2sp", [.simplify, .twStandard, .twIdiom]),
]

struct TestCase: Decodable {
    let id: String
    let input: String
    let expected: [String: String]
}

struct TestCasesFile: Decodable {
    let cases: [TestCase]
}

class OpenCCTests: XCTestCase {

    func converter(option: ChineseConverter.Options) throws -> ChineseConverter {
        return try ChineseConverter(options: option)
    }

    func testConversion() throws {
        // Load test cases from JSON - try multiple paths
        var testCasesFile: TestCasesFile
        
        // Try Bundle.module first
        if let url = Bundle.module.url(forResource: "testcases", withExtension: "json", subdirectory: "testcases"),
           let data = try? Data(contentsOf: url) {
            testCasesFile = try JSONDecoder().decode(TestCasesFile.self, from: data)
        } else {
            // Fallback: load from source directory
            let sourcePath = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("testcases")
                .appendingPathComponent("testcases.json")
            let data = try Data(contentsOf: sourcePath)
            testCasesFile = try JSONDecoder().decode(TestCasesFile.self, from: data)
        }
        
        for testCase in testCasesFile.cases {
            for (conversionType, expectedOutput) in testCase.expected {
                guard let options = conversionOptions(for: conversionType) else {
                    continue // Skip unsupported conversion types
                }
                let converter = try ChineseConverter(options: options)
                let result = converter.convert(testCase.input)
                XCTAssertEqual(result, expectedOutput, "Conversion \(conversionType) failed for test case: \(testCase.id)")
            }
        }
    }
    
    func conversionOptions(for type: String) -> ChineseConverter.Options? {
        switch type {
        case "s2t":
            return [.traditionalize]
        case "t2s":
            return [.simplify]
        case "s2hk":
            return [.traditionalize, .hkStandard]
        case "hk2s":
            return [.simplify, .hkStandard]
        case "s2tw":
            return [.traditionalize, .twStandard]
        case "tw2s":
            return [.simplify, .twStandard]
        case "s2twp":
            return [.traditionalize, .twStandard, .twIdiom]
        case "tw2sp":
            return [.simplify, .twStandard, .twIdiom]
        case "t2hk":
            return [.hkStandard]
        case "tw2t":
            return [.traditionalize]
        default:
            return nil
        }
    }

    func testConverterCreationPerformance() {
        let options: ChineseConverter.Options = [.traditionalize, .twStandard, .twIdiom]
        measure {
            for _ in 0..<10 {
                _ = try! ChineseConverter(options: options)
            }
        }
    }

    func testDictionaryCache() {
        let options: ChineseConverter.Options = [.traditionalize, .twStandard, .twIdiom]
        let holder = try! ChineseConverter(options: options)
        measure {
            for _ in 0..<1_000 {
                _ = try! ChineseConverter(options: options)
            }
        }
        _ = holder.convert("foo")
    }

    func testConversionPerformance() throws {
        let cov = try converter(option: [.traditionalize, .twStandard, .twIdiom])
        
        // Try Bundle.module first, then fallback to source directory
        var url: URL?
        url = Bundle.module.url(forResource: "zuozhuan", withExtension: "txt", subdirectory: "benchmark")
        if url == nil {
            url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("benchmark")
                .appendingPathComponent("zuozhuan.txt")
        }
        
        guard let fileURL = url else {
            XCTFail("Could not find benchmark file")
            return
        }
        
        // 1.9 MB, 624k word
        let str = try String(contentsOf: fileURL)
        measure {
            _ = cov.convert(str)
        }
    }
}
