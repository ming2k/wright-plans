#!/usr/bin/env bash
set -euo pipefail

wbuild run -if bash-completion
wbuild run -if appstream
