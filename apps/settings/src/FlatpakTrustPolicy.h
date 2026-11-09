#pragma once

#include <array>

namespace FlatpakTrustPolicy {
struct Remote {
    const char* url;
    const char* primaryFingerprint;
    bool applications;
    bool runtimes;
};

// Release maintainers must review the HTTPS URL and full primary-key fingerprint
// together. Never populate this from a remote name, user catalog or network reply.
// Each entry explicitly authorizes applications, runtimes, or both. Key rotation
// requires reviewing every primary key accepted by the configured remote.
// Runtime sources are independently reviewed; bundle apps need no hosted remote.
// Reviewed 2026-11-05 against the official setup URL documented at
// https://docs.flathub.org/docs/for-users/installation and its HTTPS
// https://flathub.org/repo/flathub.flatpakrepo (redirects to dl.flathub.org).
// Primary key expires 2027-06-14; signing subkeys are not policy identities.
// Existing remote configuration must still verify commits and summaries, and
// every imported primary key must match. An explicit Install/Update request may add
// the pinned Flathub runtime source if needed; inventory never adds sources.
inline constexpr std::array remotes{
    Remote{"https://dl.flathub.org/repo/", "6E5C05D979C76DAF93C081354184DD4D907A7CAE", false, true},
};

// Public key matches the already-reviewed runtime primary fingerprint above.
inline constexpr char runtimePublicKey[] =
    "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";

// Application publisher keys live in the signed application catalog.
}
