# Plan: Weather Location Live Search

## Goal

Replace the current "type city name → click Search → one result or error" flow with a live search that shows a scrollable list of matching locations as the user types. Selecting a row applies the location immediately.

---

## Current State

- `LocationService.geocode()` fetches `count=1` from Open-Meteo geocoding API and returns a single `LocationResult`
- `WidgetsSettingsTab` has: `TextField` + `isGeocoding` spinner + "Search" button + `geocodeError` flag
- Success applies `latitude`, `longitude`, `weatherLocationName` to `AppStorage` and clears the field
- The Search button and `onSubmit` both call `performGeocode()`

---

## Phases

---

### Phase 1 — LocationService: multi-result search

**File:** `LocationService.swift`

Add a `search()` method alongside the existing `geocode()`. Keep `geocode()` unchanged — it's still used by the onboarding flow and any call sites outside settings.

```swift
static func search(_ query: String, count: Int = 5) async throws -> [LocationResult] {
    let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
    let urlString = "https://geocoding-api.open-meteo.com/v1/search?name=\(encoded)&count=\(count)&language=en&format=json"
    guard let url = URL(string: urlString) else { throw URLError(.badURL) }

    let (data, _) = try await URLSession.shared.data(from: url)
    let response = try JSONDecoder().decode(GeocodingResponse.self, from: data)

    return (response.results ?? []).map { place in
        var display = place.name
        if let state = place.admin1 { display += ", \(state)" }
        if let country = place.country { display += ", \(country)" }
        return LocationResult(latitude: place.latitude, longitude: place.longitude, displayName: display)
    }
}
```

`GeocodingResponse` and `Place` are already private to the file — no structural changes needed.

---

### Phase 2 — Debounced search state

**File:** `SettingsView.swift` (`WidgetsSettingsTab`)

#### State changes

Remove `isGeocoding` and `geocodeError`. Add:

```swift
@State private var searchResults: [LocationResult] = []
@State private var isSearching = false
@State private var searchTask: Task<Void, Never>? = nil
```

#### Debounced search on text change

Attach `.onChange(of: citySearchText)` to the `TextField`. Cancel the previous task and start a new one with a 350 ms debounce so a request fires only after the user pauses:

```swift
.onChange(of: citySearchText) { _, newValue in
    searchTask?.cancel()
    guard !newValue.trimmingCharacters(in: .whitespaces).isEmpty else {
        searchResults = []
        isSearching = false
        return
    }
    searchTask = Task {
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        isSearching = true
        searchResults = (try? await LocationService.search(newValue)) ?? []
        isSearching = false
    }
}
```

#### Remove the Search button and `performGeocode()`

The explicit button and `onSubmit` are no longer needed. Remove them along with `isGeocoding`, `geocodeError`, and `performGeocode()`.

---

### Phase 3 — Results list UI

**File:** `SettingsView.swift` (`WidgetsSettingsTab` body)

#### Replace the search row

Before:
```swift
HStack {
    TextField(...)
    Button("Search") { ... }
}
if geocodeError { Text("City not found...") }
Text(Strings.Settings.weatherCurrentLocation(...))
```

After:
```swift
HStack {
    TextField(Strings.Settings.weatherLocationField, text: $citySearchText)
        .onChange(of: citySearchText) { ... }   // Phase 2
    if isSearching {
        ProgressView().controlSize(.small)
    }
}

// Results list — only shown while there are results
if !searchResults.isEmpty {
    VStack(spacing: 0) {
        ForEach(searchResults, id: \.displayName) { result in
            Button {
                applyLocation(result)
            } label: {
                HStack {
                    Text(result.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if result.displayName != searchResults.last?.displayName {
                Divider()
            }
        }
    }
    .background(.background)
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .overlay {
        RoundedRectangle(cornerRadius: 6)
            .stroke(.separator, lineWidth: 0.5)
    }
}

// Current location (always shown)
if searchResults.isEmpty {
    Text(Strings.Settings.weatherCurrentLocation(weatherLocationName))
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

#### `applyLocation()` helper

Extracts the selection logic out of `performGeocode()`:

```swift
private func applyLocation(_ result: LocationResult) {
    weatherLatitude     = result.latitude
    weatherLongitude    = result.longitude
    weatherLocationName = result.displayName
    citySearchText      = ""
    searchResults       = []
}
```

---

## Files Changed

| File | Change |
|---|---|
| `LocationService.swift` | Add `search()` returning `[LocationResult]` |
| `SettingsView.swift` | Replace `isGeocoding`/`geocodeError`/`performGeocode()` with debounced search state + results list UI |

`geocode()` in `LocationService` is untouched — other call sites continue to work.

---

## Behaviour Summary

| Action | Result |
|---|---|
| User types | 350 ms after last keystroke, fetches up to 5 matches |
| Results appear | List drops in below the text field |
| User taps a row | Location applied, field cleared, list dismissed |
| User clears the field | List immediately clears, no network call |
| No results found | List is empty (hidden); current location line stays visible |
