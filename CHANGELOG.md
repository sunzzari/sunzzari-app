# Changelog

Newest entries at the top. Every push to `main` adds one - see [CONTRIBUTING.md](CONTRIBUTING.md).

## 2026-10-07

### Around Town: rating colours that show, chains with every branch in view

Elisa: "when something has multiple locations, it's not showing all the locations on the
map. It's just showing one of them. for example mian" and "there is a color legend that's
always on the map, but the colors don't actually show on the bubble, so it's completely
pointless."

- **Pins show their rating colour.** Every rated place is one we have been to, and
  been-there grey was covering all four rating colours: most of the map was grey. Grey now
  means "been there, not rated", and the legend says so.
- **A bubble takes the colour most of its places have**, instead of always amber. Trips
  keep amber (`bubblesTakePinColor` on `TripMKMap` is opt-in).
- **A chain shows all its branches.** A search frames every match across the whole area,
  Orange County included, and tapping a chain in the list frames all of its pins instead
  of jumping to one. Mian's three (Costa Mesa, San Gabriel, West Adams) are in view
  together. Browsing with no search keeps the LA-proper frame.
- **An area search leaves off branches outside the area**: "cafe in san gabriel valley"
  no longer draws a matching chain's Santa Monica branch. The server names the pins to
  hide; the app just skips them.
- The rest of this round is on the travel map server and needs no app build: a place with
  a blank Location in Notion is no longer dropped (why "jian bing" could not find Yu Ji
  Stone Mill Chinese Crepes), a row with an address and no pin is pinned automatically,
  "Chinese" also covers Taiwanese, and results come back best-rated first.

## 2026-10-06

### Maps: single pins instead of bubbles, search matches in a list, and the dot no longer hides pins

Elisa: "i searched jian bing and nothing acame up. also, the bubbles are over-clustering.
i want to see individual entries where I can, but now I just see bubbles. Bubble should
only be used in the case where there are too many bubbles to display. Also, if there are
multiple hits for a search term, all of the items should be highlighted on the map, and a
list should be shown."

- **Her own location dot was hiding the pins around her.** The dot's view is 80 points
  wide to hold the heading cone, and MapKit dropped every pin and bubble under that
  square. On the full LA map that removed the three biggest bubbles (278 of 387 places)
  whenever location was on. The dot no longer collides with anything. Trips had the same
  fault and get the same fix.
- **Bubbles only when crowded.** MapKit merged two pins the moment they touched. Now,
  with 40 pins or fewer in view, every pin is drawn on its own; past that, bubbles come
  back. Places at the same address still share one bubble, and a tap lists them. This is
  `TripMKMap`, the app's one map, so trips and Around Town both change.
- **A list of matches under the search bar.** Every match is listed (about three rows,
  then it scrolls). A match with no pin comes first and says "No pin yet - tap to find
  it", which is why "jian bing" looked like it found nothing: it was found, had no pin,
  and showed only as a count. Tapping a pinned match points the map at it.
- **Matches are framed together below the list**, not under it. The map takes a new
  opt-in `topCover` so a fit keeps pins clear of whatever the screen puts on top. Trips
  pass nothing and frame as before.
- The lists of a bubble's members, of places with no pin, and of search matches now
  share one row view.
- "jianbing" typed as one word finds Jian Bing too; that fix is on the travel map server.

## 2026-10-05

### Around Town: a search bar that takes a name or a question

Elisa: "i want a search feature. either keyword search or claude ai search like 'jian
bing in rowland heights' or chinese food near me. and i want to be able to search by
name". Around Town on the phone had chips and no search at all.

- **A search bar above the chips.** Type a name ("bestia") or a question ("chinese food
  near me", "cafe in san gabriel valley", "tacos i haven't been to"). The map narrows to
  the matches and re-frames on them; a line under the bar says how the question was read.
- **It is a keyword search, not Claude, so it costs nothing per search.** It finds our own
  saved places by the words written on them: name, neighborhood, address, Good For, Top
  Dishes, Comments.
- **The travel map server reads the question** (`/api/around-town/search`), the same code
  the website's search box runs, so the phone and the website cannot answer differently.
  `AroundTownService.search` asks; there is no Swift copy of the matching.
- **Near me**: a new chip, also switched on by typing "near me". Within 5 miles, nearest
  first; if nothing is that close, the 5 nearest, and it says so. Worked out on the phone:
  the question is sent to the server, the location never is. Only the pins that are
  near are drawn, so a chain with one branch close by does not also show its branch
  across town.
- **No signal:** the bar falls back to matching names and says so.
- **One search bar in the app.** The "Ask Claude..." bar on My Restaurants moved into
  `Views/Shared/AskSearchBar.swift` and both screens use it. My Restaurants looks and
  behaves as before, and still asks Claude.
- `TripMKMap` is untouched, so trips are unaffected.

## 2026-10-02

### Around Town: Edit a restaurant from its pin, and saves no longer look lost

Elisa: "can i toggle want to try on the app? or add my reviews on the app?" Want to Try
was already on the pin sheet; reviews could only be edited from the Restaurants list.

- **"Edit" on a restaurant's pin sheet.** It opens the same edit screen the Restaurants
  list uses (been there, want to try, preference, review, top dishes, address, good
  for), not a second copy. Activities have no edit screen, so they get no button.
- **The form opens from Notion's row as it is that second.** It saves every field, so
  starting from the map's copy could have written an old review back over a newer one.
  New `NotionService.fetchRestaurant(id:)` reads the one row; the list and this read
  share one parser.
- **Around Town now reads a live copy from the server.** The cached copy it was reading
  was found 64 minutes old, so a "Want to Try" or a review saved on the phone could
  have looked unsaved when the map was reopened. `AroundTownService.fetchPlaces` asks
  `/api/around-town/live` first and falls back to the cached route.
- **Needs the travel map server change pushed first** (same day). Until then the app
  quietly uses the cached route, as before.
- Checked in the simulator: Edit opens the form with the place's real review; Cancel
  returns to the map. A save was not tested, to keep test edits out of the real list.

### Around Town: "Haven't Tried" is one chip, not a switch

Elisa: "whats the point of the "around town" button on the round town page?" then "make
the havent tried a single chip".

- **The "Around Town | Haven't Tried" switch at the top of the map is gone.** Its
  "Around Town" half only meant "show everything" and repeated the page title.
- **"Haven't Tried" is now an on/off chip** at the end of the filter row, after "Want to
  Try", the same as the website. On hides the places we have been to; off shows
  everything. "Clear" turns it off with the other filters.
- The filter bar is one row shorter, so the map gets that space back.
- Checked in the simulator: 387 places on the map with it off, 150 with it on, back to
  387 when tapped again.
- Only the Around Town screen changed. Trip maps and `TripMKMap` are untouched.

### Wine Picker: log the one you tried

Elisa: "is there also a flow to add a wine bsaed on the picker? like "sleect the one i
tried" from the menu adn then add it with all the necessary data fields".

- **"Log one I tried" on the pick screen.** It reads every wine in the photo and lists
  them (name, producer, vintage, region, type, price). Tap one and the usual New Wine
  form opens with name, type, producer, vintage, region and cost already filled in.
  Rating, where it was bought and notes are left for her. Nothing is saved until she
  taps Save Wine; a saved wine shows "Added" in the list.
- **One extra paid read, only when the button is tapped.** The list is kept for that
  photo, so going back and forth does not pay twice.
- **Only what the photo shows.** The reader is told to leave producer, vintage and price
  blank when they are not visible. A line it cannot make sense of is skipped, not
  guessed at.
- **One Add Wine form, not two.** `AddWineView` gained an optional `prefill`; the picker
  opens that same form. Add Wine from the Wine hub is unchanged.
- **Tested live on a 31-wine list:** all 31 came back with the right producer, vintage,
  region, type and price, in roughly 10 to 20 seconds. Wines with no vintage on the list
  kept a blank vintage.
- **Known limit:** the backend function has a time cap, so a much longer list (untested
  past 31 wines) may time out with the usual "taking longer than usual" message. The
  answer format was kept to one short line per wine to leave as much room as possible.
- **The pick no longer shows stray `**` symbols.** The sommelier marks bold and italic
  with asterisks and the app was printing them as-is. They now draw as bold and italic.

### Wine Picker takes a typed note

Elisa: "add a feature to my wine feature in the app that lets me type notes. for
example (" i want a white" or "red" or wines by the galss only")".

- **A notes box on the photo screen**, above "Pick for us": "Anything specific?
  (optional)". Whatever is typed there is sent with the photo as a requirement that
  comes ahead of the usual taste profile, so "a white" gets a white. If nothing in the
  photo fits the note, the sommelier is told to say so instead of picking something
  else. Left blank, the picker behaves exactly as before.
- **The note stays put across "Try Another"**, so the second page of the same wine list
  needs no retyping. Closing the Wine Picker clears it.
- **The note rides in the request, not in the taste profile.** `winePickerSystemPrompt`
  is untouched and still owned by `/wine-picker-sync`.
- **Fixed on the same screen:** a wide (landscape) photo stretched the whole column past
  both screen edges, so the button ran edge to edge and left-aligned text was cut off.
  The photo now stays inside the margins.

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
- **A "+" on Around Town** opens the app's existing Add Restaurant / Add Activity
  forms (no new form), the same job as "+ Add place" on the website. The map reloads
  when the form closes.
- **"Find it"** on any Around Town place with no map location: look it up, tap the
  match, save, and the pin appears.
- **Every branch of a chain gets its own pin** (her request), on Around Town and on
  trips, through `TripMKMap`, still the app's only map. A tap on a branch opens the place.
- **"LA proper" fit** (paused 2026-09-15, now in): fitting on LA no longer zooms out to
  San Diego or Orange County. Which frame a pin belongs to is the server's call.
- The app signs in to the server's lookup and save with the Notion key it already
  carries (Elisa, 2026-10-01: "use the notion key"). No new app secret, no new server
  setting and no Xcode Cloud change.

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
