vec4 processSnellSample(sampler2D tex, vec2 baseUv, vec3 glassNormal,
    float ior, float dispersion, float magnitude, vec2 uvScale,
    vec2 lensShift)
{
    vec3 viewRay = vec3(0.0, 0.0, -1.0);
    vec3 refracted = refract(viewRay, glassNormal, 1.0 / ior);
    vec2 direction = length(refracted.xy) > 0.001
        ? normalize(refracted.xy) : vec2(0.0);
    // Keep the refraction local to the glass edge. The shape's edge width
    // controls where this is visible, not how far the backdrop can be pulled.
    // Clamp every channel after combining the optical and positional shifts so
    // a large panel or a high offset-strength setting cannot create a repeated
    // wallpaper-sized smear.
    // One budget for the whole lens, in `pixelUv` units. The edge direction term
    // and the body shift below are combined into a single texture lookup, so
    // they share this clamp; it is an absolute count of backdrop pixels, not a
    // fraction of the surface, which is what keeps a wide surface from dragging
    // far-away wallpaper features into itself.
    const float maxLensShiftPx = 48.0;
    vec2 maxShift = uvScale * maxLensShiftPx;
    vec2 shiftG = clamp(direction * magnitude * uvScale + lensShift,
                         -maxShift, maxShift);
    vec4 sampleG = texture(tex, clamp(baseUv + shiftG, 0.0, 1.0));

    if (dispersion > 0.001) {
        float fringe = clamp(dispersion, 0.0, 1.0) * 0.3;
        vec2 shiftR = clamp(direction * (magnitude * (1.0 + fringe)) * uvScale
                            + lensShift, -maxShift, maxShift);
        vec2 shiftB = clamp(direction * (magnitude * (1.0 - fringe)) * uvScale
                            + lensShift, -maxShift, maxShift);
        float red = texture(tex, clamp(baseUv + shiftR, 0.0, 1.0)).r;
        float blue = texture(tex, clamp(baseUv + shiftB, 0.0, 1.0)).b;
        return vec4(red, sampleG.g, blue, sampleG.a);
    }
    return sampleG;
}

GlassFragment snellsRefraction(vec2 position, vec2 halfShapeSize,
    vec4 cornerRadius, float minHalfSize, float dist, float concaveFactor)
{
    float bandWidth = clamp(edgeSizePixels, 0.1, minHalfSize * 0.9);
    // How far the body lens reaches inward from the rim, in device pixels, and
    // the largest shift it may ask for, in `pixelUv` units (one of those is two
    // logical pixels -- see below). Deliberately not derived from the shape: the
    // reach has to be the same on a wide launcher as on a small Dock, or one
    // configuration bends one and not the other.
    const float bodyReachPx = 40.0;
    const float bodyMaxPx = 40.0;
    float ior = 1.0 + refractionStrength;

    float minRadius = min(min(cornerRadius.x, cornerRadius.y),
        min(cornerRadius.z, cornerRadius.w));
    float epsilon = min(bandWidth * 0.75, minRadius * 0.6);
    float dxp = roundedRectangleDist(position + vec2(epsilon, 0.0),
        halfShapeSize, cornerRadius);
    float dxn = roundedRectangleDist(position - vec2(epsilon, 0.0),
        halfShapeSize, cornerRadius);
    float dyp = roundedRectangleDist(position + vec2(0.0, epsilon),
        halfShapeSize, cornerRadius);
    float dyn = roundedRectangleDist(position - vec2(0.0, epsilon),
        halfShapeSize, cornerRadius);
    vec2 smoothGradient = vec2(dxp - dxn, dyp - dyn);
    float gradientLength = length(smoothGradient);

    // Edge tilt is part of the liquid material, not a public tuning knob.
    // Soft glass uses only its inward glow and has no raised edge lens.
    float fixedBevelIntensity = materialSoftness > 0.001 ? 0.0 : 1.4;
    float normalHeight = concaveFactor * fixedBevelIntensity;
    vec2 normalXY = gradientLength > 0.001
        ? (smoothGradient / gradientLength) * normalHeight : vec2(0.0);
    vec3 glassNormal = normalize(vec3(normalXY, 1.0));

    // `bandWidth` is solely the width of the liquid edge. It used to multiply
    // the displacement as well, so widening an edge could turn into hundreds
    // of pixels of refraction. Keep the lens visible but strictly local.
    float lensMagnitude = min(concaveFactor * fixedBevelIntensity * 6.0,
        10.0);
    vec2 surfaceNormal = gradientLength > 0.001
        ? smoothGradient / gradientLength : vec2(1.0, 0.0);

    // The lens field belongs to this protocol shape, while UV conversion
    // belongs to the shared offscreen texture. Main used one blurSize for
    // both because it could only draw one window-wide shape.
    //
    // A size-normalised corner term used to be added to surfaceNormal here. Its
    // only reader was the fringing factor of the removed refraction twin, and it
    // made refractionOffsetStrength bend two unrelated optical terms at once --
    // the edge direction and the body lens below. The body lens is now the sole
    // consumer of that setting.
    //
    // `pixelUv` is one displacement unit: a texel of the half-resolution capture
    // the onscreen pass samples, so it is two logical pixels of the backdrop.
    vec2 pixelUv = halfpixel * 2.0;
    vec2 lensDirection = length(surfaceNormal) > 0.001
        ? normalize(surfaceNormal) : vec2(0.0);
    vec2 lensShift = -lensDirection * lensMagnitude * pixelUv;

    // ── Volume body lens ──────────────────────────────────────────────────
    // Everything above is edge work: `lensMagnitude` carries `concaveFactor`,
    // which is close to zero beyond a few pixels of the rim, so the interior of
    // every surface is optically flat and a Dock only showed a hairline of bend
    // along its silhouette. A thick glass body bends the whole of what is seen
    // through it, so the body gets its own profile, ungated by concaveFactor.
    //
    // The direction is the SDF normal -- each edge pulls the backdrop inward,
    // perpendicular to itself, exactly as the edge lens does -- and NOT a
    // radial pull toward the centre. A radial pull converges on one point, so
    // every direction meets there and the middle of the surface reads as a
    // swirl. Perpendicular-to-edge has no such point: it is the direction the
    // edge lens already uses, and where two edges meet (the medial axis) the
    // profile below has faded to nothing, so nothing has to agree there.
    //
    // The profile is the circular arc from the iOS lens: full strength at the
    // rim, easing to zero `bodyReachPx` inward. It is measured in absolute
    // pixels from the rim, and the displacement in absolute texels -- nothing
    // is divided by halfShapeSize, so a wide launcher and a small Dock bend by
    // the same amount under one configuration. That size-normalisation is what
    // made the previous body lens bend a Dock hard and a launcher barely.
    float interiorDist = max(-dist, 0.0);
    float bodyT = 1.0 - clamp(interiorDist / bodyReachPx, 0.0, 1.0);
    float bodyProfile = 1.0 - sqrt(max(1.0 - bodyT * bodyT, 0.0));
    vec2 outwardDir = gradientLength > 0.001
        ? smoothGradient / gradientLength : vec2(0.0);

    // How far the shift may go, in texels: as far as the captured backdrop
    // actually extends, never past it. The capture is exactly this shape's
    // bounding box, so a shift that runs off the edge re-reads one clamped
    // pixel and smears it -- the "repeated refraction" that the old
    // size-proportional offset produced, where the dock pulled its ends
    // hundreds of pixels because the offset was a *fraction* of the region.
    // Bounding by the room that is really there makes that impossible, and
    // that is what allows the magnitude below to be large again.
    vec2 sampleDir = -outwardDir;
    vec2 dirAbs = max(abs(sampleDir), vec2(1e-3));
    vec2 roomToEdge = (halfShapeSize - sign(sampleDir) * position) / dirAbs;
    float available = min(roomToEdge.x, roomToEdge.y);
    // The user's offset-strength setting drives this, so the body is tunable
    // from the same place as the edge lens instead of hiding a second knob.
    //
    // The magnitude is absolute and small on purpose. An offset proportional
    // to the surface -- which is what this looked like up to 2f97168 -- drags
    // whatever is behind the glass far enough that the window's own edges are
    // read several times over and the refraction reads as repeated copies of
    // the neighbour rather than as a bend. Bounding it by the room that is
    // really there keeps the sample inside the capture, and keeping it a fixed
    // number of texels keeps the bend the same on every surface.
    float bodyMagnitude = min(clamp(refractionOffsetStrength, 0.0, 12.0)
        * refractionStrength * 6.0, bodyMaxPx);
    // `available` is device pixels (it comes from the shape's own box) but the
    // shift it bounds is measured in `pixelUv`, and one pixelUv is a texel of
    // the half-resolution capture -- two logical pixels, so `2 * viewportScale`
    // device pixels. Comparing the two without that factor is what let the shift
    // overshoot the capture on a scaled output and smear the clamped edge.
    float roomInShiftUnits = available / max(viewportScale * 2.0, 0.0001);
    bodyMagnitude = min(bodyMagnitude, roomInShiftUnits * 0.85);
    lensShift -= outwardDir * bodyMagnitude * bodyProfile * pixelUv;

    float refractionMagnitude = lensMagnitude * refractionStrength;
    vec4 color = processSnellSample(texUnit, uv, glassNormal, ior,
        refractionRGBFringing, refractionMagnitude, pixelUv, lensShift);

    return GlassFragment(color);
}
