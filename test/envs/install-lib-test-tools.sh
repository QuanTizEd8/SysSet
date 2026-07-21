#!/bin/sh
# Provision the immutable ordinary-suite tool bundle. POSIX sh only.
set -eu

JQ_VERSION=1.8.2
YQ_VERSION=4.53.2
JSONSCHEMA_VERSION=16.2.0
ORAS_VERSION=1.3.2
TOOL_DIR=${DEVFEATS_LIB_TEST_TOOL_DIR:-/opt/devfeats/lib-test-tools/bin}

# The hashes below are published on the immutable GitHub release pages and in
# their upstream checksum assets:
# - https://github.com/jqlang/jq/releases/tag/jq-1.8.2
# - https://github.com/mikefarah/yq/releases/tag/v4.53.2
# - https://github.com/sourcemeta/jsonschema/releases/tag/v16.2.0
# - https://github.com/oras-project/oras/releases/tag/v1.3.2

retry() {
  retry_count=1
  while [ "$retry_count" -le 3 ]; do
    "$@" && return 0
    [ "$retry_count" -eq 3 ] && return 1
    retry_count=$((retry_count + 1))
    sleep 5
  done
}

install_linux_prerequisites() {
  if command -v apt-get > /dev/null 2>&1; then
    retry apt-get update -qq
    DEBIAN_FRONTEND=noninteractive retry apt-get install -y --no-install-recommends \
      ca-certificates curl coreutils diffutils git gnupg passwd findutils \
      util-linux tar gzip unzip xz-utils bzip2
    apt-get clean
    rm -rf /var/lib/apt/lists/*
  elif command -v apk > /dev/null 2>&1; then
    retry apk add --no-cache \
      ca-certificates curl coreutils diffutils git gnupg shadow findutils \
      flock tar gzip unzip xz bzip2
  elif command -v dnf > /dev/null 2>&1; then
    # Minimal EL images provide coreutils-single, which supplies the commands
    # verified below and conflicts with the full coreutils package.
    retry dnf install -y \
      ca-certificates curl diffutils git gnupg2 shadow-utils util-linux-core util-linux-user \
      findutils tar gzip unzip xz bzip2
    dnf clean all
    rm -rf /var/cache/dnf
  elif command -v zypper > /dev/null 2>&1; then
    _zypper_install_prerequisites() {
      set +e
      zypper --non-interactive install --no-recommends \
        ca-certificates curl coreutils diffutils git gpg2 shadow util-linux findutils \
        tar gzip unzip xz bzip2
      _zypper_rc=$?
      set -e
      [ "$_zypper_rc" -eq 0 ] || [ "$_zypper_rc" -eq 106 ]
    }
    retry _zypper_install_prerequisites
    zypper clean --all
  elif command -v pacman > /dev/null 2>&1; then
    # Rolling Arch must never perform a partial `-Sy` upgrade.
    retry pacman -Syu --noconfirm --needed \
      ca-certificates curl coreutils diffutils git gnupg shadow util-linux findutils \
      tar gzip unzip xz bzip2
    pacman -Scc --noconfirm
  else
    echo 'Unsupported package manager for library-test tools.' >&2
    return 1
  fi
}

install_darwin_prerequisites() {
  command -v brew > /dev/null 2>&1 || {
    echo 'Homebrew is required to prepare macOS library-test prerequisites.' >&2
    return 1
  }
  retry brew install flock gnupg xz
}

kernel=$(uname -s)
case "$kernel" in
  Linux)
    asset_os=linux
    ;;
  Darwin)
    asset_os=darwin
    ;;
  *)
    echo "Unsupported operating system for library-test tools: $kernel" >&2
    exit 1
    ;;
esac

machine=$(uname -m)
case "$machine" in
  x86_64 | amd64)
    asset_arch=amd64
    jsonschema_arch=x86_64
    ;;
  aarch64 | arm64)
    asset_arch=arm64
    jsonschema_arch=arm64
    ;;
  *)
    echo "Unsupported architecture for library-test tools: $machine" >&2
    exit 1
    ;;
esac

jsonschema_libc=
if [ "$asset_os" = linux ]; then
  libc_description=$(ldd --version 2>&1 || :)
  if printf '%s\n' "$libc_description" | grep -qi musl; then
    jsonschema_libc=-musl
  elif ! printf '%s\n' "$libc_description" | grep -Eqi 'glibc|GNU libc|GNU C Library'; then
    echo "Unsupported Linux libc for library-test tools: $libc_description" >&2
    exit 1
  fi
fi

case "$asset_os/$asset_arch$jsonschema_libc" in
  linux/amd64)
    jq_sha=b1c22172dd303f3be49e935aa56aa48a8b7a46e0bc838b4997d3bb451495870f
    yq_sha=d56bf5c6819e8e696340c312bd70f849dc1678a7cda9c2ad63eebd906371d56b
    jsonschema_sha=6706cf6bd80d978ecbe0e3fbb7b44aee75a8bb6baa2ee5452dc55cb6c8f3e1be
    oras_sha=9229ccc6d17bb282039ad4a69abb16dcb887a5bce567c075d731d9b3c7ad8eaf
    ;;
  linux/arm64)
    jq_sha=8b85c817833814ddca00a144c33705546355afccf0cf39b188f3cdb48b852309
    yq_sha=03061b2a50c7a498de2bbb92d7cb078ce433011f085a4994117c2726be4106ea
    jsonschema_sha=a7eb3f9005c065290514661fdedacf0e0f0bec05bcbe1fcc9600e3ba0de16ed9
    oras_sha=8db4a223bd6034deff198e791ea7cb3af0840df25b7e9f370e2f1f3fd20d389b
    ;;
  linux/amd64-musl)
    jq_sha=b1c22172dd303f3be49e935aa56aa48a8b7a46e0bc838b4997d3bb451495870f
    yq_sha=d56bf5c6819e8e696340c312bd70f849dc1678a7cda9c2ad63eebd906371d56b
    jsonschema_sha=2296c08debdb471dcc5e35af2e4d6f6f6b27baa5e96db9cc65423bd7c2810f6c
    oras_sha=9229ccc6d17bb282039ad4a69abb16dcb887a5bce567c075d731d9b3c7ad8eaf
    ;;
  linux/arm64-musl)
    jq_sha=8b85c817833814ddca00a144c33705546355afccf0cf39b188f3cdb48b852309
    yq_sha=03061b2a50c7a498de2bbb92d7cb078ce433011f085a4994117c2726be4106ea
    jsonschema_sha=bc9e27e33a13106e58bb000fafe8e47b95f8f8208481ea202d6ca916ffdb2a8e
    oras_sha=8db4a223bd6034deff198e791ea7cb3af0840df25b7e9f370e2f1f3fd20d389b
    ;;
  darwin/amd64)
    jq_sha=e94b266e3c26690550006abe63152b782280f4e14374accdf04cbde844f00bc0
    yq_sha=616b0a0f6a5b79d746f05a169c2b9bb40dee00c605ef165b9a1c1681bba738ac
    jsonschema_sha=44f5dfbba2a1f2bbf2d85b7c5b2cd5055a20d1a5656e602c6d146edea235ff5c
    oras_sha=2621f6b252b222f6fbf4e114d2fcaa0cec6b632624ffaf73143f66e4e0994f86
    ;;
  darwin/arm64)
    jq_sha=2d75340ba57a4b4b4c8708a21c2dc8e958a48aaa8bba13b27f77f6e4c0eca07e
    yq_sha=541ba2287560df70f561955e2d7f7e1cd00cf2a15a884f6b5c87a4bfa887bc07
    jsonschema_sha=95574d8ad36a30fb91967b056441a2b68c24d2441741b271544c3fb48a6c8f97
    oras_sha=7929f792cf272268412375ecad6f0fb3c20f164368d5b57966e67ad6d36eca53
    ;;
  *)
    echo "Unsupported platform for library-test tools: $asset_os/$asset_arch$jsonschema_libc" >&2
    exit 1
    ;;
esac

case "$TOOL_DIR" in
  /*/)
    echo "Library-test tool directory must not end with '/': $TOOL_DIR" >&2
    exit 1
    ;;
  /*) ;;
  *)
    echo "Library-test tool directory must be absolute: $TOOL_DIR" >&2
    exit 1
    ;;
esac
if [ "$TOOL_DIR" = / ] || [ -e "$TOOL_DIR" ] || [ -L "$TOOL_DIR" ]; then
  echo "Library-test tool directory must be a new non-root path: $TOOL_DIR" >&2
  exit 1
fi

[ "$asset_os" = linux ] && install_linux_prerequisites
[ "$asset_os" = darwin ] && install_darwin_prerequisites

if ! command -v flock > /dev/null 2>&1 && ! command -v shlock > /dev/null 2>&1; then
  echo 'Missing library-test locking prerequisite (flock or shlock).' >&2
  exit 1
fi

for prerequisite in curl grep cmp git gpg find install tar gzip unzip xz bzip2; do
  if ! command -v "$prerequisite" > /dev/null 2>&1; then
    echo "Missing prerequisite for library-test tools: $prerequisite" >&2
    exit 1
  fi
done
if [ "$asset_os" = linux ]; then
  for prerequisite in getent groupadd useradd userdel groupdel chsh; do
    if ! command -v "$prerequisite" > /dev/null 2>&1; then
      echo "Missing Linux integration prerequisite: $prerequisite" >&2
      exit 1
    fi
  done
fi
if command -v sha256sum > /dev/null 2>&1; then
  checksum_tool=sha256sum
elif command -v shasum > /dev/null 2>&1; then
  checksum_tool=shasum
else
  echo 'Missing SHA-256 checksum tool (sha256sum or shasum).' >&2
  exit 1
fi

work_dir=$(mktemp -d)
destination_created=0
cleanup() {
  rm -rf "$work_dir"
  if [ "$destination_created" -eq 1 ]; then
    rm -rf "$TOOL_DIR"
  fi
}
on_signal() {
  _signal_status=$1
  trap - EXIT HUP INT TERM
  cleanup
  exit "$_signal_status"
}
trap cleanup EXIT
trap 'on_signal 129' HUP
trap 'on_signal 130' INT
trap 'on_signal 143' TERM

download() {
  # curl owns the sole bounded retry budget. Do not wrap this call in retry().
  curl --fail --show-error --silent --location --compressed \
    --proto '=https' --tlsv1.2 --connect-timeout 20 --max-time 300 \
    --retry 5 --retry-delay 2 --retry-connrefused \
    -H 'User-Agent: devfeats-lib-tests' "$1" -o "$2"
}

verify_checksum() {
  _expected=$1
  _path=$2
  _manifest=$3
  printf '%s  %s\n' "$_expected" "$_path" > "$_manifest"
  if [ "$checksum_tool" = sha256sum ]; then
    sha256sum -c "$_manifest"
  else
    shasum -a 256 -c "$_manifest"
  fi
}

jq_asset=jq-$asset_os-$asset_arch
[ "$asset_os" = darwin ] && jq_asset=jq-macos-$asset_arch
yq_asset=yq_${asset_os}_${asset_arch}
jsonschema_asset=jsonschema-${JSONSCHEMA_VERSION}-${asset_os}-${jsonschema_arch}${jsonschema_libc}.zip
jsonschema_package=${jsonschema_asset%.zip}
oras_asset=oras_${ORAS_VERSION}_${asset_os}_${asset_arch}.tar.gz

jq_tmp=$work_dir/jq
yq_tmp=$work_dir/yq
jsonschema_archive=$work_dir/jsonschema.zip
oras_archive=$work_dir/oras.tar.gz

download "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/${jq_asset}" "$jq_tmp"
download "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/${yq_asset}" "$yq_tmp"
download "https://github.com/sourcemeta/jsonschema/releases/download/v${JSONSCHEMA_VERSION}/${jsonschema_asset}" "$jsonschema_archive"
download "https://github.com/oras-project/oras/releases/download/v${ORAS_VERSION}/${oras_asset}" "$oras_archive"

# Authenticate every archive before extracting it and every binary before it is
# made executable. This prevents unverified release content from being run.
verify_checksum "$jq_sha" "$jq_tmp" "$work_dir/jq.sha256"
verify_checksum "$yq_sha" "$yq_tmp" "$work_dir/yq.sha256"
verify_checksum "$jsonschema_sha" "$jsonschema_archive" "$work_dir/jsonschema.sha256"
verify_checksum "$oras_sha" "$oras_archive" "$work_dir/oras.sha256"

mkdir "$work_dir/jsonschema-extract" "$work_dir/oras-extract"
jsonschema_member=$jsonschema_package/bin/jsonschema
unzip -q "$jsonschema_archive" "$jsonschema_member" -d "$work_dir/jsonschema-extract"
tar -xzf "$oras_archive" -C "$work_dir/oras-extract" oras
jsonschema_tmp=$work_dir/jsonschema-extract/$jsonschema_member
oras_tmp=$work_dir/oras-extract/oras
for path in "$jq_tmp" "$yq_tmp" "$jsonschema_tmp" "$oras_tmp"; do
  test -f "$path" && test ! -L "$path"
done
chmod 0555 "$jq_tmp" "$yq_tmp" "$jsonschema_tmp" "$oras_tmp"

[ "$("$jq_tmp" --version)" = "jq-${JQ_VERSION}" ]
[ "$("$yq_tmp" --version)" = "yq (https://github.com/mikefarah/yq/) version v${YQ_VERSION}" ]
[ "$("$jsonschema_tmp" version)" = "$JSONSCHEMA_VERSION" ]
"$oras_tmp" version > "$work_dir/oras.version"
grep -Eq "^Version:[[:space:]]+${ORAS_VERSION}$" "$work_dir/oras.version"
[ "$(printf '%s\n' '{"value":42}' | "$jq_tmp" -r '.value')" = 42 ]
[ "$(printf 'value: 42\n' | "$yq_tmp" -r '.value')" = 42 ]
printf '{"$schema":"https://json-schema.org/draft/2020-12/schema"}\n' > "$work_dir/schema.json"
"$jsonschema_tmp" metaschema "$work_dir/schema.json" > /dev/null
"$oras_tmp" manifest fetch --help > /dev/null

tool_parent=${TOOL_DIR%/*}
mkdir -p "$tool_parent"
test ! -L "$tool_parent"
mkdir "$TOOL_DIR"
destination_created=1
cp "$jq_tmp" "$TOOL_DIR/jq"
cp "$yq_tmp" "$TOOL_DIR/yq"
cp "$jsonschema_tmp" "$TOOL_DIR/jsonschema"
cp "$oras_tmp" "$TOOL_DIR/oras"
if [ "$asset_os" = linux ]; then
  chown root:root "$TOOL_DIR/jq" "$TOOL_DIR/yq" "$TOOL_DIR/jsonschema" "$TOOL_DIR/oras" "$TOOL_DIR"
fi
chmod 0555 "$TOOL_DIR/jq" "$TOOL_DIR/yq" "$TOOL_DIR/jsonschema" "$TOOL_DIR/oras" "$TOOL_DIR"
for path in "$TOOL_DIR/jq" "$TOOL_DIR/yq" "$TOOL_DIR/jsonschema" "$TOOL_DIR/oras"; do
  test -f "$path" && test ! -L "$path" && test -x "$path"
done
test -d "$TOOL_DIR" && test ! -L "$TOOL_DIR"
destination_created=0
