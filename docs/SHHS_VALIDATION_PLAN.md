# SHHS Validation Plan

## What SHHS Can Validate

SHHS is useful as an external sleep cohort for model sanity checks, transportability checks, feature coverage, and subgroup stress testing. It should not be treated as a direct supervised RLS validation set unless a defensible RLS outcome label is added from approved SHHS variables or external adjudication.

Recommended first pass:

1. Download `shhs/datasets` only.
2. Project SHHS Visit 1 rows into the current RLS feature schema.
3. Score the cohort with the wearable-only `sleep_heart_basic__apple` adapter.
4. Report missingness, score distribution, and subgroup summaries by age, sex, BMI, sleep efficiency, AHI, and PSG quality.
5. Only download EDF/PSG files if we need to recompute raw sleep or heart-rate features.

## Download

SHHS data is distributed by the National Sleep Research Resource (NSRR). Access requires approval through sleepdata.org, and downloads use the user's NSRR token.

The current SHHS datasets folder includes:

- `shhs1-dataset-0.21.0.csv`
- `shhs2-dataset-0.21.0.csv`
- `shhs-harmonized-dataset-0.21.0.csv`
- CVD event/summary datasets
- data dictionary CSVs

Use the local script:

```bash
tools/download_shhs.sh datasets
```

For non-interactive use:

```bash
NSRR_TOKEN='...' tools/download_shhs.sh datasets
```

The script downloads into `data/nsrr`, which is ignored by git. On the current machine, Ruby 2.6.10 works with the last compatible NSRR gem:

```bash
gem install nsrr -v 5.0.0 --user-install --no-document
```

The latest NSRR gem requires Ruby 2.7.2+, but upgrading Ruby is not required for the tabular SHHS download path. The script also accepts `NSSR_TOKEN` to tolerate the current local `.env` typo, but new environments should use `NSRR_TOKEN`.

Avoid `tools/download_shhs.sh all` or `polysomnography` until we have a storage plan. EDFs and annotation files are much larger than the tabular datasets and are not needed for the first validation pass.

## Feature Projection

Prepare JSONL model inputs from downloaded CSVs:

```bash
/Users/greentao/anaconda3/bin/python tools/prepare_shhs_features.py \
  --input-dir data/nsrr/shhs/datasets \
  --visit shhs1 \
  --output outputs/shhs/shhs1_features.jsonl
```

Initial mapping:

| RLS feature | SHHS variable candidates |
| --- | --- |
| `sleep_duration_minutes` / `总睡眠时间/分` | `nsrr_ttldursp_f1`, `slpprdp` |
| `sleep_efficiency` / `睡眠效率%` | `nsrr_ttleffsp_f1`, `slpeffp` |
| `WASO/分 入睡后清醒时间` | `nsrr_ttldurws_f1`, `waso` |
| `睡眠潜伏期/分` | `nsrr_ttllatsp_f1`, `slplatp` |
| `REM睡眠潜伏期/分` | `nsrr_ttldursp_s1sr`, `remlaiip`, `remlaip` |
| `N1N2%` | `nsrr_pctdursp_s1 + nsrr_pctdursp_s2` |
| `N3%` | `nsrr_pctdursp_s3` |
| `R%` | `nsrr_pctdursp_sr` |
| `年龄_发病年龄合并` / `age` | `nsrr_age`, `age_s1`, `age_s2` |
| `性别_男1女0` / `sex` | `nsrr_sex`, `gender` |
| `身高cm` / `height` | `height`, `pm207` |
| `体重Kg` / `weight` | `weight`, `pm202` |
| `BMI` / `bmi` | `nsrr_bmi`, `bmi_s1`, `bmi_s2` |

Known gaps:

- Current app adapter does not directly expose all PSG-derived features, so `prepare_shhs_features.py` places extra exact experiment names under `experiment_features`.
- Mean/min SpO2 and mean/min/max heart-rate fields need confirmation against the downloaded dictionary before being used as final validation features.
- SHHS does not provide the Tier 2 app questionnaire fields, so use Tier 1 unless a clinically defensible proxy is specified.

## Scoring

Use the project conda environment that already has the optional model dependencies:

```bash
/Users/greentao/Development/RLS-app/.conda/rls-ios-infer/bin/python tools/score_shhs_features.py \
  --input outputs/shhs/shhs1_features.jsonl \
  --output outputs/shhs/shhs1_scores.jsonl
```

For raw ensemble scores without the app adapter's population-prevalence adjustment:

```bash
/Users/greentao/Development/RLS-app/.conda/rls-ios-infer/bin/python tools/score_shhs_features.py \
  --input outputs/shhs/shhs1_features.jsonl \
  --output outputs/shhs/shhs1_scores_raw.jsonl \
  --no-prevalence-adjustment
```

The current `.conda/rls-ios-infer` environment has `xgboost`, `torch`, and `tabm`. It uses `scikit-learn 1.9.0`, while `tabm_qt.pkl` was saved with `scikit-learn 1.5.2`; scoring works, but final validation reports should pin a closer sklearn version or document the persistence-version warning.

## Validation Outputs

Minimum report:

- Row count and feature coverage.
- Missingness by feature and by subgroup.
- Model score distribution before and after prevalence adjustment.
- Sensitivity of scores to missing SHHS-only fields.
- Subgroup summaries: sex, age band, BMI band, AHI band, sleep efficiency quartile, Visit 1 vs Visit 2 if both are used.
- Clear statement that this is external-cohort behavior validation, not diagnostic RLS performance validation.

Do not commit SHHS data, derived row-level features, model outputs with subject identifiers, tokens, or local reports containing restricted data.

## First SHHS1 Run

Downloaded files:

- `shhs1-dataset-0.21.0.csv`
- `shhs2-dataset-0.21.0.csv`
- CVD event/summary datasets
- SHHS 0.21.0 data dictionaries

Feature projection for SHHS Visit 1 produced 5,804 rows. Coverage was 100% for total sleep time, sleep efficiency, age, and sex; 98.05%-99.28% for weight, height, and BMI; 97.21% for sleep-stage percentage/time features.

Wearable-only `sleep_heart_basic__apple-xgb-tabm-v2` scores:

| Run | Mean | Median | P95 | Max | Low | Moderate | High |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Prevalence-adjusted | 0.1240 | 0.0999 | 0.3120 | 0.6832 | 78.95% | 17.80% | 3.26% |
| Raw ensemble | 0.2735 | 0.2482 | 0.5742 | 0.8651 | 33.49% | 38.15% | 28.36% |

Interpretation: the external cohort can already test feature transport and score behavior. The raw-to-adjusted difference is large enough that prevalence/calibration assumptions need explicit review before treating thresholds as clinically meaningful.
