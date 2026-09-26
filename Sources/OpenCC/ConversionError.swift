//
//  ConversionError.swift
//  OpenCC
//
//  Created by ddddxxx on 2020/1/3.
//

import Foundation
import copencc

public enum ConversionError: Error {
    
    case fileNotFound
    
    case invalidFormat
    
    case invalidTextDictionary
    
    case invalidUTF8
    
    case unknown

    /// The loaded converter uses a stage or segmenter without exact streaming support.
    case unsupportedStreamingConfiguration

    /// The stream has already finished or a previous append/finish failed.
    case streamClosed
    
    init(_ code: CCErrorCode) {
        switch code {
        case .fileNotFound:
            self = .fileNotFound
        case .invalidFormat:
            self = .invalidFormat
        case .invalidTextDictionary:
            self = .invalidTextDictionary
        case .invalidUTF8:
            self = .invalidUTF8
        case .unsupportedStreamingConfiguration:
            self = .unsupportedStreamingConfiguration
        case .streamClosed:
            self = .streamClosed
        case .unknown, _:
            self = .unknown
        }
    }
}
