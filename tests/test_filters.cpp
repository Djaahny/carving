#include <cmath>
#include <cstdio>
#include <cstdlib>

#include "../carving_filters.h"

int failures = 0;

void Check(bool condition, const char *message) {
  if (!condition) {
    std::fprintf(stderr, "FAIL: %s\n", message);
    ++failures;
  }
}

void TestCoefficientsFinite() {
  BiquadFilter filter = MakeLowPass(12.0f, 200.0f, 0.707f);
  Check(std::isfinite(filter.b0), "b0 finite");
  Check(std::isfinite(filter.b1), "b1 finite");
  Check(std::isfinite(filter.b2), "b2 finite");
  Check(std::isfinite(filter.a1), "a1 finite");
  Check(std::isfinite(filter.a2), "a2 finite");
}

void TestStepResponse() {
  BiquadFilter filter = MakeLowPass(12.0f, 200.0f, 0.707f);
  float output = 0.0f;
  for (int i = 0; i < 200; ++i) {
    output = filter.Update(1.0f);
  }
  Check(output > 0.9f, "step response settles above 0.9");
  Check(output < 1.1f, "step response settles below 1.1");
}

void TestZeroInput() {
  BiquadFilter filter = MakeLowPass(12.0f, 200.0f, 0.707f);
  float output = 0.0f;
  for (int i = 0; i < 50; ++i) {
    output = filter.Update(0.0f);
  }
  Check(std::fabs(output) < 1e-6f, "zero input stays near zero");
}

int main() {
  TestCoefficientsFinite();
  TestStepResponse();
  TestZeroInput();

  if (failures > 0) {
    std::fprintf(stderr, "%d test(s) failed.\n", failures);
    return 1;
  }

  std::printf("All tests passed.\n");
  return 0;
}
