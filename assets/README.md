# assets

Drop the app icon source here as **`AppIcon-1024.png`** (1024×1024 PNG).

`make build-app` runs `scripts/make-icns.sh` to generate `AppIcon.icns` into the
`.app` bundle's Resources. If this file is absent, the app still builds — just
without a custom icon (the Makefile prints a warning).
