set windows-shell := ["pwsh.exe", "-NoLogo", "-Command"]

# Same gates as CI / pre-commit.
check:
    dart format --output=none --set-exit-if-changed .
    flutter analyze
    flutter test

# Interactive dev: Windows desktop (audio routing is Windows-only). Trace flags: `just dev --dart-define=STAGE_CUE_SYNC_TRACE=true`.
dev *args:
    flutter run -d windows {{ args }}
