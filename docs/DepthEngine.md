# Local AI depth engine

`liquid-ai/` is a standalone C++ library. It depends on Qt Core/Network,
OpenCV and ONNX Runtime, but has no dependency on Quickshell, Plasma, KDE or
QML. The optional `kos-ai-worker` process owns `DepthGenerator` and its ONNX
session. `kos-platform` starts it on the first request, sends bounded JSONL
messages over stdin/stdout, serializes inference, and retires it after one idle
minute. A worker crash, timeout or failed model download returns an error for
that request without stopping the platform daemon. On Linux, the worker runs at
lower CPU priority and is made a preferred OOM victim so core desktop controls
retain priority under system memory pressure.

The Settings app exposes an opt-in **空间壁纸视差** toggle. It is off by
default. `SpatialWallpaperService` requests a depth map only after the user
enables it, and only when the selected wallpaper changes. It waits briefly for
the wallpaper path to settle and retries temporary worker failures with a
delay. `DepthManager`
requests generation through `qs.desktop.modules.platform`; the daemon returns a
local PNG path, image dimensions, cache status, model ID and preprocessing
contract. The request can take up to five minutes while the model downloads or
a large image is inferred. On success, `DepthWallpaperLayer` uses a small GPU
shader pass to shift wallpaper samples according to depth and pointer position.
The shader reproduces Plasma's aspect-preserving center crop for both the
wallpaper and depth texture; Qt does not carry an Image's `fillMode` into a
`ShaderEffect` sampler. It then applies an extra 3.2% crop per axis for
movement. Most pointer motion pans the image together (2.75% per axis); the
relative depth contribution is limited to 0.25% either way and fades where a
depth boundary would otherwise pull colors across a foreground edge. Pointer
changes are eased over 150 ms.
The wallpaper and depth textures are decoded at the output's physical pixel
size so high-DPI screens do not upscale a logical-resolution image.
The renderer lives in a separate click-through Bottom-layer window, mapped
before the desktop widget window. KWin can therefore blur the spatial wallpaper
behind widget glass cards. It appears only on the selected desktop output;
errors leave the normal wallpaper in place.

## Pinned model

The current candidate is Depth Anything V2 Small / ViT-S from the
`fabio-sim/Depth-Anything-ONNX` `v2.0.0` release. The original Depth Anything V2
project links this ONNX implementation from its community-support section.
The AI worker downloads the dynamic-shape ONNX asset once to
`~/.cache/liquid-shell/models/`, checks its SHA256 before atomically installing
it, and rejects a mismatched input signature.

| Property | Pinned value |
| --- | --- |
| Asset | `depth_anything_v2_vits_dynamic.onnx` |
| URL | `https://github.com/fabio-sim/Depth-Anything-ONNX/releases/download/v2.0.0/depth_anything_v2_vits_dynamic.onnx` |
| SHA256 | `46c4e8eeda3a27f34701831b6a2ec7753d7b38779b215acb5633424703deed8f` |
| Input | float32 NCHW `[1,3,H,W]`, H and W dynamic and divisible by 14 |
| Output | float32 `[1,H,W]` |
| Runtime provider | ONNX Runtime CPU |

The URL can move to a project-owned GitHub Release after the same model bytes
and license notices are published there; keep the checksum and model contract
unchanged for that byte-identical mirror. To change the model or export, add a
new model ID, checksum and contract version. Existing cache entries then stay
separate automatically.

## Image and output contract

1. Hash the original file bytes with SHA256. Decode 8-bit color through OpenCV;
   file extensions do not determine image format.
2. Convert BGR to RGB. Set scale to `max(518/width, 518/height)`, round each
   scaled dimension to a multiple of 14 with a minimum of 518, and resize using
   OpenCV cubic interpolation.
3. Convert to float32 `[0,1]`, normalize RGB with means
   `[0.485,0.456,0.406]` and standard deviations `[0.229,0.224,0.225]`, then
   form NCHW input.
4. Resize raw model output to original dimensions with cubic interpolation.
   Reject non-finite or constant output. Normalize each image to unsigned
   16-bit grayscale `[0,65535]` and write PNG atomically.
5. Cache under `$XDG_CACHE_HOME/liquid-shell/wallpapers/<key>/`, where key is
   SHA256 of source hash, model hash and contract version. Metadata records the
   model, contract, source hash, generation time and output dimensions.

Values are relative depth responses rather than distances; larger values
indicate stronger near-depth response for this model. The current renderer uses
them only for coarse parallax. It does not yet place widgets behind foreground
objects: clean widget occlusion requires segmentation or matting to recover the
foreground pixels. The 16-bit depth map remains cached independently of the
renderer and is reused if the feature is turned off and on again.

## Build runtime

Nix builds use OpenCV and ONNX Runtime from `nix/kos-platform.nix`. On Arch,
`kosctl build` installs OpenCV when needed and fetches the official ONNX Runtime
Linux x64 1.30.0 C++ SDK into the ignored build directory. The SDK archive is
SHA256-checked and its CPU shared libraries are installed beside
`kos-platform` under `~/.local/lib`. The model itself is downloaded only when a
non-cached depth request is made.

The ONNX Runtime archive is currently Linux x64. The `liquid-ai` public API is
standard C++ and the model/runtime design allows platform-specific SDKs, but
Windows and macOS packaging have not been implemented or validated in this
project yet.
