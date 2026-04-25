#!/usr/bin/env bash
layout=$(LC_ALL=C hyprctl devices -j 2>/dev/null | jq -r '(.keyboards[] | select(.main == true) | .active_keymap) // .keyboards[0].active_keymap // empty' | head -n1)
[[ -z "$layout" || "$layout" == "null" ]] && layout="US"
echo "${layout:0:2}" | tr '[:lower:]' '[:upper:]'
