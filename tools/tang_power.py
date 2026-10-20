#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Switch the Tang's power and choose the mode it boots in, from this PC.

The board's power input runs through one relay of a dcttech USBRelay8
(16c0:05df) on its normally open contact, so the relay energised is the board
powered. The OTG cable to the PC has its VBUS wire cut, so the PC cannot keep
the board alive and the relay is a true power switch. Which program the BL616
runs is chosen at a cold power-up: a USB host on the OTG port then brings up
Sipeed's FT2232 debugger (one-wire), and none brings up TinyTang's CDC
(two-wire). The PC hides itself from the board by disabling the OTG cable's
USB port, which stops the data and nothing else, so a two-wire boot is the
port disabled, the board powered off and on, the loader given time to choose,
and the port enabled again.

    tang_power.py status
    tang_power.py on | off
    tang_power.py cycle [--mode two-wire|one-wire]

`cycle` waits for the mode it asked for and fails unless it arrives: two-wire
must answer on TinyTang's console, one-wire must enumerate as the debugger.
The port is the one the Tang is plugged into, read from where the board shows
up on the bus in either mode and remembered in build/ for when it is off;
TINYCREATURE_TANG_USB_PORT names one instead, and a cycle refuses if the board
is on another. TINYCREATURE_POWER_RELAY names the relay, 1 by default. The
relay board and the port both need write access for this user, which
README.md's udev rules give the plugdev group.
"""
import argparse
import fcntl
import glob
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RELAY_ID = "0003:000016C0:000005DF"
USB = "/sys/bus/usb/devices"
TANG_IDS = ("ffff:5454", "0403:6010")   # TinyTang's CDC, Sipeed's debugger
PORT_MEMO = os.path.join(ROOT, "build", "tang_power.port")
TINYTANG_CDC = "/dev/serial/by-id/usb-TinyTang_TinyTang_CDC_*"
DEBUGGER = "/dev/serial/by-id/usb-SIPEED_USB_Debugger_*"


def ioc(nr, size):
    """A hidraw feature-report ioctl: HIDIOCSFEATURE is 6, HIDIOCGFEATURE 7."""
    return (3 << 30) | (size << 16) | (ord("H") << 8) | nr


class Relays:
    """The relay board, found by its HID ID rather than a fixed hidraw number,
    which moves when anything else is plugged in. A report is the report ID
    and eight bytes: 0xff or 0xfd and a relay number switch one relay on or
    off, and a read returns the board's serial in bytes 1 to 5 and the relays'
    state as a bitmask in byte 8."""

    def __init__(self):
        for node in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
            with open(os.path.join(node, "device", "uevent")) as f:
                if f"HID_ID={RELAY_ID}" in f.read():
                    self.path = "/dev/" + os.path.basename(node)
                    break
        else:
            sys.exit("tang_power: no USBRelay8 (16c0:05df) is plugged in")
        try:
            self.fd = os.open(self.path, os.O_RDWR)
        except PermissionError:
            sys.exit(f"tang_power: {self.path} is not writable; install the "
                     "relay board's udev rule from README.md")

    def state(self):
        report = bytearray(9)
        fcntl.ioctl(self.fd, ioc(0x07, 9), report)
        return report[8]

    def set(self, relay, on):
        report = bytearray(9)
        report[1] = 0xFF if on else 0xFD
        report[2] = relay
        fcntl.ioctl(self.fd, ioc(0x06, 9), report)
        if bool(self.state() >> (relay - 1) & 1) != on:
            sys.exit(f"tang_power: relay {relay} did not switch {'on' if on else 'off'}")


def tang_port():
    """The sysfs directory of the port the Tang is plugged into, if it is on the
    bus in either mode: a device named 1-7.2 hangs off port 2 of hub 1-7, and
    one named 1-5 off port 5 of bus 1's root hub."""
    for dev in sorted(glob.glob(os.path.join(USB, "*"))):
        try:
            with open(os.path.join(dev, "idVendor")) as f:
                vid = f.read().strip()
            with open(os.path.join(dev, "idProduct")) as f:
                pid = f.read().strip()
        except OSError:
            continue
        if f"{vid}:{pid}" not in TANG_IDS:
            continue
        name = os.path.basename(dev)
        bus, path = name.split("-", 1)
        hops = path.split(".")
        if len(hops) == 1:
            hub, interface, port = f"usb{bus}", f"{bus}-0:1.0", f"usb{bus}-port{hops[0]}"
        else:
            hub = f"{bus}-" + ".".join(hops[:-1])
            interface, port = f"{hub}:1.0", f"{hub}-port{hops[-1]}"
        return os.path.join(USB, hub, interface, port)
    return None


def choose_port():
    """The port to switch: the one the Tang is on now, or the one it was last
    seen on, which a board that is off or hidden behind a disabled port needs;
    an override that disagrees with where the board is refuses outright."""
    here = tang_port()
    named = os.environ.get("TINYCREATURE_TANG_USB_PORT")
    if named:
        if here and os.path.realpath(here) != os.path.realpath(named):
            sys.exit(f"tang_power: TINYCREATURE_TANG_USB_PORT is {named} but the "
                     f"Tang is on {here}")
        return named
    if here:
        os.makedirs(os.path.dirname(PORT_MEMO), exist_ok=True)
        with open(PORT_MEMO, "w") as f:
            f.write(here + "\n")
        return here
    try:
        with open(PORT_MEMO) as f:
            return f.read().strip()
    except OSError:
        sys.exit("tang_power: the Tang is not on the bus and no port is "
                 "remembered; power it on with its OTG cable plugged in once, "
                 "or set TINYCREATURE_TANG_USB_PORT")


def port_disable(port, disable):
    try:
        with open(os.path.join(port, "disable"), "w") as f:
            f.write("1" if disable else "0")
    except PermissionError:
        sys.exit(f"tang_power: {port}/disable is not writable; install the "
                 "port's udev rule from README.md")


def port_disabled(port):
    with open(os.path.join(port, "disable")) as f:
        return f.read().strip() == "1"


def mode_seen():
    if glob.glob(TINYTANG_CDC):
        return "two-wire"
    if glob.glob(DEBUGGER):
        return "one-wire"
    return "none"


def wait_for(mode, seconds):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        seen = mode_seen()
        if seen != "none":
            return seen
        time.sleep(0.1)
    return "none"


def console_answers(seconds):
    """TinyTang's shell, asked to echo a word back: the CDC enumerating says the
    firmware started, an answer says it is running. The shell is not at a
    prompt until the boot script has run, which is after the CDC enumerates,
    so the question is asked until it is answered or the time is up."""
    tinytang = os.environ.get("TINYTANG_DIR", os.path.join(os.path.dirname(ROOT), "TinyTang"))
    tool = os.path.join(tinytang, "tools", "tinytang_run.py")
    if not os.path.exists(tool):
        sys.exit(f"tang_power: {tool} is missing; set TINYTANG_DIR")
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        found = glob.glob(TINYTANG_CDC)
        if found:
            try:
                result = subprocess.run(
                    [sys.executable, tool, "--port", os.path.realpath(found[0]),
                     "--seconds", "1", "--wait", "5", "echo tang_power: console-ok"],
                    capture_output=True, text=True, timeout=30)
                if "\ntang_power: console-ok" in result.stdout:
                    return True
            except subprocess.TimeoutExpired:
                pass
        time.sleep(1)
    return False


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("action", choices=["status", "on", "off", "cycle"])
    ap.add_argument("--mode", choices=["two-wire", "one-wire"], default="two-wire")
    ap.add_argument("--off-seconds", type=float, default=5.0,
                    help="how long the board stays unpowered in a cycle")
    ap.add_argument("--choose-seconds", type=float, default=6.0,
                    help="how long the loader is given to choose before the port returns")
    ap.add_argument("--timeout", type=float, default=30.0,
                    help="how long a cycle waits for the mode it asked for")
    args = ap.parse_args()
    relay = int(os.environ.get("TINYCREATURE_POWER_RELAY", "1"))
    relays = Relays()
    port = choose_port()

    if args.action == "status":
        powered = bool(relays.state() >> (relay - 1) & 1)
        print(f"relay {relay} {'on' if powered else 'off'} ({relays.path}, "
              f"relays {relays.state():08b}); port {os.path.basename(port)} "
              f"{'disabled' if port_disabled(port) else 'enabled'}; mode {mode_seen()}")
        return
    if args.action in ("on", "off"):
        relays.set(relay, args.action == "on")
        print(f"relay {relay} {args.action}")
        return

    start = time.monotonic()

    def say(text):
        print(f"{time.monotonic() - start:5.1f}s {text}", flush=True)

    # The port goes before the power: while it is disabled the board sees no
    # host, whatever was running, and the cut VBUS means it is the relay alone
    # that powers the board.
    port_disable(port, args.mode == "two-wire")
    say(f"port {os.path.basename(port)} {'disabled' if args.mode == 'two-wire' else 'enabled'}")
    relays.set(relay, False)
    say(f"relay {relay} off")
    time.sleep(args.off_seconds)
    relays.set(relay, True)
    say(f"relay {relay} on")
    if args.mode == "two-wire":
        time.sleep(args.choose_seconds)
        port_disable(port, False)
        say(f"port {os.path.basename(port)} enabled")
    seen = wait_for(args.mode, args.timeout)
    say(f"mode {seen}")
    if seen != args.mode:
        sys.exit(f"tang_power: asked for {args.mode}, the board came up {seen}")
    if seen == "two-wire":
        if not console_answers(args.timeout):
            sys.exit("tang_power: TinyTang's CDC enumerated but its console did not answer")
        say("TinyTang's console answers")


if __name__ == "__main__":
    main()
