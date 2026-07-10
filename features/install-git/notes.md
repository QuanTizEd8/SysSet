# Notes

## Ubuntu git-core PPA

The newest upstream stable Git — ahead of what the distribution ships — is only
available on Ubuntu, through the `git-core` PPA. This is the `upstream-package`
method, which `method=auto` selects on Ubuntu (it is preferred over the plain
`package` method there). On Debian and every other distribution there is no PPA
equivalent: `method=auto` installs the distribution-provided Git via `package`.
To get a newer Git on those systems, use `method=source`.

## Version pinning

Pinning an exact `X.Y.Z` version through a package method requires that exact
version to be present in the currently configured repositories. Homebrew (macOS)
does not support installing arbitrary past Git versions this way, so a pinned
version has no effect there — use `method=source` with an exact `version` to pin
a specific release on macOS (and on any distribution whose repositories do not
carry the version you need).

## Source builds on Debian/Ubuntu register a dummy package

After a `method=source` build on Debian/Ubuntu, a dummy `git` package is
registered with the OS package manager at the built version. This satisfies
`Depends: git` for anything installed later (e.g. `apt install <pkg>`), so the
package manager will not pull a second, distribution-packaged Git onto the
system. The dummy package installs no files — the source-built `git` under the
prefix remains the only binary. Registration is best-effort: if it fails,
installation still succeeds and PATH ordering keeps the built Git in front.
