# UI and Android

## Layout Contract

- Reference viewport: `540×960`
- Portrait orientation
- `canvas_items` stretch
- Desktop size override: `405×720`
- Board cell order: row-major
- Five fixed hand slots per side
- Turn status is below the player's hand
- Opponent identity and exit controls occupy the top bar

The user has tuned several offsets/colors directly. Treat current scenes and scripts as source of truth, not old screenshots or plans.

## Card Rendering

`card_view.gd` owns:

- player/opponent face colors and borders;
- card-back styling;
- four directional power labels;
- centered card picture;
- ki bead visibility/animation;
- drag/tap gesture disambiguation;
- flip, draw, exile, invalid, and ability-loss effects.

Art scale is `CARD_PICTURE_SCALE = 0.8`: the full source texture, including transparent background, is fit relative to the card's shorter side. Power labels must render above art. Glyph/title display was disabled by the creator; do not re-enable it without asking.

Hand slot backgrounds are separate from card backgrounds. If opponent and player empty slots differ, inspect slot styling and inherited/self modulation, not only the top red background.

## Inspector Contract

`card_inspector.gd` takes exactly the board's global rectangle. It is a parchment-like scroll with content structured as:

1. glyph/name;
2. sect tag;
3. tier tag;
4. weapon tag;
5. effect/description;
6. background/flavor.

Unknown or empty content uses a placeholder. Opening uses a snapshot of revealed card data. Face-down cards cannot open it.

The modal blocks drag/play/activation. A tap closes it; a swipe is treated as scroll input. The board and score are hidden, while both hands, top bar, and bottom status remain visible.

## Chinese Line Wrapping

Godot/Android may treat long Chinese text differently from desktop when word-based autowrap is used. The creator already fixed and device-verified the flavor-text issue using the current smart/arbitrary wrapping implementation.

Do not replace it with word-only wrapping. Test long punctuation-heavy Chinese strings on Android, because desktop success is not sufficient evidence.

## Interaction Rules

- Single tap revealed card: inspect.
- Drag beyond threshold: play or activate.
- Tap face-down card: no metadata leak.
- Tap during resolution: inspector does not open.
- Inspector open: no duel action commits.
- AI may think in background, but its move waits to apply.
- Mouse must mirror touch.

## Android Environment

The current machine was previously found to have:

- JDK: Eclipse Temurin 21 at `C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot`
- Android SDK root configured as `C:\Games`
- adb/platform tools 36.0.0
- Android platform 36
- build-tools 36.0.0 (plus a 36.1.0 release candidate)

These are machine-specific facts, not portable project configuration. A replacement developer should inspect Godot Editor Settings → Export → Android rather than assuming the same paths.

Never commit keystore passwords or private signing material. The existing debug export uses Godot-managed debug signing.

## Export Preset Status

`export_presets.cfg` currently:

- is built through `tools/build_android_release.ps1`, whose default artifact is
  `build/android/WuxiaCard-android-arm64-0.1.0.apk`;
- uses the Gradle source-template export so the Android-to-Godot splash handoff
  can retain the original splash until engine setup completes;
- selects ARM64 only;
- leaves min/target SDK on automatic values;
- uses placeholder package ID `com.example.$genname`;
- declares no Android permissions;
- falls back to the Godot debug keystore for local release builds when no
  explicit release keystore is supplied.

Before distribution:

- choose a permanent reverse-domain package ID;
- set version code/name policy;
- decide supported ABIs;
- configure release signing securely;
- verify target/min SDK against the current store;
- audit permissions and data safety;
- produce icons/store assets;
- test install/upgrade on physical devices.

Store requirements change over time and must be checked from official current sources at release time.

## Manual Device Checklist

- safe areas/notches and black bars;
- hand/board spacing at multiple aspect ratios;
- drag targets under finger;
- tap-versus-drag threshold;
- all four power labels;
- fixed empty hand slots;
- card-back concealment;
- long Chinese description/flavor wrapping;
- inspector scrolling and tap close;
- VFX timing and performance;
- lifecycle pause/resume;
- exit behavior;
- vibration behavior;
- AI responsiveness during a 10-second search.
