// SPDX-License-Identifier: GPL-3.0-or-later
//
// TinyCreature's launcher-only keyboard contract. TinyTang sends the
// Bluetooth keyboard's modifier and six HID usage slots as frame type 0x17.
// (The reserved byte from the raw eight-byte boot report is not put on this
// wire.) The interactive player treats Escape and F12 as requests to finish
// cleanly, so the launcher task can restore the desktop core.
#ifndef TINYCREATURE_LAUNCHER_H
#define TINYCREATURE_LAUNCHER_H

#include <stdint.h>

#define TC_FRAME_KEYBOARD     0x17u
#define TC_KEYBOARD_PAYLOAD   7u
#define TC_KEY_ESCAPE         0x29u
#define TC_KEY_F12            0x45u

static inline int tc_launcher_quit_report(const uint8_t report[TC_KEYBOARD_PAYLOAD])
{
	/* Byte 0 is the modifier; bytes 1..6 are the six usage slots. */
	for (unsigned i = 1; i < TC_KEYBOARD_PAYLOAD; i++)
		if (report[i] == TC_KEY_ESCAPE || report[i] == TC_KEY_F12)
			return 1;
	return 0;
}

#endif
