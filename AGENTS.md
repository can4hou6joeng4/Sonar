# Sonar development guidelines

- Build the shared application with `Sonar.xcodeproj`, scheme `Sonar`. Keep the app and widget extension build versions aligned.
- Keep one root playback service and route persistent library changes through LibraryStore. Preserve user data during migrations and failures.
- Never commit credentials, signing certificates, provisioning profiles, local workflow data, test source, or generated build artifacts.
- Local tests and their `Sonar.local.xcodeproj` are intentionally untracked. Use them when present; the shared application must build without them.
- Read README.md for the build procedure. Project operation must not require locally installed agent frameworks.
- Commit messages use `type(scope): 中文描述`, one subject line only, without a body or trailers.
- For simulator screenshots use `scripts/shot.sh` to produce reduced JPEGs. Inspect each screenshot once and reuse the observation.
