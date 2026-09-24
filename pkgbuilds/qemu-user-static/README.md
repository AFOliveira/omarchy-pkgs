# ARM static QEMU

This aarch64-only split recipe provides qemu-user-static and qemu-user-static-binfmt using Debian’s static ARM64 binaries. It preserves Marcelo’s recipe, imported through omarchy-mac/omarchy-pkgs-aarch64#61, including licensing and binfmt behavior. It does not change x86 packages or the build workers.

## Updates

The package-local upstream hook checks Debian 13 (trixie), trixie-updates, and trixie-security ARM64 indexes. It compares full Debian versions, including epochs, security revisions and binary rebuilds, and resolves the selected binary through snapshot.debian.org’s API. The immutable content-addressed archive must match the index’s size and SHA256 as well as the snapshot SHA1 before an update is returned.

A one-time Arch epoch of 1 moves away from the previous upstream-only version. pkgver encodes Debian epoch.upstream.revision. The hook requires both Debian ordering and pacman vercmp to advance; unfamiliar prerelease conventions or ordering discrepancies fail for manual review. Debian distribution upgrades are explicit recipe changes, not automatic jumps to testing/unstable.

The existing six-hour upstream update PR workflow discovers the hook. Its pkgver, _debver, _snapshot and ARM checksum are applied atomically through the normal sync interface. Repeated checks are idempotent. Feed failures, malformed metadata, conflicting checksums and unavailable/corrupt snapshots fail visibly before recipe mutation. No update installs packages or registers binfmt rules.

Offline fixtures cover version/epoch/security/binNMU updates, security-feed selection, unchanged versions, metadata and snapshot failures, atomic application, and hostile/missing scalar rejection. Existing GUI-independent VM qualification and packaging evidence are recorded in the PR; new binaries still receive build and runtime checks before publication.
