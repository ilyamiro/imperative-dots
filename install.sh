#!/usr/bin/env bash

DOTS_VERSION="2.0.0"

set -euo pipefail

exec bash -c "$(curl -fsSL https://raw.githubusercontent.com/ilyamiro/serpantinum/master/install/install.sh)" -- "$@"
