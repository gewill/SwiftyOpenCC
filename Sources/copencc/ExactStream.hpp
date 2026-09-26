#pragma once

#include "ConfigBasedConverter.hpp"
#include "ConversionChain.hpp"
#include "MaxMatchSegmentation.hpp"
#include "PrefixMatch.hpp"
#include "SingleStageConverter.hpp"
#include "UTF8Util.hpp"
#include <algorithm>
#include <memory>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace swiftyopencc {

struct UnsupportedStream : std::runtime_error {
    UnsupportedStream() : std::runtime_error("Unsupported streaming configuration") {}
};

// A stable prefix ends after a complete dictionary match or unmatched IDS/scalar.
// Keeping a fixed tail and converting the prefix is NOT equivalent: its cut can
// land inside a phrase. All offsets below advance only by complete match units.
class StablePrefixScanner {
public:
    explicit StablePrefixScanner(const opencc::DictPtr& dictionary)
        : matcher(dictionary), keyMaxLength(dictionary->KeyMaxLength()) {}

    template <typename Emit, typename Flush>
    void Append(std::string_view bytes, bool finish, Emit emit, Flush flush) {
        if (!bytes.empty()) pending.append(bytes.data(), bytes.size());
        size_t offset = 0;
        while (offset < pending.size()) {
            const char* cursor = pending.data() + offset;
            const size_t remaining = pending.size() - offset;
            // Dictionary lengths are bytes. Cache once, not once per character.
            if (!finish && remaining < keyMaxLength) break;
            const auto match = matcher.MatchPrefixView(cursor, remaining);
            size_t length;
            if (match.matched) {
                length = match.keyLength;
            } else {
                // Upstream bounds IDS parsing to 64 scalars and depth 16. Its
                // own incomplete-prefix predicate distinguishes more input from
                // an invalid/over-limit sequence without a separate IDS parser.
                if (!finish && opencc::UTF8Util::IsIncompleteIdeographicDescriptionSequencePrefix(cursor, remaining)) break;
                length = opencc::UTF8Util::NextIdeographicDescriptionSequenceLength(cursor, remaining);
                if (length == 0) length = opencc::UTF8Util::NextCharLength(cursor);
                // Bulk skipping is safe only where no dictionary key can start;
                // it also stops before an IDS operator, exactly as OpenCC does.
                length += matcher.SkipUnmatchable(cursor + length, remaining - length);
            }
            emit(std::string_view(cursor, length), match.matched);
            offset += length;
        }
        flush(std::string_view(pending.data(), offset));
        // One compaction per append; erasing for every token would be quadratic.
        pending.erase(0, offset);
    }

    size_t PendingBytes() const { return pending.size(); }

private:
    opencc::PrefixMatch matcher;
    const size_t keyMaxLength;
    std::string pending;
};

class IncrementalConversion {
public:
    explicit IncrementalConversion(opencc::ConversionPtr conversion)
        : conversion(std::move(conversion)), scanner(this->conversion->GetDict()) {}

    std::string Append(std::string_view input, bool finish) {
        std::string output;
        // Find the stable, contiguous prefix first, then use the original
        // conversion primitive once. Its matching and priority remain upstream.
        scanner.Append(input, finish, [](std::string_view, bool) {}, [&](std::string_view prefix) {
            conversion->AppendConverted(prefix, &output);
        });
        return output;
    }

    size_t PendingBytes() const { return scanner.PendingBytes(); }

private:
    opencc::ConversionPtr conversion;
    StablePrefixScanner scanner;
};

class IncrementalStage {
public:
    IncrementalStage(opencc::SegmentationPtr segmentation, opencc::ConversionChainPtr chain)
        : chain(std::move(chain)) {
        if (!this->chain) throw UnsupportedStream();
        if (segmentation) {
            auto mmseg = std::dynamic_pointer_cast<opencc::MaxMatchSegmentation>(segmentation);
            if (!mmseg) throw UnsupportedStream();
            scanner = std::make_unique<StablePrefixScanner>(mmseg->GetDict());
        }
        for (const auto& conversion : this->chain->GetConversions()) {
            conversions.emplace_back(std::make_unique<IncrementalConversion>(conversion));
        }
    }

    std::string Append(std::string_view input, bool finish) {
        if (!scanner) return AppendUnmatched(input, finish);
        std::string output;
        const char* runStart = nullptr;
        size_t runLength = 0;
        auto flushRun = [&] {
            if (runLength != 0) output += AppendUnmatched(std::string_view(runStart, runLength), false);
            runStart = nullptr;
            runLength = 0;
        };
        scanner->Append(input, finish, [&](std::string_view unit, bool matched) {
            if (matched) {
                // An mmseg match terminates the preceding logical unmatched
                // segment. Flush all chain stages BEFORE converting that match.
                flushRun();
                output += AppendUnmatched({}, true);
                chain->AppendConvertedSegment(unit, &output);
            } else {
                // A long unmatched run remains one segment across append calls;
                // do not create an artificial boundary every IO chunk/scalar.
                if (!runStart) runStart = unit.data();
                runLength += unit.size();
            }
        }, [&](std::string_view) { flushRun(); });
        if (finish) output += AppendUnmatched({}, true);
        return output;
    }

    size_t PendingBytes() const {
        size_t bytes = scanner ? scanner->PendingBytes() : 0;
        for (const auto& conversion : conversions) bytes += conversion->PendingBytes();
        return bytes;
    }

private:
    std::string AppendUnmatched(std::string_view input, bool finish) {
        std::string output(input);
        for (const auto& conversion : conversions) output = conversion->Append(output, finish);
        return output;
    }

    opencc::ConversionChainPtr chain;
    std::unique_ptr<StablePrefixScanner> scanner;
    std::vector<std::unique_ptr<IncrementalConversion>> conversions;
};

class ExactStream {
public:
    explicit ExactStream(const opencc::ConverterPtr& converter) { AddConverter(converter); }

    std::string Append(std::string_view input, bool finish) {
        std::string bytes = std::move(incompleteUTF8);
        if (!input.empty()) bytes.append(input.data(), input.size());
        const size_t validLength = ValidPrefixLength(bytes);
        incompleteUTF8.assign(bytes, validLength, std::string::npos);
        if (finish && !incompleteUTF8.empty()) throw opencc::InvalidUTF8("Truncated UTF-8");
        std::string output;
        size_t start = 0;
        for (;;) {
            size_t separator = bytes.find('\0', start);
            if (separator == std::string::npos || separator >= validLength) break;
            output += Convert(std::string_view(bytes).substr(start, separator - start), true);
            output.push_back('\0');
            start = separator + 1;
        }
        output += Convert(std::string_view(bytes).substr(start, validLength - start), finish);
        return output;
    }

    size_t PendingBytes() const {
        size_t bytes = incompleteUTF8.size();
        for (const auto& stage : stages) bytes += stage->PendingBytes();
        return bytes;
    }

private:
    void AddConverter(const opencc::ConverterPtr& converter) {
        if (auto configured = std::dynamic_pointer_cast<opencc::ConfigBasedConverter>(converter)) {
            AddConverter(configured->GetNormalizationConverter());
        } else if (!std::dynamic_pointer_cast<opencc::SingleStageConverter>(converter)) {
            // Future pipeline/plugin implementations must be reviewed explicitly.
            throw UnsupportedStream();
        }
        stages.emplace_back(std::make_unique<IncrementalStage>(converter->GetSegmentation(), converter->GetConversionChain()));
    }

    std::string Convert(std::string_view input, bool finish) {
        std::string output(input);
        for (const auto& stage : stages) output = stage->Append(output, finish);
        return output;
    }

    // Strict RFC 3629 validation: upstream assumes already-valid scalar input.
    // Only an incomplete final scalar may be retained (at most three bytes).
    static size_t ValidPrefixLength(std::string_view input) {
        size_t offset = 0;
        while (offset < input.size()) {
            const auto lead = static_cast<unsigned char>(input[offset]);
            size_t length;
            if (lead <= 0x7f) length = 1;
            else if (lead >= 0xc2 && lead <= 0xdf) length = 2;
            else if (lead >= 0xe0 && lead <= 0xef) length = 3;
            else if (lead >= 0xf0 && lead <= 0xf4) length = 4;
            else throw opencc::InvalidUTF8("Invalid UTF-8 lead byte");
            const size_t available = std::min(length, input.size() - offset);
            for (size_t index = 1; index < available; ++index) {
                const auto byte = static_cast<unsigned char>(input[offset + index]);
                if (byte < 0x80 || byte > 0xbf ||
                    (index == 1 && ((lead == 0xe0 && byte < 0xa0) || (lead == 0xed && byte > 0x9f) ||
                                   (lead == 0xf0 && byte < 0x90) || (lead == 0xf4 && byte > 0x8f)))) {
                    throw opencc::InvalidUTF8("Invalid UTF-8 continuation byte");
                }
            }
            if (available != length) return offset;
            offset += length;
        }
        return offset;
    }

    std::vector<std::unique_ptr<IncrementalStage>> stages;
    std::string incompleteUTF8;
};
} // namespace swiftyopencc
