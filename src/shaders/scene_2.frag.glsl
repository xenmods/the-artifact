#include "./pathtracing_core.glsl"

vec3 getSkyColor(vec3 rayDir, bool isPrimaryRay) {
    vec3 skyColor = vec3(0);
    if (uUseHDRI) {
        vec2 uv = vec2(atan(rayDir.z, rayDir.x) / (2.0 * PI) + 0.5, asin(rayDir.y) / PI + 0.5);
        skyColor = texture(tHDRI, uv).rgb;
    } else {
        skyColor = uLightColor * 0.4;
    }
    
    vec3 sunDir = normalize(uLightPos);
    if (isPrimaryRay) {
        float skyIntensity = max(dot(rayDir, sunDir), 0.0);
        skyIntensity = pow(skyIntensity, 64.0) * uLightRadius * 4.0; 
        skyColor += uLightColor * skyIntensity;
    }
    return skyColor;
}

// Helper for CSG
void checkHit(float d, vec3 n, int mat, vec3 hp, float scale, inout float t, inout vec3 outN, inout int outMat, inout vec2 outUV) {
    if (d < t) {
        t = d; outN = n; outMat = mat;
        outUV = (abs(n.y) > 0.5) ? hp.xz * scale : ((abs(n.x) > 0.5) ? hp.zy * scale : hp.xy * scale);
    }
}

float sceneIntersect(vec3 ro, vec3 rd, bool isPrimaryRay, out vec3 outNormal, out int outMat, out vec3 outEmission, out vec2 outUV) {
    float t = INFINITY; float d; vec3 n;
    outEmission = vec3(0);
    
    // --- ROOM BOUNDS ---
    d = boxIntersect(vec3(-40.0, 0.0, -40.0), vec3(40.0, 20.0, 40.0), ro, rd, n);
    if (d < t) {
        vec3 hp = ro + rd * d;
        // Left Wall: Massive Window
        if (n.x > 0.5) {
            float pillarSpacing = mod(hp.z + 10.0, 20.0);
            if (pillarSpacing < 2.0 || hp.y > 18.0 || hp.y < 0.5) {
                t = d; outNormal = n; outMat = MAT_CONCRETE; outUV = hp.zy * 0.05;
            }
        } 
        // Back Wall: Recessed Bookshelf & TV
        else if (n.z > 0.5) {
            // Bookshelf cutout on left side (-25 to -10), y=2 to 15
            if (hp.x > -30.0 && hp.x < -10.0 && hp.y > 2.0 && hp.y < 15.0) {
                // Open hole (the actual shelf is built separately inside the wall)
            } else {
                t = d; outNormal = n; outMat = MAT_CONCRETE; outUV = hp.xy * 0.05;
            }
        }
        else {
            t = d; outNormal = n;
            if (n.y > 0.5) { // Floor
                outMat = MAT_WOOD; outUV = hp.xz * 0.1;
            } else if (n.y < -0.5) { // Ceiling
                outMat = MAT_CONCRETE; outUV = hp.xz * 0.05;
            } else { // Right & Front walls
                outMat = MAT_CONCRETE; outUV = (abs(n.x) > 0.5) ? hp.zy * 0.05 : hp.xy * 0.05;
            }
        }
    }
    
    // --- BACK WALL SHELF ---
    // Recessed backing
    d = boxIntersect(vec3(-30.0, 2.0, -42.0), vec3(-10.0, 15.0, -40.0), ro, rd, n);
    checkHit(d, n, MAT_CONCRETE, ro + rd*d, 0.05, t, outNormal, outMat, outUV);
    // Shelves
    for (float sy = 4.0; sy <= 14.0; sy += 3.0) {
        d = boxIntersect(vec3(-30.0, sy, -42.0), vec3(-10.0, sy+0.2, -40.0), ro, rd, n);
        checkHit(d, n, MAT_WOOD, ro + rd*d, 0.1, t, outNormal, outMat, outUV);
    }
    
    // Objects on shelves (Spheres & Boxes)
    d = sphereIntersect(0.8, vec3(-25.0, 4.8, -41.0), ro, rd); if (d < t) { t = d; outNormal = normalize((ro+rd*d)-vec3(-25.0,4.8,-41.0)); outMat = MAT_METAL; }
    d = sphereIntersect(1.0, vec3(-15.0, 7.8, -41.0), ro, rd); if (d < t) { t = d; outNormal = normalize((ro+rd*d)-vec3(-15.0,7.8,-41.0)); outMat = MAT_GLASS; }
    d = boxIntersect(vec3(-28.0, 7.2, -41.5), vec3(-27.0, 9.2, -40.5), ro, rd, n); checkHit(d, n, MAT_WOOD, ro+rd*d, 0.2, t, outNormal, outMat, outUV);
    
    // --- TV ---
    d = boxIntersect(vec3(0.0, 6.0, -39.5), vec3(20.0, 14.0, -39.0), ro, rd, n);
    if (d < t) {
        t = d; outNormal = n; outMat = MAT_METAL;
        vec3 hp = ro+rd*d;
        // Screen is perfectly black plastic
        if (n.z > 0.5 && hp.x > 0.5 && hp.x < 19.5 && hp.y > 6.5 && hp.y < 13.5) {
            outEmission = vec3(0.01); // Tiny glow
        }
    }
    // TV Stand
    d = boxIntersect(vec3(-5.0, 0.0, -38.0), vec3(25.0, 3.0, -34.0), ro, rd, n);
    checkHit(d, n, MAT_CONCRETE, ro+rd*d, 0.1, t, outNormal, outMat, outUV);

    // --- L-SHAPED COUCH ---
    // Main seating
    d = boxIntersect(vec3(-15.0, 0.0, -10.0), vec3(15.0, 2.5, 0.0), ro, rd, n); checkHit(d, n, MAT_CONCRETE, ro+rd*d, 0.1, t, outNormal, outMat, outUV);
    // Backrest
    d = boxIntersect(vec3(-15.0, 2.5, -2.0), vec3(15.0, 5.0, 0.0), ro, rd, n); checkHit(d, n, MAT_CONCRETE, ro+rd*d, 0.1, t, outNormal, outMat, outUV);
    // L-Section
    d = boxIntersect(vec3(5.0, 0.0, -20.0), vec3(15.0, 2.5, -10.0), ro, rd, n); checkHit(d, n, MAT_CONCRETE, ro+rd*d, 0.1, t, outNormal, outMat, outUV);

    // --- GLASS COFFEE TABLE ---
    // Glass Top
    d = boxIntersect(vec3(-5.0, 2.5, -18.0), vec3(5.0, 2.6, -10.0), ro, rd, n); checkHit(d, n, MAT_GLASS, ro+rd*d, 0.1, t, outNormal, outMat, outUV);
    // Metal Legs
    d = cylIntersect(vec3(-3.0, 0.0, -12.0), vec3(0.0,1.0,0.0), 0.5, 2.5, ro, rd, n); checkHit(d, n, MAT_METAL, ro+rd*d, 0.2, t, outNormal, outMat, outUV);
    d = cylIntersect(vec3(3.0, 0.0, -16.0), vec3(0.0,1.0,0.0), 0.5, 2.5, ro, rd, n); checkHit(d, n, MAT_METAL, ro+rd*d, 0.2, t, outNormal, outMat, outUV);

    // --- CHANDELIER ---
    vec3 cp = vec3(0.0, 18.0, -10.0);
    // Stem
    d = cylIntersect(cp, vec3(0.0,1.0,0.0), 0.1, 4.0, ro, rd, n); checkHit(d, n, MAT_METAL, ro+rd*d, 0.5, t, outNormal, outMat, outUV);
    // Glowing Light Cubes
    for (float dx = -4.0; dx <= 4.0; dx += 4.0) {
        if (dx == 0.0) continue;
        d = boxIntersect(cp + vec3(dx-0.5, -2.5, -0.5), cp + vec3(dx+0.5, -1.5, 0.5), ro, rd, n);
        if (d < t) { t = d; outNormal = n; outMat = MAT_LIGHT; outEmission = vec3(1.0, 0.9, 0.8) * 15.0; }
        // Horizontal arms
        d = boxIntersect(cp + vec3(min(0.0, dx), -2.0, -0.1), cp + vec3(max(0.0, dx), -1.9, 0.1), ro, rd, n);
        checkHit(d, n, MAT_METAL, ro+rd*d, 0.5, t, outNormal, outMat, outUV);
    }

    return t;
}

bool shadowIntersect(vec3 ro, vec3 rd, float maxDist) {
    float t = INFINITY; vec3 sn;
    
    // Room bounds
    float d = boxIntersect(vec3(-40.0, 0.0, -40.0), vec3(40.0, 20.0, 40.0), ro, rd, sn);
    if (d < t) {
        vec3 hp = ro + rd * d;
        if (sn.x > 0.5) {
            float pillarSpacing = mod(hp.z + 10.0, 20.0);
            if (pillarSpacing < 2.0 || hp.y > 18.0 || hp.y < 0.5) t = d;
        } else if (sn.z > 0.5) {
            if (!(hp.x > -30.0 && hp.x < -10.0 && hp.y > 2.0 && hp.y < 15.0)) t = d;
        } else {
            t = d;
        }
    }
    
    if (t < maxDist) return true;
    
    // Quick checks for major occluders
    if (boxIntersect(vec3(0.0, 6.0, -39.5), vec3(20.0, 14.0, -39.0), ro, rd, sn) < maxDist) return true;
    if (boxIntersect(vec3(-15.0, 0.0, -10.0), vec3(15.0, 2.5, 0.0), ro, rd, sn) < maxDist) return true;
    if (boxIntersect(vec3(-15.0, 2.5, -2.0), vec3(15.0, 5.0, 0.0), ro, rd, sn) < maxDist) return true;
    if (boxIntersect(vec3(5.0, 0.0, -20.0), vec3(15.0, 2.5, -10.0), ro, rd, sn) < maxDist) return true;
    
    return false;
}
