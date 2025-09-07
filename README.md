# heart_guard

Un proyecto que simula leer los latidos del corazón y manda estos datos a una app que fue desarrollada usando flutter en dart, recibe los dato de una ESP32 que simula ser una pulsera.
## CODIGO DE WOKWI

- Debes primero ingresar a wokwi y escoger que quieres simular en una "ESP32"([https://wokwi.com/esp32])

*A continuación copia y pega el siguiente código:*

```
#include <WiFi.h>
#include <PubSubClient.h>

const char* WIFI_SSID = "Wokwi-GUEST";
const char* WIFI_PASS = "";
const char* MQTT_SERVER = "test.mosquitto.org";
const int   MQTT_PORT   = 1883;
const char* MQTT_TOPIC  = "bracelet/demo2/hr";

WiFiClient espClient;
PubSubClient client(espClient);
unsigned long lastPublish = 0;
int baseHR = 78;
bool panicSpike = false;

void connectWifi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  Serial.print("Conectando WiFi");
  while (WiFi.status() != WL_CONNECTED) { delay(500); Serial.print("."); }
  Serial.println("\nWiFi OK");
}

void connectMQTT() {
  while (!client.connected()) {
    String cid = "esp32-" + String(random(0xffff), HEX);
    Serial.print("Conectando MQTT...");
    if (client.connect(cid.c_str())) {
      Serial.println("OK");
    } else {
      Serial.print("Fallo (state="); Serial.print(client.state()); Serial.println(") reintento...");
      delay(1000);
    }
  }
}

void setup() {
  Serial.begin(115200);
  connectWifi();
  client.setServer(MQTT_SERVER, MQTT_PORT);
  connectMQTT();
  randomSeed(analogRead(0));
}

void loop() {
  if (WiFi.status() != WL_CONNECTED) connectWifi();
  if (!client.connected()) connectMQTT();
  client.loop();

  unsigned long now = millis();
  if (now - lastPublish > 1000) {
    lastPublish = now;

    if (random(0, 100) < 2) panicSpike = true;
    int noise = random(-3, 4);
    int hr = baseHR + noise + (panicSpike ? random(25, 40) : 0);
    if (panicSpike && random(0, 100) < 30) panicSpike = false;

    char payload[100];
    snprintf(payload, sizeof(payload), "{\"hr\":%d,\"batt\":%.2f,\"ts\":%lu}", hr, 0.72, now);

    bool ok = client.publish(MQTT_TOPIC, payload);
    Serial.print(payload);
    Serial.println(ok ? "  (MQTT publish OK)" : "  (MQTT publish FALLÓ)");
  }
}
```

## APK
Una vez puesto el codigo en Wokwi le das a run, y usas la siguiente apk para recibir los datos
- Link de la apk ([https://drive.google.com/file/d/1FcT2mEUYHXF4tdXrAD_di71Lzw845xEW/view?usp=drive_link])

