#!/bin/bash
# Verifies that manifest prescript runs before package install and script
# runs after, by checking the order of entries written to /tmp/order.log.
set -e

source dev-container-features-test-lib

check "order log has two entries" bash -c "[ \$(wc -l < /tmp/order.log) -eq 2 ]"
check "first entry is 'pre'" bash -c "[ \"\$(sed -n '1p' /tmp/order.log)\" = 'pre' ]"
check "second entry is 'post'" bash -c "[ \"\$(sed -n '2p' /tmp/order.log)\" = 'post' ]"
check "tree is installed" command -v tree

reportResults
