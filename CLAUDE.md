# Project Instructions

## Changelog (MANDATORY)

**Every time you commit and push to main, you MUST update `CHANGELOG.md`** in the same
commit. Format:
- Add a new date heading (`## YYYY-MM-DD`) if one doesn't exist for today
- Newest entries go at the TOP
- Bold the headline, then say what actually changed and why it matters, in plain
  language. Someone reading in six months should understand it without the diff.
- Include "- Cathy" attribution on entries Cathy wrote
- This is not optional - do it before telling the user you're done.

History: this file was started on 2026-05-13, then went unwritten for 41 commits and
four months, because nothing enforced it. Backfilled 2026-09-14.

A pre-push hook in `.githooks/pre-push` enforces this. If it isn't firing, run:
`git config core.hooksPath .githooks`

## Before pushing

1. `git pull --rebase` - Cathy pushes here too
2. `xcodebuild -scheme Sunzzari -sdk iphonesimulator build` must pass
3. Update `CHANGELOG.md`
4. Ask before pushing - a push to main triggers an Xcode Cloud build to TestFlight

## Secrets.swift members must exist in THREE places

`Sunzzari/Config/Secrets.swift` is gitignored and Xcode Cloud regenerates it. Any
`Secrets.X.y` you add must go in all of:
1. your local `Sunzzari/Config/Secrets.swift`
2. `ci_scripts/ci_post_clone.sh`
3. `Sunzzari/Config/Secrets.template`

Miss #2 and local builds pass while every cloud build dies at Archive. That happened
with `Secrets.GooglePlaces` - see the 2026-08-19 changelog entry.

## One map only

`TripMKMap` in `Views/Travel/TripMapView.swift` is the app's only map. Around Town
renders through it via `AroundTownItem.asTripItem` plus the opt-in `styleFor`. A change
to `TripMKMap` reaches both surfaces - say so in the same pass. Never add another map.

## Where things are: the travel map server decides

Elisa, 2026-09-30: "the same data is used for both and the same features should be used
for both". This app does not work out where a place is. Pins, chain branches, areas,
colours, the address lookup and saving an address all live on the `elisa-travel-map`
server; this app draws `/api/around-town` and `/api/trips/<id>/pins`
(`AroundTownService`, `TravelService`) and saves through `/api/places*`.

- **A location feature is built on the server first**, then drawn here. Never add a
  Swift copy of a server rule, and never add a geocoder or a paid lookup to the app.
- `AroundTownItem` is built only from the server's answer, never from Notion rows.

Still duplicated by hand in `elisa-travel-map`, and not location code:

| This repo | elisa-travel-map |
|---|---|
| `Services/TripTime.swift` | `lib/time.ts` |
| `Services/TripDayPlanner.swift` | `lib/day.ts` |

Editing one means editing the other in the same pass, or saying out loud that you did not.
