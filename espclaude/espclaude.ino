#include <Arduino_GFX_Library.h>
#include <HWCDC.h>

// Native USB serial, independent of the "USB CDC On Boot" setting
HWCDC HostSerial;
#define HOST HostSerial

#define ROTATION 3
#define SCR_W 320
#define SCR_H 172

Arduino_DataBus *bus = new Arduino_HWSPI(15 /* DC */, 14 /* CS */, 1 /* SCK */, 2 /* MOSI */);

Arduino_GFX *gfx = new Arduino_ST7789(
  bus, 22 /* RST */, 0 /* rotation */, false /* IPS */,
  172 /* width */, 320 /* height */,
  34 /*col_offset1*/, 0 /*uint8_t row_offset1*/,
  34 /*col_offset2*/, 0 /*row_offset2*/);

void lcd_reg_init(void) {
  static const uint8_t init_operations[] = {
    BEGIN_WRITE,
    WRITE_COMMAND_8, 0x11,  // 2: Out of sleep mode, no args, w/delay
    END_WRITE,
    DELAY, 120,

    BEGIN_WRITE,
    WRITE_C8_D16, 0xDF, 0x98, 0x53,
    WRITE_C8_D8, 0xB2, 0x23,

    WRITE_COMMAND_8, 0xB7,
    WRITE_BYTES, 4,
    0x00, 0x47, 0x00, 0x6F,

    WRITE_COMMAND_8, 0xBB,
    WRITE_BYTES, 6,
    0x1C, 0x1A, 0x55, 0x73, 0x63, 0xF0,

    WRITE_C8_D16, 0xC0, 0x44, 0xA4,
    WRITE_C8_D8, 0xC1, 0x16,

    WRITE_COMMAND_8, 0xC3,
    WRITE_BYTES, 8,
    0x7D, 0x07, 0x14, 0x06, 0xCF, 0x71, 0x72, 0x77,

    WRITE_COMMAND_8, 0xC4,
    WRITE_BYTES, 12,
    0x00, 0x00, 0xA0, 0x79, 0x0B, 0x0A, 0x16, 0x79, 0x0B, 0x0A, 0x16, 0x82,

    WRITE_COMMAND_8, 0xC8,
    WRITE_BYTES, 32,
    0x3F, 0x32, 0x29, 0x29, 0x27, 0x2B, 0x27, 0x28, 0x28, 0x26, 0x25, 0x17, 0x12, 0x0D, 0x04, 0x00, 0x3F, 0x32, 0x29, 0x29, 0x27, 0x2B, 0x27, 0x28, 0x28, 0x26, 0x25, 0x17, 0x12, 0x0D, 0x04, 0x00,

    WRITE_COMMAND_8, 0xD0,
    WRITE_BYTES, 5,
    0x04, 0x06, 0x6B, 0x0F, 0x00,

    WRITE_C8_D16, 0xD7, 0x00, 0x30,
    WRITE_C8_D8, 0xE6, 0x14,
    WRITE_C8_D8, 0xDE, 0x01,

    WRITE_COMMAND_8, 0xB7,
    WRITE_BYTES, 5,
    0x03, 0x13, 0xEF, 0x35, 0x35,

    WRITE_COMMAND_8, 0xC1,
    WRITE_BYTES, 3,
    0x14, 0x15, 0xC0,

    WRITE_C8_D16, 0xC2, 0x06, 0x3A,
    WRITE_C8_D16, 0xC4, 0x72, 0x12,
    WRITE_C8_D8, 0xBE, 0x00,
    WRITE_C8_D8, 0xDE, 0x02,

    WRITE_COMMAND_8, 0xE5,
    WRITE_BYTES, 3,
    0x00, 0x02, 0x00,

    WRITE_COMMAND_8, 0xE5,
    WRITE_BYTES, 3,
    0x01, 0x02, 0x00,

    WRITE_C8_D8, 0xDE, 0x00,
    WRITE_C8_D8, 0x35, 0x00,
    WRITE_C8_D8, 0x3A, 0x05,

    WRITE_COMMAND_8, 0x2A,
    WRITE_BYTES, 4,
    0x00, 0x22, 0x00, 0xCD,

    WRITE_COMMAND_8, 0x2B,
    WRITE_BYTES, 4,
    0x00, 0x00, 0x01, 0x3F,

    WRITE_C8_D8, 0xDE, 0x02,

    WRITE_COMMAND_8, 0xE5,
    WRITE_BYTES, 3,
    0x00, 0x02, 0x00,

    WRITE_C8_D8, 0xDE, 0x00,
    WRITE_C8_D8, 0x36, 0x00,
    WRITE_COMMAND_8, 0x21,
    END_WRITE,

    DELAY, 10,

    BEGIN_WRITE,
    WRITE_COMMAND_8, 0x29,  // 5: Main screen turn on, no args, w/delay
    END_WRITE
  };
  bus->batchOperation(init_operations, sizeof(init_operations));
}

// ---------------------------------------------------------------------------
// Synthwave usage display
// Host (tools/usage_push.py) sends one line per update over USB serial:
//   U,<weekday 0=Mon>,<d0>,...,<d6>,<tokens last 5h>,<messages today>[,<5h %>,<5h reset min>,<7d %>,<7d reset min>[,<5h cents>,<today cents>,<7d cents>]]\n//   limit fields are -1 when unknown
// d0..d6 = tokens per day, oldest first, d6 = today.
// ---------------------------------------------------------------------------

Arduino_Canvas *canvas = nullptr;

struct Usage {
  uint8_t weekday = 0;
  uint32_t day[7] = { 0 };
  uint32_t h5 = 0;
  uint32_t msgs = 0;
  int pct5 = -1, reset5 = -1, pct7 = -1, reset7 = -1;
  long cost5 = -1, costDay = -1, costWeek = -1;  // USD cents
  unsigned long lastRx = 0;
  bool valid = false;
} usage;

static uint16_t C(uint8_t r, uint8_t g, uint8_t b) {
  return canvas->color565(r, g, b);
}
static uint8_t lerp8(uint8_t a, uint8_t b, int t, int tmax) {
  return a + (int)(b - a) * t / tmax;
}
static uint16_t mix(uint8_t r1, uint8_t g1, uint8_t b1, uint8_t r2, uint8_t g2, uint8_t b2, int t, int tmax) {
  return C(lerp8(r1, r2, t, tmax), lerp8(g1, g2, t, tmax), lerp8(b1, b2, t, tmax));
}

static void fmtTokens(uint32_t v, char *out, size_t n) {
  if (v >= 1000000) snprintf(out, n, "%lu.%luM", v / 1000000, (v % 1000000) / 100000);
  else if (v >= 10000) snprintf(out, n, "%luK", v / 1000);
  else if (v >= 1000) snprintf(out, n, "%lu.%luK", v / 1000, (v % 1000) / 100);
  else snprintf(out, n, "%lu", v);
}

static void fmtCost(long cents, char *out, size_t n) {
  if (cents < 0) snprintf(out, n, "$--");
  else snprintf(out, n, "$%ld.%02ld", cents / 100, cents % 100);
}

static void glowText(int x, int y, const char *s, uint8_t size, uint16_t col, uint16_t shadow) {
  canvas->setTextSize(size);
  canvas->setTextColor(shadow);
  canvas->setCursor(x + 1, y + 1);
  canvas->print(s);
  canvas->setTextColor(col);
  canvas->setCursor(x, y);
  canvas->print(s);
}

static const int HORIZON = 112;
static const int FLOOR_END = 156;

static void drawBackground(unsigned long t) {
  // sky gradient
  for (int y = 0; y < HORIZON; y += 2) {
    canvas->fillRect(0, y, SCR_W, 2, mix(8, 0, 22, 48, 0, 62, y, HORIZON));
  }
  // sun with cut-out stripes (dim so the chart stays readable)
  const int cx = 236, cy = HORIZON, r = 46;
  for (int dy = -r; dy <= 0; dy++) {
    int depth = -dy;  // 0 at horizon, r at top
    if (depth > 4 && (depth % 8) < (r - depth) / 7 + 0 && depth < 28) continue;
    int hw = (int)sqrtf((float)(r * r - dy * dy));
    canvas->drawFastHLine(cx - hw, cy + dy, hw * 2, mix(120, 20, 90, 150, 70, 20, depth, r));
  }
  // floor (limit bars live here)
  canvas->fillRect(0, HORIZON, SCR_W, SCR_H - HORIZON, C(14, 0, 30));
  canvas->drawFastHLine(0, HORIZON, SCR_W, C(0, 240, 255));
}

static void drawHeader(unsigned long t) {
  glowText(8, 4, "CLAUDE", 2, C(255, 60, 200), C(0, 200, 255));
  char a[12], b[12], c[12], line[40];
  fmtCost(usage.cost5, a, sizeof(a));
  fmtCost(usage.costDay, b, sizeof(b));
  fmtCost(usage.costWeek, c, sizeof(c));
  snprintf(line, sizeof(line), "%s | %s | %s", a, b, c);
  canvas->setTextSize(1);
  canvas->setTextColor(C(0, 255, 160));
  canvas->setCursor(SCR_W - 28 - 6 * (int)strlen(line), 7);
  canvas->print(line);
  for (int x = 0; x < SCR_W; x += 2) {
    canvas->fillRect(x, 22, 2, 1, mix(255, 40, 200, 0, 240, 255, x, SCR_W));
  }
}

static void drawBars() {
  uint32_t mx = 1;
  uint32_t total = 0;
  for (int i = 0; i < 7; i++) {
    if (usage.day[i] > mx) mx = usage.day[i];
    total += usage.day[i];
  }
  const int x0 = 170, bw = 16, gap = 4, base = 100, maxh = 56;
  static const char letters[] = "MDMDFSS";  // Mo Di Mi Do Fr Sa So

  char buf[16];
  fmtTokens(total, buf, sizeof(buf));
  canvas->setTextSize(1);
  canvas->setTextColor(C(0, 240, 255));
  canvas->setCursor(x0, 28);
  canvas->print("7D ");
  canvas->setTextColor(C(255, 255, 255));
  canvas->print(buf);

  for (int i = 0; i < 7; i++) {
    int h = (int)((uint64_t)usage.day[i] * maxh / mx);
    if (usage.day[i] > 0 && h < 2) h = 2;
    int x = x0 + i * (bw + gap);
    for (int y = 0; y < h; y += 2) {  // vertical gradient: cyan (top) -> magenta (bottom)
      canvas->fillRect(x, base - h + y, bw, 2, mix(0, 240, 255, 255, 40, 200, y, maxh));
    }
    if (i == 6 && h > 0) canvas->drawFastHLine(x, base - h, bw, C(255, 255, 255));
    int wd = ((usage.weekday - (6 - i)) % 7 + 7) % 7;
    canvas->setTextColor(i == 6 ? C(255, 255, 255) : C(190, 150, 255));
    canvas->setCursor(x + 5, base + 3);
    canvas->print(letters[wd]);
  }
  canvas->drawFastHLine(x0 - 2, base + 1, 7 * (bw + gap), C(255, 40, 200));
}

static void drawStats() {
  char buf[16];
  canvas->setTextSize(1);
  canvas->setTextColor(C(0, 240, 255));
  canvas->setCursor(8, 26);
  canvas->print("TODAY");
  canvas->setTextColor(C(190, 150, 255));
  snprintf(buf, sizeof(buf), "%lu MSGS", usage.msgs);
  canvas->setCursor(8 + 6 * 7, 26);
  canvas->print(buf);
  fmtTokens(usage.day[6], buf, sizeof(buf));
  glowText(8, 35, buf, 4, C(255, 70, 210), C(70, 0, 140));

  canvas->setTextSize(1);
  canvas->setTextColor(C(0, 240, 255));
  canvas->setCursor(8, 70);
  canvas->print("LAST 5H");
  fmtTokens(usage.h5, buf, sizeof(buf));
  glowText(8, 79, buf, 4, C(255, 230, 80), C(120, 60, 0));
}

// [█████          ] 70%  -- segmented neon bar
static void drawLimitBar(int y, const char *label, int pct) {
  const int segs = 20, segW = 10, h = 14, x0 = 60;
  canvas->setTextSize(1);
  canvas->setTextColor(C(0, 240, 255));
  canvas->setCursor(8, y + 3);
  canvas->print(label);

  uint16_t br = C(190, 150, 255);
  canvas->drawFastVLine(x0 - 3, y - 1, h + 2, br);
  canvas->drawFastHLine(x0 - 3, y - 1, 3, br);
  canvas->drawFastHLine(x0 - 3, y + h, 3, br);
  canvas->drawFastVLine(x0 + segs * segW + 2, y - 1, h + 2, br);
  canvas->drawFastHLine(x0 + segs * segW, y - 1, 3, br);
  canvas->drawFastHLine(x0 + segs * segW, y + h, 3, br);

  int filled = pct < 0 ? 0 : (pct * segs + 50) / 100;
  if (filled > segs) filled = segs;
  for (int i = 0; i < segs; i++) {
    uint16_t col = i < filled ? mix(0, 240, 255, 255, 40, 200, i, segs - 1) : C(40, 10, 70);
    canvas->fillRect(x0 + i * segW, y, segW - 2, h, col);
  }

  char buf[8];
  if (pct < 0) snprintf(buf, sizeof(buf), "--%%");
  else snprintf(buf, sizeof(buf), "%d%%", pct);
  uint16_t pc = pct >= 90 ? C(255, 50, 60) : pct >= 70 ? C(255, 140, 40)
                                                       : C(255, 255, 255);
  glowText(x0 + segs * segW + 8, y, buf, 2, pc, C(70, 0, 140));
}

static void drawLimits() {
  drawLimitBar(118, "SESSION", usage.pct5);
  drawLimitBar(137, "WEEKLY", usage.pct7);
}

static void drawFooter(unsigned long t) {
  canvas->fillRect(0, FLOOR_END + 1, SCR_W, SCR_H - FLOOR_END - 1, C(6, 0, 16));
  canvas->setTextSize(1);
  canvas->setCursor(8, SCR_H - 11);
  if (!usage.valid) {
    canvas->setTextColor((t / 400) % 2 ? C(255, 60, 200) : C(90, 20, 80));
    canvas->print("> WAITING FOR HOST...");
  } else {
    unsigned long age = (millis() - usage.lastRx) / 1000;
    bool stale = age > 180;
    canvas->setTextColor(stale ? C(255, 80, 80) : C(0, 255, 160));
    canvas->print(stale ? "> LINK LOST " : "> LINK OK ");
    canvas->setTextColor(C(190, 150, 255));
    canvas->print(age);
    canvas->print("s");
  }
  canvas->setTextColor(C(255, 60, 200));
  canvas->setCursor(SCR_W - 6 * 12 - 8, SCR_H - 11);
  canvas->print("TOKENS 1984");
}

static void parseLine(char *line) {
  if (line[0] != 'U' || line[1] != ',') return;
  long v[17];
  int n = 0;
  char *tok = strtok(line + 2, ",");
  while (tok && n < 17) {
    v[n++] = strtol(tok, nullptr, 10);
    tok = strtok(nullptr, ",");
  }
  if (n < 10) return;
  usage.weekday = v[0] % 7;
  for (int i = 0; i < 7; i++) usage.day[i] = v[1 + i];
  usage.h5 = v[8];
  usage.msgs = v[9];
  usage.pct5 = n >= 14 ? v[10] : -1;
  usage.reset5 = n >= 14 ? v[11] : -1;
  usage.pct7 = n >= 14 ? v[12] : -1;
  usage.reset7 = n >= 14 ? v[13] : -1;
  usage.cost5 = n >= 17 ? v[14] : -1;
  usage.costDay = n >= 17 ? v[15] : -1;
  usage.costWeek = n >= 17 ? v[16] : -1;
  usage.lastRx = millis();
  usage.valid = true;
  HOST.println("RX ok");
}

static void pollSerial() {
  static char buf[128];
  static size_t len = 0;
  while (HOST.available()) {
    char c = HOST.read();
    if (c == '\n' || c == '\r') {
      if (len) {
        buf[len] = 0;
        parseLine(buf);
        len = 0;
      }
    } else if (len < sizeof(buf) - 1) {
      buf[len++] = c;
    } else {
      len = 0;
    }
  }
}

void setup(void) {
  HOST.begin(115200);
  pinMode(23, OUTPUT);
  digitalWrite(23, HIGH);

  if (!gfx->begin()) {
    HOST.println("gfx->begin() failed!");
  }
  lcd_reg_init();
  gfx->setRotation(ROTATION);
  gfx->fillScreen(RGB565_BLACK);

#ifdef GFX_BL
  pinMode(GFX_BL, OUTPUT);
  digitalWrite(GFX_BL, HIGH);
#endif

  // Off-screen buffer (110 KB) -> flicker-free animation
  canvas = new Arduino_Canvas(SCR_W, SCR_H, gfx, 0, 0);
  if (!canvas->begin(GFX_SKIP_OUTPUT_BEGIN)) {
    HOST.println("canvas->begin() failed!");
  }
}

void loop() {
  static unsigned long lastFrame = 0;
  pollSerial();
  static unsigned long lastBeat = 0;
  if (millis() - lastBeat > 2000) {
    lastBeat = millis();
    HOST.println("alive");
  }

  unsigned long now = millis();
  if (now - lastFrame < 66) return;  // ~15 fps
  lastFrame = now;

  drawBackground(now);
  drawHeader(now);
  drawStats();
  drawBars();
  drawLimits();
  drawFooter(now);
  canvas->flush();
}
