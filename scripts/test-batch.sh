#!/bin/sh
for version in 2.0.68 2.0.69 2.0.70 2.0.71 2.0.72 2.0.73; do
  echo "========================================="
  echo "Testing version $version"
  echo "========================================="
  sh test-single.sh $version | grep -E '(Testing|LSP function:|pathToFileURL alias:|path module alias:|Found old|Patched|LSP fix applied)'
  echo
done
