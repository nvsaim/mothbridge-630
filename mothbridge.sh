#!/bin/bash
# MothBridge 630 - lets the NVIDIA GPU of a muxless Coffee Lake laptop (UHD 630 + Turing GTX/RTX, no display
# outputs on the NVIDIA side) draw the macOS desktop, and shows its frames on the built-in panel through the Intel GPU.
#
#   bash mothbridge.sh build          download sources and build NMIntelFB + NVAccel (no sudo, ~10 min)
#   sudo bash mothbridge.sh install   install them, the boot helper and the settings (NullMoth 2.6.3 must be installed)
#   sudo bash mothbridge.sh remove    undo install (NullMoth itself stays)
#   bash mothbridge.sh status         show whether the GTX is drawing the desktop
#
# Builds on NullMoth (github.com/nullmoth/nvidia-macos-driver) and nmx-intel (github.com/kitsuneislife/nmx-intel).
# Nothing from them is copied here: build downloads them. Authors: nvsaim and Claude.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
U=${SUDO_USER:-$USER}; UH=$(eval echo ~"$U")
W=$UH/nmx-build                       # nmx-intel's scripts expect their sources here
NMX=$UH/nmx-intel
NM_TAG=v2.6.3                         # NullMoth release this was tested with
NMX_REV=b4bb3a0                       # nmx-intel commit this was tested with
OGKM_TAG=615.78.08                    # NVIDIA open-gpu-kernel-modules tag NullMoth 2.6.x builds against
die() { echo "ERROR: $*" >&2; exit 1; }
step() { echo; echo "== $*"; }

check_hw() {
  local pci; pci=$(ioreg -r -c IOPCIDevice -d1 2>/dev/null || true)   # read once: grep -q would cut the pipe
  case "$pci" in *'"device-id" = <9b3e0000>'*) ;; *) echo "WARNING: no Intel UHD 630 (8086:3E9B) found. MothBridge 630 is tested only on that GPU.";; esac
  case "$pci" in *'"vendor-id" = <de100000>'*) ;; *) echo "WARNING: macOS does not see the NVIDIA GPU now. NullMoth's installer turns it on (README step 2).";; esac
}

build() {
  [ "$(id -u)" != 0 ] || die "run build without sudo"
  xcode-select -p >/dev/null 2>&1 || die "install the Xcode command line tools first: xcode-select --install"
  check_hw
  mkdir -p "$W"
  step "1/5 NullMoth source ($NM_TAG)"
  [ -d "$W/nvidia-macos-driver/.git" ] || git clone --filter=blob:none https://github.com/nullmoth/nvidia-macos-driver "$W/nvidia-macos-driver"
  git -C "$W/nvidia-macos-driver" fetch --tags -q
  step "2/5 nmx-intel ($NMX_REV)"
  [ -d "$NMX/.git" ] || git clone https://github.com/kitsuneislife/nmx-intel "$NMX"
  git -C "$NMX" checkout -q "$NMX_REV" -- source-fixes tools
  cp "$HERE"/patches/intelfb-90*.patch "$NMX/source-fixes/intelfb/"
  grep -q blank_hold "$NMX/tools/intelfb/auto.sh" || patch -s -d "$NMX" -p1 < "$HERE/patches/auto-sh-blank-hold-and-boot-log.patch"
  step "3/5 NVIDIA kernel headers ($OGKM_TAG)"
  [ -d "$UH/ogkm615/src" ] || git clone -q --depth 1 --branch "$OGKM_TAG" https://github.com/NVIDIA/open-gpu-kernel-modules "$UH/ogkm615"
  step "4/5 build NMIntelFB (Intel panel framebuffer)"
  NM="$W/nvidia-macos-driver" bash "$NMX/tools/intelfb/build.sh" 2>&1 | tail -3
  step "5/5 build NVAccel $NM_TAG with the fast-copy and RAM-flip patches"
  S="$W/accel/src-263"
  if [ ! -d "$S" ]; then
    git -C "$W/nvidia-macos-driver" worktree add -q -b mothbridge-263 "$S" "$NM_TAG"
    git -C "$S" -c user.name=mothbridge -c user.email=mothbridge@local am -q "$NMX"/source-fixes/accel/v2.6.4/*.patch
  fi
  SRC="$S" OUT="$W/accel/out-263" OGKM="$UH/ogkm615" bash "$NMX/tools/accel/build.sh" 2>&1 | tail -2
  [ -d "$W/intelfb/out/NMIntelFB.kext" ] && [ -d "$W/accel/out-263/NVAccel.kext" ] || die "build failed (see above)"
  echo; echo "Build done. Next: sudo bash mothbridge.sh install"
}

install() {
  [ "$(id -u)" = 0 ] || die "run install with sudo"
  [ "$(cat /Library/NullMoth/driver-version 2>/dev/null)" = 2.6.3 ] || die "install NullMoth 2.6.3 first (README step 2)"
  [ -d "$W/intelfb/out/NMIntelFB.kext" ] && [ -d "$W/accel/out-263/NVAccel.kext" ] || die "run: bash mothbridge.sh build"
  step "1/4 NMIntelFB"
  bash "$NMX/tools/intelfb/install.sh" 2>&1 | tail -2
  step "2/4 patched NVAccel (rebuilds the kext collection, 1-2 min)"
  SRC="$W/accel/out-263/NVAccel.kext" bash "$NMX/tools/accel/install.sh" 2>&1 | tail -3
  step "3/4 boot helper (turns on GTX frames, fast copy, RAM flip and blank hold after each boot)"
  (cd "$NMX/tools/intelfb" && bash auto.sh install 2>&1 | tail -1)
  step "4/4 settings"
  nvram nullmoth-intelfb-gen9=1          # let NMIntelFB take the Coffee Lake panel
  nvram nullmoth-intelfb-delay=30        # wait before taking the panel
  nvram nullmoth-accel-ram=2             # RAM flip: no tearing
  nvram nullmoth-intelfb-backlight=1     # brightness keys and slider
  pmset -a disablesleep 1                # sleep blanks the Intel display engine: keep it off
  echo; echo "Installed. Now add  -nvaccelnoheadless nvrmsettle=10000  to boot-args in OpenCore config.plist (README step 4), then reboot."
}

remove() {
  [ "$(id -u)" = 0 ] || die "run remove with sudo"
  (cd "$NMX/tools/intelfb" && bash auto.sh remove 2>&1 | tail -1) || true
  bash "$NMX/tools/intelfb/install.sh" remove 2>&1 | tail -1 || true
  [ -d "$UH/NVAccel.kext.original" ] && bash "$NMX/tools/accel/install.sh" restore 2>&1 | tail -1 || true
  for v in nullmoth-intelfb-gen9 nullmoth-intelfb-delay nullmoth-accel-ram nullmoth-intelfb-backlight nullmoth-accel-hold; do nvram -d $v 2>/dev/null || true; done
  pmset -a disablesleep 0
  echo; echo "Removed. Take  -nvaccelnoheadless nvrmsettle=10000  out of config.plist boot-args, then reboot."
}

status() {
  r() { sysctl -n "debug.$1" 2>/dev/null || echo "-"; }
  echo "NullMoth $(cat /Library/NullMoth/driver-version 2>/dev/null || echo none)"
  echo "headless $(r nvaccel_headless) (0 = GTX draws the desktop)"
  echo "frames on panel $(r nvaccel_iop_ok), failed $(r nvaccel_iop_fail)"
  echo "copy mode $(r nvaccel_iop_direct) / RAM flip $(r nmintelfb_ram) (2 / 2 = fast, no tearing)"
  echo "blank frames held $(r nvaccel_iop_blank_held) (hold $(r nvaccel_iop_blank_hold))"
  [ -f /var/log/nmx-intelfb-auto.log ] && { echo "boot helper:"; tail -5 /var/log/nmx-intelfb-auto.log; }
}

case "${1:-}" in
  build) build;; install) install;; remove) remove;; status) status;;
  *) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//';;
esac
