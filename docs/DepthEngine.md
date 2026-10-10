# Local AI depth engine

`services/ai/` is a standalone C++ library. It depends on Qt Core/Network,
OpenCV and ONNX Runtime, but has no dependency on Quickshell, Plasma, KDE or
QML. The optional `kos-ai-worker` process owns `DepthGenerator` and its ONNX
session. `kos-platform` starts it on the first request, sends bounded JSONL
messages over stdin/stdout, serializes inference, and retires it after 15 idle
seconds. A worker crash, timeout or failed model download returns an error for
that request without stopping the platform daemon. On Linux, the worker runs at
lower CPU priority and is made a preferred OOM victim so core desktop controls
retain priority under system memory pressure.

The Settings app exposes an opt-in **空间壁纸视差** toggle. It is off by
default. `SpatialWallpaperService` requests assets only after the user enables
it, and when the selected wallpaper changes. It waits briefly for the path to
settle and retries temporary worker failures with a delay. `DepthManager`
requests generation through `qs.desktop.modules.platform`; the daemon returns
a local depth PNG, dimensions, cache status and model contract. The request can
take up to five minutes during the first model download or a large inference.

After depth generation, the worker optionally prepares a foreground matte, a
filled background, and a near-field motion map under `spatial-v3/`. The matte
uses a pinned local IS-Net general-use ONNX model. A depth island checks that
the model selected the nearby subject; depth-guided GrabCut fills small gaps
near that subject. If model download or inference fails, the bounded GrabCut
path remains available. The preparation contract is
`isnet-general-use-softmatte-lowhalo-v13`; the model confidence matte is kept
soft at the contour and the background fill halo is bounded to the expected
parallax travel. Mismatched cached
metadata forces regeneration. Preparation is limited to 2560 pixels wide.
The model runs only in `kos-ai-worker`. A rejected spatial result still returns
the depth map and leaves the normal wallpaper usable.

The foreground model is the `isnet-general-use.onnx` asset from the
[`rembg` model release](https://github.com/danielgatis/rembg/releases/tag/v0.0.0),
originally based on [DIS / IS-Net](https://github.com/xuebinqin/DIS).
Its pinned SHA256 is
`60920e99c45464f2ba57bee2ad08c919a52bbf852739e96947fbb4358c0d964a`.
The worker validates float32 NCHW input `[1,3,1024,1024]`, 12 outputs, and
the first output's float32 shape `[1,1,1024,1024]`. Input is RGB resized to
1024 square with OpenCV area interpolation, scaled to `[0,1]`, then shifted by
`0.5` per channel. The first output is normalized per image and resized to the
working image size. No Python runtime is used.

When all three assets load, `DepthWallpaperLayer` prefers the optional
Qt Quick 3D renderer. It projects the reconstructed background onto a depth
mesh, orbits the camera around the center, and composites a mostly stationary
original-photo foreground with the cached soft matte. The 16% image zoom keeps
the orbit inside the source image. The foreground shader applies a bounded
color correction only to partially transparent pixels: it estimates the
foreground contribution using the reconstructed background color at the
original coordinate before blending over the moving background. This reduces
color spill without changing the matte outline. If the 3D plugin cannot load,
the two-layer shader remains available, followed by the simpler depth shader
when layered assets are unavailable. The shader fallback uses a 5% crop.
The shader paths recreate Plasma's aspect-preserving center crop in texture
coordinates because Qt does not pass an Image's `fillMode` into a
`ShaderEffect` sampler. Pointer changes are eased over 150 ms.
In the shader fallback, wallpaper and depth textures are decoded at the
output's physical pixel size so high-DPI screens do not upscale a
logical-resolution image.
The renderer lives in a separate click-through Bottom-layer window, mapped
before the desktop widget window. KWin can therefore blur the spatial wallpaper
behind widget glass cards. It appears only on the selected desktop output;
errors leave the normal wallpaper in place.

The design follows [waydeeper's optional perspective mesh and flat
mode](https://github.com/EdenQwQ/waydeeper) and the foreground-color
decontamination used by [rembg](https://github.com/danielgatis/rembg/blob/main/rembg/bg.py).
The bounded shader correction is an approximation: the matte is a model
confidence map, and the reconstructed background may differ from the true
hidden scene. [3D Photo Inpainting](https://github.com/vt-vl-lab/3d-photo-inpainting)
shows the more complete approach of filling both occluded color and depth in
a layered image, but that pipeline would add several inference models and
substantial cost to this CPU-first feature. Large hidden areas and fine fur or
grass cannot be made artifact-free from one photograph with the current assets.

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
indicate stronger near-depth response for this model. The 16-bit depth map
remains cached independently of the renderer and is reused if the feature is
turned off and on again. Model segmentation improves the cutout but cannot
reconstruct every hidden part of a background; complex hair, grass, and large
occluded regions may still show artifacts during motion. The current scene
assets do not yet put widgets
behind foreground objects; widget occlusion needs a separate, verified mask
and compositing path.

## Build runtime

Nix builds use OpenCV and ONNX Runtime from `packaging/nix/kos-platform.nix`. On Arch,
`kosctl build` installs OpenCV when needed and fetches the official ONNX Runtime
Linux x64 1.30.0 C++ SDK into the ignored build directory. The SDK archive is
SHA256-checked and its CPU shared libraries are installed beside
`kos-platform` under `~/.local/lib`. The model itself is downloaded only when a
non-cached depth request is made.

The ONNX Runtime archive is currently Linux x64. The `kos-ai` public API is
standard C++ and the model/runtime design allows platform-specific SDKs, but
Windows and macOS packaging have not been implemented or validated in this
project yet.
