# Textify app icon

`textify-icon.png` is the owner's selected concept A from the September 22, 2026
logo exploration: a white T with cyan waveform bars on a blue rounded square.
The built-in image generation tool isolated and refined the selected concept,
including a transparent background. No manual drawing or overlays were applied.

The build copies this source to `resources/icon.png` for application and tray
packaging on macOS and Linux. The renderer imports the same source for its
sidebar. Keep the alpha channel and surrounding padding when producing platform
icon formats.

## Windows icon

Windows shows app icons at 16–48 px in the taskbar, title bar and notification
area, where the tile shrinks to a blue square. `scripts/windows-icon.mjs` draws
the same T and waveform bars without the tile, on a transparent background, in
the logo's blue and cyan darkened to read on light and dark taskbars. It lays
out each of the 15 Win32 sizes on whole pixels. On Windows the build writes the
result to `resources/icon.ico`, which electron-builder uses for the program,
installer and uninstaller, and the app uses for its tray icon.

## Final generation prompt

Extract and finish ONLY the TOP-LEFT blue icon (concept A) from the supplied Textify logo comparison sheet as the final app icon. Preserve that exact chosen design: cobalt/electric-blue rounded-square tile, large bold white rounded T in the center, three cyan rounded vertical waveform bars on EACH side of the T with short-tall-short heights. Preserve the original T shape, proportions, colors, restrained surface shading, edge highlight, and visual balance. Recreate it crisply at high resolution; this is an isolation/production cleanup, not a redesign. Output one square 1024x1024 PNG with a genuinely TRANSPARENT background outside the rounded-square icon, including transparent corners. Center the tile with about 7 percent transparent padding on all sides so it sits correctly beside other macOS Dock icons. No colored backdrop, no background glow, no label A, no words, no other icons, no grid, no added decoration. Keep the icon front-facing, symmetrical and undistorted, with a sharp silhouette and clean alpha edge.
