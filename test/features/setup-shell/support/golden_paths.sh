# shellcheck shell=bash
# Enumerate every setup-shell-managed file on the live filesystem, NUL-separated.
#
# Shared by golden_capture.sh (which copies these into the committed fixtures)
# and assert_golden.sh (which diffs the fixtures back against these), so capture
# and assertion always look at the exact same set — the golden comparison is
# symmetric and needs no per-scenario option values.
#
# "Managed" = any file carrying a `# >>> setup-shell-… >>>` marker, plus the two
# categories that setup-shell deploys without a marker: the (possibly empty)
# theme scaffold files, and the /etc/environment BASH_ENV line.

ss_golden_live_files() {
  {
    grep -rlZ '# >>> setup-shell-' /etc /root /home 2> /dev/null || true
    if [ -f /etc/environment ] && grep -q '^BASH_ENV=' /etc/environment 2> /dev/null; then
      printf '/etc/environment\0'
    fi
    find /root /home -maxdepth 6 -type f \( -name bashtheme -o -name zshtheme \) \
      -print0 2> /dev/null || true
  } | sort -zu
}
