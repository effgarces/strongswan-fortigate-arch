# strongswan-fortigate-arch

Automatically builds Arch Linux's current `strongswan` package with the
FortiGate/FortiClient compatibility patches from
[Noneawe/strongswan-deb-build](https://github.com/Noneawe/strongswan-deb-build),
so a standard strongSwan can log in to a FortiGate IKEv2 gateway that uses
EAP-MSCHAPv2 plus an email/token second factor (EAP-GTC).

Every Monday a GitHub Actions workflow checks which strongswan version Arch
ships. If there is no release for it yet, it builds the package in an Arch
container and publishes it as a GitHub **Release** (package, `PKGBUILD`,
patches, checksums). If a patch stops applying, the build fails and the
workflow opens an issue instead of publishing something half-working.

> This is only the package. The token prompt (helper + agent) and the
> `swanctl`/`strongswan.d` configuration are not included here.

## Install a release

```bash
# from the Releases page: the .pkg.tar.zst and SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing
sudo pacman -U strongswan-<version>-x86_64.pkg.tar.zst
sudo systemctl restart strongswan
```

To keep a routine `pacman -Syu` from replacing it with Arch's unpatched
package, add `IgnorePkg = strongswan` under `[options]` in `/etc/pacman.conf`.
That also means **you must install new releases yourself** (security fixes
included). Watch this repo's Releases, or "Watch -> Custom -> Releases".

The packages are not PGP-signed. Verify the checksum, or rebuild from the
attached `PKGBUILD` and `.patch` files (download them into one folder, then `makepkg -s`).

## What the build does

1. Reads the current strongswan version from archlinux.org.
2. Clones Arch's own packaging repo at that version's tag (so Arch's configure
   flags and fixes are used unchanged).
3. Downloads the patches from the **pinned commit** in `patches.lock` and
   refuses to continue if any SHA-512 differs.
4. Adds the patches to `source=()`, the checksums and `prepare()`
   (`patch --fuzz=0`, no fuzzy matching) and sets `pkgrel` to `<arch pkgrel>.<PATCH_REV>`.
5. Builds with `makepkg`; makepkg verifies strongSwan's own PGP signature.


## Limits and honesty

- The patches are written against strongSwan 6.0.x/6.1.0 and were checked to
  apply cleanly to 6.1.0. A future strongSwan may need them rebased; then the
  build fails and someone has to update the patches.
- They change EAP handling for every connection of this build (see the
  patch descriptions upstream) and can make strongSwan present itself as
  FortiClient. Use them only against gateways you are entitled to connect to.
- x86_64 only (what Arch ships).
- The patch repo has no license file, which is why its patches are fetched at
  build time and not copied here. strongSwan itself is GPL-2.0; the exact
  source (upstream tarball URL in the `PKGBUILD`, plus the patches) is attached to each release.

## License

MIT for the scripts and workflows in this repository (see `LICENSE`).
