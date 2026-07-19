// Random number generation using blue noise + hash functions

// Hash function for seeds
uvec2 seed;

void initRNG(vec2 screenCoord, float frameCounter)
{
    seed = uvec2(screenCoord) * uvec2(1973u, 9277u) + uvec2(uint(frameCounter) * 26699u);
}

uint wang_hash(inout uint s)
{
    s = (s ^ 61u) ^ (s >> 16u);
    s *= 9u;
    s = s ^ (s >> 4u);
    s *= 0x27d4eb2du;
    s = s ^ (s >> 15u);
    return s;
}

float rng()
{
    uint s = seed.x ^ seed.y;
    float result = float(wang_hash(s)) * (1.0 / 4294967296.0);
    seed.x = s;
    return result;
}

vec2 rng2()
{
    return vec2(rng(), rng());
}

// Cosine-weighted hemisphere sampling
vec3 cosineWeightedDirection(vec3 normal)
{
    float r1 = TWO_PI * rng();
    float r2 = rng();
    float r2s = sqrt(r2);

    vec3 w = normal;
    vec3 u = normalize(cross((abs(w.x) > 0.1 ? vec3(0, 1, 0) : vec3(1, 0, 0)), w));
    vec3 v = cross(w, u);

    return normalize(u * cos(r1) * r2s + v * sin(r1) * r2s + w * sqrt(1.0 - r2));
}

// Uniform sphere sampling
vec3 uniformSphereDirection()
{
    float phi = TWO_PI * rng();
    float cosTheta = 1.0 - 2.0 * rng();
    float sinTheta = sqrt(1.0 - cosTheta * cosTheta);
    return vec3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);
}
