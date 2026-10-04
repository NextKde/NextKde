#version 100
// ES 变体：活体卡逐像素投影 + 圆角（与 _core 版数学一致）
precision mediump float;
uniform sampler2D texUnit;
uniform float angleRad;
uniform float focal;
uniform float yOff;
uniform vec2 camRel;
uniform vec2 itemSize;
uniform vec2 cardSize;
uniform float crad;
uniform float alpha;
varying vec2 uv;
void main(void)
{
    vec2 p = uv * itemSize;
    float c = cos(angleRad);
    float s = sin(angleRad);
    float A = p.x - camRel.x;
    float denom = c * focal - A * s;
    if (abs(denom) < 1.0)
        discard;
    float u = A * focal / denom;
    float k = focal / (focal + u * s);
    float v = (p.y - camRel.y) / k - yOff;
    vec2 tuv = vec2(u / cardSize.x + 0.5, 0.5 - v / cardSize.y);
    if (tuv.x < 0.0 || tuv.x > 1.0 || tuv.y < 0.0 || tuv.y > 1.0)
        discard;
    vec2 q = abs(vec2(u, v)) - (cardSize * 0.5 - vec2(crad));
    float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - crad;
    float a = 1.0 - smoothstep(-1.0, 1.0, d);
    if (a <= 0.003)
        discard;
    gl_FragColor = texture2D(texUnit, tuv) * a * vec4(alpha, alpha, alpha, alpha);
}
