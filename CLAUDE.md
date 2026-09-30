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

## Logic that is duplicated in the travel map repo

These files have a hand-maintained twin in `elisa-travel-map`. Nothing checks that they
agree, so **editing one means editing the other in the same pass, or saying out loud
that you did not**:

| This repo | elisa-travel-map |
|---|---|
| `Models/AroundTownItem.swift` (region lists, bounding boxes, preference colours) | `lib/aroundtown-shared.ts` |
| `Services/TripTime.swift` | `lib/time.ts` |
| `Services/TripDayPlanner.swift` | `lib/day.ts` |

The region word lists are 105 tokens long on each side. They were verified identical on
2026-09-14; that is a snapshot, not a guarantee.

Geocoding is NOT duplicated - both apps call the travel map's `/api/geocode`. That is
the pattern to extend when this duplication gets painful, not a monorepo: Swift cannot
import TypeScript, so merging the repos would preserve every copy above.
