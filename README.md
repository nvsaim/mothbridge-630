# MothBridge 630

**The NVIDIA GPU draws the macOS desktop on a muxless Optimus laptop, and the Intel UHD 630 shows it on the built-in screen.**

By **nvsaim** and **Claude** (Anthropic). Tested on one laptop, November 2026. Experimental: read the cons before you install.

---

## Who this is for

Only for laptops like this:

- The integrated GPU is an **Intel UHD 630** (Coffee Lake, 8th/9th gen Core, device id `8086:3E9B`).
- The NVIDIA GPU is a **Turing** card (GTX 16xx or RTX 20xx) with **no display outputs of its own**. Every screen, the built-in panel and the HDMI port, is wired to the Intel GPU. This is called a *muxless Optimus* laptop.
- **macOS 15 Sequoia** with **OpenCore**.

On such a laptop macOS normally cannot use the NVIDIA GPU at all. [NullMoth](https://github.com/nullmoth/nvidia-macos-driver) gives macOS a driver for it, but with no screen attached to the NVIDIA GPU, NullMoth cannot show the desktop it draws. MothBridge 630 builds the bridge: the GTX draws (composites) the desktop and the Intel GPU puts the frames on the panel.

**Not for:** laptops where a screen is wired to the NVIDIA GPU (use NullMoth alone), other Intel GPUs (Ice Lake, Tiger Lake, Xe), AMD, or desktops.

## Tested on

| | |
|---|---|
| Laptop | MSI GF63 Thin 9SCXR |
| CPU | Intel Core i5-9300H |
| iGPU | Intel UHD 630 (`8086:3E9B`), drives the eDP panel and HDMI (HDMI through an LSPCON chip) |
| dGPU | NVIDIA GTX 1650 with Max-Q (`10DE:1F99`, TU117), 4 GB, no display outputs, 256 MB BAR1 |
| Panel | 1920×1080, 59.73 Hz |
| macOS | 15.7.8 Sequoia, OpenCore |
| Base EFI | [rahulhingve/Hackintosh-Msi-GF63-Thin-9SCXR-Sonoma](https://github.com/rahulhingve/Hackintosh-Msi-GF63-Thin-9SCXR-Sonoma) |
| NullMoth | 2.6.3 (2.5.2 also tested) |

## What it does

1. **Starts the GTX as the desktop GPU.** NullMoth gives up and marks the GTX "headless" after 60 s when no screen is found. On this hardware the NVIDIA driver itself waits 100 s first, so NullMoth always gave up before the panel was ready. The boot-arg `-nvaccelnoheadless` stops that.
2. **Takes the panel from Apple's Intel driver.** NMIntelFB (from NullMoth, built with nmx-intel's patches) drives the panel the firmware already turned on, and offers it to the NVIDIA driver as its screen. MothBridge adds patch `9022` so NMIntelFB accepts a Coffee Lake (Gen 9) GPU, and `9023` to stop it writing logs into NVRAM.
3. **Moves each frame fast.** The GTX copy engine writes each finished frame straight into the panel's memory (about 0.8 ms per frame). Stock NullMoth copies it word by word with the CPU (about 30 fps).
4. **Removes tearing.** Patch `9024` turns on the *RAM flip* on Gen 9: two buffers in system memory, and the panel switches between them only at vertical blank.
5. **Hides black flashes.** Up to 30 one-colour frames in a row are kept off the panel (`blank hold`).
6. **Brightness keys and slider work** (`nullmoth-intelfb-backlight=1`).
7. **Boots about 90 s faster** (`nvrmsettle=10000`: the 10 s wait NullMoth already uses for other Turing cards, instead of 100 s).
8. **A boot helper** (`auto.sh`, a LaunchDaemon) turns all of this on about 75 s after each boot and logs each step to `/var/log/nmx-intelfb-auto.log`.

## What worked (results on the test laptop)

- The GTX 1650 composites the whole desktop. *About This Mac* lists the GTX 1650, and *System Information* shows the built-in panel under the GTX as **Main Display**. Apple's Intel framebuffer is gone.
- **75–83 fps** while dragging windows (panel is 59.73 Hz), copy time **0.7–1 ms** per frame, **0 late flips**, **0 failed frames**.
- **No tearing** with the RAM flip.
- **Brightness** keys and slider work.
- **Chrome WebGL** works on the GTX with NullMoth 2.6.3.
- The panel shows the first GTX frame about **120 s** after power-on, down from about 212 s.

## Cons (read all of these)

- **HDMI does not work.** The HDMI port hangs off the Intel GPU through an LSPCON chip. NMIntelFB only takes over the screen the firmware turned on (the panel). Driving HDMI would mean writing a full DisplayPort and LSPCON mode-setting driver.
- **Sleep must stay off.** Sleep turns off the Intel display engine and the panel stays black. `install` sets `pmset -a disablesleep 1`.
- **Slow boot.** The panel stays on the frozen boot picture for about 2 minutes, then the desktop appears. Expect another 2 s pause right after you log in, while macOS starts Dock, Finder and login items.
- **Black flicker on NullMoth 2.6.x.** NullMoth 2.6.5 and 2.6.6 show black patches over parts of the screen. 2.6.3 shows fewer, but some remain. 2.5.2 has none, but apps crash on it. The cause is in NullMoth's Metal plugin, not in the bridge.
- **Apps crash.** After Effects and other pro apps crashed on NullMoth 2.5.2 and later versions. NullMoth's Metal support is still incomplete.
- **NullMoth 2.7.x hangs at boot** on this laptop, at the Apple logo near the end of the progress bar, with both stock and patched NVAccel. The 1401 app always offers the newest driver, so **never update NullMoth through the 1401 app**.
- **Worse battery and more heat.** The GTX stays on the whole time.
- **Security is lowered.** NullMoth needs `amfi_get_out_of_my_way=0x1 amfi=0x80 ipc_control_port_options=0` and a relaxed SIP setting.
- **Screen apps hurt it.** Screen-capture and ambient-light apps (Hyperion, for example) cut it to about 27 fps.
- **One laptop tested.** Other UHD 630 laptops should behave the same, but nobody has tried.
- **A hybrid mode was tried and is useless.** In it the Intel GPU draws the desktop, HDMI and sleep work, and the GTX is offered only to apps. But Chrome cannot use the GTX that way (acceleration turns off), and Blender's Cycles does not list it (Blender's Metal render path accepts only Apple and AMD GPUs).
- **Experimental, no warranty.** A mistake in OpenCore can stop the Mac booting. Keep a USB installer and a backup EFI.

## Before you start

- Back up your EFI folder and keep a bootable USB stick that works.
- Install the Xcode command line tools: `xcode-select --install`
- Your laptop must already boot macOS with the Intel GPU working (panel, brightness and audio fine).
- Know how to mount your EFI partition and edit `EFI/OC/config.plist` (ProperTree or any plist editor).

## Install (5 steps)

### 1. Get MothBridge 630

```bash
git clone https://github.com/nvsaim/mothbridge-630 ~/mothbridge-630
```

### 2. Install NullMoth 2.6.3

The 1401 app installs only the newest driver (2.7.x, which hangs). Use it for the OpenCore setup, then put 2.6.3 over it **before you restart**:

1. Download the 1401 app from [NullMoth's releases](https://github.com/nullmoth/nvidia-macos-driver/releases) and install the driver with it. **Do not restart.**
2. Download `nullmoth-nvidia-2.6.3.tar.gz` from the [v2.6.3 release](https://github.com/nullmoth/nvidia-macos-driver/releases/tag/v2.6.3) and install it:

```bash
cd ~/Downloads && mkdir -p nm263 && tar -xzf nullmoth-nvidia-2.6.3.tar.gz -C nm263
```
```bash
cd ~/Downloads/nm263/pkgroot && sudo bash ./install.sh
```

It ends with "Done. Reboot now". **Do not restart yet.**

### 3. Build and install MothBridge

```bash
bash ~/mothbridge-630/mothbridge.sh build
```
```bash
sudo bash ~/mothbridge-630/mothbridge.sh install
```

`build` downloads NullMoth's source, nmx-intel and NVIDIA's kernel headers into `~/nmx-build`, `~/nmx-intel` and `~/ogkm615`, then builds two kexts. It takes about 10 minutes and needs no password. On the test laptop it gives NMIntelFB `4500e734` and NVAccel `b8c1df32`.

### 4. Add two boot-args in OpenCore

Mount your EFI partition. Open `EFI/OC/config.plist`. Under `NVRAM > Add > 7C436110-AB2A-4BBB-A880-FE41995C9F82 > boot-args`, add at the end:

```
-nvaccelnoheadless nvrmsettle=10000
```

Save the file. Keep a copy of the old one.

### 5. Restart and check

Restart. The panel shows the frozen boot picture for about 2 minutes, then the desktop. Then run:

```bash
bash ~/mothbridge-630/mothbridge.sh status
```

It works when you see `headless 0`, a rising `frames on panel` count, `failed 0`, and `copy mode 2 / RAM flip 2`.

## If something goes wrong

| Problem | What to do |
|---|---|
| Hangs at the Apple logo | Hold the power button. In the OpenCore picker choose **1401: Start once without NVIDIA driver**. Then run `sudo bash ~/mothbridge-630/mothbridge.sh remove` and take the two boot-args out again. |
| Panel stays black after 3 minutes | Same as above. |
| Tearing | Check `status`. `RAM flip` must be `2`. |
| Black flashes | Raise the hold: `sudo nvram nullmoth-accel-hold=60`, then restart. |
| Choppy | Quit screen-capture and ambient-light apps. |
| Brightness does nothing | `nvram nullmoth-intelfb-backlight` must print `1`. |

## Uninstall

1. `sudo bash ~/mothbridge-630/mothbridge.sh remove`
2. Take `-nvaccelnoheadless nvrmsettle=10000` out of the boot-args.
3. To remove NullMoth too, open the 1401 app and choose remove. Or run `sudo bash /Library/NullMoth/nullmoth-setup.sh --remove`. That command really removes the driver even with `--dry`.
4. Restart.

## Settings (NVRAM)

| Setting | Value | What it does |
|---|---|---|
| `nullmoth-intelfb-gen9` | `1` | lets NMIntelFB take a Coffee Lake panel |
| `nullmoth-intelfb-delay` | `30` | seconds NMIntelFB waits before taking the panel |
| `nullmoth-accel-ram` | `2` | `2` = RAM flip (no tearing), `1` = RAM copy, `0` = fast copy only |
| `nullmoth-accel-fast` | unset | `0` turns the fast copy off |
| `nullmoth-accel-hold` | unset (30) | one-colour frames kept off the panel |
| `nullmoth-intelfb-backlight` | `1` | brightness control |
| `nullmoth-intelfb-auto` | unset | `0` turns the boot helper off |

## Files in this repo

| File | What it is |
|---|---|
| `mothbridge.sh` | build, install, remove and status |
| `patches/intelfb-9022-coffee-lake-gen9.patch` | NMIntelFB: claim a Coffee Lake (Gen 9) Intel GPU when `nullmoth-intelfb-gen9=1` |
| `patches/intelfb-9023-quiet-nvram.patch` | NMIntelFB: stop writing debug trails into NVRAM |
| `patches/intelfb-9024-ram-scanout-on-gen9.patch` | NMIntelFB: allow the RAM flip on Gen 9 (it uses the same GGTT page format as Gen 12) |
| `patches/auto-sh-blank-hold-and-boot-log.patch` | boot helper: set the blank hold, log each step with seconds since boot |

## How we found it

- Frames never reached the panel (`iop_ok` stayed `0`). NVAccel's headless check gave up at 60 s, but NVRM waits 100 s before starting the display when BAR1 is too small to move (256 MB). After that NVAccel never retried, and NullMoth's Metal plugin gave WindowServer no NVIDIA device. `-nvaccelnoheadless` fixed it.
- The first working desktop ran at about 30 fps. The fast copy and the RAM flip took it to 75–83 fps without tearing. An ambient-light app (Hyperion) had been holding it at 27 fps.
- NMIntelFB refused the RAM flip on Gen 9 (`fVer < 12`). Coffee Lake uses the same GGTT page entries (`phys | 1`) as newer GPUs, so patch `9024` lowered the check to Gen 9.
- 2.6.6 lets single black frames through the default hold of 3. A hold of 30 stopped them.

## Credits

- **nvsaim**: idea, testing on the MSI GF63, every reboot.
- **Claude** (Anthropic): source reading, root cause, patches 9024 and the boot-helper changes, scripts, this guide.
- **[NullMoth](https://github.com/nullmoth/nvidia-macos-driver)**: the NVIDIA driver for macOS, NVAccel and NMIntelFB.
- **[kitsuneislife/nmx-intel](https://github.com/kitsuneislife/nmx-intel)**: NMIntelFB patches 0001–0021, the NVAccel fast-copy and RAM-flip patches, and the build and install scripts. MothBridge downloads them and does not copy them.
- **NVIDIA [open-gpu-kernel-modules](https://github.com/NVIDIA/open-gpu-kernel-modules)**: kernel headers used to build.
- **[rahulhingve](https://github.com/rahulhingve/Hackintosh-Msi-GF63-Thin-9SCXR-Sonoma)**: the base OpenCore EFI for this laptop.

## License

[PolyForm Noncommercial 1.0.0](LICENSE), the same as NullMoth, whose code these patches change. Personal and research use only. This repo ships only scripts and patches, never binaries: you build the kexts yourself.
