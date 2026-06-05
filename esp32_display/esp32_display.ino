/*
 * ESP32-S3 — Serveur HTTP + Affichage du mot de passe sur OLED SSD1306
 *
 * Connexions écran I2C :
 *   SDA → GPIO 8
 *   SCL → GPIO 9
 *   VCC → 3.3V
 *   GND → GND
 *
 * Librairies Arduino requises :
 *   - Adafruit SSD1306
 *   - Adafruit GFX Library
 *
 * Endpoint exposé :
 *   POST http://<ip-esp32>/password
 *   Body (form) : password=<mdp>&services=<svc>:<user>:<port>,...
 *
 * L'IP est affichée sur l'écran OLED au démarrage.
 */

#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <WiFi.h>
#include <WebServer.h>

// ── Config ────────────────────────────────────────────────────────────────────
#define SDA_PIN       8
#define SCL_PIN       9
#define SCREEN_WIDTH  128
#define SCREEN_HEIGHT  64
#define OLED_ADDRESS  0x3C

const char* WIFI_SSID = "decode-etudiants";  
const char* WIFI_PASS = "learnByDoing25!"; 

// ── Globals ───────────────────────────────────────────────────────────────────
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, -1);
WebServer server(80);

#define MAX_SERVICES 8
#define SCROLL_MS    3000

struct Service { String name, user, port; };
Service       services[MAX_SERVICES];
int           serviceCount = 0;
String        sharedPwd    = "";
int           currentIndex = 0;
unsigned long lastScroll   = 0;

// ── Parsing ───────────────────────────────────────────────────────────────────
void parseServices(const String& raw) {
  serviceCount = 0;
  int pos = 0;
  while (pos < (int)raw.length() && serviceCount < MAX_SERVICES) {
    int commaPos = raw.indexOf(',', pos);
    String chunk = (commaPos == -1) ? raw.substring(pos) : raw.substring(pos, commaPos);
    pos = (commaPos == -1) ? raw.length() : commaPos + 1;

    int p = 0, p2;
    p2 = chunk.indexOf(':', p);
    if (p2 == -1) continue;
    services[serviceCount].name = chunk.substring(p, p2); p = p2 + 1;
    p2 = chunk.indexOf(':', p);
    if (p2 == -1) {
      services[serviceCount].user = chunk.substring(p);
      services[serviceCount].port = "";
    } else {
      services[serviceCount].user = chunk.substring(p, p2);
      services[serviceCount].port = chunk.substring(p2 + 1);
    }
    serviceCount++;
  }
}

// ── Affichage ─────────────────────────────────────────────────────────────────
void showConnecting() {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 10); display.println("Connexion WiFi...");
  display.setCursor(0, 30); display.print("SSID: "); display.println(WIFI_SSID);
  display.display();
}

void showReady(const String& ip) {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 0);  display.println("En attente du");
  display.setCursor(0, 10); display.println("deploiement...");
  display.drawFastHLine(0, 22, 128, SSD1306_WHITE);
  display.setCursor(0, 28); display.print("IP: "); display.println(ip);
  display.display();
}

void drawService(int idx) {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);

  // Mot de passe
  display.setCursor(0, 0);
  display.print("MDP: ");
  display.println(sharedPwd);
  display.drawFastHLine(0, 10, 128, SSD1306_WHITE);

  if (serviceCount == 0) { display.display(); return; }

  const Service& s = services[idx];
  display.setCursor(0, 14); display.println(s.name);
  display.setCursor(0, 27); display.print("user: "); display.println(s.user.length() ? s.user : "N/A");
  display.setCursor(0, 39); display.print("port: "); display.println(s.port);

  // Indicateur de page + barre
  display.setCursor(0, 54);
  display.print(idx + 1); display.print("/"); display.print(serviceCount);
  int barW = map(idx + 1, 0, serviceCount, 0, 100);
  display.drawRect(20, 56, 100, 6, SSD1306_WHITE);
  display.fillRect(20, 56, barW, 6, SSD1306_WHITE);

  display.display();
}

// ── Routes HTTP ───────────────────────────────────────────────────────────────
void handlePassword() {
  if (!server.hasArg("password")) {
    server.send(400, "text/plain", "Parametre 'password' manquant");
    return;
  }
  sharedPwd = server.arg("password");
  String svcs = server.hasArg("services") ? server.arg("services") : "";
  parseServices(svcs);
  currentIndex = 0;
  lastScroll   = millis();
  drawService(0);
  server.send(200, "text/plain", "OK");
}

void handleRoot() {
  String html = "<h2>ESP32 Password Display</h2>"
                "<p>POST /password?password=xxx&services=svc:user:port,...</p>"
                "<p>MDP actuel : " + (sharedPwd.length() ? sharedPwd : "(aucun)") + "</p>";
  server.send(200, "text/html", html);
}

// ── Setup / Loop ──────────────────────────────────────────────────────────────
void setup() {
  Serial.begin(115200);
  Wire.begin(SDA_PIN, SCL_PIN);

  if (!display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDRESS)) {
    Serial.println("ERR: OLED non détecté");
    while (true) delay(1000);
  }

  Serial.println("Demarrage...");
  Serial.print("SSID: "); Serial.println(WIFI_SSID);
  showConnecting();

  WiFi.begin(WIFI_SSID, WIFI_PASS);
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) {
    delay(500);
    attempts++;
    Serial.print(".");
  }
  Serial.println();

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("ERREUR: WiFi non connecte apres 10s");
    display.clearDisplay();
    display.setTextSize(1);
    display.setTextColor(SSD1306_WHITE);
    display.setCursor(0, 10); display.println("WiFi: ECHEC");
    display.setCursor(0, 25); display.println(WIFI_SSID);
    display.setCursor(0, 40); display.println("Verif SSID/mdp");
    display.display();
    while (true) delay(1000);  // stop — évite le redémarrage watchdog
  }

  String ip = WiFi.localIP().toString();
  Serial.println("IP: " + ip);
  showReady(ip);

  server.on("/",         HTTP_GET,  handleRoot);
  server.on("/password", HTTP_POST, handlePassword);
  server.begin();
  Serial.println("Serveur HTTP démarré sur http://" + ip);
}

void loop() {
  server.handleClient();

  if (sharedPwd.length() > 0 && serviceCount > 1 && millis() - lastScroll >= SCROLL_MS) {
    currentIndex = (currentIndex + 1) % serviceCount;
    drawService(currentIndex);
    lastScroll = millis();
  }
}
