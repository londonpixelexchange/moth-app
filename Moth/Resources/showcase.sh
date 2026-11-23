#!/bin/bash
# Copyright (c) 2026 T E Vaughan.
# SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
# Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

showcase() {
printf '\033[2J\033[H\n  \033[1mMoth\033[0m\n\n'
printf '  Nerd Font   \xee\x82\xa0 main  \xee\x82\xb0  \xef\x84\xa0  \xef\x84\xa1  \xef\x92\x89  \xef\x83\xa7\n\n'
printf '  Truecolour  '
for i in $(seq 0 59); do printf '\033[48;2;%d;%d;%dm ' "$((65+i*3))" "$((90+i))" "$((180+i))"; done
printf '\033[0m\n\n  Sixel / live raster graphics\n\n'
# A 240 x 60 raster, transmitted over the PTY using DCS sixel.
printf '\033Pq"1;1;240;60#0;2;65;72;100#1;2;55;85;70#2;2;100;70;45'
for row in $(seq 1 10); do printf '#0!80~#1!80~#2!80~-'; done
printf '\033\\\n\n  Graphics test complete.\n\n'

}
payload="$(showcase)"
printf "%s\n" "$payload"
