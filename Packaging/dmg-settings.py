# Copyright (c) 2026 T E Vaughan.
# SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0

from pathlib import Path

app = Path(defines["app"])
files = [(str(app), "Moth.app")]
symlinks = {"Applications": "/Applications"}
icon = str(app / "Contents/Resources/Moth.icns")
background = defines["background"]
hide_extensions = ["Moth.app"]
icon_locations = {"Moth.app": (180, 260), "Applications": (580, 260)}
window_rect = ((120, 120), (760, 508))
icon_size = 112
text_size = 14
format = "UDZO"
