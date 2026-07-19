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

// Textures - Wood
uniform sampler2D tWoodColor;
uniform sampler2D tWoodNormal;
uniform sampler2D tWoodRoughness;
// Textures - Metal
uniform sampler2D tMetalColor;
uniform sampler2D tMetalNormal;
uniform sampler2D tMetalRoughness;
// Textures - Concrete
uniform sampler2D tConcreteColor;
uniform sampler2D tConcreteNormal;
uniform sampler2D tConcreteRoughness;


// Artifact objects
uniform int uNumBoxes;
uniform vec3 uBoxMins[32];
uniform vec3 uBoxMaxs[32];
uniform int uBoxMats[32]; // 1 = wood, 2 = metal, 3 = concrete, 4 = pure gold

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

// ============ GLOBAL STATE ============
vec3 rayOrigin, rayDirection;
vec3 hitNormal, hitEmission, hitColor;
float hitRoughness, hitMetallic;
int hitMatType;
vec2 hitUV;

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
// PBR Material evaluation using GGX Microfacet BRDF
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

float D_GGX(float NdotH, float roughness) {
    float a = roughness*roughness; float a2 = a*a; float NdotH2 = NdotH*NdotH;
    float nom = a2; float denom = (NdotH2 * (a2 - 1.0) + 1.0); denom = PI * denom * denom;
    return nom / max(denom, 0.0000001);
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

vec3 evaluateMaterial(vec3 rd, vec3 hn, vec3 albedo, float rough, float metal, out vec3 newDir, out bool absorbed) {
    absorbed = false;
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
            // The mathematically exact weight (BRDF * cosTheta / PDF)
            // Weight = (F * G * VdotH) / (NdotV * NdotH)
            vec3 weight = (F * G * VdotH) / max(NdotV * NdotH, 0.001);
            return weight;
        } else {
            absorbed = true;
            return vec3(0);
        }
    } else {
        newDir = cosWeightedDir(hn);
        vec3 kD = (vec3(1.0) - F) * (1.0 - metal);
        return (albedo / PI) * kD;
    }
}


// ============ INTERSECTIONS ============

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

float sphereIntersect(float r, vec3 pos, vec3 ro, vec3 rd) {
    vec3 oc = ro - pos; float b = dot(oc, rd); float c = dot(oc, oc) - r*r; float disc = b*b - c;
    if (disc < 0.0) return INFINITY; disc = sqrt(disc);
    float t0 = -b - disc; float t1 = -b + disc;
    return t0 > 0.0 ? t0 : (t1 > 0.0 ? t1 : INFINITY);
}

float mannequinIntersect(vec3 ro, vec3 rd, out vec3 n) {
    float t = INFINITY;
    float d; vec3 tempN;
    
    vec3 camPos = uCameraMatrix[3].xyz;
    vec3 yAxis = vec3(0.0, 1.0, 0.0);
    
    // Animate walk offsets based on uWalkPhase
    float swing = sin(uWalkPhase) * 2.5; // Amount of forward/backward limb swing
    float swingUpper = swing * 0.5;
    float swingLower = swing * 1.0;
    float bodyBob = abs(sin(uWalkPhase)) * 0.3; // Slight up/down bounce
    
    camPos.y += bodyBob;
    
    // Head (box, 2.5 x 3 x 2)
    vec3 headCenter = camPos - vec3(0.0, 1.5, 0.0);
    d = boxIntersect(headCenter - vec3(1.25, 1.5, 1.0), headCenter + vec3(1.25, 1.5, 1.0), ro, rd, tempN);
    if (d < t) { t = d; n = tempN; }
    
    // Neck (thin cylinder)
    d = cylIntersect(camPos - vec3(0.0, 3.5, 0.0), yAxis, 0.6, 2.0, ro, rd, tempN);
    if (d < t) { t = d; n = tempN; }
    
    // Torso upper (broad box, 5 x 4 x 2.5)
    vec3 torsoUpper = camPos - vec3(0.0, 6.5, 0.0);
    d = boxIntersect(torsoUpper - vec3(2.5, 2.0, 1.25), torsoUpper + vec3(2.5, 2.0, 1.25), ro, rd, tempN);
    if (d < t) { t = d; n = tempN; }
    
    // Torso lower / waist (narrower box, 3.5 x 3 x 2)
    vec3 torsoLower = camPos - vec3(0.0, 10.0, 0.0);
    d = boxIntersect(torsoLower - vec3(1.75, 1.5, 1.0), torsoLower + vec3(1.75, 1.5, 1.0), ro, rd, tempN);
    if (d < t) { t = d; n = tempN; }
    
    // LEFT ARM (swings opposite to walkPhase, so -swing)
    d = cylIntersect(camPos - vec3(3.5, 6.5, swingUpper), yAxis, 0.9, 4.0, ro, rd, tempN);
    if (d < t) { t = d; n = tempN; }
    
    d = cylIntersect(camPos - vec3(3.5, 10.5, swingLower), yAxis, 0.7, 4.0, ro, rd, tempN);
    if (d < t) { t = d; n = tempN; }
    
    // RIGHT ARM (swings with walkPhase, so +swing)
    d = cylIntersect(camPos - vec3(-3.5, 6.5, -swingUpper), yAxis, 0.9, 4.0, ro, rd, tempN);
    if (d < t) { t = d; n = tempN; }
    
    d = cylIntersect(camPos - vec3(-3.5, 10.5, -swingLower), yAxis, 0.7, 4.0, ro, rd, tempN);
    if (d < t) { t = d; n = tempN; }
    
    // LEFT LEG (swings with walkPhase, opposite to left arm)
    d = cylIntersect(camPos - vec3(1.2, 13.0, -swingUpper), yAxis, 1.1, 5.0, ro, rd, tempN);
    if (d < t) { t = d; n = tempN; }
    
    d = cylIntersect(camPos - vec3(1.2, 17.5, -swingLower), yAxis, 0.8, 4.0, ro, rd, tempN);
    if (d < t) { t = d; n = tempN; }
    
    // RIGHT LEG (swings opposite to walkPhase, opposite to right arm)
    d = cylIntersect(camPos - vec3(-1.2, 13.0, swingUpper), yAxis, 1.1, 5.0, ro, rd, tempN);
    if (d < t) { t = d; n = tempN; }
    
    d = cylIntersect(camPos - vec3(-1.2, 17.5, swingLower), yAxis, 0.8, 4.0, ro, rd, tempN);
    if (d < t) { t = d; n = tempN; }
    
    return t;
}

// ============ SCENE ============

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
    } else {
        albedo = vec3(1); rough = 0.5; metal = 0.0; normal = hn;
    }
}

float sceneIntersect(bool isPrimaryRay) {
    float t = INFINITY; float d; vec3 n;
    
    // Light (Replaced with Directional NEE in main loop)

    // Room
    vec3 invD = 1.0 / (rayDirection + step(abs(rayDirection), vec3(1e-8)) * 1e-8);
    vec3 t0s = (uRoomMin - rayOrigin) * invD; vec3 t1s = (uRoomMax - rayOrigin) * invD; vec3 tmax = max(t0s, t1s);
    float tFar = min(min(tmax.x, tmax.y), tmax.z);
    if (tFar > 0.0 && tFar < t) {
        vec3 hp = rayOrigin + rayDirection * tFar;
        vec3 hn = -sign(rayDirection) * step(tmax.xyz, tmax.zxy) * step(tmax.xyz, tmax.yzx);
        
        // Window Cutout on the -Z Wall (Clean Cutout)
        bool isWindow = (hn.z > 0.5 && hp.x > -25.0 && hp.x < 25.0 && hp.y > 15.0 && hp.y < 45.0);
        
        if (!isWindow) {
            t = tFar; hitNormal = hn;
            hitMatType = MAT_CONCRETE; hitEmission = vec3(0); hitUV = hp.xz * 0.05;
            if (abs(hitNormal.y) < 0.5) hitUV = hp.xy * 0.05;
        }
    }

    // Boxes
    for (int i=0; i<32; i++) {
        if (i >= uNumBoxes) break;
        d = boxIntersect(uBoxMins[i], uBoxMaxs[i], rayOrigin, rayDirection, n);
        if (d < t) {
            t = d; hitNormal = n; hitMatType = uBoxMats[i]; hitEmission = vec3(0);
            vec3 hp = rayOrigin + rayDirection*t;
            hitUV = (abs(n.y) > 0.5) ? hp.xz * 0.2 : ((abs(n.x) > 0.5) ? hp.zy * 0.2 : hp.xy * 0.2);
        }
    }

    // Cylinders
    for (int i=0; i<32; i++) {
        if (i >= uNumCylinders) break;
        d = cylIntersect(uCylPos[i], uCylAxis[i], uCylRadii[i], uCylHeights[i], rayOrigin, rayDirection, n);
        if (d < t) {
            t = d; hitNormal = n; hitMatType = uCylMats[i]; hitEmission = vec3(0);
            vec3 hp = rayOrigin + rayDirection*t;
            float angle = atan(hp.z - uCylPos[i].z, hp.x - uCylPos[i].x);
            hitUV = vec2(angle / (2.0 * 3.14159265), hp.y * 0.2);
        }
    }
    
    // ====== Player Mannequin Body ======
    // Built from multiple primitives for a recognizable human shadow.
    // Only visible to bounce rays (isPrimaryRay hides the body from the camera).
    if (!isPrimaryRay) {
        d = mannequinIntersect(rayOrigin, rayDirection, n);
        if (d < t) {
            t = d; hitNormal = n; hitMatType = MAT_CONCRETE; hitEmission = vec3(0); hitUV = vec2(0);
        }
    }

    return t;
}

// shadowIntersect removed because NEE has a customized loop

vec3 pathTrace() {
    vec3 accum = vec3(0);
    vec3 throughput = vec3(1);
    
    for (int bounce=0; bounce<4; bounce++) { // Max 4 loop iterations, soft capped by uMaxBounces
        if (bounce >= uMaxBounces) break;
        
        float t = sceneIntersect(bounce == 0);
        if (t == INFINITY) { 
            // Dynamic Time-of-Day Sky
            vec3 sunDir = normalize(uLightPos);
            float skyIntensity = max(dot(rayDirection, sunDir), 0.0);
            skyIntensity = pow(skyIntensity, 32.0) * uLightRadius * 4.0; 
            // Mix horizon color with sun color
            vec3 skyColor = mix(uLightColor * 0.4, uLightColor, skyIntensity);
            accum += throughput * skyColor;
            break; 
        }
        
        // If we randomly hit the light
        if (hitMatType == MAT_LIGHT) { 
            accum += throughput * hitEmission; 
            break; 
        }
        if (hitMatType == MAT_GEM) {
            // Ethereal Cyan Gem emission
            accum += throughput * vec3(0.2, 2.0, 1.5) * 15.0; 
            break;
        }
        
        vec3 hp = rayOrigin + rayDirection*t;
        vec3 hn = hitNormal;
        
        vec3 albedo, mappedNormal; float rough, metal;
        getPBRProps(hitMatType, hitUV, hp, hn, albedo, mappedNormal, rough, metal);
        
        // Indirect bounce
        bool absorbed; vec3 newDir;
        vec3 materialColor = evaluateMaterial(rayDirection, mappedNormal, albedo, rough, metal, newDir, absorbed);
        
        // --- NEXT EVENT ESTIMATION (DIRECT SUNLIGHT) ---
        vec3 sunDir = normalize(uLightPos);
        if (rough > 0.1) {
            float st = INFINITY; vec3 sn;
            vec3 srO = hp + mappedNormal * uEPS_intersect;
            vec3 srD = sunDir;
            
            // Room
            vec3 invD = 1.0 / (srD + step(abs(srD), vec3(1e-8)) * 1e-8);
            vec3 t0s = (uRoomMin - srO) * invD; vec3 t1s = (uRoomMax - srO) * invD; vec3 tmax = max(t0s, t1s);
            float tFar = min(min(tmax.x, tmax.y), tmax.z);
            if (tFar > 0.0) {
                vec3 shp = srO + srD * tFar;
                vec3 shn = -sign(srD) * step(tmax.xyz, tmax.zxy) * step(tmax.xyz, tmax.yzx);
                bool isWindow = (shn.z > 0.5 && shp.x > -25.0 && shp.x < 25.0 && shp.y > 15.0 && shp.y < 45.0);
                if (!isWindow) st = tFar;
            }
            // Boxes
            for (int j=0; j<32; j++) {
                if (j >= uNumBoxes) break;
                float bd = boxIntersect(uBoxMins[j], uBoxMaxs[j], srO, srD, sn);
                if (bd < st) st = bd;
            }
            // Cylinders
            for (int j=0; j<32; j++) {
                if (j >= uNumCylinders) break;
                float cd = cylIntersect(uCylPos[j], uCylAxis[j], uCylRadii[j], uCylHeights[j], srO, srD, sn);
                if (cd < st) st = cd;
            }
            
            // Player Mannequin Shadow
            float pcd = mannequinIntersect(srO, srD, sn);
            if (pcd < st) st = pcd;
            
            if (st == INFINITY) {
                float NdotL = max(dot(mappedNormal, sunDir), 0.0);
                vec3 brdf = albedo / 3.14159;
                accum += throughput * brdf * NdotL * (uLightColor * uLightRadius * 0.75);
            }
        }
        
        if (absorbed) break;
        
        throughput *= materialColor;
        rayOrigin = hp + mappedNormal * uEPS_intersect;
        rayDirection = newDir;
        
        // Russian Roulette
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
        
        // Subpixel jitter for perfect anti-aliasing
        vec2 jitter = (vec2(rand(), rand()) - 0.5) / uResolution;
        vec2 jitteredUV = vUv + jitter;
        
        vec2 ndc = jitteredUV * 2.0 - 1.0; 
        ndc.x *= uResolution.x / uResolution.y;
        
        vec3 rd = normalize(vec3(ndc.x * uULen, ndc.y * uVLen, -1.0));
        rayOrigin = (uCameraMatrix * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
        rayDirection = normalize((uCameraMatrix * vec4(rd, 0.0)).xyz);
        
        vec3 color = pathTrace();
        color = min(color, vec3(50.0)); // Prevent massive fireflies without crushing bright lights
        totalColor += color;
    }
    
    vec3 avgColor = totalColor / float(uSamplesPerFrame);
    
    vec3 prev = texture(tPreviousTexture, vUv).rgb;
    fragColor = vec4(mix(prev, avgColor, 1.0 / max(uSampleCounter, 1.0)), 1.0);
}
