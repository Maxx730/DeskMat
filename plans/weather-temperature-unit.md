# Plan: Weather Temperature Unit Toggle (°F / °C)

## Goal

Add a segmented °F / °C toggle to the weather settings section. The setting persists across launches, defaults to Fahrenheit, and causes the widget to re-fetch immediately with the correct unit from the Open-Meteo API.

---

## Current State

- `WeatherService.fetch()` hardcodes `temperature_unit=fahrenheit` in the URL (line 75)
- The widget re-fetches whenever `weatherLatitude` changes (`.task(id: weatherLatitude)`)
- Weather settings live in `WidgetsSettingsTab` inside `SettingsView.swift` (around line 374)
- No unit preference exists in `UserDefaults` yet

---

## Phases

---

### Phase 1 — Persist the unit preference + pass it to the API

**Files:** `WeatherService.swift`

#### Change `fetch()` signature

Add a `unit` parameter so the caller controls which unit the API returns:

```swift
func fetch(latitude: Double, longitude: Double, locationName: String, unit: String = "fahrenheit") async {
```

#### Update the URL

Replace the hardcoded `temperature_unit=fahrenheit`:

```swift
guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current=temperature_2m,weather_code&temperature_unit=\(unit)") else { return }
```

#### Update the formatted temperature string

Append the correct symbol after the number:

```swift
let symbol = unit == "celsius" ? "°C" : "°F"
temperature = "\(temp)\(symbol)"
```

Currently the widget shows `"72°"` — this changes it to `"72°F"` or `"22°C"`. The `°` alone is ambiguous once a unit toggle exists.

---

### Phase 2 — Settings UI + widget re-fetch on change

**Files:** `SettingsView.swift`, `WeatherWidget.swift`, `Strings.swift`

#### AppStorage key

Use `"weatherTemperatureUnit"` with a default of `"fahrenheit"`. Add it in both `WidgetsSettingsTab` and `WeatherWidget`.

#### Settings UI

In `WidgetsSettingsTab`, inside the existing `if showWeatherWidget && license.isPro` block, add the picker below the current location display:

```swift
@AppStorage("weatherTemperatureUnit") private var temperatureUnit = "fahrenheit"

// In the settings block:
Picker("", selection: $temperatureUnit) {
    Text("°F").tag("fahrenheit")
    Text("°C").tag("celsius")
}
.pickerStyle(.segmented)
.frame(width: 80)
.labelsHidden()
```

Label it with `Strings.Settings.temperatureUnit`.

#### WeatherWidget re-fetch

Add `@AppStorage("weatherTemperatureUnit")` to `WeatherWidget` and pass it through to `fetch()`. Change the `.task` to re-trigger on unit changes by making it depend on both `weatherLatitude` and `temperatureUnit`:

```swift
@AppStorage("weatherTemperatureUnit") private var temperatureUnit = "fahrenheit"

// Task that re-fetches when location OR unit changes:
.task(id: "\(weatherLatitude)-\(temperatureUnit)") {
    while !Task.isCancelled {
        await weatherService.fetch(
            latitude: weatherLatitude,
            longitude: weatherLongitude,
            locationName: weatherLocationName,
            unit: temperatureUnit
        )
        try? await Task.sleep(for: .seconds(refreshInterval))
    }
}
```

Using a combined string ID means the task cancels and restarts whenever either value changes — triggering an immediate re-fetch with the new unit.

#### String to add

In `Strings.Settings`:
```swift
static let temperatureUnit = "Temperature"
```

---

## Files Changed

| File | Change |
|---|---|
| `WeatherService.swift` | Add `unit` param to `fetch()`, use it in URL, append `°F`/`°C` symbol |
| `WeatherWidget.swift` | Add `temperatureUnit` AppStorage, pass to `fetch()`, update task id |
| `SettingsView.swift` | Add segmented Picker in weather settings block |
| `Strings.swift` | Add `Strings.Settings.temperatureUnit` |

---

## Reset defaults

Add `weatherTemperatureUnit = "fahrenheit"` to the reset-to-defaults block in `SettingsView` (around line 162).
