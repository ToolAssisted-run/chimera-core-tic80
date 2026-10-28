/* cinterface.c - TIC-80 as a Chimera core: the functions Chimera calls.
 *
 * TIC-80 comes with an API for a program that embeds it (include/tic80.h):
 * make a machine, give it a cart, then once a frame give it the controls,
 * run the frame and take the picture and the sound. This file is that
 * program, inside the sandbox. It reads the cart and the settings from the
 * project, answers TIC-80's questions about the time with a clock of its
 * own, and draws the mouse cursor the way TIC-80's own player does.
 *
 * SPDX-License-Identifier: MIT
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/time.h>
#include <time.h>

#include <emulibc.h>
#include <waterbox_settings.h>
#include <waterbox_slots.h>

#include "tic80.h"
#include "api.h"
#include "cart.h"
#include "script.h"
#include "tools.h"
#include "core/core.h"

/* ---- what went wrong, for Chimera to show -------------------------------- */
/* A text a person reads is a key of languages/en.json, each of its
 * arguments after a TEXT_ARG (chimera docs/translations.md). TEXT_ARG is a
 * string of its own so the byte after it is never read as more of its hex. */
#define TEXT_ARG "\x1f"

static char g_loadError[512];

/* ---- the machine -------------------------------------------------------- */
static tic80 *g_tic;
static tic_mem *g_mem;
static char g_cartName[256];
static int g_exited;          /* the cart called exit(): the machine stops */
static char g_lastError[256]; /* the cart's last error, said once */

/* ---- the picture -------------------------------------------------------
 * TIC-80's picture is 256x144: its 240x136 screen and a border around it,
 * which carts draw on too. The Picture setting shows all of it, or the
 * screen alone. */
ECL_INVISIBLE static uint32_t g_picture[TIC80_FULLWIDTH * TIC80_FULLHEIGHT];
static int g_full = 1;
static int g_render = 1;
static int g_drawCursor = 1;

/* ---- the sound ---------------------------------------------------------- */
#define MAX_SAMPLES 2048
ECL_INVISIBLE static int16_t g_audio[MAX_SAMPLES * 2];
static int g_audioFrames;

/* ---- the controls -------------------------------------------------------
 * Four gamepads of eight buttons, the mouse's three buttons, and the 94 keys
 * TIC-80 knows, listed as they sit on the keyboard, row by row from the top,
 * then the keys beside the rows, the arrows and the keypad (chimera#337),
 * each with TIC-80's code for it. A cart sees at most four keys at once
 * (TIC80_KEY_BUFFER): if more are held, the four with the lowest codes, as
 * it was before the keys were listed in rows. Every control is live whatever
 * the cart declares (its "input" tag), because a cart can read them all. */
enum { kPadButtons = 8, kPads = 4, kMouseLeft = kPads * kPadButtons, kMouseMiddle, kMouseRight, kFirstKey };
static const char *const kPadNames[kPadButtons] = { "Up", "Down", "Left", "Right", "A", "B", "X", "Y" };
static const struct { const char *name; tic_key code; } kKeys[tic_keys_count - 1] = {
	{ "Escape", tic_key_escape }, { "F1", tic_key_f1 }, { "F2", tic_key_f2 }, { "F3", tic_key_f3 },
	{ "F4", tic_key_f4 }, { "F5", tic_key_f5 }, { "F6", tic_key_f6 }, { "F7", tic_key_f7 },
	{ "F8", tic_key_f8 }, { "F9", tic_key_f9 }, { "F10", tic_key_f10 }, { "F11", tic_key_f11 },
	{ "F12", tic_key_f12 },
	{ "`", tic_key_grave }, { "1", tic_key_1 }, { "2", tic_key_2 }, { "3", tic_key_3 }, { "4", tic_key_4 },
	{ "5", tic_key_5 }, { "6", tic_key_6 }, { "7", tic_key_7 }, { "8", tic_key_8 }, { "9", tic_key_9 },
	{ "0", tic_key_0 }, { "-", tic_key_minus }, { "=", tic_key_equals }, { "Backspace", tic_key_backspace },
	{ "Tab", tic_key_tab }, { "Q", tic_key_q }, { "W", tic_key_w }, { "E", tic_key_e }, { "R", tic_key_r },
	{ "T", tic_key_t }, { "Y", tic_key_y }, { "U", tic_key_u }, { "I", tic_key_i }, { "O", tic_key_o },
	{ "P", tic_key_p }, { "[", tic_key_leftbracket }, { "]", tic_key_rightbracket },
	{ "\\", tic_key_backslash },
	{ "Caps Lock", tic_key_capslock }, { "A", tic_key_a }, { "S", tic_key_s }, { "D", tic_key_d },
	{ "F", tic_key_f }, { "G", tic_key_g }, { "H", tic_key_h }, { "J", tic_key_j }, { "K", tic_key_k },
	{ "L", tic_key_l }, { ";", tic_key_semicolon }, { "'", tic_key_apostrophe }, { "Return", tic_key_return },
	{ "Shift", tic_key_shift }, { "Z", tic_key_z }, { "X", tic_key_x }, { "C", tic_key_c }, { "V", tic_key_v },
	{ "B", tic_key_b }, { "N", tic_key_n }, { "M", tic_key_m }, { ",", tic_key_comma }, { ".", tic_key_period },
	{ "/", tic_key_slash },
	{ "Ctrl", tic_key_ctrl }, { "Alt", tic_key_alt }, { "Space", tic_key_space },
	{ "Insert", tic_key_insert }, { "Home", tic_key_home }, { "Page Up", tic_key_pageup },
	{ "Delete", tic_key_delete }, { "End", tic_key_end }, { "Page Down", tic_key_pagedown },
	{ "Up", tic_key_up }, { "Left", tic_key_left }, { "Down", tic_key_down }, { "Right", tic_key_right },
	{ "Keypad /", tic_key_numpaddivide }, { "Keypad *", tic_key_numpadmultiply },
	{ "Keypad -", tic_key_numpadminus }, { "Keypad 7", tic_key_numpad7 }, { "Keypad 8", tic_key_numpad8 },
	{ "Keypad 9", tic_key_numpad9 }, { "Keypad +", tic_key_numpadplus }, { "Keypad 4", tic_key_numpad4 },
	{ "Keypad 5", tic_key_numpad5 }, { "Keypad 6", tic_key_numpad6 }, { "Keypad 1", tic_key_numpad1 },
	{ "Keypad 2", tic_key_numpad2 }, { "Keypad 3", tic_key_numpad3 }, { "Keypad Enter", tic_key_numpadenter },
	{ "Keypad 0", tic_key_numpad0 }, { "Keypad .", tic_key_numpadperiod },
};
#define KEY_COUNT ((int)(sizeof kKeys / sizeof kKeys[0]))
#define BUTTON_COUNT (kFirstKey + KEY_COUNT)
static char g_buttonNames[BUTTON_COUNT][24];
static int g_held[BUTTON_COUNT];

/* Mouse X and Y say where the mouse is, as a fraction of the picture shown
 * (0 to 65535, Chimera's spelling for a place on the screen). A cart can
 * instead ask for the mouse's movement (TIC-80's relative mode, which it
 * sets in its memory): then Mouse Move X and Y are how far it moved in the
 * frame. Scroll X and Y are the wheel's turn in the frame. */
enum { kMouseX, kMouseY, kMoveX, kMoveY, kScrollX, kScrollY, kAxes };
static const char *const kAxisNames[kAxes] = { "Mouse X", "Mouse Y", "Mouse Move X", "Mouse Move Y", "Scroll X", "Scroll Y" };
static int g_axis[kAxes] = { 32768, 32768, 0, 0, 0, 0 };

static int g_inputReads;
static int g_inputRead;
/* above 0 while the machine itself looks at the keys (its gamepad mapping),
 * which is not the cart reading them (core/io.c, patch 0001) */
int chimera_input_quiet;

/* Chimera's function to call at each look the cart takes at the controls, so
 * a Lua script's event.oninputpoll runs there (chimera#344). It is the same
 * callback slot in every session and no savestate carries it. */
ECL_INVISIBLE static uintptr_t (*g_inputPoll)(uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t);
ECL_EXPORT void SetInputPollCallback(uint64_t fn)
{
	g_inputPoll = (uintptr_t (*)(uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t))(uintptr_t)fn;
}

/* core/io.c and core/core.c call this at each look (patch 0001) */
void chimera_input_read(void)
{
	if (chimera_input_quiet) return;
	g_inputReads++;
	if (g_inputPoll) g_inputPoll(0, 0, 0, 0, 0, 0);
}

static int clampi(int v, int lo, int hi) { return v < lo ? lo : v > hi ? hi : v; }

static tic80_input make_input(void)
{
	tic80_input in;
	memset(&in, 0, sizeof in);
	for (int p = 0; p < kPads; p++)
		for (int b = 0; b < kPadButtons; b++)
			if (g_held[p * kPadButtons + b])
				in.gamepads.data |= 1u << (p * kPadButtons + b);

	in.mouse.left = g_held[kMouseLeft];
	in.mouse.middle = g_held[kMouseMiddle];
	in.mouse.right = g_held[kMouseRight];
	in.mouse.scrollx = clampi(g_axis[kScrollX], -32, 31);
	in.mouse.scrolly = clampi(g_axis[kScrollY], -32, 31);
	if (g_mem->ram->input.mouse.relative)
	{
		in.mouse.relative = 1;
		in.mouse.rx = (s8)clampi(g_axis[kMoveX], -128, 127);
		in.mouse.ry = (s8)clampi(g_axis[kMoveY], -128, 127);
	}
	else
	{
		/* the pixel under the place, in the whole 256x144 picture */
		int w = g_full ? TIC80_FULLWIDTH : TIC80_WIDTH, h = g_full ? TIC80_FULLHEIGHT : TIC80_HEIGHT;
		int x = (int)((int64_t)clampi(g_axis[kMouseX], 0, 65535) * w / 65536);
		int y = (int)((int64_t)clampi(g_axis[kMouseY], 0, 65535) * h / 65536);
		if (!g_full) { x += TIC80_MARGIN_LEFT; y += TIC80_MARGIN_TOP; }
		in.mouse.x = (u8)x;
		in.mouse.y = (u8)y;
	}

	int n = 0;
	for (int code = 1; code <= KEY_COUNT && n < TIC80_KEY_BUFFER; code++)
		for (int k = 0; k < KEY_COUNT; k++)
			if (kKeys[k].code == code && g_held[kFirstKey + k])
				in.keyboard.keys[n++] = (tic_key)code;
	return in;
}

/* ---- the clock ----------------------------------------------------------
 * TIC-80's time() is the milliseconds since the cart started and tstamp()
 * the date in seconds; the script languages seed their random numbers from
 * the C library's clocks. All of them are given the project's Starting
 * Clock plus the frames run, at 60 a second: the same in every run and in
 * every build. These definitions take the place of the C library's for
 * everything in the core; localtime() is UTC. */
static int64_t g_startTime = 946684800;   /* the first of January 2000 */
static uint64_t g_frameCount;

static int64_t emulated_usec(void) { return (int64_t)(g_frameCount * 1000000 / TIC80_FRAMERATE); }

time_t time(time_t *t)
{
	time_t v = (time_t)(g_startTime + emulated_usec() / 1000000);
	if (t) *t = v;
	return v;
}
int gettimeofday(struct timeval *restrict tv, void *restrict tz)
{
	(void)tz;
	int64_t us = emulated_usec();
	if (tv)
	{
		tv->tv_sec = (time_t)(g_startTime + us / 1000000);
		tv->tv_usec = (suseconds_t)(us % 1000000);
	}
	return 0;
}
int clock_gettime(clockid_t id, struct timespec *ts)
{
	(void)id;
	int64_t us = emulated_usec();
	ts->tv_sec = (time_t)(g_startTime + us / 1000000);
	ts->tv_nsec = (long)(us % 1000000) * 1000;
	return 0;
}
int timespec_get(struct timespec *ts, int base)
{
	clock_gettime(CLOCK_REALTIME, ts);
	return base;
}
clock_t clock(void) { return (clock_t)emulated_usec(); }
struct tm *localtime(const time_t *t) { return gmtime(t); }
struct tm *localtime_r(const time_t *restrict t, struct tm *restrict out) { return gmtime_r(t, out); }

/* rand() is the C library's own in each build (glibc's in the native one,
 * musl's in the sandbox), and Lua's math.random and Squirrel's rand() use
 * it: it is defined here, as musl has it, so that both builds draw the same
 * numbers */
static uint64_t g_randSeed;
void srand(unsigned s) { g_randSeed = s - 1; }
int rand(void)
{
	g_randSeed = 6364136223846793005ULL * g_randSeed + 1;
	return (int)(g_randSeed >> 33);
}

/* TIC-80's own clock: the ticks of a counter and how many make a second */
static u64 tic_counter(void *data) { (void)data; return g_frameCount * 1000; }
static u64 tic_freq(void *data) { (void)data; return TIC80_FRAMERATE * 1000; }

/* ---- what the cart says ------------------------------------------------- */
static void on_trace(const char *text, u8 color)
{
	(void)color;
	if (getenv("CHIMERA_TIC80_TRACE")) fprintf(stderr, "trace: %s\n", text);
}
static void on_error(const char *info)
{
	if (strncmp(g_lastError, info, sizeof g_lastError - 1))
	{
		snprintf(g_lastError, sizeof g_lastError, "%s", info);
		fprintf(stderr, "the cart stopped with an error: %s\n", info);
	}
}
static void on_cart_exit(void) { g_exited = 1; }

/* ---- the mouse cursor ---------------------------------------------------
 * TIC-80's player draws the cursor on top of the picture when the cart
 * reads the mouse: the cart's own sprite, or one of the three arrows of
 * TIC-80's built-in cart (studio.c, blitCursor). The same is done here; the
 * Mouse Cursor setting can leave it out. It is drawn on the picture only,
 * never into the machine. */
static tic_cartridge *g_systemCart;

static void load_system_cart(void)
{
	static const u8 ConfigZip[] = {
#include "config.tic.dat"
	};
	u8 *data = malloc(TIC_CART_SAVE_SIZE);
	g_systemCart = calloc(1, sizeof *g_systemCart);
	if (!data || !g_systemCart) { free(data); return; }
	s32 size = tic_tool_unzip(data, TIC_CART_SAVE_SIZE, ConfigZip, sizeof ConfigZip);
	tic_cart_load(g_systemCart, data, size);
	free(data);
}

/* The cursor is the first video bank's, whichever bank the frame ended on.
 * TIC-80 keeps a cursor in each bank's memory and its player draws the one
 * of the bank that happens to be active; a cart that draws two layers can
 * end every other frame on the second, whose cursor is another or none,
 * and the cursor then showed on every other frame (Hollow Knight Demake,
 * chimera#318). TIC-80 itself treats the cursor as one for both banks when
 * it switches for OVR. Nothing here is the machine's: it is the picture. */
static const tic_vram *first_bank(void)
{
	tic_core *core = (tic_core *)g_mem;
	return core->state.vbank.id ? &core->state.vbank.mem : &g_mem->ram->vram;
}

static void draw_cursor(void)
{
	tic80_mouse *m = &g_mem->ram->input.mouse;
	if (!g_drawCursor || !g_mem->input.mouse || m->relative || (s32)m->y >= TIC80_FULLHEIGHT) return;
	const tic_vram *v = first_bank();
	s32 sprite = clampi(v->vars.cursor.sprite, 0, TIC_BANK_SPRITES - 1);
	const tic_bank *bank = &g_mem->cart.bank0;
	tic_point hot = { 0, 0 };
	if (v->vars.cursor.system)
	{
		if (!g_systemCart) return;
		bank = &g_systemCart->bank0;
		static const tic_point kHot[3] = { { 0, 0 }, { 3, 0 }, { 2, 3 } };
		hot = kHot[clampi(sprite, 0, 2)];
	}
	else if (sprite == 0)
		return;
	const tic_palette *pal = &bank->palette.vbank0;
	const tic_tile *tile = &bank->sprites.data[sprite];
	s32 sx = m->x - hot.x, sy = m->y - hot.y;
	for (s32 i = 0; i < TIC_SPRITESIZE * TIC_SPRITESIZE; i++)
	{
		s32 x = sx + i % TIC_SPRITESIZE, y = sy + i / TIC_SPRITESIZE;
		if (x < 0 || y < 0 || x >= TIC80_FULLWIDTH || y >= TIC80_FULLHEIGHT) continue;
		u8 c = tic_tool_peek4(tile->data, i);
		if (!c) continue;
		const tic_rgb *rgb = &pal->colors[c];
		g_picture[y * TIC80_FULLWIDTH + x] = 0xFF000000u | (uint32_t)rgb->r << 16 | (uint32_t)rgb->g << 8 | rgb->b;
	}
}

static void take_picture(void)
{
	/* BGRA8888 in TIC-80's words is 0xAARRGGBB in a little-endian word, as
	 * Chimera takes it */
	const uint32_t *src = g_tic->screen;
	for (int i = 0; i < TIC80_FULLWIDTH * TIC80_FULLHEIGHT; i++)
		g_picture[i] = src[i] | 0xFF000000u;
	draw_cursor();
	if (!g_full)
		for (int y = 0; y < TIC80_HEIGHT; y++)
			memmove(g_picture + y * TIC80_WIDTH,
				g_picture + (y + TIC80_MARGIN_TOP) * TIC80_FULLWIDTH + TIC80_MARGIN_LEFT,
				TIC80_WIDTH * sizeof(uint32_t));
}

/* ---- files -------------------------------------------------------------- */
static void *read_file(const char *name, long *size)
{
	FILE *f = fopen(name, "rb");
	if (!f) return NULL;
	fseek(f, 0, SEEK_END);
	long n = ftell(f);
	fseek(f, 0, SEEK_SET);
	void *data = n > 0 ? malloc((size_t)n) : NULL;
	if (data && fread(data, 1, (size_t)n, f) != (size_t)n) { free(data); data = NULL; }
	fclose(f);
	*size = n;
	return data;
}

static int setting_is(const char *name, const char *value, int otherwise)
{
	char v[32];
	if (wbx_setting_str(name, v, sizeof v) <= 0) return otherwise;
	return !strcmp(v, value);
}

/* ---- Chimera's calls ---------------------------------------------------- */
ECL_EXPORT const char *GetLoadError(void) { return g_loadError; }
ECL_EXPORT const char *SuggestSettings(void) { return "{\"values\":{},\"note\":\"\",\"firmware\":[]}"; }
ECL_EXPORT const char *DescribeDips(void) { return ""; }

ECL_EXPORT int Init(void)
{
	g_loadError[0] = '\0';
	g_cartName[0] = '\0';
	if (wbx_slot_count("cart") > 0)
		wbx_slot_name("cart", 0, g_cartName, sizeof g_cartName);
	else
	{
		/* a cart opened with no project is mounted under its own name */
		FILE *f = fopen("rom.name", "rb");
		if (f)
		{
			size_t got = fread(g_cartName, 1, sizeof g_cartName - 1, f);
			g_cartName[got] = '\0';
			fclose(f);
		}
	}
	if (!g_cartName[0])
	{
		snprintf(g_loadError, sizeof g_loadError, "error.no_file");
		return 0;
	}
	long size = 0;
	void *cart = read_file(g_cartName, &size);
	if (!cart)
	{
		snprintf(g_loadError, sizeof g_loadError, "error.not_read" TEXT_ARG "%s", g_cartName);
		return 0;
	}

	{
		char v[32];
		if (wbx_setting_str("initialTime", v, sizeof v) > 0) g_startTime = strtoll(v, NULL, 10);
	}
	g_frameCount = 0;
	g_full = !setting_is("picture", "screen", 0);
	g_drawCursor = setting_is("mouseCursor", "show", 1);

	for (int p = 0; p < kPads; p++)
		for (int b = 0; b < kPadButtons; b++)
			snprintf(g_buttonNames[p * kPadButtons + b], sizeof g_buttonNames[0], "P%d %s", p + 1, kPadNames[b]);
	snprintf(g_buttonNames[kMouseLeft], sizeof g_buttonNames[0], "Mouse Left");
	snprintf(g_buttonNames[kMouseMiddle], sizeof g_buttonNames[0], "Mouse Middle");
	snprintf(g_buttonNames[kMouseRight], sizeof g_buttonNames[0], "Mouse Right");
	for (int k = 0; k < KEY_COUNT; k++)
		snprintf(g_buttonNames[kFirstKey + k], sizeof g_buttonNames[0], "Key %s", kKeys[k].name);

	g_tic = tic80_create(TIC80_SAMPLERATE, TIC80_PIXEL_COLOR_BGRA8888);
	if (!g_tic)
	{
		free(cart);
		snprintf(g_loadError, sizeof g_loadError, "error.not_started");
		return 0;
	}
	g_mem = (tic_mem *)g_tic;
	g_tic->callback.trace = on_trace;
	g_tic->callback.error = on_error;
	g_tic->callback.exit = on_cart_exit;
	tic80_load(g_tic, cart, (s32)size);
	free(cart);

	/* a cart whose language is not in this core (Ruby), or with no code */
	if (!g_mem->cart.code.data[0] && !g_mem->cart.binary.size)
	{
		snprintf(g_loadError, sizeof g_loadError, "error.not_cart" TEXT_ARG "%s", g_cartName);
		return 0;
	}
	/* TIC-80 runs a cart whose language it does not find as Lua; a cart that
	 * names a language this core does not have (Ruby) is refused instead */
	{
		int known = 0;
		FOREACH_LANG(script)
		{
			if (script->id == g_mem->cart.lang
				|| !strcmp(tic_tool_metatag(g_mem->cart.code.data, "script", script->singleComment), script->name))
				known = 1;
		}
		const char *lang = tic_tool_metatag(g_mem->cart.code.data, "script", NULL);
		if (!known && *lang)
		{
			snprintf(g_loadError, sizeof g_loadError, "error.language" TEXT_ARG "%s", lang);
			return 0;
		}
	}

	/* the cart's saved values (pmem), from the project's save data */
	if (wbx_slot_count("savedata") > 0)
	{
		char name[256];
		if (wbx_slot_name("savedata", 0, name, sizeof name))
		{
			long n = 0;
			void *data = read_file(name, &n);
			if (data)
			{
				memcpy(&g_mem->ram->persistent, data, n < (long)sizeof(tic_persistent) ? (size_t)n : sizeof(tic_persistent));
				free(data);
			}
		}
	}

	load_system_cart();
	memset(g_picture, 0, sizeof g_picture);
	return 1;
}

ECL_EXPORT int GetButtonCount(void) { return BUTTON_COUNT; }
ECL_EXPORT const char *GetButtonName(int32_t i) { return i >= 0 && i < BUTTON_COUNT ? g_buttonNames[i] : ""; }
ECL_EXPORT int IsButtonActive(int32_t i) { return i >= 0 && i < BUTTON_COUNT; }
ECL_EXPORT void SetButton(int32_t i, int32_t state)
{
	if (i >= 0 && i < BUTTON_COUNT) g_held[i] = state != 0;
}

ECL_EXPORT int GetAxisCount(void) { return kAxes; }
ECL_EXPORT const char *GetAxisName(int32_t i) { return i >= 0 && i < kAxes ? kAxisNames[i] : ""; }
ECL_EXPORT int IsAxisActive(int32_t i) { return i >= 0 && i < kAxes; }
ECL_EXPORT void SetAxis(int32_t i, int32_t value)
{
	if (i >= 0 && i < kAxes) g_axis[i] = value;
}

ECL_EXPORT void FrameAdvance(uint64_t packed)
{
	(void)packed;
	g_audioFrames = 0;
	g_inputReads = 0;
	if (!g_exited)
	{
		tic80_tick(g_tic, make_input(), tic_counter, tic_freq);
		tic80_sound(g_tic);
		int n = g_tic->samples.count / TIC80_SAMPLE_CHANNELS;
		if (n > MAX_SAMPLES) n = MAX_SAMPLES;
		memcpy(g_audio, g_tic->samples.buffer, (size_t)n * TIC80_SAMPLE_CHANNELS * sizeof(int16_t));
		g_audioFrames = n;
	}
	else
	{
		/* after exit() the machine is still: a frame of silence */
		g_audioFrames = TIC80_SAMPLERATE / TIC80_FRAMERATE;
		memset(g_audio, 0, (size_t)g_audioFrames * 2 * sizeof(int16_t));
	}
	g_frameCount++;
	g_inputRead = g_inputReads > 0;
	if (g_render) take_picture();
}

ECL_EXPORT int InputWasRead(void) { return g_inputRead; }
ECL_EXPORT void SetRenderingEnabled(int on) { g_render = on != 0; }

ECL_EXPORT uint32_t *GetVideoBgra(void) { return g_picture; }
ECL_EXPORT int GetVideoWidth(void) { return g_full ? TIC80_FULLWIDTH : TIC80_WIDTH; }
ECL_EXPORT int GetVideoHeight(void) { return g_full ? TIC80_FULLHEIGHT : TIC80_HEIGHT; }
ECL_EXPORT int GetDisplayAspectX(void) { return GetVideoWidth(); }
ECL_EXPORT int GetDisplayAspectY(void) { return GetVideoHeight(); }
ECL_EXPORT int GetVsyncNumerator(void) { return TIC80_FRAMERATE; }
ECL_EXPORT int GetVsyncDenominator(void) { return 1; }

ECL_EXPORT int16_t *GetAudio(void) { return g_audio; }
ECL_EXPORT int GetAudioSampleCount(void) { return g_audioFrames; }

/* the machine's 96 KB of memory, as a cart's peek() and poke() see it */
ECL_EXPORT int GetMemoryDomainCount(void) { return 1; }
ECL_EXPORT const char *GetMemoryDomainName(int i) { return i == 0 ? "RAM" : ""; }
ECL_EXPORT uint8_t *GetMemoryDomainPtr(int i) { return i == 0 && g_mem ? g_mem->ram->data : NULL; }
ECL_EXPORT int64_t GetMemoryDomainSize(int i) { return i == 0 ? TIC_RAM_SIZE : 0; }
ECL_EXPORT int GetMemoryDomainWritable(int i) { return i == 0; }

ECL_EXPORT const int64_t *GetBusRanges(int32_t bus) { (void)bus; return NULL; }
ECL_EXPORT const uint8_t *ReadBus(int32_t bus, int64_t addr, int32_t len) { (void)bus; (void)addr; (void)len; return NULL; }
ECL_EXPORT void PokeBus(int32_t bus, int32_t addr, int32_t value) { (void)bus; (void)addr; (void)value; }

/* Export Save Data: the cart's saved values (pmem), 1 KB, once it has any */
static char g_saveName[300];
static int has_pmem(void)
{
	for (size_t i = 0; i < sizeof(tic_persistent); i++)
		if (((const u8 *)&g_mem->ram->persistent)[i]) return 1;
	return 0;
}
ECL_EXPORT int32_t GetSaveDataFileCount(void)
{
	if (!g_mem || !has_pmem()) return 0;
	snprintf(g_saveName, sizeof g_saveName, "%s", g_cartName);
	char *dot = strrchr(g_saveName, '.');
	if (dot) *dot = '\0';
	strcat(g_saveName, ".pmem");
	return 1;
}
ECL_EXPORT const char *GetSaveDataFileName(int32_t i) { return i == 0 ? g_saveName : ""; }
ECL_EXPORT int64_t GetSaveDataFileSize(int32_t i) { return i == 0 ? (int64_t)sizeof(tic_persistent) : 0; }
ECL_EXPORT const uint8_t *GetSaveDataFileBuffer(int32_t i) { return i == 0 && g_mem ? (const uint8_t *)&g_mem->ram->persistent : NULL; }
