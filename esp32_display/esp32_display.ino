/*
 * ESP32 — Affichage du mot de passe partagé + défilement des services
 *
 * Connexions écran OLED SSD1306 I2C :
 *   SDA → GPIO 8
 *   SCL → GPIO 3
 *   VCC → 3.3V
 *   GND → GND
 *
 * Librairies Arduino (Bibliothèque Manager) :
 *   - Adafruit SSD1306
 *   - Adafruit GFX Library
 *
 * Protocole série reçu depuis le PC :
 *   PASS:<mdp>|<service>:<user>:<port>,...\n
 *   Exemple: PASS:aB3!xZ9k|WP Multisite:wp_user::8080,VPS SSH:admin::2222
 */

#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

#define SCREEN_WIDTH  128
#define SCREEN_HEIGHT  64
#define OLED_RESET     -1
#define OLED_ADDRESS  0x3C
#define SDA_PIN 8
#define SCL_PIN 3

#define MAX_SERVICES 8
#define SCROLL_INTERVAL_MS 3000

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

struct Service {
  String name;
  String user;
  String port;
};

String      password      = "";
Service     services[MAX_SERVICES];
int         serviceCount  = 0;
int         currentIndex  = 0;
unsigned long lastScroll  = 0;
bool        hasData       = false;

// ── Parsing ──────────────────────────────────────────────────────────────────

String nextToken(const String& s, int& pos, char delim) {
  int end = s.indexOf(delim, pos);
  String token;
  if (end == -1) {
    token = s.substring(pos);
    pos   = s.length();
  } else {
    token = s.substring(pos, end);
    pos   = end + 1;
  }
  return token;
}

bool parsePayload(const String& raw) {
  // Format: PASS:<mdp>|<svc>:<user>:<port>,...
  if (!raw.startsWith("PASS:")) return false;

  int pipePos = raw.indexOf('|');
  if (pipePos == -1) {
    password = raw.substring(5);
    serviceCount = 0;
  } else {
    password = raw.substring(5, pipePos);
    String svcs = raw.substring(pipePos + 1);

    serviceCount = 0;
    int pos = 0;
    while (pos < (int)svcs.length() && serviceCount < MAX_SERVICES) {
      String chunk = nextToken(svcs, pos, ',');
      int p1 = 0;
      services[serviceCount].name = nextToken(chunk, p1, ':');
      services[serviceCount].user = nextToken(chunk, p1, ':');
      services[serviceCount].port = nextToken(chunk, p1, ':');
      serviceCount++;
    }
  }
  return password.length() > 0;
}

// ── Affichage ─────────────────────────────────────────────────────────────────

void showWaiting() {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(20, 20);
  display.println("En attente du");
  display.setCursor(20, 32);
  display.println("deploiement...");
  display.display();
}

void drawFrame(int serviceIdx) {
  display.clearDisplay();

  // ── Ligne 1 : mot de passe (taille 1)
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 0);
  display.print("MDP: ");
  display.println(password);

  // Séparateur
  display.drawLine(0, 10, 127, 10, SSD1306_WHITE);

  if (serviceCount == 0) {
    display.setCursor(0, 20);
    display.println("Pret");
    display.display();
    return;
  }

  // ── Ligne 2 : nom du service (taille 1, gras simulé via taille 1)
  const Service& svc = services[serviceIdx];
  display.setTextSize(1);
  display.setCursor(0, 14);
  display.setTextColor(SSD1306_WHITE);
  display.println(svc.name);

  // ── Ligne 3 : user
  display.setCursor(0, 27);
  display.print("user: ");
  display.println(svc.user == "-" ? "N/A" : svc.user);

  // ── Ligne 4 : port
  display.setCursor(0, 39);
  display.print("port: ");
  display.println(svc.port);

  // ── Pied : indicateur de page
  display.setCursor(0, 54);
  display.print(serviceIdx + 1);
  display.print("/");
  display.print(serviceCount);

  // Barre de progression
  int barWidth = map(serviceIdx + 1, 0, serviceCount, 0, 100);
  display.drawRect(20, 56, 100, 6, SSD1306_WHITE);
  display.fillRect(20, 56, barWidth, 6, SSD1306_WHITE);

  display.display();
}

// ── Setup / Loop ──────────────────────────────────────────────────────────────

void setup() {
  Serial.begin(115200);
  Wire.begin(SDA_PIN, SCL_PIN);

  if (!display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDRESS)) {
    Serial.println("ERR:SSD1306");
    while (true) delay(1000);
  }

  display.clearDisplay();
  display.display();
  showWaiting();
  Serial.println("READY");
}

void loop() {
  // Réception série
  if (Serial.available()) {
    String line = Serial.readStringUntil('\n');
    line.trim();

    if (parsePayload(line)) {
      hasData      = true;
      currentIndex = 0;
      lastScroll   = millis();
      drawFrame(0);
      Serial.println("OK:displayed");
    } else {
      Serial.println("ERR:parse_failed");
    }
  }

  // Défilement automatique entre les services
  if (hasData && serviceCount > 1 && millis() - lastScroll >= SCROLL_INTERVAL_MS) {
    currentIndex = (currentIndex + 1) % serviceCount;
    drawFrame(currentIndex);
    lastScroll = millis();
  }
}
