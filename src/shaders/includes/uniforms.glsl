// Shared uniforms and defines for the path tracing pipeline

precision highp float;
precision highp int;
precision highp sampler2D;

uniform sampler2D tPreviousTexture;
uniform sampler2D tBlueNoiseTexture;
uniform mat4 uCameraMatrix;
uniform vec2 uResolution;
uniform vec2 uRandomVec2;
uniform float uEPS_intersect;
uniform float uTime;
uniform float uSampleCounter;
uniform float uFrameCounter;
uniform float uULen;
uniform float uVLen;
uniform float uApertureSize;
uniform float uFocusDistance;
uniform float uPreviousSampleCount;
uniform bool uCameraIsMoving;
uniform bool uSceneIsDynamic;

#define PI               3.14159265358979323
#define TWO_PI           6.28318530717958648
#define ONE_OVER_PI      0.31830988618379067
#define PI_OVER_TWO      1.57079632679489662
#define INFINITY         1000000.0

#define LIGHT 0
#define DIFF  1
#define REFR  2
#define SPEC  3
#define COAT  4
#define EMIT  5

#define TRUE  1
#define FALSE 0

// Max scene objects
#define MAX_BOXES   32
#define MAX_SPHERES 4
#define MAX_QUADS   4
