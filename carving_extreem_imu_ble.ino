/*
 * Carving Extreem IMU BLE streamer (ESP32 + MPU9250)
 *
 * Streams filtered accel/gyro data over BLE notifications.
 * Debug serial output can be enabled with DEBUG_SERIAL.
 *
 * Phone connection quick start:
 * 1) Flash the sketch and power the ESP32.
 * 2) On iPhone, open a BLE scanner app (e.g. LightBlue or nRF Connect).
 * 3) Scan for the device name in DEVICE_NAME (default: "Carving-Extreem").
 * 4) Connect and subscribe to notifications on DATA_CHAR_UUID.
 * 5) Notifications are CSV: ax,ay,az,gx,gy,gz at BLE_OUTPUT_RATE_HZ.
 */

#include <Arduino.h>
#include <Wire.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#include "mpu9250.h"
#include "carving_filters.h"

/* ===================== User Tunables ===================== */
// I2C pins (ESP32 default: SDA=21, SCL=22)
constexpr int SDA_PIN = 21;
constexpr int SCL_PIN = 22;

// IMU sample rate divider (see MPU9250 datasheet). 0 => 1000 Hz.
constexpr uint8_t IMU_SRD = 4; // 1000 / (1 + SRD) => 200 Hz

// Target BLE output rate (Hz) for accel/gyro data
constexpr float BLE_OUTPUT_RATE_HZ = 100.0f;

// Biquad low-pass filter tuning
constexpr float ACCEL_CUTOFF_HZ = 12.0f;
constexpr float GYRO_CUTOFF_HZ = 18.0f;
constexpr float FILTER_Q = 0.707f; // Butterworth

// IMU dynamic ranges (keep headroom for skiing impacts)
constexpr auto ACCEL_RANGE = bfs::Mpu9250::ACCEL_RANGE_16G;
constexpr auto GYRO_RANGE = bfs::Mpu9250::GYRO_RANGE_2000DPS;

// BLE settings
constexpr char DEVICE_NAME[] = "Carving-Extreem";
constexpr char SERVICE_UUID[] = "7a3f0001-3c12-4b50-8d32-9f8c8a3d8f31";
constexpr char DATA_CHAR_UUID[] = "7a3f0002-3c12-4b50-8d32-9f8c8a3d8f31";

// Debug serial output
constexpr bool DEBUG_SERIAL = true;
constexpr uint32_t DEBUG_PRINT_INTERVAL_MS = 250;
constexpr uint32_t SERIAL_BAUD = 115200;
/* ========================================================= */

struct ImuFilteredData {
  float ax = 0.0f;
  float ay = 0.0f;
  float az = 0.0f;
  float gx = 0.0f;
  float gy = 0.0f;
  float gz = 0.0f;
};

struct Vec3 {
  float x = 0.0f;
  float y = 0.0f;
  float z = 0.0f;
};

struct WelfordStats {
  Vec3 mean{};
  Vec3 m2{};
  uint32_t count = 0;

  void Reset() {
    mean = {};
    m2 = {};
    count = 0;
  }

  void Update(const Vec3 &sample) {
    ++count;
    const float dx = sample.x - mean.x;
    const float dy = sample.y - mean.y;
    const float dz = sample.z - mean.z;
    mean.x += dx / static_cast<float>(count);
    mean.y += dy / static_cast<float>(count);
    mean.z += dz / static_cast<float>(count);
    m2.x += dx * (sample.x - mean.x);
    m2.y += dy * (sample.y - mean.y);
    m2.z += dz * (sample.z - mean.z);
  }

  Vec3 Variance() const {
    if (count < 2) {
      return {};
    }
    const float denom = static_cast<float>(count - 1);
    return {m2.x / denom, m2.y / denom, m2.z / denom};
  }
};

struct CalibrationResult {
  bool ready = false;
  float R_sb[3][3] = {
    {1.0f, 0.0f, 0.0f},
    {0.0f, 1.0f, 0.0f},
    {0.0f, 0.0f, 1.0f}
  };
  Vec3 gyro_bias{};
  float accel_scale = 1.0f;
};

bfs::Mpu9250 imu;

BiquadFilter accelFilters[3];
BiquadFilter gyroFilters[3];

BLECharacteristic *dataCharacteristic = nullptr;
uint32_t lastBleNotifyMs = 0;
uint32_t lastDebugPrintMs = 0;

bool deviceConnected = false;

enum class CalibrationPhase {
  kStill,
  kForward,
  kReady
};

struct CalibrationState {
  CalibrationPhase phase = CalibrationPhase::kStill;
  uint32_t phase_start_ms = 0;
  WelfordStats accel_stats{};
  WelfordStats gyro_stats{};
  Vec3 forward_sum{};
  uint32_t forward_samples = 0;
  Vec3 z_hat{};
  CalibrationResult result{};
};

CalibrationState calibration;

constexpr uint32_t STILL_CAL_DURATION_MS = 2000;
constexpr uint32_t FORWARD_CAL_DURATION_MS = 2500;
constexpr float STILL_ACCEL_STD_MAX = 0.15f;
constexpr float STILL_GYRO_STD_MAX = 0.05f;
constexpr float MIN_FORWARD_NORM = 0.05f;
constexpr float MIN_FORWARD_ORTHO = 0.3f;
constexpr float ACCEL_Z_TOL = 0.15f;
constexpr float ACCEL_XY_TOL = 0.12f;
constexpr float GYRO_ZERO_TOL = 0.05f;

class CarvingServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *server) override {
    deviceConnected = true;
  }

  void onDisconnect(BLEServer *server) override {
    deviceConnected = false;
    server->getAdvertising()->start();
  }
};

float ImuSampleRateHz() {
  return 1000.0f / (1.0f + static_cast<float>(IMU_SRD));
}

float VecDot(const Vec3 &a, const Vec3 &b) {
  return (a.x * b.x) + (a.y * b.y) + (a.z * b.z);
}

Vec3 VecCross(const Vec3 &a, const Vec3 &b) {
  return {
    (a.y * b.z) - (a.z * b.y),
    (a.z * b.x) - (a.x * b.z),
    (a.x * b.y) - (a.y * b.x)
  };
}

float VecNorm(const Vec3 &v) {
  return sqrtf(VecDot(v, v));
}

Vec3 VecScale(const Vec3 &v, float scale) {
  return {v.x * scale, v.y * scale, v.z * scale};
}

Vec3 VecAdd(const Vec3 &a, const Vec3 &b) {
  return {a.x + b.x, a.y + b.y, a.z + b.z};
}

Vec3 VecSub(const Vec3 &a, const Vec3 &b) {
  return {a.x - b.x, a.y - b.y, a.z - b.z};
}

Vec3 VecNormalize(const Vec3 &v) {
  const float norm = VecNorm(v);
  if (norm <= 0.0f) {
    return {};
  }
  return VecScale(v, 1.0f / norm);
}

Vec3 MatVec(const float m[3][3], const Vec3 &v) {
  return {
    (m[0][0] * v.x) + (m[0][1] * v.y) + (m[0][2] * v.z),
    (m[1][0] * v.x) + (m[1][1] * v.y) + (m[1][2] * v.z),
    (m[2][0] * v.x) + (m[2][1] * v.y) + (m[2][2] * v.z)
  };
}

void SetupFilters() {
  const float sampleRate = ImuSampleRateHz();
  for (int i = 0; i < 3; ++i) {
    accelFilters[i] = MakeLowPass(ACCEL_CUTOFF_HZ, sampleRate, FILTER_Q);
    gyroFilters[i] = MakeLowPass(GYRO_CUTOFF_HZ, sampleRate, FILTER_Q);
  }
}

void SetupImu() {
  Wire.begin(SDA_PIN, SCL_PIN);
  Wire.setClock(400000);
  imu.Config(&Wire, bfs::Mpu9250::I2C_ADDR_PRIM);

  if (!imu.Begin()) {
    if (DEBUG_SERIAL) {
      Serial.println("Error initializing communication with IMU");
    }
    while (true) {
      delay(1000);
    }
  }

  if (!imu.ConfigAccelRange(ACCEL_RANGE)) {
    if (DEBUG_SERIAL) {
      Serial.println("Error configuring accel range");
    }
    while (true) {
      delay(1000);
    }
  }

  if (!imu.ConfigGyroRange(GYRO_RANGE)) {
    if (DEBUG_SERIAL) {
      Serial.println("Error configuring gyro range");
    }
    while (true) {
      delay(1000);
    }
  }

  if (!imu.ConfigSrd(IMU_SRD)) {
    if (DEBUG_SERIAL) {
      Serial.println("Error configuring SRD");
    }
    while (true) {
      delay(1000);
    }
  }
}

void SetupBle() {
  BLEDevice::init(DEVICE_NAME);
  BLEServer *server = BLEDevice::createServer();
  server->setCallbacks(new CarvingServerCallbacks());

  BLEService *service = server->createService(SERVICE_UUID);
  dataCharacteristic = service->createCharacteristic(
    DATA_CHAR_UUID,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  dataCharacteristic->addDescriptor(new BLE2902());

  service->start();

  BLEAdvertising *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->start();
}

ImuFilteredData ReadFilteredImu() {
  ImuFilteredData data;
  data.ax = accelFilters[0].Update(imu.accel_x_mps2());
  data.ay = accelFilters[1].Update(imu.accel_y_mps2());
  data.az = accelFilters[2].Update(imu.accel_z_mps2());
  data.gx = gyroFilters[0].Update(imu.gyro_x_radps());
  data.gy = gyroFilters[1].Update(imu.gyro_y_radps());
  data.gz = gyroFilters[2].Update(imu.gyro_z_radps());
  return data;
}

Vec3 ReadAccelRaw() {
  return {imu.accel_x_mps2(), imu.accel_y_mps2(), imu.accel_z_mps2()};
}

Vec3 ReadGyroRaw() {
  return {imu.gyro_x_radps(), imu.gyro_y_radps(), imu.gyro_z_radps()};
}

void ResetCalibration(uint32_t now_ms) {
  calibration.phase = CalibrationPhase::kStill;
  calibration.phase_start_ms = now_ms;
  calibration.accel_stats.Reset();
  calibration.gyro_stats.Reset();
  calibration.forward_sum = {};
  calibration.forward_samples = 0;
  calibration.z_hat = {};
  calibration.result = {};
  if (DEBUG_SERIAL) {
    Serial.println("Calibration: stand still for 2 seconds.");
  }
}

bool ValidateCalibration(const Vec3 &accel_mean, const Vec3 &gyro_mean) {
  const Vec3 accel_scaled = VecScale(accel_mean, calibration.result.accel_scale);
  const Vec3 accel_b = MatVec(calibration.result.R_sb, accel_scaled);
  const Vec3 gyro_unbiased = VecSub(gyro_mean, calibration.result.gyro_bias);
  const Vec3 gyro_b = MatVec(calibration.result.R_sb, gyro_unbiased);

  if (fabsf(accel_b.z - 1.0f) > ACCEL_Z_TOL) {
    return false;
  }
  if (fabsf(accel_b.x) > ACCEL_XY_TOL || fabsf(accel_b.y) > ACCEL_XY_TOL) {
    return false;
  }
  if (VecNorm(gyro_b) > GYRO_ZERO_TOL) {
    return false;
  }
  return true;
}

void PrintCalibrationJson() {
  if (!DEBUG_SERIAL) {
    return;
  }
  Serial.println("Calibration JSON:");
  Serial.print("{\"calibration\":{\"R_sb\":[[");
  Serial.print(calibration.result.R_sb[0][0], 6);
  Serial.print(',');
  Serial.print(calibration.result.R_sb[0][1], 6);
  Serial.print(',');
  Serial.print(calibration.result.R_sb[0][2], 6);
  Serial.print("],[");
  Serial.print(calibration.result.R_sb[1][0], 6);
  Serial.print(',');
  Serial.print(calibration.result.R_sb[1][1], 6);
  Serial.print(',');
  Serial.print(calibration.result.R_sb[1][2], 6);
  Serial.print("],[");
  Serial.print(calibration.result.R_sb[2][0], 6);
  Serial.print(',');
  Serial.print(calibration.result.R_sb[2][1], 6);
  Serial.print(',');
  Serial.print(calibration.result.R_sb[2][2], 6);
  Serial.print("]],\"gyro_bias\":[");
  Serial.print(calibration.result.gyro_bias.x, 6);
  Serial.print(',');
  Serial.print(calibration.result.gyro_bias.y, 6);
  Serial.print(',');
  Serial.print(calibration.result.gyro_bias.z, 6);
  Serial.print("],\"accel_scale\":");
  Serial.print(calibration.result.accel_scale, 6);
  Serial.println("}}");
}

void UpdateCalibration(const Vec3 &accel_raw, const Vec3 &gyro_raw, uint32_t now_ms) {
  if (calibration.phase == CalibrationPhase::kReady) {
    return;
  }

  if (calibration.phase == CalibrationPhase::kStill) {
    calibration.accel_stats.Update(accel_raw);
    calibration.gyro_stats.Update(gyro_raw);

    if ((now_ms - calibration.phase_start_ms) >= STILL_CAL_DURATION_MS) {
      const Vec3 accel_var = calibration.accel_stats.Variance();
      const Vec3 gyro_var = calibration.gyro_stats.Variance();
      const float accel_std_max = sqrtf(max(accel_var.x, max(accel_var.y, accel_var.z)));
      const float gyro_std_max = sqrtf(max(gyro_var.x, max(gyro_var.y, gyro_var.z)));

      if (accel_std_max > STILL_ACCEL_STD_MAX || gyro_std_max > STILL_GYRO_STD_MAX) {
        if (DEBUG_SERIAL) {
          Serial.println("Calibration: movement detected, restarting.");
        }
        ResetCalibration(now_ms);
        return;
      }

      const Vec3 accel_mean = calibration.accel_stats.mean;
      const float accel_norm = VecNorm(accel_mean);
      if (accel_norm <= 0.0f) {
        ResetCalibration(now_ms);
        return;
      }

      calibration.result.gyro_bias = calibration.gyro_stats.mean;
      calibration.result.accel_scale = 1.0f / accel_norm;
      const Vec3 g_hat = VecScale(accel_mean, 1.0f / accel_norm);
      calibration.z_hat = VecScale(g_hat, -1.0f);

      calibration.phase = CalibrationPhase::kForward;
      calibration.phase_start_ms = now_ms;
      calibration.forward_sum = {};
      calibration.forward_samples = 0;
      if (DEBUG_SERIAL) {
        Serial.println("Calibration: glide straight or toe-tap for 2-3 seconds.");
      }
    }
    return;
  }

  if (calibration.phase == CalibrationPhase::kForward) {
    const Vec3 accel_scaled = VecScale(accel_raw, calibration.result.accel_scale);
    const float gravity_component = VecDot(accel_scaled, calibration.z_hat);
    const Vec3 accel_flat = VecSub(accel_scaled, VecScale(calibration.z_hat, gravity_component));
    calibration.forward_sum = VecAdd(calibration.forward_sum, accel_flat);
    ++calibration.forward_samples;

    if ((now_ms - calibration.phase_start_ms) >= FORWARD_CAL_DURATION_MS) {
      Vec3 forward_mean = calibration.forward_sum;
      if (calibration.forward_samples > 0) {
        forward_mean = VecScale(forward_mean, 1.0f / static_cast<float>(calibration.forward_samples));
      }

      if (VecNorm(forward_mean) < MIN_FORWARD_NORM) {
        if (DEBUG_SERIAL) {
          Serial.println("Calibration: forward motion too small, restarting.");
        }
        ResetCalibration(now_ms);
        return;
      }

      Vec3 x_hat = VecNormalize(forward_mean);
      const Vec3 cross_zx = VecCross(calibration.z_hat, x_hat);
      const float cross_norm = VecNorm(cross_zx);
      if (cross_norm < MIN_FORWARD_ORTHO) {
        if (DEBUG_SERIAL) {
          Serial.println("Calibration: forward vector too close to gravity, restarting.");
        }
        ResetCalibration(now_ms);
        return;
      }

      Vec3 y_hat = VecNormalize(cross_zx);
      x_hat = VecCross(y_hat, calibration.z_hat);

      calibration.result.R_sb[0][0] = x_hat.x;
      calibration.result.R_sb[0][1] = x_hat.y;
      calibration.result.R_sb[0][2] = x_hat.z;
      calibration.result.R_sb[1][0] = y_hat.x;
      calibration.result.R_sb[1][1] = y_hat.y;
      calibration.result.R_sb[1][2] = y_hat.z;
      calibration.result.R_sb[2][0] = calibration.z_hat.x;
      calibration.result.R_sb[2][1] = calibration.z_hat.y;
      calibration.result.R_sb[2][2] = calibration.z_hat.z;

      if (!ValidateCalibration(calibration.accel_stats.mean, calibration.gyro_stats.mean)) {
        if (DEBUG_SERIAL) {
          Serial.println("Calibration: validation failed, restarting.");
        }
        ResetCalibration(now_ms);
        return;
      }

      calibration.phase = CalibrationPhase::kReady;
      calibration.result.ready = true;
      if (DEBUG_SERIAL) {
        Serial.println("Calibration complete.");
        PrintCalibrationJson();
      }
    }
  }
}

void NotifyBle(const ImuFilteredData &data) {
  char payload[128];
  snprintf(
    payload,
    sizeof(payload),
    "%.4f,%.4f,%.4f,%.4f,%.4f,%.4f",
    data.ax,
    data.ay,
    data.az,
    data.gx,
    data.gy,
    data.gz
  );
  dataCharacteristic->setValue(reinterpret_cast<uint8_t *>(payload), strlen(payload));
  dataCharacteristic->notify();
}

void DebugPrint(const ImuFilteredData &data) {
  Serial.print("a:");
  Serial.print(data.ax);
  Serial.print(',');
  Serial.print(data.ay);
  Serial.print(',');
  Serial.print(data.az);
  Serial.print(" g:");
  Serial.print(data.gx);
  Serial.print(',');
  Serial.print(data.gy);
  Serial.print(',');
  Serial.println(data.gz);
}

void setup() {
  if (DEBUG_SERIAL) {
    Serial.begin(SERIAL_BAUD);
    while (!Serial) {
      delay(10);
    }
  }

  SetupImu();
  SetupFilters();
  SetupBle();
  ResetCalibration(millis());
}

void loop() {
  if (!imu.Read()) {
    return;
  }

  const uint32_t now = millis();
  const Vec3 accel_raw = ReadAccelRaw();
  const Vec3 gyro_raw = ReadGyroRaw();
  UpdateCalibration(accel_raw, gyro_raw, now);

  ImuFilteredData filtered = ReadFilteredImu();
  ImuFilteredData output = filtered;

  if (calibration.result.ready) {
    const Vec3 accel_scaled = VecScale({filtered.ax, filtered.ay, filtered.az}, calibration.result.accel_scale);
    const Vec3 gyro_unbiased = VecSub({filtered.gx, filtered.gy, filtered.gz}, calibration.result.gyro_bias);
    const Vec3 accel_b = MatVec(calibration.result.R_sb, accel_scaled);
    const Vec3 gyro_b = MatVec(calibration.result.R_sb, gyro_unbiased);
    output.ax = accel_b.x;
    output.ay = accel_b.y;
    output.az = accel_b.z;
    output.gx = gyro_b.x;
    output.gy = gyro_b.y;
    output.gz = gyro_b.z;
  }

  const uint32_t bleIntervalMs = static_cast<uint32_t>(1000.0f / BLE_OUTPUT_RATE_HZ);
  if (calibration.result.ready && deviceConnected && (now - lastBleNotifyMs) >= bleIntervalMs) {
    NotifyBle(output);
    lastBleNotifyMs = now;
  }

  if (DEBUG_SERIAL && (now - lastDebugPrintMs) >= DEBUG_PRINT_INTERVAL_MS) {
    if (calibration.result.ready) {
      DebugPrint(output);
    } else {
      Serial.println("Calibration in progress...");
    }
    lastDebugPrintMs = now;
  }
}
