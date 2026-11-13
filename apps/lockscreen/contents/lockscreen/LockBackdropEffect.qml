// SPDX-FileCopyrightText: 2026 KOS
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Effects

MultiEffect {
    property Item backdrop: null
    source: backdrop
    blurEnabled: true
    blurMax: 32
    blur: 0.35
    autoPaddingEnabled: false
}
