# Component 2 — Chrome preview

Five files. Drop the first four into `lib/pages/`; the fifth is the entry point
you run.

```
lib/pages/digital_phenotyping_page.dart   the page (replaces the existing one)
lib/pages/c2_device_metrics.dart          device abstraction + browser stand-in
lib/pages/c2_device_metrics_live.dart     all Android plugin calls, isolated here
lib/pages/c2_mock_data.dart               fixtures: P613, P658, two synthetic
lib/pages/c2_preview_main.dart            Chrome harness (dev entry point)
```

## Run it

```bash
flutter config --enable-web        # once, if you have not already
flutter run -d chrome -t lib/pages/c2_preview_main.dart
```

No backend, no Android device, no permissions. A rail on the left switches
between fixtures; the phone frame on the right is the real
`DigitalPhenotypingPage`, not a mock-up of it.

If `flutter devices` does not list Chrome, set `CHROME_EXECUTABLE` to your
browser binary.

## What changed so this works

The page previously called `battery_plus`, `geolocator`, `call_log`,
`usage_stats` and `flutter_sms_inbox` directly, which meant it could not build
for the web. Those calls now sit behind `DeviceMetricsSource`:

| Implementation | Used by | Lives in |
|---|---|---|
| `LiveDeviceMetrics` | the Android app | `c2_device_metrics_live.dart` |
| `MockDeviceMetrics` | the Chrome preview | `c2_device_metrics.dart` |
| `null` | anything else | renders every device row as unavailable |

One change is needed wherever the app builds this page:

```dart
// before
DigitalPhenotypingPage(userId: id)

// after
DigitalPhenotypingPage(userId: id, metrics: LiveDeviceMetrics(userId: id))
```

Behaviour on the handset is unchanged — the same code, moved.

## Turning the fixtures off

`c2_mock_data.dart`:

```dart
static const bool _requested = true;                 // set false for real data
static bool get enabled => _requested && !kReleaseMode;
```

`kReleaseMode` means a forgotten `true` cannot reach a participant. With
fixtures off the page falls back to the cached payload from
`SharedPreferences`, then to the baseline-building state.

## Fixtures

| Fixture | Source | Stage shown |
|---|---|---|
| `participant613` | real workbook | 2 — insights, location unavailable |
| `participant658` | real workbook | 2 — insights, location intact |
| `syntheticStage3` | fabricated | 3 — baseline comparison |
| `syntheticStage4` | fabricated | 4 — change detection |

Both synthetic fixtures carry `'synthetic': true`, and the page draws a
sand-coloured banner across the top whenever one is loaded. Do not screenshot
them for the paper.

## Usable-day criterion

A day counts when events land in **at least 12 distinct hours** of it.

The earlier criterion — at least 24 service heartbeats — does not port between
participants. P658 logs exactly one heartbeat per day across all 17 days while
carrying 20 location fixes and 27 screen events daily, so the heartbeat rule
scored it zero usable days despite near-complete coverage.

| Participant | Days with data | Usable, heartbeat rule | Usable, hours rule |
|---|---|---|---|
| 613 | 21 | 14 | 10 |
| 658 | 17 | 0 | 17 |

613 dropping to 10 is the correct direction: 25, 26 and 27 July were observed
for 9–11 hours each.

## Known gaps

- `c2_device_metrics_live.dart` imports `../services/background_service_helper.dart`.
  Adjust the relative path if you place the file elsewhere.
- The clinician app has not been reviewed. The same `display_permitted` guard
  needs to exist there, and absence of a score must be stated rather than left
  blank — otherwise a blank field reads as "low risk".
- The fuse payload still needs `behavioral_score: null, behavioral_weight: 0.0`
  stated explicitly rather than the field being absent.
