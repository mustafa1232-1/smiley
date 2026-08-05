#version 460 core
#include <flutter/runtime_effect.glsl>

// Anime-style procedural sky: smooth gradient, soft volumetric clouds with
// top-lighting, a warm sun/horizon bloom, and a haze band at the horizon.
// The tree, grass, avatars and weather FX are drawn on top by the CustomPainter.

out vec4 fragColor;

uniform vec2 uResolution;
uniform float uTime;
uniform vec2 uSun;      // sun/moon centre in pixels
uniform float uNight;   // 0 = day, 1 = night
uniform float uOvercast;// 0..1 how grey/heavy the sky is
uniform float uCloud;   // 0..1 cloud coverage
uniform vec3 uSkyTop;
uniform vec3 uSkyBot;
uniform vec3 uSunColor;
uniform float uHorizon; // horizon y in pixels

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 345.45));
  p += dot(p, p + 34.345);
  return fract(p.x * p.y);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 5; i++) {
    v += a * noise(p);
    p = p * 2.0;
    a *= 0.5;
  }
  return v;
}

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  vec2 uv = fragCoord / uResolution;
  float horizon = uHorizon / uResolution.y;

  // Base sky gradient (top -> horizon).
  float g = clamp(uv.y / max(horizon, 0.001), 0.0, 1.0);
  vec3 col = mix(uSkyTop, uSkyBot, g);

  // Sun / moon glow bloom.
  float dpx = distance(fragCoord, uSun) / uResolution.y;
  float glow = exp(-dpx * 4.5);
  col += uSunColor * glow * (1.0 - uNight) * 1.1;

  // Procedural clouds above the horizon, drifting with time.
  vec2 cp = vec2(uv.x * 2.4, uv.y * 1.4);
  cp.x += uTime * 0.015;
  float warp = fbm(cp * 1.3);
  float density = fbm(cp * 3.0 + warp);
  float coverage = mix(0.72, 0.30, clamp(uCloud, 0.0, 1.0));
  float clouds = smoothstep(coverage, coverage + 0.22, density);
  // Soft top-lighting: sample a little higher for the lit edge.
  float above = fbm((cp + vec2(0.0, -0.06)) * 3.0 + warp);
  float lit = smoothstep(coverage, coverage + 0.40, above);
  vec3 cloudCol = mix(vec3(0.62, 0.66, 0.72), vec3(1.0), lit);
  cloudCol = mix(cloudCol, vec3(0.50, 0.53, 0.60), uOvercast * 0.6);
  cloudCol = mix(cloudCol, cloudCol * 0.45, uNight);
  cloudCol += uSunColor * glow * 0.4 * (1.0 - uNight);
  float aboveHorizon = smoothstep(horizon + 0.05, horizon - 0.25, uv.y);
  col = mix(col, cloudCol, clouds * aboveHorizon * mix(0.85, 0.95, uOvercast));

  // Warm haze band right at the horizon.
  float haze = smoothstep(horizon - 0.12, horizon, uv.y) *
               (1.0 - smoothstep(horizon, horizon + 0.10, uv.y));
  col = mix(col, mix(uSunColor, vec3(0.85), 0.35), haze * 0.30 * (1.0 - uNight * 0.6));

  fragColor = vec4(col, 1.0);
}
