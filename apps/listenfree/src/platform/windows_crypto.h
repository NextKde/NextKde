#pragma once
// Shared Windows primitives used by the legacy source contract and account requests.
// Extracted unchanged from sourcehost/plugin_runtime.cpp.
#include <QByteArray>
#include <QString>
#include <QScopeGuard>
#include <algorithm>
#include <vector>
#ifdef Q_OS_WIN
#include <windows.h>
#include <bcrypt.h>
#include <wincrypt.h>
#endif
namespace listenfree::platform {
#ifdef Q_OS_WIN
inline QByteArray rsaEncryptBytes(const QByteArray& input, const QString& publicKeyPem) {
    // The legacy LX runtime pads to a 1024-bit block and uses Node's
    // RSA_NO_PADDING mode.  Preserve that byte-for-byte contract.
    constexpr DWORD RsaBlockBytes = 128;
    if (input.size() > static_cast<qsizetype>(RsaBlockBytes) || publicKeyPem.isEmpty()) return {};

    const QByteArray pem = publicKeyPem.toUtf8();
    DWORD derLength = 0;
    if (!CryptStringToBinaryA(pem.constData(), static_cast<DWORD>(pem.size()),
                              CRYPT_STRING_BASE64HEADER, nullptr, &derLength, nullptr, nullptr) ||
        derLength == 0) {
        return {};
    }
    QByteArray der(static_cast<qsizetype>(derLength), Qt::Uninitialized);
    if (!CryptStringToBinaryA(pem.constData(), static_cast<DWORD>(pem.size()),
                              CRYPT_STRING_BASE64HEADER,
                              reinterpret_cast<BYTE*>(der.data()), &derLength, nullptr, nullptr)) {
        return {};
    }
    der.resize(static_cast<qsizetype>(derLength));

    CERT_PUBLIC_KEY_INFO* keyInfo = nullptr;
    DWORD keyInfoLength = 0;
    if (!CryptDecodeObjectEx(X509_ASN_ENCODING, X509_PUBLIC_KEY_INFO,
                             reinterpret_cast<const BYTE*>(der.constData()),
                             static_cast<DWORD>(der.size()), CRYPT_DECODE_ALLOC_FLAG, nullptr,
                             &keyInfo, &keyInfoLength) || keyInfo == nullptr) {
        return {};
    }
    const auto freeKeyInfo = qScopeGuard([&] { LocalFree(keyInfo); });

    BCRYPT_KEY_HANDLE keyHandle = nullptr;
    if (!CryptImportPublicKeyInfoEx2(X509_ASN_ENCODING, keyInfo, 0, nullptr, &keyHandle) ||
        keyHandle == nullptr) {
        return {};
    }
    const auto destroyKey = qScopeGuard([&] { BCryptDestroyKey(keyHandle); });

    QByteArray padded(static_cast<qsizetype>(RsaBlockBytes), '\0');
    std::copy(input.cbegin(), input.cend(), padded.end() - input.size());
    ULONG outputLength = 0;
    if (BCryptEncrypt(keyHandle, reinterpret_cast<PUCHAR>(padded.data()), RsaBlockBytes,
                      nullptr, nullptr, 0, nullptr, 0, &outputLength, 0) != 0 ||
        outputLength != RsaBlockBytes) {
        return {};
    }
    QByteArray output(static_cast<qsizetype>(outputLength), Qt::Uninitialized);
    if (BCryptEncrypt(keyHandle, reinterpret_cast<PUCHAR>(padded.data()), RsaBlockBytes,
                      nullptr, nullptr, 0, reinterpret_cast<PUCHAR>(output.data()), outputLength,
                      &outputLength, 0) != 0) {
        return {};
    }
    output.resize(static_cast<qsizetype>(outputLength));
    return output;
}

inline QByteArray aesEncryptBytes(const QByteArray& input, const QByteArray& key, const QByteArray& iv, const QString& mode) {
    const bool ecb = mode.endsWith(QStringLiteral("-ecb"));
    const bool validMode = mode == QStringLiteral("aes-128-cbc") || mode == QStringLiteral("aes-192-cbc") ||
                           mode == QStringLiteral("aes-256-cbc") || mode == QStringLiteral("aes-128-ecb") ||
                           mode == QStringLiteral("aes-192-ecb") || mode == QStringLiteral("aes-256-ecb");
    const bool validKey = (mode.contains(QStringLiteral("128")) && key.size() == 16) ||
                          (mode.contains(QStringLiteral("192")) && key.size() == 24) ||
                          (mode.contains(QStringLiteral("256")) && key.size() == 32);
    if (!validMode || !validKey || (!ecb && iv.size() != 16)) return {};
    BCRYPT_ALG_HANDLE algorithm = nullptr;
    if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_AES_ALGORITHM, nullptr, 0) != 0) return {};
    const auto closeAlgorithm = qScopeGuard([&] { BCryptCloseAlgorithmProvider(algorithm, 0); });
    const wchar_t* chaining = ecb ? BCRYPT_CHAIN_MODE_ECB : BCRYPT_CHAIN_MODE_CBC;
    if (BCryptSetProperty(algorithm, BCRYPT_CHAINING_MODE, reinterpret_cast<PUCHAR>(const_cast<wchar_t*>(chaining)),
                          static_cast<ULONG>((wcslen(chaining) + 1) * sizeof(wchar_t)), 0) != 0) return {};
    DWORD objectLength = 0;
    DWORD resultLength = 0;
    if (BCryptGetProperty(algorithm, BCRYPT_OBJECT_LENGTH, reinterpret_cast<PUCHAR>(&objectLength), sizeof(objectLength),
                          &resultLength, 0) != 0) return {};
    std::vector<UCHAR> object(objectLength);
    BCRYPT_KEY_HANDLE handle = nullptr;
    if (BCryptGenerateSymmetricKey(algorithm, &handle, object.data(), objectLength,
                                   reinterpret_cast<PUCHAR>(const_cast<char*>(key.constData())),
                                   static_cast<ULONG>(key.size()), 0) != 0) return {};
    const auto destroyKey = qScopeGuard([&] { BCryptDestroyKey(handle); });
    QByteArray mutableIv = iv;
    ULONG outputLength = 0;
    const auto inputData = reinterpret_cast<PUCHAR>(const_cast<char*>(input.constData()));
    const auto ivData = mutableIv.isEmpty() ? nullptr : reinterpret_cast<PUCHAR>(mutableIv.data());
    if (BCryptEncrypt(handle, inputData, static_cast<ULONG>(input.size()), nullptr, ivData,
                      static_cast<ULONG>(mutableIv.size()), nullptr, 0, &outputLength, BCRYPT_BLOCK_PADDING) != 0) return {};
    QByteArray output(static_cast<qsizetype>(outputLength), Qt::Uninitialized);
    mutableIv = iv;
    if (BCryptEncrypt(handle, inputData, static_cast<ULONG>(input.size()), nullptr,
                      mutableIv.isEmpty() ? nullptr : reinterpret_cast<PUCHAR>(mutableIv.data()),
                      static_cast<ULONG>(mutableIv.size()), reinterpret_cast<PUCHAR>(output.data()), outputLength,
                      &outputLength, BCRYPT_BLOCK_PADDING) != 0) return {};
    output.resize(static_cast<qsizetype>(outputLength));
    return output;
}
#endif
}
