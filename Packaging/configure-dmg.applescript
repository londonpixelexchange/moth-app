-- Copyright (C) 2026 T E Vaughan and Moth contributors.
-- SPDX-License-Identifier: GPL-3.0-or-later

on run argv
 set mountPath to item 1 of argv
 tell application "Finder"
  set installerDisk to disk of (POSIX file mountPath as alias)
  tell installerDisk
   open
   tell container window
    set current view to icon view
    set toolbar visible to false
    set statusbar visible to false
    set bounds to {120, 120, 880, 628}
   end tell
   set opts to icon view options of container window
   set arrangement of opts to not arranged
   set icon size of opts to 112
   set text size of opts to 14
   set background picture of opts to file ".background:installer-background.tiff"
   set position of item "Moth.app" to {180, 260}
   set extension hidden of item "Moth.app" to true
   set position of item "Applications" to {580, 260}
   close
   open
   delay 2
   close
  end tell
 end tell
 delay 2
end run
