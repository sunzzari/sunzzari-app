# Changelog

Newest entries at the top. Every push to `main` adds one - see [CONTRIBUTING.md](CONTRIBUTING.md).

## 2026-09-30

### Locations come from the travel map server, the same as the website

Elisa: "the overall goal is to make the locations on my app and web app functional
(these two things should be synced in terms of function)" and "the same data is used
for both and the same features should be used for both". The app no longer decides
where a place is. It asks the travel map server and draws the answer.

- **Around Town loads `/api/around-town`** (new `AroundTownService`): places, saved
  pins, chain branches, colours and areas, computed by the same code that draws the
  website. The last answer is kept on disk, so the map still opens offline. The app's
  own Around Town Notion reading, its region word lists and its geocoding loop are
  deleted (`PlaceGeocoder.swift` is gone).
- **Trip maps load `/api/trips/<id>/pins`**: one request per trip instead of one per
  item, cached on disk for offline. Trip content is still read from Notion as before.
- **No Google lookup.** The Google Places address search a cloud session added earlier
  today (never merged) is removed. `AddressLookupField` now calls the server's free
  lookup (OpenStreetMap and the US Census), and tapping a match sets the address and
  its pin. The Open Now filter's existing Google call is unchanged.
- **Restaurant edit screen kept** (Elisa's call): tap a restaurant to edit Been There,
  Want to Try, Preference, Review / Comments, Top Dishes, Address, Neighborhood,
  Location and Good For; swipe right to mark Been There. Address and pin save through
  the server (`/api/places/<id>`), everything else straight to Notion.
- **Adding a restaurant or activity saves its pin** the same way, right after the row
  is created.
- **"Find it"** on any Around Town place with no map location: look it up, tap the
  match, save, and the pin appears.
- **Every branch of a chain gets its own pin** (her request), on Around Town and on
  trips, through `TripMKMap`, still the app's only map. A tap on a branch opens the place.
- **"LA proper" fit** (paused 2026-09-15, now in): fitting on LA no longer zooms out to
  San Diego or Orange County. Which frame a pin belongs to is the server's call.
- Needs `PHONE_APP_SECRET` on the travel map's Vercel project, equal to this app's
  existing push secret. No new app secret and no Xcode Cloud change.

## 2026-09-14

### Around Town moved onto the trip map

- **Around Town now renders on `TripMKMap`, and two maps were deleted.**
  `RestaurantMapView` (718 lines) and most of the old `AroundTownMapView`
  are gone. `AroundTownItem` grew an `asTripItem` conversion, so the one
  remaining map draws both surfaces. `TripMKMap` gained an opt-in `styleFor`
  hook for Around Town's pin colours; trip rendering is unchanged. A fix to
  the map now reaches both screens instead of one.
- **A fit never spans LA and the Bay.** `TripMapView` gained an opt-in
  `fitScopeIds`. Left undefined it fits everything, which stays right for a
  trip whose items are all in one place. Around Town scopes the fit to a
  single area: the explicit LA / SF Bay chip if one is set, otherwise
  whichever area holds more of the pins on screen. Pins outside that area
  stay on the map and stay tappable, they just never stretch the frame.
- **The pin-style lookup was quadratic.** `AroundTownMapView` was scanning
  the whole item list for every annotation it drew. Replaced with a
  dictionary built once.

## 2026-09-08

- **Opening a trip opens the map, every time. Today is a filter on it.**
  `TripTodayView` was rebuilt around the map rather than sitting beside it.
- **Tapping an event points at the map instead of opening a sheet.** Selecting
  a day's event now moves and highlights the pin, so the map stays the thing
  you are looking at.
- **Every geocode is anchored to the trip's country, and cached results are
  re-fetched.** `TravelService` was resolving place names without a country
  hint, which put pins on the wrong continent for ambiguous names. Existing
  bad cache entries are refreshed rather than trusted.

## 2026-09-07

- **One map on iOS, not two. `TripDetailView` retired.** `TripDetailView`
  (497 lines), `TripBottomSheetView`, `TripFilterBar`, `TripSidebarView` and
  `TripSortPicker` all deleted, about 1,300 lines removed. Their jobs moved
  into `TripTodayView` and the shared map.
- **Assistant highlighting restored, two more duplicate surfaces dropped.**
  `ItineraryWebView`'s duplicate rendering path removed.

## 2026-09-06

- **New Trip Today screen, for using a trip rather than planning one.**
  `TripTodayView` plus `TripDayPlanner` and `TripTime`, roughly 1,200 lines.
  Shows what is happening now and next, in the trip's own timezone.
- **The day page was rebuilt around what is actually settled**, so
  unconfirmed items stop reading as plans.
- **Opens where she left off.** New `TravelResume` remembers the last trip
  and day. The assistant is now reachable from the day screen, and the app
  stopped over-claiming that something was booked when it wasn't.
- **Finished days dim in the trip's timezone**, and the offline itinerary
  message came back.
- **Day map, last-minute add, and clusters that can actually be opened.**
  New `QuickAddItemSheet` for adding something on the day. Tapping a cluster
  now expands it instead of doing nothing.
- **Trip items prefer their Address when geocoding**, falling back to the
  name only when there is no address.

## 2026-08-24

- **Around Town and the restaurant map got real geocoding.** New
  `PlaceGeocoder`, region refinement, and working callouts, replacing
  approximate placement.
- **Fixed the stacked-bubble dead end**, wrong pin colours, and rows that
  were being dropped from the map silently rather than surfaced.
- **Travel wishlist: Home entry point and a full list screen.** New
  `TravelWishlistView`, wired into the Home checklists.

## 2026-08-19

- **Fixed Xcode Cloud by generating `Secrets.GooglePlaces` in
  `ci_post_clone.sh`.** Every cloud build had been failing at Archive with
  "Type 'Secrets' has no member 'GooglePlaces'" since the Open Now filter
  shipped, so builds 70 to 75 never reached TestFlight and both testers lost
  access to the app for about three months. Local builds passed the whole
  time, which is why it went unnoticed. Any new `Secrets` member must be
  added in three places: the local `Secrets.swift`, `ci_scripts/ci_post_clone.sh`,
  and `Sunzzari/Config/Secrets.template`.
- **Fixed Home tap targets, wired the period row, fixed the chip picker.**

## 2026-08-18

- **Home checklists.** New `HomeChecklistSection` and `HomeListsModel`, about
  630 lines, plus fixes to Hub card tap targets.

## 2026-07-09

- **Travel fixes:** the offline itinerary cache, the Near Me location flow,
  stale geocodes, and error states that previously showed nothing.
  `TripTypeLegend` removed.

## 2026-06-24

- **Stories: permanent header entry point**, falling back to the archive when
  nothing is live.

## 2026-06-21

- **Thinking About toggle** added to the restaurant and activity add forms.

## 2026-06-19

- **Around Town home map (LA + SF Bay)** with Thinking About / Done intent.
  First version of `AroundTownMapView`.

## 2026-06-12

- **The broken Day/newsletter view was replaced with a live itinerary viewer.**
- **Wine picker: graceful timeout and human error messages** instead of a
  hang with no explanation.

## 2026-06-10

- **Wine picker taste profile rebuilt Burgundy-forward**, from a re-evaluation
  of the Notion wine database.

## 2026-05-19

- **Open Now filter on the restaurant map**, via the Google Places API. New
  `PlacesService`. (This is the change whose secret broke Xcode Cloud - see
  2026-08-19.)
- **Fixed Clear All not cancelling an in-progress Open Now fetch.**

## 2026-05-18

- **Google Maps-style heading cone** on the trip and restaurant maps.

## 2026-05-17

- **AI Trip Assistant added to the travel map.** New `TripAssistantSheet`,
  `TripAssistantResponse`, and assistant support in `AnthropicService`.
- **Assistant results persist**, with source badges, a selected state, AI pin
  highlighting, and a date-filter bypass so a result is never hidden by the
  current filter.
- **Clusters burst open when an assistant result is selected.**
- **The bottom sheet hides while the assistant is open**, and items with no
  location are handled instead of silently skipped.
- **The chip filter bar was replaced with a compact dropdown filter sheet.**
- **Fixed a zoom crash**, wired up the info button, and put notes in the
  callout.
- **Fixed type legend overflow, sparkles visibility, and keyboard dismissal.**

## 2026-05-13 (later)

### Stories follow-ups

- **Embedded IG-style camera.** Tapping the Stories tab now opens
  directly into a fullscreen in-app camera (live preview, shutter,
  flip, library thumbnail) instead of the old system camera flashed
  behind an "Add a photo" intermediate screen. The intermediate
  picker is gone.
- **No more zoom-crop in compose.** Photos render with `scaledToFit`
  + blurred backdrop, so the entire frame is visible while composing
  and the baked upload matches what you see.

## 2026-05-13

### Stories overhaul

- **New Today header story ring (IG-style).** When the partner has active
  stories, a colored avatar ring appears in the Today page header next to the
  inbox bell. Solid accent ring when there are unseen stories, faded grey once
  everything has been watched. Tap opens the fullscreen story tray.
- **Stories tab is now a pure compose launcher.** Tapping the Stories tab
  always opens the new-story flow directly; viewing partner stories happens
  from the Today header. Returns to Today after post or cancel.
- **Stories Archive moved to More.** New "Stories Archive" row in the More
  tab navigates to all past archived stories. The old in-tab archive button
  is gone.
- **Instagram-style compose (full rewrite).** Fullscreen photo, tap the photo
  to write a caption inline with keyboard, drag the caption pill to position,
  floating "Aa" button to re-edit. Location field removed.
- **Camera defaults to flash off.** `cameraFlashMode = .off` on capture.
- **No more flash-of-compose-step before camera.** The picker placeholder
  stays hidden behind the camera slide-up; reveals only if the camera was
  cancelled or unavailable.
- **Replay screen no longer blacks out the last frame.** Replaced the
  full-screen dim and giant Replay circle with a small glass-blur Replay pill
  + minimal Close. The final story photo stays fully visible behind.
- **Notifications now count UNSEEN stories instead of total daily count.**
  New `SeenStoriesStore` tracks viewed story IDs locally. Inbox titles read
  "Elisa posted 3 stories" only for stories you haven't watched yet, and
  auto-mark the entry read when the bucket is fully viewed.

### Build / project

- **Restricted supported platforms to iOS only** (`iphoneos`,
  `iphonesimulator`). Previously included `macosx`, `xros`, and `xrsimulator`,
  which made Xcode previews fail with a UIKit-not-found error in
  AnthropicService and Mac App provisioning errors. Previews now build.
- `SDKROOT` pinned to `iphoneos`, `TARGETED_DEVICE_FAMILY` reduced to `1,2`
  (iPhone + iPad), `XROS_DEPLOYMENT_TARGET` removed.
