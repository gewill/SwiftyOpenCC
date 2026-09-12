#include "header.h"
#include "Config.hpp"
#include "Converter.hpp"
#include "Exception.hpp"
#include "ResourceProvider.hpp"
#include <atomic>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

namespace {
std::atomic<size_t> liveConverters{0};
std::atomic<size_t> liveStrings{0};

// All ownership is inside this handle. Destroying it releases the converter,
// conversion stages and their shared dictionaries through upstream RAII.
struct ConverterHandle {
    opencc::ConverterPtr converter;
};

template <typename Operation>
void *catchException(CCErrorCode *error, Operation operation) {
    try {
        return operation();
    } catch (const opencc::FileNotFound &) {
        *error = CCErrorCodeFileNotFound;
    } catch (const opencc::InvalidTextDictionary &) {
        *error = CCErrorCodeInvalidTextDictionary;
    } catch (const opencc::InvalidFormat &) {
        *error = CCErrorCodeInvalidFormat;
    } catch (const opencc::InvalidUTF8 &) {
        *error = CCErrorCodeInvalidUTF8;
    } catch (...) {
        *error = CCErrorCodeUnknown;
    }
    return nullptr;
}
} // namespace

CCConverterRef CCConverterCreateWithConfig(const char *configPath,
                                           const char *dictionaryDirectory,
                                           CCErrorCode *error) {
    return catchException(error, [&]() -> void * {
        opencc::Config config;
        auto provider = std::make_shared<opencc::FilesystemResourceProvider>(
            std::vector<std::string>{dictionaryDirectory});
        auto handle = std::make_unique<ConverterHandle>();
        handle->converter = config.NewFromFile(configPath, provider);
        ++liveConverters;
        return handle.release();
    });
}

void CCConverterDestroy(CCConverterRef converter) {
    delete static_cast<ConverterHandle *>(converter);
    --liveConverters;
}

STLString CCConverterCreateConvertedStringFromBytes(CCConverterRef converter,
                                                   const char *bytes,
                                                   size_t length,
                                                   CCErrorCode *error) {
    return catchException(error, [&]() -> void * {
        const auto &engine = static_cast<ConverterHandle *>(converter)->converter;
        const std::string_view input(bytes, length);
        auto result = std::make_unique<std::string>();
        size_t separator = input.find('\0');
        if (separator == std::string_view::npos) {
            *result = engine->Convert(input);
        } else {
            // OpenCC 1.4.2 mmseg paths still treat embedded NUL as an end
            // marker internally. Keep each NUL as a literal separator while
            // converting complete NUL-free spans; input/output remain sized.
            result->reserve(length);
            size_t start = 0;
            while (separator != std::string_view::npos) {
                if (separator > start) {
                    result->append(engine->Convert(input.substr(start, separator - start)));
                }
                result->push_back('\0');
                start = separator + 1;
                separator = input.find('\0', start);
            }
            if (start < length) { result->append(engine->Convert(input.substr(start))); }
        }
        ++liveStrings;
        return result.release();
    });
}

const char *STLStringGetUTF8String(STLString string) {
    return static_cast<std::string *>(string)->data();
}
size_t STLStringGetLength(STLString string) {
    return static_cast<std::string *>(string)->size();
}
void STLStringDestroy(STLString string) {
    delete static_cast<std::string *>(string);
    --liveStrings;
}
size_t CCConverterGetLiveHandleCount() { return liveConverters.load(); }
size_t STLStringGetLiveHandleCount() { return liveStrings.load(); }
