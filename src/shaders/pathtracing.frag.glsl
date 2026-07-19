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

float sceneIntersect(vec3 ro, vec3 rd, bool isPrimaryRay, out vec3 outNormal, out int outMat, out vec3 outEmission, out vec2 outUV) {
    float t = INFINITY; float d; vec3 n;
    outEmission = vec3(0);
    
    vec3 invD = 1.0 / (rd + step(abs(rd), vec3(1e-8)) * 1e-8);
    vec3 t0s = (uRoomMin - ro) * invD; vec3 t1s = (uRoomMax - ro) * invD; vec3 tmax = max(t0s, t1s);
    float tFar = min(min(tmax.x, tmax.y), tmax.z);
    
    if (tFar > 0.0 && tFar < t) {
        vec3 hp = ro + rd * tFar;
        vec3 hn = -sign(rd) * step(tmax.xyz, tmax.zxy) * step(tmax.xyz, tmax.yzx);
        
        // Window Cutout on the -Z Wall (Clean Cutout)
        bool isWindow = (hn.z > 0.5 && hp.x > -25.0 && hp.x < 25.0 && hp.y > 15.0 && hp.y < 45.0);
        
        if (!isWindow) {
            t = tFar; outNormal = hn;
            if (hn.y > 0.5) {
                outMat = MAT_MARBLE;
                outUV = hp.xz * 0.05;
            } else {
                outMat = MAT_CONCRETE;
                outUV = (abs(hn.y) < 0.5) ? hp.xy * 0.05 : hp.xz * 0.05;
            }
        }
    }

    // Boxes
    for (int i=0; i<32; i++) {
        if (i >= uNumBoxes) break;
        d = boxIntersect(uBoxMins[i], uBoxMaxs[i], ro, rd, n);
        if (d < t) {
            t = d; outNormal = n; outMat = uBoxMats[i];
            vec3 hp = ro + rd*t;
            outUV = (abs(n.y) > 0.5) ? hp.xz * 0.2 : ((abs(n.x) > 0.5) ? hp.zy * 0.2 : hp.xy * 0.2);
        }
    }

    // Cylinders
    for (int i=0; i<32; i++) {
        if (i >= uNumCylinders) break;
        d = cylIntersect(uCylPos[i], uCylAxis[i], uCylRadii[i], uCylHeights[i], ro, rd, n);
        if (d < t) {
            t = d; outNormal = n; outMat = uCylMats[i];
            vec3 hp = ro + rd*t;
            float angle = atan(hp.z - uCylPos[i].z, hp.x - uCylPos[i].x);
            outUV = vec2(angle / (2.0 * 3.14159265), hp.y * 0.2);
        }
    }
    
    if (!isPrimaryRay) {
        d = mannequinIntersect(ro, rd, n);
        if (d < t) {
            t = d; outNormal = n; outMat = MAT_CONCRETE; outUV = vec2(0);
        }
    }

    return t;
}

bool shadowIntersect(vec3 ro, vec3 rd, float maxDist) {
    float t = INFINITY; vec3 sn;
    
    vec3 invD = 1.0 / (rd + step(abs(rd), vec3(1e-8)) * 1e-8);
    vec3 t0s = (uRoomMin - ro) * invD; vec3 t1s = (uRoomMax - ro) * invD; vec3 tmax = max(t0s, t1s);
    float tFar = min(min(tmax.x, tmax.y), tmax.z);
    
    if (tFar > 0.0) {
        vec3 shp = ro + rd * tFar;
        vec3 shn = -sign(rd) * step(tmax.xyz, tmax.zxy) * step(tmax.xyz, tmax.yzx);
        bool isWindow = (shn.z > 0.5 && shp.x > -25.0 && shp.x < 25.0 && shp.y > 15.0 && shp.y < 45.0);
        if (!isWindow) t = tFar;
    }
    
    if (t < maxDist) return true;
    
    for (int j=0; j<32; j++) {
        if (j >= uNumBoxes) break;
        if (boxIntersect(uBoxMins[j], uBoxMaxs[j], ro, rd, sn) < maxDist) return true;
    }
    for (int j=0; j<32; j++) {
        if (j >= uNumCylinders) break;
        if (cylIntersect(uCylPos[j], uCylAxis[j], uCylRadii[j], uCylHeights[j], ro, rd, sn) < maxDist) return true;
    }
    
    if (mannequinIntersect(ro, rd, sn) < maxDist) return true;
    
    return false;
}
