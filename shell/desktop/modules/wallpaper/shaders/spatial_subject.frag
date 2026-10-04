// Qt Quick 3D CustomMaterial snippet; compiled by the renderer at run time.
VARYING vec2 subjectUv;

void MAIN()
{
    vec3 captured = texture(sourceTexture, subjectUv).rgb;
    float alpha = texture(matteTexture, subjectUv).r;
    vec3 premultiplied = captured * alpha;
    if (alpha > 0.08 && alpha < 0.98) {
        vec3 oldBackground = texture(backgroundTexture, subjectUv).rgb;
        vec3 recovered = clamp(captured - oldBackground * (1.0 - alpha),
                               vec3(0.0), vec3(alpha));
        float maximumChange = 0.18 * alpha;
        recovered = clamp(recovered, premultiplied - vec3(maximumChange),
                          premultiplied + vec3(maximumChange));
        float edgeWeight = smoothstep(0.08, 0.30, alpha)
                         * (1.0 - smoothstep(0.82, 0.98, alpha));
        premultiplied = mix(premultiplied, recovered, 0.75 * edgeWeight);
    }
    FRAGCOLOR = vec4(premultiplied, alpha);
}
