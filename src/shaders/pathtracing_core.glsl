precision highp float;
precision highp int;
precision highp sampler2D;

// ============ UNIFORMS ============
uniform sampler2D tPreviousTexture;
uniform mat4 uCameraMatrix;
uniform vec2 uResolution;
uniform vec2 uRandomVec2;
uniform float uEPS_intersect;
uniform float uTime;
uniform float uSampleCounter;
uniform float uFrameCounter;
uniform float uULen;
uniform float uVLen;
uniform bool uCameraIsMoving;
uniform int uSamplesPerFrame;
uniform float uWalkPhase;

// Textures placeholder
uniform sampler2D tWoodColor; uniform sampler2D tWoodNormal; uniform sampler2D tWoodRoughness;
uniform sampler2D tMetalColor; uniform sampler2D tMetalNormal; uniform sampler2D tMetalRoughness;
uniform sampler2D tConcreteColor; uniform sampler2D tConcreteNormal; uniform sampler2D tConcreteRoughness;
uniform sampler2D tMarbleColor; uniform sampler2D tMarbleNormal; uniform sampler2D tMarbleRoughness;

// Artifact objects
uniform int uNumBoxes;
uniform vec3 uBoxMins[32];
uniform vec3 uBoxMaxs[32];
uniform int uBoxMats[32];

uniform int uNumCylinders;
uniform vec3 uCylPos[32];
uniform vec3 uCylAxis[32];
uniform float uCylRadii[32];
uniform float uCylHeights[32];
uniform int uCylMats[32];

// Room
uniform vec3 uRoomMin;
uniform vec3 uRoomMax;

// Light
uniform vec3 uLightPos;
uniform vec3 uLightColor;
uniform float uLightRadius;
uniform int uMaxBounces;

// HDRI
uniform sampler2D tHDRI;
uniform bool uUseHDRI;

in vec2 vUv;
out vec4 fragColor;

// ============ CONSTANTS ============
#define INFINITY 1000000.0
#define MAX_BOUNCES 4

const int MAT_LIGHT = 0;
const int MAT_WOOD = 1;
const int MAT_METAL = 2;
const int MAT_CONCRETE = 3;
const int MAT_GOLD = 4;
const int MAT_GEM = 5;
const int MAT_MARBLE = 6;
const int MAT_GLASS = 7;

// ============ GLOBAL STATE ============
vec3 rayOrigin, rayDirection;

uvec2 randSeed;
void initRNG(vec2 fragCoord, float frame) {
    randSeed = uvec2(fragCoord.xy) + uvec2(frame * 1337.0, frame * 997.0);
}
uint wangHash(inout uint s) { s=(s^61u)^(s>>16u); s*=9u; s=s^(s>>4u); s*=0x27d4eb2du; s=s^(s>>15u); return s; }
float rand() { uint s = randSeed.x^randSeed.y; float r = float(wangHash(s))*(1.0/4294967296.0); randSeed.x=s; return r; }

vec3 cosWeightedDir(vec3 n) {
    float r1 = 6.2831853 * rand();
    float r2 = rand(); float r2s = sqrt(r2);
    vec3 w = n; vec3 u = normalize(cross((abs(w.x)>0.1 ? vec3(0,1,0):vec3(1,0,0)), w)); vec3 v = cross(w,u);
    return normalize(u*cos(r1)*r2s + v*sin(r1)*r2s + w*sqrt(1.0-r2));
}

// ============ PBR MATERIAL INCLUDES ============
#define PI 3.14159265358979323

vec3 getNormalFromMap(vec3 mappedNormal, vec3 hn) {
    vec3 up = abs(hn.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(up, hn));
    vec3 bitangent = cross(hn, tangent);
    mat3 tbn = mat3(tangent, bitangent, hn);
    return normalize(tbn * (mappedNormal * 2.0 - 1.0));
}

vec3 importanceSampleGGX(vec2 Xi, vec3 N, float roughness) {
    float a = roughness * roughness;
    float phi = 2.0 * PI * Xi.x;
    float cosTheta = sqrt((1.0 - Xi.y) / (1.0 + (a*a - 1.0) * Xi.y));
    float sinTheta = sqrt(1.0 - cosTheta*cosTheta);
    
    vec3 H;
    H.x = cos(phi) * sinTheta;
    H.y = sin(phi) * sinTheta;
    H.z = cosTheta;
    
    vec3 up = abs(N.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(up, N));
    vec3 bitangent = cross(N, tangent);
    
    vec3 sampleVec = tangent * H.x + bitangent * H.y + N * H.z;
    return normalize(sampleVec);
}

float GeometrySchlickGGX(float NdotV, float roughness) {
    float r = (roughness + 1.0); float k = (r*r) / 8.0;
    return NdotV / (NdotV * (1.0 - k) + k);
}
float GeometrySmith(float NdotV, float NdotL, float roughness) {
    return GeometrySchlickGGX(NdotV, roughness) * GeometrySchlickGGX(NdotL, roughness);
}

vec3 fresnelSchlickRoughness(float cosTheta, vec3 F0, float roughness) {
    return F0 + (max(vec3(1.0 - roughness), F0) - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

vec3 evaluateMaterial(int matType, vec3 rd, vec3 hn, vec3 albedo, float rough, float metal, out vec3 newDir, out bool absorbed) {
    absorbed = false;
    
    if (matType == MAT_GLASS) {
        float ior = 1.5;
        float cosI = dot(rd, hn);
        bool isOutside = cosI < 0.0;
        float eta = isOutside ? (1.0 / ior) : ior;
        vec3 n = isOutside ? hn : -hn;
        float cosTheta = min(dot(-rd, n), 1.0);
        float sinTheta = sqrt(1.0 - cosTheta * cosTheta);
        
        bool cannotRefract = eta * sinTheta > 1.0;
        float r0 = (1.0 - ior) / (1.0 + ior);
        r0 = r0 * r0;
        float reflectance = r0 + (1.0 - r0) * pow(1.0 - cosTheta, 5.0);
        
        if (cannotRefract || rand() < reflectance) {
            newDir = reflect(rd, n);
        } else {
            newDir = refract(rd, n, eta);
        }
        // Tint the glass slightly at grazing angles
        return mix(albedo, vec3(1.0), reflectance);
    }
    
    vec3 viewDir = -rd;
    vec3 F0 = mix(vec3(0.04), albedo, metal);
    float NdotV = max(dot(hn, viewDir), 0.0);
    vec3 F = fresnelSchlickRoughness(NdotV, F0, rough);
    float specChance = max(F.x, max(F.y, F.z));
    
    if (rand() < specChance) {
        vec2 Xi = vec2(rand(), rand());
        vec3 H = importanceSampleGGX(Xi, hn, rough);
        newDir = reflect(rd, H);
        
        float NdotL = max(dot(hn, newDir), 0.0);
        float NdotH = max(dot(hn, H), 0.0);
        float VdotH = max(dot(viewDir, H), 0.0);
        
        if (NdotL > 0.0) {
            float G = GeometrySmith(NdotV, NdotL, rough);
            vec3 weight = (F * G * VdotH) / max(NdotV * NdotH, 0.001);
            return min(weight, vec3(5.0));
        } else {
            absorbed = true;
            return vec3(0);
        }
    } else {
        newDir = cosWeightedDir(hn);
        vec3 kD = (vec3(1.0) - F) * (1.0 - metal);
        return albedo * kD;
    }
}

// ============ INTERSECTIONS ============

float sphereIntersect(float rad, vec3 pos, vec3 ro, vec3 rd) {
    vec3 oc = ro - pos;
    float b = dot(oc, rd);
    float c = dot(oc, oc) - rad*rad;
    float h = b*b - c;
    if(h < 0.0) return INFINITY;
    h = sqrt(h);
    float t = -b - h;
    if(t > 0.0) return t;
    t = -b + h;
    if(t > 0.0) return t;
    return INFINITY;
}

float boxIntersect(vec3 mn, vec3 mx, vec3 ro, vec3 rd, out vec3 n) {
    vec3 invD = 1.0 / (rd + step(abs(rd), vec3(1e-8)) * 1e-8);
    vec3 t0s = (mn - ro) * invD;
    vec3 t1s = (mx - ro) * invD;
    vec3 tmin = min(t0s, t1s);
    vec3 tmax = max(t0s, t1s);
    float tNear = max(max(tmin.x, tmin.y), tmin.z);
    float tFar  = min(min(tmax.x, tmax.y), tmax.z);
    if (tNear > tFar || tFar < 0.0) return INFINITY;
    if (tNear > 0.0) { n = -sign(rd) * step(tmin.zxy, tmin.xyz) * step(tmin.yzx, tmin.xyz); return tNear; }
    else { n = -sign(rd) * step(tmax.xyz, tmax.zxy) * step(tmax.xyz, tmax.yzx); return tFar; }
}

float cylIntersect(vec3 pos, vec3 axis, float r, float h, vec3 ro, vec3 rd, out vec3 n) {
    vec3 p = ro - pos;
    vec3 dir = rd - axis * dot(rd, axis);
    vec3 dp = p - axis * dot(p, axis);
    float a = dot(dir, dir);
    
    float t_cyl = INFINITY;
    float t_cap = INFINITY;
    float hit_y_cap = 0.0;
    
    if (a > 0.000001) {
        float b = 2.0 * dot(dir, dp);
        float c = dot(dp, dp) - r*r;
        float disc = b*b - 4.0*a*c;
        if (disc >= 0.0) {
            disc = sqrt(disc);
            float t1 = (-b - disc) / (2.0*a);
            float t2 = (-b + disc) / (2.0*a);
            if (t1 > 0.0) {
                float y1 = dot(p + rd*t1, axis);
                if (abs(y1) <= h/2.0) t_cyl = t1;
            }
            if (t_cyl == INFINITY && t2 > 0.0) {
                float y2 = dot(p + rd*t2, axis);
                if (abs(y2) <= h/2.0) t_cyl = t2;
            }
        }
    }
    
    float denom = dot(rd, axis);
    if (abs(denom) > 0.000001) {
        float tc1 = (h/2.0 - dot(p, axis)) / denom;
        if (tc1 > 0.0) {
            vec3 p1 = p + rd*tc1;
            if (length(p1 - axis*dot(p1, axis)) <= r) { t_cap = tc1; hit_y_cap = h/2.0; }
        }
        float tc2 = (-h/2.0 - dot(p, axis)) / denom;
        if (tc2 > 0.0 && tc2 < t_cap) {
            vec3 p2 = p + rd*tc2;
            if (length(p2 - axis*dot(p2, axis)) <= r) { t_cap = tc2; hit_y_cap = -h/2.0; }
        }
    }
    
    if (t_cyl == INFINITY && t_cap == INFINITY) return INFINITY;
    
    if (t_cyl < t_cap) {
        vec3 hp = p + rd*t_cyl;
        n = normalize(hp - axis*dot(hp, axis));
        return t_cyl;
    } else {
        n = axis * sign(hit_y_cap);
        return t_cap;
    }
}

float mannequinIntersect(vec3 ro, vec3 rd, out vec3 n) {
    float t = INFINITY;
    float d; vec3 tempN;
    
    vec3 camPos = uCameraMatrix[3].xyz;
    vec3 yAxis = vec3(0.0, 1.0, 0.0);
    
    float swing = sin(uWalkPhase) * 2.5;
    float swingUpper = swing * 0.5;
    float swingLower = swing * 1.0;
    float bodyBob = abs(sin(uWalkPhase)) * 0.3;
    
    camPos.y += bodyBob;
    
    vec3 headCenter = camPos - vec3(0.0, 1.5, 0.0);
    d = boxIntersect(headCenter - vec3(1.25, 1.5, 1.0), headCenter + vec3(1.25, 1.5, 1.0), ro, rd, tempN);
    if (d < t) { t = d; n = tempN; }
    
    d = cylIntersect(camPos - vec3(0.0, 3.5, 0.0), yAxis, 0.6, 2.0, ro, rd, tempN);
    if (d < t) { t = d; n = tempN; }
    
    vec3 torsoUpper = camPos - vec3(0.0, 6.5, 0.0);
    d = boxIntersect(torsoUpper - vec3(2.5, 2.0, 1.25), torsoUpper + vec3(2.5, 2.0, 1.25), ro, rd, tempN);
    if (d < t) { t = d; n = tempN; }
    
    vec3 torsoLower = camPos - vec3(0.0, 10.0, 0.0);
    d = boxIntersect(torsoLower - vec3(1.75, 1.5, 1.0), torsoLower + vec3(1.75, 1.5, 1.0), ro, rd, tempN);
    if (d < t) { t = d; n = tempN; }
    
    d = cylIntersect(camPos - vec3(3.5, 6.5, swingUpper), yAxis, 0.9, 4.0, ro, rd, tempN);
    if (d < t) { t = d; n = tempN; }
    
    d = cylIntersect(camPos - vec3(3.5, 10.5, swingLower), yAxis, 0.7, 4.0, ro, rd, tempN);
    if (d < t) { t = d; n = tempN; }
    
    d = cylIntersect(camPos - vec3(-3.5, 6.5, -swingUpper), yAxis, 0.9, 4.0, ro, rd, tempN);
    if (d < t) { t = d; n = tempN; }
    
    d = cylIntersect(camPos - vec3(-3.5, 10.5, -swingLower), yAxis, 0.7, 4.0, ro, rd, tempN);
    if (d < t) { t = d; n = tempN; }
    
    d = cylIntersect(camPos - vec3(1.2, 13.0, -swingUpper), yAxis, 1.1, 5.0, ro, rd, tempN);
    if (d < t) { t = d; n = tempN; }
    
    d = cylIntersect(camPos - vec3(1.2, 17.5, -swingLower), yAxis, 0.8, 4.0, ro, rd, tempN);
    if (d < t) { t = d; n = tempN; }
    
    d = cylIntersect(camPos - vec3(-1.2, 13.0, swingUpper), yAxis, 1.1, 5.0, ro, rd, tempN);
    if (d < t) { t = d; n = tempN; }
    
    d = cylIntersect(camPos - vec3(-1.2, 17.5, swingLower), yAxis, 0.8, 4.0, ro, rd, tempN);
    if (d < t) { t = d; n = tempN; }
    
    return t;
}

void getPBRProps(int mat, vec2 uv, vec3 hp, vec3 hn, out vec3 albedo, out vec3 normal, out float rough, out float metal) {
    if (mat == MAT_WOOD) {
        albedo = texture(tWoodColor, uv).rgb;
        rough = texture(tWoodRoughness, uv).r;
        metal = 0.0;
        vec3 nm = texture(tWoodNormal, uv).rgb;
        normal = getNormalFromMap(nm, hn);
    } else if (mat == MAT_METAL) {
        albedo = texture(tMetalColor, uv).rgb;
        rough = texture(tMetalRoughness, uv).r;
        metal = 1.0;
        vec3 nm = texture(tMetalNormal, uv).rgb;
        normal = getNormalFromMap(nm, hn);
    } else if (mat == MAT_CONCRETE) {
        albedo = texture(tConcreteColor, uv).rgb;
        rough = texture(tConcreteRoughness, uv).r;
        metal = 0.0;
        vec3 nm = texture(tConcreteNormal, uv).rgb;
        normal = getNormalFromMap(nm, hn);
    } else if (mat == MAT_GOLD) {
        albedo = vec3(1.0, 0.84, 0.0);
        rough = 0.15;
        metal = 1.0;
        normal = hn;
    } else if (mat == MAT_GEM) {
        albedo = vec3(0.0, 1.0, 0.8);
        rough = 0.05;
        metal = 0.0;
        normal = hn;
    } else if (mat == MAT_MARBLE) {
        albedo = texture(tMarbleColor, uv).rgb;
        rough = texture(tMarbleRoughness, uv).r;
        metal = 0.0;
        vec3 nm = texture(tMarbleNormal, uv).rgb;
    } else if (mat == MAT_GLASS) {
        albedo = vec3(0.9, 0.95, 1.0);
        rough = 0.01;
        metal = 0.0;
        normal = hn;
    } else {
        albedo = vec3(1); rough = 0.5; metal = 0.0; normal = hn;
    }
}

// Forward declarations! These must be implemented by the specific scene shader!
float sceneIntersect(vec3 ro, vec3 rd, bool isPrimaryRay, out vec3 outNormal, out int outMat, out vec3 outEmission, out vec2 outUV);
bool shadowIntersect(vec3 ro, vec3 rd, float maxDist);
vec3 getSkyColor(vec3 rayDir, bool isPrimaryRay);

vec3 pathTrace() {
    vec3 accum = vec3(0);
    vec3 throughput = vec3(1);
    
    for (int bounce=0; bounce<4; bounce++) { 
        if (bounce >= uMaxBounces) break;
        
        vec3 hn, hitEmission; int hitMatType; vec2 hitUV;
        float t = sceneIntersect(rayOrigin, rayDirection, bounce == 0, hn, hitMatType, hitEmission, hitUV);
        
        if (t == INFINITY) { 
            accum += throughput * getSkyColor(rayDirection, bounce == 0);
            break; 
        }
        
        if (hitMatType == MAT_LIGHT) { 
            accum += throughput * hitEmission; 
            break; 
        }
        if (hitMatType == MAT_GEM) {
            accum += throughput * vec3(0.2, 2.0, 1.5) * 15.0; 
            break;
        }
        
        vec3 hp = rayOrigin + rayDirection*t;
        vec3 albedo, mappedNormal; float rough, metal;
        getPBRProps(hitMatType, hitUV, hp, hn, albedo, mappedNormal, rough, metal);
        
        bool absorbed; vec3 newDir;
        vec3 materialColor = evaluateMaterial(hitMatType, rayDirection, mappedNormal, albedo, rough, metal, newDir, absorbed);
        
        // --- NEXT EVENT ESTIMATION ---
        vec3 sunDir = normalize(uLightPos);
        if (rough > 0.1) {
            vec3 srO = hp + mappedNormal * uEPS_intersect;
            bool hitGeometry = shadowIntersect(srO, sunDir, INFINITY);
            
            if (!hitGeometry) {
                float NdotL = max(dot(mappedNormal, sunDir), 0.0);
                vec3 brdf = albedo / 3.14159;
                accum += throughput * brdf * NdotL * (uLightColor * uLightRadius * 0.75);
            }
        }
        
        if (absorbed) break;
        
        throughput *= materialColor;
        rayOrigin = hp + mappedNormal * uEPS_intersect;
        rayDirection = newDir;
        
        if (bounce > 0) {
            float p = max(throughput.x, max(throughput.y, throughput.z));
            if (rand() > p) break; 
            throughput /= p;
        }
    }
    return accum;
}

void main() {
    vec2 pC = vUv * uResolution; 
    initRNG(pC, uFrameCounter);
    
    vec3 totalColor = vec3(0);
    
    for (int s = 0; s < 32; s++) {
        if (s >= uSamplesPerFrame) break;
        
        vec2 jitter = (vec2(rand(), rand()) - 0.5) / uResolution;
        vec2 jitteredUV = vUv + jitter;
        
        vec2 ndc = jitteredUV * 2.0 - 1.0; 
        ndc.x *= uResolution.x / uResolution.y;
        
        vec3 rd = normalize(vec3(ndc.x * uULen, ndc.y * uVLen, -1.0));
        rayOrigin = (uCameraMatrix * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
        rayDirection = normalize((uCameraMatrix * vec4(rd, 0.0)).xyz);
        
        vec3 color = pathTrace();
        color = min(color, vec3(50.0)); 
        totalColor += color;
    }
    
    vec3 avgColor = totalColor / float(uSamplesPerFrame);
    vec3 prev = texture(tPreviousTexture, vUv).rgb;
    fragColor = vec4(mix(prev, avgColor, 1.0 / max(uSampleCounter, 1.0)), 1.0);
}
