#!/bin/bash
# Exercise the real package functions with a minimal, synthetic runtime tree.
set -euo pipefail

BUILD_ROOT=$(realpath "${BASH_SOURCE[0]%/*}/..")
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
fixture=$scratch/src/omarchy

files=(
  config/autostart/limine-snapper-notify.desktop
  etc/fastfetch/config.jsonc
  etc/mkinitcpio.conf.d/omarchy_hooks.conf
  etc/mkinitcpio.conf.d/thunderbolt_module.conf
  etc/limine-entry-tool.d/omarchy-defaults.conf
  etc/limine-entry-tool.d/omarchy-uki.conf
  etc/security/faillock.conf
  etc/nsswitch.conf
  etc/cups/cups-browsed.conf
  etc/cups/cups-files.conf
  etc/plymouth/plymouthd.conf
  etc/sysctl.d/99-omarchy-sysctl.conf
  default/uwsm/env.d/10-omarchy
  default/environment.d/10-omarchy-fcitx.conf
  default/fontconfig/conf.avail/50-omarchy.conf
  default/xdg-terminal-exec/hyprland-xdg-terminals.list
  default/applications/mimeapps.list
  default/systemd/user/bt-agent.service
  default/systemd/user/omarchy-sleep-lock.service
  default/systemd/user/omarchy-recover-internal-monitor.service
  default/systemd/user/omarchy-migrate-notify.service
  default/systemd/user/omarchy-tailscale-receive.service
  default/systemd/user/omarchy-fcitx5.service
  default/systemd/user/omarchy-crash-watch.service
  default/systemd/user/app.slice.d/10-oomd.conf
  default/systemd/zram-generator.conf.d/90-omarchy.conf
  default/systemd/system/plocate-updatedb.service.d/10-omarchy.conf
  default/systemd/system-sleep/unmount-fuse
  default/bashrc
  default/limine/default.conf
  default/limine/limine.conf
  default/snapper/root
  default/sddm/omarchy/Main.qml
  default/sddm/hyprland.lua
  default/wayland-sessions/omarchy.desktop
  default/plymouth/omarchy.plymouth
  default/fonts/omarchy/omarchy.ttf
  default/hypr/toggles/flags.lua
  default/nautilus-python/extensions/localsend.py
  default/nautilus-python/extensions/transcode.py
  default/tensaku/state.toml
  applications/example.desktop
  bin/omarchy-upload-log
  bin/omarchy-debug
  bin/omarchy-debug-idle
  logo.txt
  logo.svg
  icon.txt
  icon.png
)
for path in "${files[@]}"; do
  mkdir -p "$(dirname "$fixture/$path")"
  printf 'fixture for %s\n' "$path" > "$fixture/$path"
done

# Omarchy's HOOKS line, as its sources ship it.
omarchy_hooks='base udev plymouth keyboard autodetect microcode modconf kms keymap consolefont block encrypt filesystems fsck btrfs-overlayfs'
printf 'HOOKS=(%s)\n' "$omarchy_hooks" > "$fixture/etc/mkinitcpio.conf.d/omarchy_hooks.conf"

for recipe in omarchy-settings omarchy-settings-dev; do
  for target_arch in aarch64 x86_64; do
    (
      export CARCH=$target_arch OMARCHY_SRC=$fixture
      export srcdir=$scratch/src pkgdir=$scratch/$recipe-$target_arch
      backup=()
      # shellcheck disable=SC1090 # Exercise each recipe's actual package function.
      source "$BUILD_ROOT/pkgbuilds/$recipe/PKGBUILD"
      package

      for path in etc/mkinitcpio.conf.d/omarchy_hooks.conf \
        etc/limine-entry-tool.d/omarchy-defaults.conf \
        etc/limine-entry-tool.d/omarchy-uki.conf; do
        printf '%s\n' "${backup[@]}" | grep -Fxq "$path"
      done
      for path in etc/limine-entry-tool.d/omarchy-defaults.conf etc/limine-entry-tool.d/omarchy-uki.conf; do
        cmp "$fixture/$path" "$pkgdir/$path"
      done
      hooks_conf=etc/mkinitcpio.conf.d/omarchy_hooks.conf
      if [[ $CARCH == aarch64 ]]; then
        grep -Fxq 'if [[ " ${HOOKS[*]:-} " != *" asahi "* ]]; then' "$pkgdir/$hooks_conf"
        bash -n "$pkgdir/$hooks_conf"
      else
        cmp "$fixture/$hooks_conf" "$pkgdir/$hooks_conf"
      fi
      for template in default.conf limine.conf; do
        cmp "$fixture/default/limine/$template" "$pkgdir/usr/share/omarchy/default/limine/$template"
      done
      # The installer owns the machine-specific live configuration.
      [[ ! -e $pkgdir/etc/default/limine ]]
      if printf '%s\n' "${backup[@]}" | grep -Fxq 'etc/default/limine'; then
        echo 'FAIL: installer-owned Limine configuration is in backup metadata' >&2
        exit 1
      fi
      cmp "$fixture/config/autostart/limine-snapper-notify.desktop" \
        "$pkgdir/etc/skel/.config/autostart/limine-snapper-notify.desktop"
      cmp "$fixture/config/autostart/limine-snapper-notify.desktop" \
        "$pkgdir/usr/share/omarchy/config/autostart/limine-snapper-notify.desktop"

      thunderbolt=etc/mkinitcpio.conf.d/thunderbolt_module.conf
      if [[ $CARCH == aarch64 ]]; then
        [[ ! -e $pkgdir/$thunderbolt ]]
        if printf '%s\n' "${backup[@]}" | grep -Fxq "$thunderbolt"; then
          echo 'FAIL: removed ARM Thunderbolt config remains in backup metadata' >&2
          exit 1
        fi
      else
        cmp "$fixture/$thunderbolt" "$pkgdir/$thunderbolt"
        printf '%s\n' "${backup[@]}" | grep -Fxq "$thunderbolt"
      fi
      echo "PASS: $recipe $CARCH retains boot configuration and matching backup metadata"
    )
  done
done

# The aarch64 packages also reach Apple Silicon Macs, whose initramfs needs the
# asahi hook. Source mkinitcpio.conf and the drop-ins in mkinitcpio's order and
# compare the resulting HOOKS for each kind of aarch64 install.
package_aarch64() {
  local recipe=$1 source_tree=$2 out=$3
  (
    # package() builds from $srcdir/omarchy.
    export CARCH=aarch64 OMARCHY_SRC=$source_tree srcdir=${source_tree%/omarchy} pkgdir=$out
    backup=()
    # shellcheck disable=SC1090 # Exercise the recipe's actual package function.
    source "$BUILD_ROOT/pkgbuilds/$recipe/PKGBUILD"
    package
  )
}

effective_hooks() {
  local root=$1
  (
    LC_ALL=C
    HOOKS=()
    # shellcheck disable=SC1091
    source "$root/mkinitcpio.conf"
    shopt -s nullglob
    for conf in "$root"/mkinitcpio.conf.d/*.conf; do
      # shellcheck disable=SC1090
      source "$conf"
    done
    echo "${HOOKS[*]}"
  )
}

# machine NAME MKINITCPIO_HOOKS PACKAGED_ETC [FRAGMENT FRAGMENT_HOOKS]
machine() {
  local root=$scratch/machines/$1
  mkdir -p "$root/mkinitcpio.conf.d"
  printf 'HOOKS=(%s)\n' "$2" > "$root/mkinitcpio.conf"
  cp "$3"/*.conf "$root/mkinitcpio.conf.d/"
  if (($# == 5)); then
    printf 'HOOKS=(%s)\n' "$5" > "$root/mkinitcpio.conf.d/$4"
  fi
  printf '%s\n' "$root"
}

arch_default='base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck'
snapdragon='base systemd autodetect microcode modconf kms keyboard sd-vconsole block filesystems fsck'
legacy_mac='base udev autodetect modconf kms keyboard keymap consolefont block asahi encrypt filesystems fsck'
aurora_mac='base udev autodetect modconf kms keyboard keymap consolefont block asahi omarchy-vendorfw omarchy-mac-encrypt sd-encrypt filesystems fsck'

check_machines() {
  local layout=$1 packaged=$2/etc/mkinitcpio.conf.d root
  rm -rf "$scratch/machines"
  root=$(machine snapdragon "$snapdragon" "$packaged")
  [[ $(effective_hooks "$root") == "$omarchy_hooks" ]] ||
    { echo "FAIL: $layout: Snapdragon gets $(effective_hooks "$root")" >&2; exit 1; }
  root=$(machine spark "$arch_default" "$packaged")
  [[ $(effective_hooks "$root") == "$omarchy_hooks" ]] ||
    { echo "FAIL: $layout: DGX Spark gets $(effective_hooks "$root")" >&2; exit 1; }
  root=$(machine legacy-mac "$legacy_mac" "$packaged")
  [[ $(effective_hooks "$root") == "$legacy_mac" ]] ||
    { echo "FAIL: $layout: a legacy GRUB Mac loses asahi: $(effective_hooks "$root")" >&2; exit 1; }
  root=$(machine aurora-mac "$arch_default" "$packaged" 92-omarchy-mac-boot.conf "$aurora_mac")
  [[ $(effective_hooks "$root") == "$aurora_mac" ]] ||
    { echo "FAIL: $layout: an Aurora Mac loses its hooks: $(effective_hooks "$root")" >&2; exit 1; }
  echo "PASS: $layout: Snapdragon and the Spark get Omarchy's hooks; Macs keep asahi"
}

check_machines "HOOKS in omarchy_hooks.conf" "$scratch/omarchy-settings-aarch64"

# omacom/omarchy#13362 moves the HOOKS line into 00-omarchy-hooks.conf.
split=$scratch/split/omarchy
mkdir -p "$scratch/split"
cp -a "$fixture" "$split"
printf 'HOOKS=(%s)\n' "$omarchy_hooks" > "$split/etc/mkinitcpio.conf.d/00-omarchy-hooks.conf"
sed -i '/^HOOKS=/d' "$split/etc/mkinitcpio.conf.d/omarchy_hooks.conf"
package_aarch64 omarchy-settings "$split" "$scratch/split-package" >/dev/null
grep -Fxq 'if [[ " ${HOOKS[*]:-} " != *" asahi "* ]]; then' \
  "$scratch/split-package/etc/mkinitcpio.conf.d/00-omarchy-hooks.conf"
check_machines "HOOKS in 00-omarchy-hooks.conf" "$scratch/split-package"

sed -i '/^HOOKS=/d' "$split/etc/mkinitcpio.conf.d/00-omarchy-hooks.conf"
if package_aarch64 omarchy-settings "$split" "$scratch/unguarded-package" 2>/dev/null; then
  echo 'FAIL: the aarch64 package builds without a HOOKS line to guard' >&2
  exit 1
fi
echo "PASS: the aarch64 package fails to build without a HOOKS line to guard"

# Upgrades: pacman replaces an unmodified hooks file, keeps a modified one and
# leaves the guarded version as .pacnew, and installs it where it was absent.
if ((EUID != 0)) || ! command -v pacman >/dev/null; then
  echo "SKIP: pacman upgrade checks need root"
  exit 0
fi

unguarded=$fixture/etc/mkinitcpio.conf.d/omarchy_hooks.conf
guarded=$scratch/omarchy-settings-aarch64/etc/mkinitcpio.conf.d/omarchy_hooks.conf
printf '[options]\nArchitecture = auto\nSigLevel = Never\nLocalFileSigLevel = Never\n' > "$scratch/pacman.conf"

make_pkg() {
  local ver=$1 hooks=${2:-} dir=$scratch/pkg-$1
  mkdir -p "$dir/etc/mkinitcpio.conf.d"
  [[ -z $hooks ]] || cp "$hooks" "$dir/etc/mkinitcpio.conf.d/omarchy_hooks.conf"
  cat > "$dir/.PKGINFO" <<EOF
pkgname = omarchy-settings-upgrade-test
pkgbase = omarchy-settings-upgrade-test
pkgver = $ver
pkgdesc = omarchy-settings upgrade test
arch = any
size = 1
backup = etc/mkinitcpio.conf.d/omarchy_hooks.conf
EOF
  (cd "$dir" && bsdtar -cf "$scratch/upgrade-test-$ver-any.pkg.tar" .PKGINFO etc)
  printf '%s\n' "$scratch/upgrade-test-$ver-any.pkg.tar"
}

pacman_in() {
  local root=$1
  shift
  mkdir -p "$root/var/lib/pacman" "$root/cache"
  pacman --root "$root" --dbpath "$root/var/lib/pacman" --cachedir "$root/cache" \
    --config "$scratch/pacman.conf" --logfile /dev/null --noconfirm --nodeps --noscriptlet "$@" >/dev/null
}

stripped=$(make_pkg 1-1)
old=$(make_pkg 2-1 "$unguarded")
new=$(make_pkg 3-1 "$guarded")
installed=etc/mkinitcpio.conf.d/omarchy_hooks.conf

pacman_in "$scratch/unchanged" -U "$old"
pacman_in "$scratch/unchanged" -U "$new"
cmp "$guarded" "$scratch/unchanged/$installed"
[[ ! -e $scratch/unchanged/$installed.pacnew ]]

pacman_in "$scratch/modified" -U "$old"
echo '# local change' >> "$scratch/modified/$installed"
pacman_in "$scratch/modified" -U "$new"
grep -Fxq '# local change' "$scratch/modified/$installed"
cmp "$guarded" "$scratch/modified/$installed.pacnew"

pacman_in "$scratch/absent" -U "$stripped"
pacman_in "$scratch/absent" -U "$new"
cmp "$guarded" "$scratch/absent/$installed"

# Source what the upgrades installed.
for upgrade in unchanged absent; do
  etc=$scratch/$upgrade/etc/mkinitcpio.conf.d
  [[ $(effective_hooks "$(machine "$upgrade-snapdragon" "$snapdragon" "$etc")") == "$omarchy_hooks" ]]
  [[ $(effective_hooks "$(machine "$upgrade-legacy-mac" "$legacy_mac" "$etc")") == "$legacy_mac" ]]
done
echo "PASS: pacman upgrades install the guarded hooks file and keep local changes"
