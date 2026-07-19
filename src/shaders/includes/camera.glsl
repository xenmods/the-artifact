// Camera ray generation

vec3 cameraRayOrigin;
vec3 cameraRayDirection;

void generateCameraRay(vec2 uv)
{
    // Normalized device coordinates (-1 to 1)
    vec2 ndc = uv * 2.0 - 1.0;
    ndc.x *= uResolution.x / uResolution.y; // aspect ratio correction

    // Jitter for anti-aliasing
    vec2 jitter = (rng2() - 0.5) / uResolution;
    ndc += jitter;

    // Ray from camera
    vec3 rayDir = normalize(vec3(ndc.x * uULen, ndc.y * uVLen, -1.0));

    // Transform by camera matrix
    cameraRayOrigin = (uCameraMatrix * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
    cameraRayDirection = normalize((uCameraMatrix * vec4(rayDir, 0.0)).xyz);
}
