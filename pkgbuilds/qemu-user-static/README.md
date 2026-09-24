# ARM static QEMU candidate

This split recipe provides `qemu-user-static` and `qemu-user-static-binfmt` on aarch64, where Arch Linux ARM does not supply the static emulator packages requested by Omarchy's default package set. It repackages Debian's checksum-pinned ARM64 binary; it does not compile QEMU or replace upstream's build-worker emulation setup.

Imported from Marcelo's `maralcbr/omarchy-pkgs` revision `83973903b7deb9b56ce75f02b432fba0561d6293`, through the validated candidate recipe in `omarchy-mac/omarchy-pkgs-aarch64` (#61). Debian copyright and upstream licenses are retained. The immutable Debian snapshot keeps the pinned binary available when the rolling pool removes old revisions.

## Draft readiness gates

Automatic sync is deliberately disabled in this initial draft. This does **not** detect new releases or security updates. Do not mark this PR ready until a package-local, fixture-tested update integration handles Debian's full version (epoch, upstream version, Debian security revision and architecture rebuild), immutable archive location and SHA256 together. A new Debian revision at the same QEMU version must produce a forward package version; repeated checks must be idempotent. Missing or malformed metadata, unavailable snapshots and checksum inconsistencies must leave the recipe unchanged and fail visibly.

The existing simple custom-hook contract updates pkgver and SHA256 arrays but cannot update `_debver` and the snapshot timestamp together. Do not add a misleading upstream-version-only watch. Review the smallest compatible integration with upstream before removing the hold. Once enabled, updates should join upstream's existing six-hour update PR workflow; GitHub notification settings determine who sees those PRs. Until then, check Debian's package and security updates manually.

Before readiness, build both outputs using upstream's ARM builder and test installation in a disposable ARM VM. Verify AArch64 static ELF executables, exact interpreter paths and ownership, the absence of native AArch64 binfmt rules, execution of a known foreign-architecture program both directly and through binfmt, and clean package removal. Never register binfmt rules on the developer host or assume a container isolates that kernel state. Recipe generation only writes rules into the package staging directory.
