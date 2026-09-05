# Source package recipes

The Omarchy application recipes originate from the official [package repository](https://github.com/omacom/omarchy-pkgs), inspected at `99234a4fbb61b46225b2e9e560e114fbfebe8a95`. The Neovim recipe uses the stable configuration from `2eb15bc7265c5293985f7e5f483e39df7be9c548`, version 2026.7.17. Source checksums remain enabled. Declaring `riscv64` identifies the build target and does not establish runtime compatibility.

The compositor recipes are built from pinned upstream sources:

| Package | Source commit | Port changes |
| --- | --- | --- |
| Hyprland 0.55.4 | `a0136d8c04687bb36eb8a28eb9d1ff92aea99704` | Explicit pointer conversions, corrected target comparisons, animation ownership handling for Hyprutils 0.14, and EGL import validation for PowerVR |
| Aquamarine 0.14.0 | `a79fb21b2e2a82dd061a6d071802bcf38bd5c383` | Acknowledge the parent XDG surface configuration before committing its first buffer |
| Hyprland portal 1.4.1 | `cc8e5ef8fb2acef3db488b9a33b0c48c2a4ee204` | Rebuild against the current RISC-V shared libraries |

The installed repository compositor and portal packages initially required older Aquamarine/Hyprutils SONAMEs. These recipes rebuild the binaries with dependency tracking for the installed ABI. Hyprland embeds the pinned Glaze 7.2.0 source because the repository provides a newer incompatible major version.

`build-packages.sh` compiles as the ordinary Arch user and installs through pacman. Its native helper accepts a list of recipe names, serializes use of the shared build cache, and retains successful artifacts. Compiler processes remain in the invoking systemd service. A cached build is reused only when the recipe fingerprint and artifact paths match.

All recipes listed in `packages.list` have built natively on the K3. Walker 2.17.0 with Elephant 2.22.0, the 2026.7.17 editor package, and the preview share picker have passed desktop runtime checks. `validate-plugins.lua` checks that all 52 plugin directories exist and that no error has been reported at that point; it does not exercise asynchronous file-opening callbacks. The Ristretto theme uses the maintained `loctvl842/monokai-pro.nvim` source at a pinned commit.

LuaJIT is pinned to [PLCT's RISC-V release](https://github.com/plctlab/LuaJIT/tree/2c509ee67e20772bce3a11ce8f53b6b14b4980bb), version `2.1.1786451769-1.1`. The repository's older `2.1.1702376626-1` incorrectly invokes a table's equality metamethod when comparing it with a nil variable, causing Snacks/LazyVim errors when opening Markdown. Disabling JIT does not fix the old interpreter. The updated package passes `luajit/equality.lua` with JIT enabled and disabled, including inside Neovim. A fresh graphical editor opened the boot guide and moved through it with JIT enabled, empty `v:errmsg`, and no error messages. This fixes the runtime without changing cached plugin sources. The K3 updater holds this tested runtime.

On the physical Arch host, `sudo ports/k3/build-packages.sh luajit` builds directly as the ordinary user and installs through pacman. The same entry point retains the container staging path when run from Bianbu.

The PowerVR patch skips only the driver's unsupported PRIME-to-GEM preflight check when the DRM driver name is `pvr`; plane/dimension checks and actual EGL texture import validation remain active. Other drivers retain the original path.

The share picker builds with stable Rust on RISC-V. `tzupdate` carries a locked TLS dependency update because its old `ring` dependency did not support RISC-V. The Yaru recipe builds GTK color data to generate accent variants but packages only icons and cursors. A successful package build alone is not a claim that every feature or optional hardware path has been tested.

NeatVNC 1.0.1 uses the Nettle 4 backports from Arch's package recipe at `4537131d951c92feadf3e5ad1a02872884df85ab`. H.264 is disabled for this board profile because browser viewers retained stale frames; standard Tight/ZRLE image encodings update the desktop correctly. TLS, authentication, JPEG, and GBM support remain enabled. All three upstream test groups pass natively.

## Profile layout

The tested recipes are in `ports/k3/pkgbuilds/`. They are kept separate from the upstream production package set. `packages.list` lists this profile only; the production release tools are not a RISC-V builder. The Omarchy integration repository pins this repository as its `ports/k3/packages` submodule and runs the native builder against this profile.

The package source archive URLs and hashes are recorded in each PKGBUILD. Arch dependency repositories remain rolling, so these pins do not establish a byte-for-byte reproducible distribution image. Native package build and desktop evidence is recorded in the Omarchy port documentation.
