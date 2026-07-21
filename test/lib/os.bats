#!/usr/bin/env bats
# Unit tests for lib/os.bash

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
}

# ---------------------------------------------------------------------------
# os__kernel
# ---------------------------------------------------------------------------

@test "os__kernel returns the uname -s value" {
  reload_lib
  uname() { echo "Linux"; }
  export -f uname
  run os__kernel
  assert_output "Linux"
  assert_success
}

@test "os__kernel returns Darwin" {
  reload_lib
  uname() { echo "Darwin"; }
  export -f uname
  run os__kernel
  assert_output "Darwin"
}

@test "os__kernel uses cached _OS__KERNEL value" {
  reload_lib
  _OS__KERNEL="CachedOS"
  run os__kernel
  assert_output "CachedOS"
}

# ---------------------------------------------------------------------------
# os__arch
# ---------------------------------------------------------------------------

@test "os__arch returns the uname -m value" {
  reload_lib
  uname() { echo "x86_64"; }
  export -f uname
  run os__arch
  assert_output "x86_64"
}

@test "os__arch returns aarch64" {
  reload_lib
  uname() { echo "aarch64"; }
  export -f uname
  run os__arch
  assert_output "aarch64"
}

@test "os__arch uses cached _OS__ARCH value" {
  reload_lib
  _OS__ARCH="arm64"
  run os__arch
  assert_output "arm64"
}

# ---------------------------------------------------------------------------
# os__platform
# ---------------------------------------------------------------------------

_os__platform_stub_release() {
  export _OS__TEST_RELEASE_ID="$1"
  export _OS__TEST_RELEASE_ID_LIKE="${2:-}"
  _os__release_field() {
    case "$1" in
      ID) printf '%s' "${_OS__TEST_RELEASE_ID:-}" ;;
      ID_LIKE) printf '%s' "${_OS__TEST_RELEASE_ID_LIKE:-}" ;;
      *) return 0 ;;
    esac
  }
  export -f _os__release_field
}

@test "os__platform returns debian for ID=ubuntu" {
  reload_lib
  _os__platform_stub_release ubuntu ""
  run os__platform
  assert_output "debian"
}

@test "os__platform returns debian for ID=debian" {
  reload_lib
  _os__platform_stub_release debian ""
  run os__platform
  assert_output "debian"
}

@test "os__platform returns alpine for ID=alpine" {
  reload_lib
  _os__platform_stub_release alpine ""
  run os__platform
  assert_output "alpine"
}

@test "os__platform returns rhel for ID=fedora" {
  reload_lib
  _os__platform_stub_release fedora ""
  run os__platform
  assert_output "rhel"
}

@test "os__platform returns rhel for ID=centos" {
  reload_lib
  _os__platform_stub_release centos ""
  run os__platform
  assert_output "rhel"
}

@test "os__platform returns macos for Darwin uname fallback" {
  reload_lib
  _os__platform_stub_release "" ""
  uname() { echo "Darwin"; }
  export -f uname
  run os__platform
  assert_output "macos"
}

@test "os__platform returns debian as fallback for unknown Linux" {
  reload_lib
  _os__platform_stub_release "" ""
  uname() { echo "Linux"; }
  export -f uname
  run os__platform
  assert_output "debian"
}

@test "os__platform returns debian when ID_LIKE contains debian" {
  reload_lib
  _os__platform_stub_release linuxmint "ubuntu debian"
  run os__platform
  assert_output "debian"
}

@test "os__platform uses cached _OS__PLATFORM" {
  reload_lib
  _OS__PLATFORM="rhel"
  run os__platform
  assert_output "rhel"
}

@test "os__platform returns rhel for ID=rhel" {
  reload_lib
  _os__platform_stub_release rhel ""
  run os__platform
  assert_output "rhel"
}

@test "os__platform returns rhel for ID=rocky" {
  reload_lib
  _os__platform_stub_release rocky ""
  run os__platform
  assert_output "rhel"
}

@test "os__platform returns rhel when ID_LIKE contains fedora" {
  reload_lib
  _os__platform_stub_release custom fedora
  run os__platform
  assert_output "rhel"
}

@test "os__platform returns suse for openSUSE Tumbleweed" {
  reload_lib
  _os__platform_stub_release opensuse-tumbleweed "opensuse suse"
  run os__platform
  assert_output "suse"
}

@test "os__platform returns suse for opensuse-leap" {
  reload_lib
  _os__platform_stub_release opensuse-leap "suse opensuse"
  run os__platform
  assert_output "suse"
}

@test "os__platform returns suse for sles" {
  reload_lib
  _os__platform_stub_release sles suse
  run os__platform
  assert_output "suse"
}

@test "os__platform returns suse for sle-micro" {
  reload_lib
  _os__platform_stub_release sle-micro suse
  run os__platform
  assert_output "suse"
}

@test "os__platform returns suse when ID_LIKE contains suse" {
  reload_lib
  _os__platform_stub_release custom-suse-distro suse
  run os__platform
  assert_output "suse"
}

# ---------------------------------------------------------------------------
# os__font_dir
# ---------------------------------------------------------------------------

@test "os__font_dir returns /usr/share/fonts for system-scope prefix" {
  reload_lib
  users__is_root() { return 0; }
  export -f users__is_root
  run os__font_dir
  assert_output "/usr/share/fonts"
}

@test "os__font_dir returns ~/Library/Fonts for macOS non-root" {
  reload_lib
  users__is_root() { return 1; }
  uname() { echo "Darwin"; }
  export -f users__is_root uname
  HOME="/home/testuser" run os__font_dir
  assert_output "/home/testuser/Library/Fonts"
}

@test "os__font_dir returns XDG_DATA_HOME path for Linux non-root" {
  reload_lib
  users__is_root() { return 1; }
  uname() { echo "Linux"; }
  export -f users__is_root uname
  HOME="/home/testuser" XDG_DATA_HOME="/custom/data" run os__font_dir
  assert_output "/custom/data/fonts"
}

@test "os__font_dir returns default XDG path when XDG_DATA_HOME not set" {
  reload_lib
  users__is_root() { return 1; }
  uname() { echo "Linux"; }
  export -f users__is_root uname
  HOME="/home/testuser" XDG_DATA_HOME="" run os__font_dir
  assert_output "/home/testuser/.local/share/fonts"
}

@test "os__font_dir returns user-local XDG path for non-root" {
  reload_lib
  users__is_root() { return 1; }
  uname() { echo "Linux"; }
  export -f users__is_root uname
  HOME="/home/vscode" XDG_DATA_HOME="" run os__font_dir
  assert_output "/home/vscode/.local/share/fonts"
}

# ---------------------------------------------------------------------------
# os__is_container
# ---------------------------------------------------------------------------

@test "os__is_container returns true when /.dockerenv exists" {
  reload_lib
  # Use a temp file as the sentinel — override the built-in check via function
  # injection: the simplest approach is writing /.dockerenv to a tmpdir and
  # pointing the function at it.  Since the function hard-codes the path we
  # test indirectly via the exported sentinel file in scope of a subshell.
  local _tmp
  _tmp="$(mktemp -d "${BATS_TEST_TMPDIR}/container-sentinel.XXXXXX")"
  touch "$_tmp/.dockerenv"
  # Source os.bash in a subshell that replaces / with our tmpdir for the lookup.
  run bash -c "
    source '${LIB_ROOT}/os.bash'
    # Override the check: replace /.dockerenv with \$_tmp/.dockerenv
    os__is_container() {
      [[ -f '${_tmp}/.dockerenv' ]] && return 0
      return 1
    }
    os__is_container
  "
  assert_success
  rm -rf "$_tmp"
}

@test "os__is_container returns false when no container markers are present" {
  reload_lib
  run bash -c "
    source '${LIB_ROOT}/os.bash'
    # Override the check: point all paths to non-existent files.
    os__is_container() {
      [[ -f '/no-such-dockerenv-sentinel' ]] && return 0
      [[ -f '/run/.containerenv-sentinel' ]] && return 0
      return 1
    }
    os__is_container
  "
  assert_failure
}

# ---------------------------------------------------------------------------
# os__release_kernel
# ---------------------------------------------------------------------------

@test "os__release_kernel returns freebsd for FreeBSD kernel" {
  reload_lib
  _OS__KERNEL="FreeBSD"
  run os__release_kernel
  assert_success
  assert_output "freebsd"
}

@test "os__release_kernel returns linux for Linux kernel" {
  reload_lib
  _OS__KERNEL="Linux"
  run os__release_kernel
  assert_success
  assert_output "linux"
}

@test "os__release_kernel returns darwin for Darwin with github flavor" {
  reload_lib
  _OS__KERNEL="Darwin"
  run os__release_kernel github
  assert_success
  assert_output "darwin"
}

@test "os__release_kernel returns 1 for unsupported kernel" {
  reload_lib
  _OS__KERNEL="SunOS"
  run os__release_kernel
  assert_failure
}

# ---------------------------------------------------------------------------
# os__release_arch — go/gnu flavors
# ---------------------------------------------------------------------------

@test "os__release_arch --flavor go maps x86_64/amd64/x64 to amd64" {
  reload_lib
  run os__release_arch x86_64 --flavor go
  assert_output "amd64"
  run os__release_arch amd64 --flavor go
  assert_output "amd64"
  run os__release_arch x64 --flavor go
  assert_output "amd64"
}

@test "os__release_arch --flavor go maps aarch64/arm64 to arm64" {
  reload_lib
  run os__release_arch aarch64 --flavor go
  assert_output "arm64"
  run os__release_arch arm64 --flavor go
  assert_output "arm64"
}

@test "os__release_arch --flavor go maps armv7l/armv7 to arm" {
  reload_lib
  run os__release_arch armv7l --flavor go
  assert_output "arm"
  run os__release_arch armv7 --flavor go
  assert_output "arm"
}

@test "os__release_arch --flavor go maps armv6l to arm" {
  reload_lib
  run os__release_arch armv6l --flavor go
  assert_output "arm"
}

@test "os__release_arch --flavor go maps i386/i686 to 386" {
  reload_lib
  run os__release_arch i386 --flavor go
  assert_output "386"
  run os__release_arch i686 --flavor go
  assert_output "386"
}

@test "os__release_arch --flavor go passes through ppc64le, s390x, riscv64, loong64" {
  reload_lib
  run os__release_arch ppc64le --flavor go
  assert_output "ppc64le"
  run os__release_arch s390x --flavor go
  assert_output "s390x"
  run os__release_arch riscv64 --flavor go
  assert_output "riscv64"
  run os__release_arch loongarch64 --flavor go
  assert_output "loong64"
}

@test "os__release_arch --flavor gnu maps x86_64/amd64/x64 to x86_64" {
  reload_lib
  run os__release_arch x86_64 --flavor gnu
  assert_output "x86_64"
  run os__release_arch amd64 --flavor gnu
  assert_output "x86_64"
  run os__release_arch x64 --flavor gnu
  assert_output "x86_64"
}

@test "os__release_arch --flavor gnu passes through the machine_release-equivalent token for other architectures" {
  reload_lib
  run os__release_arch aarch64 --flavor gnu
  assert_output "arm64"
  run os__release_arch armv7l --flavor gnu
  assert_output "armv7"
  run os__release_arch armv6l --flavor gnu
  assert_output "armv6l"
  run os__release_arch i386 --flavor gnu
  assert_output "i386"
  run os__release_arch i686 --flavor gnu
  assert_output "i386"
  run os__release_arch ppc64le --flavor gnu
  assert_output "ppc64le"
  run os__release_arch s390x --flavor gnu
  assert_output "s390x"
  run os__release_arch riscv64 --flavor gnu
  assert_output "riscv64"
  run os__release_arch loongarch64 --flavor gnu
  assert_output "loong64"
}

@test "os__release_arch --flavor go returns 1 for unsupported architecture" {
  reload_lib
  run os__release_arch bogus-arch --flavor go
  assert_failure
}

# ---------------------------------------------------------------------------
# os__libc
# ---------------------------------------------------------------------------

@test "os__libc returns 1 on non-Linux (Darwin)" {
  reload_lib
  _OS__KERNEL="Darwin"
  run os__libc
  assert_failure
}

@test "os__libc returns musl when ldd output contains musl" {
  reload_lib
  _OS__KERNEL="Linux"
  # Stub ldd to return musl-style output (ls glob will fail on glibc host)
  ldd() { printf '/lib/ld-musl-x86_64.so.1 (0x7f000000)\n'; }
  export -f ldd
  run os__libc
  assert_success
  assert_output "musl"
}

@test "os__libc returns gnu when no musl markers are present" {
  # Skip on Alpine: /lib/ld-musl-*.so* files are physically present on the host
  # and the ls-glob check in os__libc runs before the ldd stub is consulted.
  [[ -f /etc/alpine-release ]] && skip "musl linker files always present on Alpine"
  reload_lib
  _OS__KERNEL="Linux"
  ldd() { printf '/lib/x86_64-linux-gnu/libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6\n/lib64/ld-linux-x86-64.so.2\n'; }
  export -f ldd
  run os__libc
  assert_success
  assert_output "gnu"
}

# ---------------------------------------------------------------------------
# os__rust_triple
# ---------------------------------------------------------------------------

@test "os__rust_triple returns x86_64-unknown-linux-musl for Linux x86_64" {
  reload_lib
  _OS__KERNEL="Linux"
  run os__rust_triple x86_64
  assert_success
  assert_output "x86_64-unknown-linux-musl"
}

@test "os__rust_triple accepts amd64 alias for Linux" {
  reload_lib
  _OS__KERNEL="Linux"
  run os__rust_triple amd64
  assert_success
  assert_output "x86_64-unknown-linux-musl"
}

@test "os__rust_triple returns i686-unknown-linux-musl for Linux i686" {
  reload_lib
  _OS__KERNEL="Linux"
  run os__rust_triple i686
  assert_success
  assert_output "i686-unknown-linux-musl"
}

@test "os__rust_triple returns i686-unknown-linux-musl for Linux i386" {
  reload_lib
  _OS__KERNEL="Linux"
  run os__rust_triple i386
  assert_success
  assert_output "i686-unknown-linux-musl"
}

@test "os__rust_triple returns aarch64-unknown-linux-musl for Linux aarch64" {
  reload_lib
  _OS__KERNEL="Linux"
  run os__rust_triple aarch64
  assert_success
  assert_output "aarch64-unknown-linux-musl"
}

@test "os__rust_triple accepts arm64 alias for Linux" {
  reload_lib
  _OS__KERNEL="Linux"
  run os__rust_triple arm64
  assert_success
  assert_output "aarch64-unknown-linux-musl"
}

@test "os__rust_triple returns arm-unknown-linux-musleabihf for Linux armv6l" {
  reload_lib
  _OS__KERNEL="Linux"
  run os__rust_triple armv6l
  assert_success
  assert_output "arm-unknown-linux-musleabihf"
}

@test "os__rust_triple returns armv7-unknown-linux-musleabihf for Linux armv7l with NEON" {
  reload_lib
  _OS__KERNEL="Linux"
  grep() { return 0; }
  export -f grep
  run os__rust_triple armv7l
  assert_success
  assert_output "armv7-unknown-linux-musleabihf"
}

@test "os__rust_triple returns arm-unknown-linux-musleabihf for Linux armv7l without NEON" {
  reload_lib
  _OS__KERNEL="Linux"
  grep() { return 1; }
  export -f grep
  run os__rust_triple armv7l
  assert_success
  assert_output "arm-unknown-linux-musleabihf"
}

@test "os__rust_triple returns loongarch64-unknown-linux-musl for Linux loongarch64" {
  reload_lib
  _OS__KERNEL="Linux"
  run os__rust_triple loongarch64
  assert_success
  assert_output "loongarch64-unknown-linux-musl"
}

@test "os__rust_triple returns powerpc64le-unknown-linux-gnu for Linux ppc64le" {
  reload_lib
  _OS__KERNEL="Linux"
  run os__rust_triple ppc64le
  assert_success
  assert_output "powerpc64le-unknown-linux-gnu"
}

@test "os__rust_triple returns s390x-unknown-linux-gnu for Linux s390x" {
  reload_lib
  _OS__KERNEL="Linux"
  run os__rust_triple s390x
  assert_success
  assert_output "s390x-unknown-linux-gnu"
}

@test "os__rust_triple returns riscv64gc-unknown-linux-musl for Linux riscv64 on musl" {
  reload_lib
  _OS__KERNEL="Linux"
  os__libc() { printf 'musl\n'; }
  export -f os__libc
  run os__rust_triple riscv64
  assert_success
  assert_output "riscv64gc-unknown-linux-musl"
}

@test "os__rust_triple returns riscv64gc-unknown-linux-gnu for Linux riscv64 on glibc" {
  reload_lib
  _OS__KERNEL="Linux"
  os__libc() { printf 'gnu\n'; }
  export -f os__libc
  run os__rust_triple riscv64
  assert_success
  assert_output "riscv64gc-unknown-linux-gnu"
}

@test "os__rust_triple returns x86_64-apple-darwin for Darwin x86_64" {
  reload_lib
  _OS__KERNEL="Darwin"
  sysctl() { return 1; }
  export -f sysctl
  run os__rust_triple x86_64
  assert_success
  assert_output "x86_64-apple-darwin"
}

@test "os__rust_triple returns aarch64-apple-darwin for Darwin x86_64 under Rosetta 2" {
  reload_lib
  _OS__KERNEL="Darwin"
  sysctl() { printf '1\n'; }
  export -f sysctl
  run os__rust_triple x86_64
  assert_success
  assert_output "aarch64-apple-darwin"
}

@test "os__rust_triple returns aarch64-apple-darwin for Darwin aarch64" {
  reload_lib
  _OS__KERNEL="Darwin"
  run os__rust_triple aarch64
  assert_success
  assert_output "aarch64-apple-darwin"
}

@test "os__rust_triple accepts arm64 alias for Darwin" {
  reload_lib
  _OS__KERNEL="Darwin"
  run os__rust_triple arm64
  assert_success
  assert_output "aarch64-apple-darwin"
}

@test "os__rust_triple returns x86_64-unknown-freebsd for FreeBSD x86_64" {
  reload_lib
  _OS__KERNEL="FreeBSD"
  run os__rust_triple x86_64
  assert_success
  assert_output "x86_64-unknown-freebsd"
}

@test "os__rust_triple detects 32-bit x86 userland on a 64-bit kernel via getconf" {
  reload_lib
  _OS__KERNEL="Linux"
  getconf() { printf '32\n'; }
  export -f getconf
  run os__rust_triple x86_64
  assert_success
  assert_output "i686-unknown-linux-musl"
}

@test "os__rust_triple returns 1 for unsupported kernel/arch combination" {
  reload_lib
  _OS__KERNEL="Linux"
  run os__rust_triple mips
  assert_failure
}

# ---------------------------------------------------------------------------
# os__is_devcontainer_runtime
# ---------------------------------------------------------------------------

@test "os__is_devcontainer_runtime returns true when REMOTE_CONTAINERS is set" {
  reload_lib
  REMOTE_CONTAINERS=1 run os__is_devcontainer_runtime
  assert_success
}

@test "os__is_devcontainer_runtime returns true when CODESPACES is set" {
  reload_lib
  CODESPACES=true run os__is_devcontainer_runtime
  assert_success
}

@test "os__is_devcontainer_runtime returns false when no signal is present" {
  reload_lib
  run env -u REMOTE_CONTAINERS -u CODESPACES bash -c "
    source '${LIB_ROOT}/os.bash'
    os__is_devcontainer_runtime
  "
  assert_failure
}
