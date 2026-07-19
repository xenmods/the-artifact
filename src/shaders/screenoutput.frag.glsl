// Screen output fragment shader - tone mapping and gamma correction
precision highp float;
precision highp sampler2D;

uniform sampler2D tTexture;
uniform float uToneMappingExposure;
uniform float uPixelEdgeSharpness;
uniform vec2 uResolution;

in vec2 vUv;
out vec4 fragColor;

// ACES filmic tone mapping
vec3 ACESFilm(vec3 x)
{
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

// Edge-aware sharpening
vec3 sharpen(vec2 uv)
{
    vec2 texel = 1.0 / uResolution;
    vec3 center = texture(tTexture, uv).rgb;
    vec3 up    = texture(tTexture, uv + vec2(0.0, texel.y)).rgb;
    vec3 down  = texture(tTexture, uv - vec2(0.0, texel.y)).rgb;
    vec3 left  = texture(tTexture, uv - vec2(texel.x, 0.0)).rgb;
    vec3 right = texture(tTexture, uv + vec2(texel.x, 0.0)).rgb;

    vec3 blur = (up + down + left + right) * 0.25;
    vec3 diff = center - blur;

    // Edge detection — reduce sharpening at edges to avoid halos
    float edge = length(diff);
    float sharpAmount = uPixelEdgeSharpness * smoothstep(0.3, 0.0, edge);

    return center + diff * sharpAmount;
}

void main()
{
    vec3 color = sharpen(vUv);

    // Exposure
    color *= uToneMappingExposure;

    // ACES tone mapping
    color = ACESFilm(color);

    // Gamma correction
    color = pow(color, vec3(1.0 / 2.2));

    // Subtle vignette
    vec2 uv = vUv * 2.0 - 1.0;
    float vignette = 1.0 - dot(uv * 0.5, uv * 0.5);
    vignette = smoothstep(0.0, 1.0, vignette);
    color *= mix(0.7, 1.0, vignette);

    fragColor = vec4(color, 1.0);
}
