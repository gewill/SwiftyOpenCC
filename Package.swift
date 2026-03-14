// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "SwiftyOpenCC",
    products: [
        .library(
            name: "OpenCC",
            targets: ["OpenCC"]),
    ],
    targets: [
        .target(
            name: "OpenCC",
            dependencies: ["copencc"],
            resources: [
                .copy("Dictionary")
            ]),
        .testTarget(
            name: "OpenCCTests",
            dependencies: ["OpenCC"],
            resources: [
                .copy("benchmark"),
                .copy("testcases"),
            ]),
        .target(
            name: "copencc",
            exclude: [
                "src/benchmark",
                "src/tools",
                "src/BinaryDictTest.cpp",
                "src/Config.cpp",
                "src/ConfigTest.cpp",
                "src/ConversionChainTest.cpp",
                "src/ConversionTest.cpp",
                "src/DartsDictTest.cpp",
                "src/DictGroupTest.cpp",
                "src/MarisaDictTest.cpp",
                "src/MaxMatchSegmentationTest.cpp",
                "src/PhraseExtractTest.cpp",
                "src/SerializedValuesTest.cpp",
                "src/SimpleConverter.cpp",
                "src/SimpleConverterTest.cpp",
                "src/TextDictTest.cpp",
                "src/UTF8StringSliceTest.cpp",
                "src/UTF8UtilTest.cpp",
                "src/LexiconAnnotationTest.cpp",
                "deps/google-benchmark",
                "deps/googletest-1.15.0",
                "deps/pybind11-2.13.1",
                "deps/rapidjson-1.1.0",
                "deps/tclap-1.2.5",

                "src/CmdLineOutput.hpp",
                "src/Config.hpp",
                "src/ConfigTestBase.hpp",
                "src/DictGroupTestBase.hpp",
                "src/SimpleConverter.hpp",
                "src/TestUtils.hpp",
                "src/TestUtilsUTF8.hpp",
                "src/TextDictTestBase.hpp",
                "src/py_opencc.cpp",
                "src/opencc_config.h",
                "src/opencc_config.h.in",

                // ???
                "src/README.md",
                "src/CMakeLists.txt",
                "src/BUILD.bazel",
                "src/BUILD",
                "deps/marisa-0.2.6/AUTHORS",
                "deps/marisa-0.2.6/CMakeLists.txt",
                "deps/marisa-0.2.6/COPYING.md",
                "deps/marisa-0.2.6/README.md",
            ],
            sources: [
                "source.cpp",
                "src",
                "deps/marisa-0.2.6",
            ],
            cxxSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("configure"),
                .headerSearchPath("deps/darts-clone-0.32"),
                .headerSearchPath("deps/marisa-0.2.6/include"),
                .headerSearchPath("deps/marisa-0.2.6/lib"),
                .define("OPENCC_ENABLE_DARTS"),
            ]),
    ],
    cxxLanguageStandard: .cxx14
)
