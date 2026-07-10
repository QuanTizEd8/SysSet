# Bash Library

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/argparse.bash
. "$_LIB_DIR/argparse.bash"
# shellcheck source=lib/bootstrap.bash
. "$_LIB_DIR/bootstrap.bash"
# shellcheck source=lib/cargo.bash
. "$_LIB_DIR/cargo.bash"
# shellcheck source=lib/ctx.bash
. "$_LIB_DIR/ctx.bash"
# shellcheck source=lib/file.bash
. "$_LIB_DIR/file.bash"
# shellcheck source=lib/git.bash
. "$_LIB_DIR/git.bash"
# shellcheck source=lib/github.bash
. "$_LIB_DIR/github.bash"
# shellcheck source=lib/graph.bash
. "$_LIB_DIR/graph.bash"
# shellcheck source=lib/install.bash
. "$_LIB_DIR/install.bash"
# shellcheck source=lib/json.bash
. "$_LIB_DIR/json.bash"
# shellcheck source=lib/lock.bash
. "$_LIB_DIR/lock.bash"
# shellcheck source=lib/logging.bash
. "$_LIB_DIR/logging.bash"
# shellcheck source=lib/logging.sh
. "$_LIB_DIR/logging.sh"
# shellcheck source=lib/net.bash
. "$_LIB_DIR/net.bash"
# shellcheck source=lib/npm.bash
. "$_LIB_DIR/npm.bash"
# shellcheck source=lib/oci.bash
. "$_LIB_DIR/oci.bash"
# shellcheck source=lib/os.bash
. "$_LIB_DIR/os.bash"
# shellcheck source=lib/ospkg.bash
. "$_LIB_DIR/ospkg.bash"
# shellcheck source=lib/posix.sh
. "$_LIB_DIR/posix.sh"
# shellcheck source=lib/proc.bash
. "$_LIB_DIR/proc.bash"
# shellcheck source=lib/shell.bash
. "$_LIB_DIR/shell.bash"
# shellcheck source=lib/str.bash
. "$_LIB_DIR/str.bash"
# shellcheck source=lib/sys_req.bash
. "$_LIB_DIR/sys_req.bash"
# shellcheck source=lib/uri.bash
. "$_LIB_DIR/uri.bash"
# shellcheck source=lib/users.bash
. "$_LIB_DIR/users.bash"
# shellcheck source=lib/ver.bash
. "$_LIB_DIR/ver.bash"
# shellcheck source=lib/verify.bash
. "$_LIB_DIR/verify.bash"

unset _LIB_DIR
