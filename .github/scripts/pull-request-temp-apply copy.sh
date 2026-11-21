#!/usr/bin/env bash

set -euo pipefail

fail() {
  echo "::error::$1"
  exit 1
}

warn() {
  echo "::warning::$1"
}