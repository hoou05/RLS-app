# RLS iOS Inference Core

This package is the offline iOS inference layer for the exported RLS XGBoost + TabM artifacts.

The intended runtime split is:

- XGBoost: exported to JSON and evaluated in Swift.
- TabM: exported to JSON weights and evaluated in Swift.
- Shared preprocessing: feature projection, missing-value handling, QuantileTransformer, ensemble averaging, and prevalence adjustment in Swift.

Generate assets from the current backend model artifacts:

```bash
/Users/greentao/Development/RLS-app/.conda/rls-ios-infer/bin/python \
  tools/ios_inference_export/export_ios_inference_assets.py --write-validation
```

The exporter writes:

- `ios_inference/Artifacts/RLSModelBundle.json`
- `ios_inference/Artifacts/validation_cases.json`

In an iOS app, add the JSON file to the app bundle, then create `RLSInferenceEngine` with the file URL.

Smoke-test the Swift implementation:

```bash
cd ios_inference
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
SWIFTPM_HOME="$PWD/.build/swiftpm" \
swift run RLSInferenceSmoke
```

Current smoke output for the demo input:

```text
tier1 risk=0.4553466534409043 xgb=0.9650438453591065 tabm=0.46130820737765277
tier2 risk=0.5667035489351995 xgb=0.9987657571053854 tabm=0.5922216895357327
```

`validation_cases.json` stores Python reference outputs computed without the XGBoost runtime: it parses the `.ubj` files directly and uses PyTorch only for the TabM reference path. This avoids the macOS `libxgboost` instability observed during export.
