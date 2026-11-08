set windows-shell := ["pwsh.exe", "-NoLogo", "-Command"]

# Same gates as CI / pre-commit.
check:
    dart format --output=none --set-exit-if-changed .
    flutter analyze
    flutter test
