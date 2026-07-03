# RLS Screen iOS App

This is the first offline iOS shell for the RLS screening model.

Current scope:

- Manual feature entry.
- Fully local Tier 1 and Tier 2 inference.
- Local XGBoost + TabM ensemble via the `ios_inference` Swift package.
- On-device history stored as JSON in Application Support.
- No backend, account, network call, or HealthKit dependency yet.

Open in Xcode:

```bash
open apps/ios/RLSScreen/RLSScreen.xcodeproj
```

The app target depends on the local Swift package at:

```text
../../../ios_inference
```

The app bundle includes:

```text
RLSScreen/Resources/RLSModelBundle.json
```

When the model artifacts are regenerated, copy the refreshed bundle into the app resources:

```bash
cp ios_inference/Artifacts/RLSModelBundle.json \
  apps/ios/RLSScreen/RLSScreen/Resources/RLSModelBundle.json
```

Next HealthKit step:

- Replace `ManualOnlyHealthDataProvider` with a HealthKit-backed provider.
- Request sleep, heart-rate, resting-heart-rate, step-count, and oxygen-saturation permissions.
- Populate `ScreeningForm` from the latest available HealthKit aggregates while leaving unavailable fields nil or manually editable.
