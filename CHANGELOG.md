# Changelog

All notable changes to this project will be documented in this file.

## 0.1.0 - 2025-10-18
- Initial public-ready package skeleton
- Implemented `ZKVault` with AES-256-GCM encryption using `package:cryptography`
- `PlatformKMS` abstraction with `MockPlatformKMS` for testing
- JSON-backed atomic storage and unit tests
- README, LICENSE, and example included

## 0.1.1 - 2025-10-18
- Prefer platform application-support directory for vault storage via `path_provider`, falling back to system temp when necessary
- README updated to document storage behavior and file locations
- CI workflow and publish preparation updates
- Minor fixes: analyzer/lint cleanups and test stability improvements
