//
//  ChineseConverter.swift
//  OpenCC
//
//  Created by ddddxxx on 2017/3/9.
//

import Foundation
import copencc

/// The `ChineseConverter` class is used to represent and apply conversion
/// between Traditional Chinese and Simplified Chinese to Unicode strings.
/// An instance of this class is an immutable representation of a compiled
/// conversion pattern.
///
/// The `ChineseConverter` supporting character-level conversion, phrase-level
/// conversion, variant conversion and regional idioms among Mainland China,
/// Taiwan and HongKong
///
/// `ChineseConverter` is designed to be immutable and threadsafe, so that
/// a single instance can be used in conversion on multiple threads at once.
/// However, the string on which it is operating should not be mutated
/// during the course of a conversion.
public class ChineseConverter {
    
    /// These constants define the ChineseConverter options.
    public struct Options: OptionSet {
        
        public let rawValue: Int
        
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
        
        /// Convert to Traditional Chinese. (default)
        public static let traditionalize = Options(rawValue: 1 << 0)
        
        /// Convert to Simplified Chinese.
        public static let simplify = Options(rawValue: 1 << 1)
        
        /// Use Taiwan standard.
        public static let twStandard = Options(rawValue: 1 << 5)
        
        /// Use HongKong standard.
        public static let hkStandard = Options(rawValue: 1 << 6)
        
        /// Taiwanese idiom conversion.
        public static let twIdiom = Options(rawValue: 1 << 10)
    }
    
    private let converter: CCConverterRef

    /// The bundled configuration selected after applying the original option
    /// precedence. Internal so the public API remains source compatible.
    let configurationName: String

    init(configurationName: String, configurationURL: URL, dictionaryDirectory: URL) throws {
        var error = CCErrorCode.unknown
        guard let converter = CCConverterCreateWithConfig(
            configurationURL.path, dictionaryDirectory.path, &error
        ) else {
            throw ConversionError(error)
        }
        self.converter = converter
        self.configurationName = configurationName
    }

    /// Creates a converter using bundled, versioned OpenCC dictionaries.
    /// Unknown option bits are ignored. Traditional conversion takes precedence
    /// over simplification; Hong Kong takes precedence over Taiwan characters.
    public convenience init(options: Options) throws {
        let name = options.configurationName
        let folder = name.hasPrefix("legacy-") ? "Compatibility" : "Official"
        guard let url = Bundle.module.url(forResource: name, withExtension: "json",
                                          subdirectory: folder),
              let dictionaries = Bundle.module.url(forResource: "Official", withExtension: nil) else {
            throw ConversionError.fileNotFound
        }
        try self.init(configurationName: name, configurationURL: url, dictionaryDirectory: dictionaries)
    }

    deinit {
        CCConverterDestroy(converter)
    }

    /// Converts the complete UTF-8 string, including embedded U+0000 characters.
    public func convert(_ text: String) -> String {
        var error = CCErrorCode.unknown
        let result = text.utf8CString.withUnsafeBufferPointer { bytes in
            CCConverterCreateConvertedStringFromBytes(converter, bytes.baseAddress!, bytes.count - 1, &error)
        }
        guard let string = result else {
            preconditionFailure("OpenCC conversion failed: \(ConversionError(error))")
        }
        defer { STLStringDestroy(string) }
        let bytes = UnsafeRawPointer(STLStringGetUTF8String(string)).assumingMemoryBound(to: UInt8.self)
        return String(decoding: UnsafeBufferPointer(start: bytes, count: STLStringGetLength(string)), as: UTF8.self)
    }
}
