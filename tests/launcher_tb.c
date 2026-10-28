// SPDX-License-Identifier: GPL-3.0-or-later
#include <assert.h>
#include <stdint.h>

#include "launcher.h"

_Static_assert(TC_KEYBOARD_PAYLOAD == 7,
               "TinyTang omits the raw HID report's reserved byte");

int main(void)
{
	uint8_t report[TC_KEYBOARD_PAYLOAD] = {0};

	assert(!tc_launcher_quit_report(report));
	report[2] = 0x04; /* A */
	assert(!tc_launcher_quit_report(report));
	report[6] = TC_KEY_ESCAPE;
	assert(tc_launcher_quit_report(report));
	report[6] = 0;
	report[1] = TC_KEY_F12; /* the first usage slot */
	assert(tc_launcher_quit_report(report));
	report[1] = 0;
	report[0] = TC_KEY_F12; /* the modifier byte is not a usage slot */
	assert(!tc_launcher_quit_report(report));
	return 0;
}
