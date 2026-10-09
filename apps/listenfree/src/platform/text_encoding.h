#pragma once
#include <QByteArray>
#include <QString>
#include <memory>
#include <unicode/ucnv.h>
#include <unicode/translit.h>

namespace listenfree::platform {
inline QString decodeGb18030(const QByteArray& bytes) {
    UErrorCode status = U_ZERO_ERROR;
    std::unique_ptr<UConverter, decltype(&ucnv_close)> converter(ucnv_open("GB18030", &status), &ucnv_close);
    if (U_FAILURE(status)) return {};
    const int32_t size = ucnv_toUChars(converter.get(), nullptr, 0, bytes.constData(), int32_t(bytes.size()), &status);
    if (status != U_BUFFER_OVERFLOW_ERROR && U_FAILURE(status)) return {};
    status = U_ZERO_ERROR;
    QString result(size, Qt::Uninitialized);
    ucnv_toUChars(converter.get(), reinterpret_cast<UChar*>(result.data()), size, bytes.constData(), int32_t(bytes.size()), &status);
    return U_SUCCESS(status) ? result : QString();
}
inline QByteArray encodeGbk(const QString& text) {
    UErrorCode status = U_ZERO_ERROR;
    std::unique_ptr<UConverter, decltype(&ucnv_close)> converter(ucnv_open("GBK", &status), &ucnv_close);
    if (U_FAILURE(status)) return {};
    const auto* input = reinterpret_cast<const UChar*>(text.utf16());
    const int32_t size = ucnv_fromUChars(converter.get(), nullptr, 0, input, int32_t(text.size()), &status);
    if (status != U_BUFFER_OVERFLOW_ERROR && U_FAILURE(status)) return {};
    status = U_ZERO_ERROR;
    QByteArray result(size, Qt::Uninitialized);
    ucnv_fromUChars(converter.get(), result.data(), size, input, int32_t(text.size()), &status);
    return U_SUCCESS(status) ? result : QByteArray();
}
inline QString convertChinese(const QString& text, bool traditional) {
    const auto create = [](const char* id) {
        UErrorCode status = U_ZERO_ERROR;
        std::unique_ptr<icu::Transliterator> result(icu::Transliterator::createInstance(id, UTRANS_FORWARD, status));
        if (U_FAILURE(status)) result.reset();
        return result;
    };
    thread_local auto toTraditional = create("Simplified-Traditional");
    thread_local auto toSimplified = create("Traditional-Simplified");
    const auto& converter = traditional ? toTraditional : toSimplified;
    if (!converter || text.isEmpty()) return text;
    icu::UnicodeString value(reinterpret_cast<const UChar*>(text.utf16()), int32_t(text.size()));
    converter->transliterate(value);
    return QString::fromUtf16(reinterpret_cast<const char16_t*>(value.getBuffer()), value.length());
}
}
