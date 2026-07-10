# Notes

## Alpine Linux (musl) is not supported

The official prebuilt Node.js tarballs published on nodejs.org are dynamically
linked against glibc and cannot run on Alpine's musl libc. On Alpine the
installer detects the platform and fails fast with an actionable error instead
of installing an unusable binary. Use `install-nvm` on Alpine — it builds
Node.js from source against musl.

## Checksum verification and its limits

The downloaded tarball's SHA-256 checksum is verified against the official
`SHASUMS256.txt`, fetched from the same `nodejs.org/dist/<version>/` directory
as the tarball. `SHASUMS256.txt` is itself GPG-signed by the Node.js release
team, but this feature verifies the SHA-256 checksum only — it does **not**
verify the GPG signature of the checksums file. HTTPS transport to nodejs.org
is the baseline integrity guarantee for `SHASUMS256.txt` itself.
