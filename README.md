# README.md — HESABI

Hesabi (حسابي) — Multi-tenant SaaS for POS, Inventory, Sales and Accounting.

**Phase 0 — Foundation only.** No business features, no authentication, no
database schema.

## Requirements

| Tool  | Version       |
|-------|---------------|
| Flutter | >= 3.24.0   |
| Dart    | >= 3.5.0    |

## Bootstrap

```sh
flutter create --org com.hesabi --project-name hesabi .
# then drop the provided lib/, test/, pubspec.yaml, analysis_options.yaml in place
flutter pub get
flutter analyze
flutter test
flutter build web --release
