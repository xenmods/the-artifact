// PBR Material evaluation using GGX Microfacet BRDF

#define PI 3.14159265358979323

// Normal mapping function
vec3 getNormalFromMap(vec3 hitNormal, vec3 hitPoint, vec3 mappedNormal) {
    // Tangent space basis vectors (simple approximation assuming UVs wrap around Y)
    vec3 up = abs(hitNormal.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(up, hitNormal));
    vec3 bitangent = cross(hitNormal, tangent);
    
    mat3 tbn = mat3(tangent, bitangent, hitNormal);
    return normalize(tbn * (mappedNormal * 2.0 - 1.0));
}

// GGX / Trowbridge-Reitz Normal Distribution Function
float D_GGX(float NdotH, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH2 = NdotH * NdotH;

    float nom   = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;

    return nom / max(denom, 0.0000001);
}

// Schlick-GGX Geometry Function
float GeometrySchlickGGX(float NdotV, float roughness) {
    float r = (roughness + 1.0);
    float k = (r * r) / 8.0;

    float nom   = NdotV;
    float denom = NdotV * (1.0 - k) + k;

    return nom / denom;
}

// Smith Geometry Function
float GeometrySmith(float NdotV, float NdotL, float roughness) {
    float ggx2 = GeometrySchlickGGX(NdotV, roughness);
    float ggx1 = GeometrySchlickGGX(NdotL, roughness);
    return ggx1 * ggx2;
}

// Fresnel Schlick
vec3 fresnelSchlick(float cosTheta, vec3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

// Fresnel Schlick with roughness (for energy conservation on indirect bounces)
vec3 fresnelSchlickRoughness(float cosTheta, vec3 F0, float roughness) {
    return F0 + (max(vec3(1.0 - roughness), F0) - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

// Evaluate material response for PBR surfaces
vec3 evaluateMaterial(
    vec3 rayDirection,
    vec3 hitNormal,
    vec3 albedo,
    float roughness,
    float metallic,
    out vec3 newDirection,
    out bool absorbed
) {
    absorbed = false;
    vec3 viewDir = -rayDirection;

    // F0 for dielectrics is usually 0.04. Metallic surfaces use their albedo as F0.
    vec3 F0 = vec3(0.04); 
    F0 = mix(F0, albedo, metallic);

    // Calculate probabilities of diffuse vs specular reflection based on Fresnel
    float NdotV = max(dot(hitNormal, viewDir), 0.0);
    vec3 F = fresnelSchlickRoughness(NdotV, F0, roughness);
    
    // Simplistic chance to reflect specular vs diffuse
    float specularChance = max(F.x, max(F.y, F.z));
    
    if (rand() < specularChance) {
        // Specular reflection (Importance sampling GGX)
        // For now, pure reflection mixed with roughness offset
        vec3 reflectDir = reflect(rayDirection, hitNormal);
        vec3 roughOffset = cosWeightedDir(hitNormal) * roughness;
        newDirection = normalize(mix(reflectDir, roughOffset, roughness * roughness));
        
        // Evaluate BRDF
        vec3 H = normalize(viewDir + newDirection);
        float NdotL = max(dot(hitNormal, newDirection), 0.0);
        float NdotH = max(dot(hitNormal, H), 0.0);
        
        float NDF = D_GGX(NdotH, roughness);   
        float G   = GeometrySmith(NdotV, NdotL, roughness);      
        
        vec3 nominator    = NDF * G * F;
        float denominator = 4.0 * NdotV * NdotL + 0.001;
        vec3 specular     = nominator / denominator;
        
        return specular;
    } else {
        // Diffuse reflection (Lambertian)
        newDirection = cosWeightedDir(hitNormal);
        
        // Energy conservation
        vec3 kD = vec3(1.0) - F;
        kD *= 1.0 - metallic;
        
        return (albedo / PI) * kD;
    }
}
