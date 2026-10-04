# WHG Telematics for iOS

Native iPhone and iPad version of the WHG Telematics fleet tracker website. SwiftUI and MapKit, iOS 17+.

You import an IOT High Site payload export (a CSV with a `Payload` column) and the app detects trips
and maps them, using the same logic as the website.

## Features

- **Import**: Upload CSV from Files, or "Open in WHG Telematics" from Mail, AirDrop or Files.
  Board toggle for v370 (V2 Board) and v371; v371 reads solar charging voltage from field 23.
- **Header**: IMEI, firmware, trip count, total km, top speed, last ping.
- **Date filter**: one chip per Melbourne calendar day in the export, including idle days (shown as "(0)")
  with an explanation of why no trip qualified.
- **Trip list**: T-number, time range, HDOP badge, distance, max speed, duration, pings, DP2/DP3/DP4 tags.
- **Trip map**: route line, a heading arrow per moving ping (dots when stationary), coloured by speed or
  HDOP, DP2 heartbeats in purple, S/E markers. Tap a ping for its details. Trip stats along the bottom,
  including average solar mV on v371.
- **All Trips map**: every trip in the current filter in its own colour.
- **Journey Summary Report**: asset, driver and trip type per trip (with defaults), start/end addresses
  from Apple's reverse geocoder, CSV export via the share sheet, and Print / PDF.
- **Logic Tracker**: the trip detection rules and thresholds.

All times are Melbourne local time. The app uses the system time zone database, so the AEST/AEDT switch
lands on the exact hour (the website approximates it to the day).

## Trip detection

`TripDetector` is a direct port of the website's v4 logic: a trip opens on movement above 5 km/h or a DP2
with no trip open, stays open through DP2/DP3, and closes on DP4, 12 minutes continuously stationary, or a
30-minute comms gap. Distance uses only plausible odometer deltas (at most 160 km/h implied), and trips under
0.3 km, 1.5 minutes, or 3 pings are dropped. `TripDetectionTests` checks the port against output from the
website's own JavaScript on `TelematicsAppTests/Fixtures/sample_export.csv`.

## Layout

```
TelematicsApp/
  App/        app entry point
  Core/       CSV + payload parsing, trip detection, Melbourne time, journey report (Foundation only)
  Store/      TrackerStore: loaded export and derived trips
  Views/      SwiftUI screens
TelematicsAppTests/
```

## Run it

```sh
brew install xcodegen
xcodegen generate
open TelematicsApp.xcodeproj
```

Pick an iPhone or iPad simulator and press Run. Tests run in CI on every push (`.github/workflows/ios.yml`).
