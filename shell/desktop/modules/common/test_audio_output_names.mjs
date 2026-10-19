import assert from "node:assert/strict";
import { resolveAudioOutputName } from "./AudioOutputNames.mjs";

const sink = (name, description, nickname = undefined) => ({
    isSink: true, name, description, nickname,
});
const output = (name, description) => ({ name, description, isDefault: false });
const label = "Output devices";

// The reported case: the platform snapshot carries "(null)" for a UTF-8 name
// while PipeWire still has the original text.
assert.equal(
    resolveAudioOutputName(
        [sink("alsa_output.dp-2", "副屏幕（MG248）")],
        output("alsa_output.dp-2", "(null)"),
        label,
    ),
    "副屏幕（MG248）",
    "PipeWire description wins over a (null) platform description",
);

// Same, but the node only carries a nickname.
assert.equal(
    resolveAudioOutputName(
        [sink("alsa_output.dp-2", "", "主屏幕（XG27UCS）")],
        output("alsa_output.dp-2", "(null)"),
        label,
    ),
    "主屏幕（XG27UCS）",
    "nickname is used when description is empty",
);

// Normal ASCII name that the platform reports correctly.
assert.equal(
    resolveAudioOutputName([], output("alsa_output.usb", "USB Audio Analog Stereo"), label),
    "USB Audio Analog Stereo",
    "platform description is used when no PipeWire node matches",
);

// "(null)" must never reach the UI; the device name is the last identifier.
assert.equal(
    resolveAudioOutputName(
        [sink("alsa_output.other", "Other device")],
        output("alsa_output.dp-2", "(null)"),
        label,
    ),
    "alsa_output.dp-2",
    "an unmatched (null) falls back to the device name",
);

assert.equal(
    resolveAudioOutputName([], output("", "null"), label),
    label,
    "an unusable entry falls back to the translated label",
);

// Nodes for other sinks must not be borrowed.
assert.equal(
    resolveAudioOutputName(
        [sink("alsa_output.a", "A"), sink("alsa_output.b", "B")],
        output("alsa_output.b", "(null)"),
        label,
    ),
    "B",
    "the node is matched by name",
);

console.log("audio output names: all resolution cases passed");
