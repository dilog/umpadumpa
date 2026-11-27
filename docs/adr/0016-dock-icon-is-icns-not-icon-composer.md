# Dock icon is an icns, not Icon Composer

On macOS 27 (Golden Gate) the Dock does not show a full-bleed illustration the same way Finder does. If the app ships Icon Composer (`AppIcon.icon` + `CFBundleIconName`), the Dock composites that document into the system squircle: a gray well, even when the PNG is opaque. Finder still used `AppIcon.icns` and looked correct. We ship only `AppIcon.icns` from the opaque `AppIcon.png`. Rejected: Icon Composer around this artwork, `dockTile` / Get Info workarounds, and using the transparent mascot cut-out as the app icon.
