#pragma once
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

enum CCErrorCode {
    CCErrorCodeFileNotFound = 1,
    CCErrorCodeInvalidFormat,
    CCErrorCodeInvalidTextDictionary,
    CCErrorCodeInvalidUTF8,
    CCErrorCodeUnknown,
} __attribute__((enum_extensibility(open)));
typedef enum CCErrorCode CCErrorCode;

typedef void *CCConverterRef;
typedef void *STLString;

CCConverterRef _Nullable CCConverterCreateWithConfig(
    const char * _Nonnull configPath,
    const char * _Nonnull dictionaryDirectory,
    CCErrorCode * _Nonnull error);
void CCConverterDestroy(CCConverterRef _Nonnull converter);

STLString _Nullable CCConverterCreateConvertedStringFromBytes(
    CCConverterRef _Nonnull converter, const char * _Nonnull bytes,
    size_t length, CCErrorCode * _Nonnull error);
const char * _Nonnull STLStringGetUTF8String(STLString _Nonnull string);
size_t STLStringGetLength(STLString _Nonnull string);
void STLStringDestroy(STLString _Nonnull string);

// Internal diagnostics used by lifetime regression tests. These counters count
// owned bridge handles, not shared upstream dictionaries or allocations.
size_t CCConverterGetLiveHandleCount(void);
size_t STLStringGetLiveHandleCount(void);

#ifdef __cplusplus
}
#endif
