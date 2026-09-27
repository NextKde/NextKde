"""Check compositor-facing state at actual wl_surface commits, not QML ticks."""

import re


def check_launcher_commits(output):
    launchers = set()
    regions = {}
    effects = {}
    blur = {}
    shapes = {}
    frames = 0
    hidden_frames = 0
    failures = []

    def object_id(text):
        return int(re.search(r"[#@](\d+)", text)[1])

    for line in output.splitlines():
        match = re.search(r"-> (\w+)[#@](\d+)\.(\w+)\((.*)\)", line)
        if not match:
            continue
        protocol, identifier, request, arguments = match.groups()
        identifier = int(identifier)
        args = arguments.split(", ")
        if request == "get_layer_surface" and '"quickshell-applauncher"' in arguments:
            launchers.add(object_id(args[1]))
        elif protocol == "wl_compositor" and request == "create_region":
            regions[object_id(args[0])] = []
        elif protocol == "wl_region" and request == "add":
            regions[identifier].append(tuple(map(int, args)))
        elif protocol == "ext_background_effect_manager_v1" and request == "get_background_effect":
            effects[object_id(args[0])] = object_id(args[1])
        elif protocol == "org_kde_kwin_blur_manager" and request == "create":
            effects[object_id(args[0])] = object_id(args[1])
        elif protocol in ("ext_background_effect_surface_v1", "org_kde_kwin_blur") \
                and request in ("set_blur_region", "set_region"):
            rectangles = regions.get(object_id(args[0]), []) if args[0] != "nil" else []
            rectangles = [r for r in rectangles if r[2] > 0 and r[3] > 0]
            if rectangles:
                x = min(r[0] for r in rectangles)
                y = min(r[1] for r in rectangles)
                right = max(r[0] + r[2] for r in rectangles)
                bottom = max(r[1] + r[3] for r in rectangles)
                blur[effects[identifier]] = (x, y, right - x, bottom - y)
            else:
                blur[effects[identifier]] = None
        elif protocol == "kos_surface_shape_manager_v1" and request == "get_shape":
            shapes[object_id(args[0])] = {
                "surface": object_id(args[1]), "geometry": (0, 0, 0, 0), "enabled": True,
            }
        elif protocol == "kos_surface_shape_v1":
            if request == "set_geometry":
                shapes[identifier]["geometry"] = tuple(map(int, args))
            elif request == "set_enabled":
                shapes[identifier]["enabled"] = args[0] == "1"
            elif request == "destroy":
                shapes.pop(identifier, None)
        elif protocol == "wl_surface" and request == "commit" and identifier in launchers:
            current = [s for s in shapes.values() if s["surface"] == identifier and s["enabled"]
                       and s["geometry"][2] >= 1 and s["geometry"][3] >= 1]
            region = blur.get(identifier)
            if region is None:
                hidden_frames += 1
                if current:
                    failures.append(f"glass still enabled after blur removal: {current}")
                continue
            frames += 1
            # RoundedBlurRegion rounds each primitive; SurfaceShape rounds its
            # enclosing rectangle. Fractional animation coordinates can differ
            # by one logical pixel, but never by a whole animation frame.
            if len(current) != 1 or any(abs(a - b) > 1
                    for a, b in zip(current[0]["geometry"], region)):
                failures.append(f"commit uses blur {region} with glass {current}")

    assert frames >= 30 and hidden_frames > 0, (
        f"Missing real launcher protocol coverage: {frames} visible, {hidden_frames} hidden commits; "
        "run on KWin with the KOS glass effect and built SurfaceShape module")
    assert not failures, f"{len(failures)}/{frames} launcher commits have stale glass state:\n" \
        + "\n".join(failures[:8])
    return frames
