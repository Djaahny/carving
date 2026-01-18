#ifndef CARVING_FILTERS_H
#define CARVING_FILTERS_H

#include <cmath>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

struct BiquadFilter {
  float b0 = 1.0f;
  float b1 = 0.0f;
  float b2 = 0.0f;
  float a1 = 0.0f;
  float a2 = 0.0f;
  float z1 = 0.0f;
  float z2 = 0.0f;

  float Update(float sample) {
    const float result = (sample * b0) + z1;
    z1 = (sample * b1) + z2 - (a1 * result);
    z2 = (sample * b2) - (a2 * result);
    return result;
  }

  void Reset() {
    z1 = 0.0f;
    z2 = 0.0f;
  }
};

inline BiquadFilter MakeLowPass(float cutoffHz, float sampleRateHz, float q) {
  const float omega = 2.0f * static_cast<float>(M_PI) * (cutoffHz / sampleRateHz);
  const float sinOmega = sinf(omega);
  const float cosOmega = cosf(omega);
  const float alpha = sinOmega / (2.0f * q);

  const float b0 = (1.0f - cosOmega) * 0.5f;
  const float b1 = 1.0f - cosOmega;
  const float b2 = (1.0f - cosOmega) * 0.5f;
  const float a0 = 1.0f + alpha;
  const float a1 = -2.0f * cosOmega;
  const float a2 = 1.0f - alpha;

  BiquadFilter filter;
  filter.b0 = b0 / a0;
  filter.b1 = b1 / a0;
  filter.b2 = b2 / a0;
  filter.a1 = a1 / a0;
  filter.a2 = a2 / a0;
  return filter;
}

#endif
