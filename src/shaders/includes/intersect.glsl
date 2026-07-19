// Ray-geometry intersection functions

struct Sphere {
    float radius;
    vec3 position;
    vec3 emission;
    vec3 color;
    int type;
};

struct Box {
    vec3 minCorner;
    vec3 maxCorner;
    vec3 emission;
    vec3 color;
    int type;
};

struct Quad {
    vec3 normal;
    vec3 v0;
    vec3 v1;
    vec3 v2;
    vec3 v3;
    vec3 emission;
    vec3 color;
    int type;
};

// Sphere intersection
float SphereIntersect(float radius, vec3 position, vec3 ro, vec3 rd)
{
    vec3 oc = ro - position;
    float b = dot(oc, rd);
    float c = dot(oc, oc) - radius * radius;
    float disc = b * b - c;
    if (disc < 0.0) return INFINITY;
    disc = sqrt(disc);
    float t0 = -b - disc;
    float t1 = -b + disc;
    return t0 > 0.0 ? t0 : (t1 > 0.0 ? t1 : INFINITY);
}

// Axis-aligned box intersection (exterior)
float BoxIntersect(vec3 minCorner, vec3 maxCorner, vec3 ro, vec3 rd, out vec3 normal, out int isExiting)
{
    vec3 invDir = 1.0 / rd;
    vec3 t0s = (minCorner - ro) * invDir;
    vec3 t1s = (maxCorner - ro) * invDir;
    vec3 tmin = min(t0s, t1s);
    vec3 tmax = max(t0s, t1s);
    float tNear = max(max(tmin.x, tmin.y), tmin.z);
    float tFar  = min(min(tmax.x, tmax.y), tmax.z);

    if (tNear > tFar || tFar < 0.0) return INFINITY;

    if (tNear > 0.0)
    {
        // Hit from outside
        isExiting = FALSE;
        normal = -sign(rd) * step(tmin.zxy, tmin.xyz) * step(tmin.yzx, tmin.xyz);
        return tNear;
    }
    else
    {
        // Hit from inside
        isExiting = TRUE;
        normal = -sign(rd) * step(tmax.xyz, tmax.zxy) * step(tmax.xyz, tmax.yzx);
        return tFar;
    }
}

// Axis-aligned box interior intersection (ray starts inside)
float BoxInteriorIntersect(vec3 minCorner, vec3 maxCorner, vec3 ro, vec3 rd, out vec3 normal)
{
    vec3 invDir = 1.0 / rd;
    vec3 t0s = (minCorner - ro) * invDir;
    vec3 t1s = (maxCorner - ro) * invDir;
    vec3 tmax = max(t0s, t1s);
    float tFar = min(min(tmax.x, tmax.y), tmax.z);

    if (tFar < 0.0) return INFINITY;

    normal = -sign(rd) * step(tmax.xyz, tmax.zxy) * step(tmax.xyz, tmax.yzx);
    return tFar;
}

// Quad intersection (two triangles)
float QuadIntersect(vec3 v0, vec3 v1, vec3 v2, vec3 v3, vec3 ro, vec3 rd, bool doubleSided)
{
    // Triangle 1: v0, v1, v2
    vec3 e1 = v1 - v0;
    vec3 e2 = v2 - v0;
    vec3 pvec = cross(rd, e2);
    float det = dot(e1, pvec);

    if (!doubleSided && det < 0.001) return INFINITY;
    if (abs(det) < 0.001) return INFINITY;

    float invDet = 1.0 / det;
    vec3 tvec = ro - v0;
    float u = dot(tvec, pvec) * invDet;
    if (u < 0.0 || u > 1.0) goto tri2;

    vec3 qvec = cross(tvec, e1);
    float v = dot(rd, qvec) * invDet;
    if (v < 0.0 || u + v > 1.0) goto tri2;

    float t1 = dot(e2, qvec) * invDet;
    if (t1 > 0.0) return t1;

    tri2:
    // Triangle 2: v0, v2, v3
    e1 = v2 - v0;
    e2 = v3 - v0;
    pvec = cross(rd, e2);
    det = dot(e1, pvec);

    if (!doubleSided && det < 0.001) return INFINITY;
    if (abs(det) < 0.001) return INFINITY;

    invDet = 1.0 / det;
    tvec = ro - v0;
    u = dot(tvec, pvec) * invDet;
    if (u < 0.0 || u > 1.0) return INFINITY;

    qvec = cross(tvec, e1);
    v = dot(rd, qvec) * invDet;
    if (v < 0.0 || u + v > 1.0) return INFINITY;

    float t2 = dot(e2, qvec) * invDet;
    return t2 > 0.0 ? t2 : INFINITY;
}
