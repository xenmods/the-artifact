precision highp float;

uniform sampler2D tInput;
uniform vec2 uResolution;

in vec2 vUv;
out vec4 fragColor;

// Subtle edge-aware bilateral filter
// Smooths Monte Carlo noise while preserving hard edges
void main() {
    vec2 texelSize = 1.0 / uResolution;
    vec4 center = texture(tInput, vUv);
    
    vec3 result = vec3(0.0);
    float totalWeight = 0.0;
    
    // 3x3 kernel — light touch
    float spatialSigma = 1.0;
    float colorSigma = 0.04; // Very tight — only smooths near-identical pixels
    
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            vec2 offset = vec2(float(x), float(y)) * texelSize;
            vec4 sample_color = texture(tInput, vUv + offset);
            
            // Spatial weight
            float spatialDist = float(x * x + y * y);
            float spatialWeight = exp(-spatialDist / (2.0 * spatialSigma * spatialSigma));
            
            // Color weight — reject pixels that differ too much (= edges)
            vec3 colorDiff = sample_color.rgb - center.rgb;
            float colorDist = dot(colorDiff, colorDiff);
            float colorWeight = exp(-colorDist / (2.0 * colorSigma * colorSigma));
            
            float weight = spatialWeight * colorWeight;
            result += sample_color.rgb * weight;
            totalWeight += weight;
        }
    }
    
    fragColor = vec4(result / totalWeight, center.a);
}
