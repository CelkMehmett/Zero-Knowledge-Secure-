## Publishing zk_vault to pub.dev

This document lists the exact steps and commands to publish the `zk_vault` package to pub.dev from your local machine and how to optionally automate publishing from CI.

Prerequisites
- You have a pub.dev account and appropriate permissions to publish the package name `zk_vault`.
- The package `pubspec.yaml` `version` is set to the intended release version (currently `0.1.1`).
- All unit tests pass locally and `dart analyze` reports no issues.

Local publish checklist
1. Confirm tests and analyzer:

```bash
dart pub get
dart analyze
flutter test --reporter=expanded   # if you have Flutter-based tests (recommended)
```

2. Run a dry-run publish to validate package contents and metadata:

```bash
dart pub publish --dry-run
```

3. If the dry-run is successful, publish interactively:

```bash
dart pub publish
```

- The `dart pub publish` command is interactive. It will ask for confirmation and to authenticate if necessary. Follow the prompts.

4. (Optional) Push commit and tag to your remote (recommended for traceability):

```bash
git remote add origin git@github.com:your-org/zk_vault.git   # only if not set
git push -u origin main
git push origin v0.1.1
```

Troubleshooting notes
- "Authentication required": run `dart pub publish` and follow the login prompts. If running from CI, create a pub.dev upload token and use it in your workflow secrets.
- "Package already exists / different owner": either transfer ownership on pub.dev or pick a different package name.
- Dry-run shows unexpected files: use `dart pub pack` to inspect the archive and adjust `pubspec.yaml` `exclude` or `.gitignore`.

Optional: GitHub Actions workflow to publish on tag

Below is a minimal workflow you can add under `.github/workflows/publish.yml`. It will run on push tags like `v*.*.*` and publish using a `PUB_DEV_TOKEN` repo secret.

```yaml
name: Publish

on:
  push:
    tags:
      - 'v*.*.*'

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup Dart
        uses: dart-lang/setup-dart@v2
        with:
          sdk: 'stable'
      - name: Install dependencies
        run: dart pub get
      - name: Analyze
        run: dart analyze
      - name: Run tests
        run: dart test --reporter=expanded
      - name: Publish to pub.dev
        env:
          PUB_DEV_TOKEN: ${{ secrets.PUB_DEV_TOKEN }}
        run: |
          echo "$PUB_DEV_TOKEN" | dart pub token add
          dart pub publish --force
```

Notes on CI token: create a pub.dev token (on pub.dev account page) and store it as the repository secret `PUB_DEV_TOKEN`. Publishing from CI is powerful and irreversible — use with care.

If you'd like, I can:
- Create this workflow file in your repo and commit it.
- Push your local tag to a remote you provide.
- Walk you through the interactive `dart pub publish` process step-by-step while you run it locally.

---
Small reminder: publishing a package is irreversible and may affect users. Ensure the public API and docs are ready before publishing.
