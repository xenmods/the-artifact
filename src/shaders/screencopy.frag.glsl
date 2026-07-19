// Screen copy fragment shader - copies current frame for progressive accumulation
precision highp float;
precision highp sampler2D;

uniform sampler2D tTexture;

in vec2 vUv;
out vec4 fragColor;

void main()
{
    fragColor = texture(tTexture, vUv);
}
