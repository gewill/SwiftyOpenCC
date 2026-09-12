// swift-tools-version:5.4
import PackageDescription
import Foundation

// The generated manifest keeps the native version macro in step with the
// submodule without changing this package file for every dictionary release.
let manifestURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Sources/OpenCC/Resources/manifest.json")
let manifest = try! JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
let engineTag = (manifest["opencc"] as! [String: String])["tag"]!
let engineVersion = String(engineTag.dropFirst(4))

let package = Package(
    name: "SwiftyOpenCC",
    products: [.library(name: "OpenCC", targets: ["OpenCC"])],
    targets: [
        .target(name: "OpenCC", dependencies: ["copencc"], resources: [.copy("Resources")]),
        .testTarget(name: "OpenCCTests", dependencies: ["OpenCC", "copencc"],
                    resources: [.copy("testcases")]),
        .target(
            name: "copencc",
            sources: [
                "source.cpp",
                "src/Config.cpp",
                "src/Conversion.cpp",
                "src/ConversionAmbiguities.cpp",
                "src/ConversionCandidates.cpp",
                "src/ConversionChain.cpp",
                "src/Converter.cpp",
                "src/Dict.cpp",
                "src/DictConverter.cpp",
                "src/DictEntry.cpp",
                "src/DictGroup.cpp",
                "src/Lexicon.cpp",
                "src/MarisaDict.cpp",
                "src/MaxMatchSegmentation.cpp",
                "src/PhraseExtract.cpp",
                "src/PipelineConverter.cpp",
                "src/PluginSegmentation.cpp",
                "src/PrefixMatch.cpp",
                "src/SingleStageConverter.cpp",
                "src/ResourceProvider.cpp",
                "src/SerializableDict.cpp",
                "src/SerializedValues.cpp",
                "src/SimpleConverter.cpp",
                "src/Segmentation.cpp",
                "src/TextDict.cpp",
                "src/UTF8StringSlice.cpp",
                "src/UTF8Util.cpp",
                "src/BinaryDict.cpp",
                "src/DartsDict.cpp",
                "marisa",

            ],
            cxxSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("deps/marisa-0.3.1/include"),
                .headerSearchPath("deps/marisa-0.3.1/lib"),
                .headerSearchPath("deps/darts-clone-0.32h/include"),
                .headerSearchPath("deps/rapidjson-1.1.0"),
                .define("Opencc_BUILT_AS_STATIC"),
                .define("OPENCC_VERSION", to: "\"" + engineVersion + "\"")
            ]
        )
    ],
    cxxLanguageStandard: .cxx17
)
