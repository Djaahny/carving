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

bfs::Mpu9250 imu;

BiquadFilter accelFilters[3];
BiquadFilter gyroFilters[3];

BLECharacteristic *dataCharacteristic = nullptr;
uint32_t lastBleNotifyMs = 0;
uint32_t lastDebugPrintMs = 0;

bool deviceConnected = false;

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
}

void loop() {
  if (!imu.Read()) {
    return;
  }

  ImuFilteredData filtered = ReadFilteredImu();

  const uint32_t now = millis();
  const uint32_t bleIntervalMs = static_cast<uint32_t>(1000.0f / BLE_OUTPUT_RATE_HZ);
  if (deviceConnected && (now - lastBleNotifyMs) >= bleIntervalMs) {
    NotifyBle(filtered);
    lastBleNotifyMs = now;
  }

  if (DEBUG_SERIAL && (now - lastDebugPrintMs) >= DEBUG_PRINT_INTERVAL_MS) {
    DebugPrint(filtered);
    lastDebugPrintMs = now;
  }
}
