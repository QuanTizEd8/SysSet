#!/usr/bin/env bats
# Unit tests for lib/os.sh

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/common'
  load 'helpers/stubs'
}

# ---------------------------------------------------------------------------
# os::kernel
# ---------------------------------------------------------------------------

@test "os::kernel returns the uname -s value" {
  reload_lib os.sh
  uname() { echo "Linux"; }
  export -f uname
  run os::kernel
  assert_output "Linux"
  assert_success
}

@test "os::kernel returns Darwin" {
  reload_lib os.sh
  uname() { echo "Darwin"; }
  export -f uname
  run os::kernel
  assert_output "Darwin"
}

@test "os::kernel uses cached _OS_KERNEL value" {
  reload_lib os.sh
  _OS_KERNEL="CachedOS"
  run os::kernel
  assert_output "CachedOS"
}

# ---------------------------------------------------------------------------
# os::arch
# ---------------------------------------------------------------------------

@test "os::arch returns the uname -m value" {
  reload_lib os.sh
  uname() { echo "x86_64"; }
  export -f uname
  run os::arch
  assert_output "x86_64"
}

@test "os::arch returns aarch64" {
  reload_lib os.sh
  uname() { echo "aarch64"; }
  export -f uname
  run os::arch
  assert_output "aarch64"
}

@test "os::arch uses cached _OS_ARCH value" {
  reload_lib os.sh
  _OS_ARCH="arm64"
  run os::arch
  assert_output "arm64"
}

# ---------------------------------------------------------------------------
# os::id / os::id_like  (injecting pre-loaded release state)
# ---------------------------------------------------------------------------

@test "os::id returns ID injected via cached globals" {
  reload_lib os.sh
  _OS_ID="ubuntu"
  _OS_RELEASE_LOADED=1
  run os::id
  assert_output "ubuntu"
}

@test "os::id returns alpine" {
  reload_lib os.sh
  _OS_ID="alpine"
  _OS_RELEASE_LOADED=1
  run os::id
  assert_output "alpine"
}

@test "os::id_like returns injected ID_LIKE" {
  reload_lib os.sh
  _OS_ID_LIKE="debian ubuntu"
  _OS_RELEASE_LOADED=1
  run os::id_like
  assert_output "debian ubuntu"
}

@test "os::id_like returns empty string when unset" {
  reload_lib os.sh
  _OS_ID_LIKE=""
  _OS_RELEASE_LOADED=1
  run os::id_like
  assert_output ""
}

# ---------------------------------------------------------------------------
# os::platform
# ---------------------------------------------------------------------------

@test "os::platform returns debian for ID=ubuntu" {
  reload_lib os.sh
  _OS_ID="ubuntu"
  _OS_ID_LIKE=""
  _OS_RELEASE_LOADED=1
  run os::platform
  assert_output "debian"
}

@test "os::platform returns debian for ID=debian" {
  reload_lib os.sh
  _OS_ID="debian"
  _OS_ID_LIKE=""
  _OS_RELEASE_LOADED=1
  run os::platform
  assert_output "debian"
}

@test "os::platform returns alpine for ID=alpine" {
  reload_lib os.sh
  _OS_ID="alpine"
  _OS_ID_LIKE=""
  _OS_RELEASE_LOADED=1
  run os::platform
  assert_output "alpine"
}

@test "os::platform returns rhel for ID=fedora" {
  reload_lib os.sh
  _OS_ID="fedora"
  _OS_ID_LIKE=""
  _OS_RELEASE_LOADED=1
  run os::platform
  assert_output "rhel"
}

@test "os::platform returns rhel for ID=centos" {
  reload_lib os.sh
  _OS_ID="centos"
  _OS_ID_LIKE=""
  _OS_RELEASE_LOADED=1
  run os::platform
  assert_output "rhel"
}

@test "os::platform returns macos for Darwin uname fallback" {
  reload_lib os.sh
  _OS_ID=""
  _OS_ID_LIKE=""
  _OS_RELEASE_LOADED=1
  uname() { echo "Darwin"; }
  export -f uname
  run os::platform
  assert_output "macos"
}

@test "os::platform returns debian as fallback for unknown Linux" {
  reload_lib os.sh
  _OS_ID=""
  _OS_ID_LIKE=""
  _OS_RELEASE_LOADED=1
  uname() { echo "Linux"; }
  export -f uname
  run os::platform
  assert_output "debian"
}

@test "os::platform returns debian when ID_LIKE contains debian" {
  reload_lib os.sh
  _OS_ID="linuxmint"
  _OS_ID_LIKE="ubuntu debian"
  _OS_RELEASE_LOADED=1
  run os::platform
  assert_output "debian"
}

@test "os::platform uses cached _OS_PLATFORM" {
  reload_lib os.sh
  _OS_PLATFORM="rhel"
  run os::platform
  assert_output "rhel"
}

@test "os::platform returns rhel for ID=rhel" {
  reload_lib os.sh
  _OS_ID="rhel"
  _OS_ID_LIKE=""
  _OS_RELEASE_LOADED=1
  run os::platform
  assert_output "rhel"
}

@test "os::platform returns rhel for ID=rocky" {
  reload_lib os.sh
  _OS_ID="rocky"
  _OS_ID_LIKE=""
  _OS_RELEASE_LOADED=1
  run os::platform
  assert_output "rhel"
}

@test "os::platform returns rhel when ID_LIKE contains fedora" {
  reload_lib os.sh
  _OS_ID="custom"
  _OS_ID_LIKE="fedora"
  _OS_RELEASE_LOADED=1
  run os::platform
  assert_output "rhel"
}

# ---------------------------------------------------------------------------
# os::require_root
# ---------------------------------------------------------------------------

@test "os::require_root succeeds when id -u returns 0" {
  reload_lib os.sh
  create_fake_bin "id" "0"
  prepend_fake_bin_path
  run os::require_root
  assert_success
}

@test "os::require_root fails with message when id -u returns non-zero" {
  reload_lib os.sh
  create_fake_bin "id" "1001"
  prepend_fake_bin_path
  run os::require_root
  assert_failure
  assert_output --partial "must be run as root"
}

# ---------------------------------------------------------------------------
# os::font_dir
# ---------------------------------------------------------------------------

@test "os::font_dir returns /usr/share/fonts for root" {
  reload_lib os.sh
  create_fake_bin "id" "0"
  prepend_fake_bin_path
  run os::font_dir
  assert_output "/usr/share/fonts"
}

@test "os::font_dir returns ~/Library/Fonts for macOS non-root" {
  reload_lib os.sh
  create_fake_bin "id" "1001"
  prepend_fake_bin_path
  uname() { echo "Darwin"; }
  export -f uname
  HOME="/home/testuser" run os::font_dir
  assert_output "/home/testuser/Library/Fonts"
}

@test "os::font_dir returns XDG_DATA_HOME path for Linux non-root" {
  reload_lib os.sh
  create_fake_bin "id" "1001"
  prepend_fake_bin_path
  uname() { echo "Linux"; }
  export -f uname
  HOME="/home/testuser" XDG_DATA_HOME="/custom/data" run os::font_dir
  assert_output "/custom/data/fonts"
}

@test "os::font_dir returns default XDG path when XDG_DATA_HOME not set" {
  reload_lib os.sh
  create_fake_bin "id" "1001"
  prepend_fake_bin_path
  uname() { echo "Linux"; }
  export -f uname
  HOME="/home/testuser" XDG_DATA_HOME="" run os::font_dir
  assert_output "/home/testuser/.local/share/fonts"
}
