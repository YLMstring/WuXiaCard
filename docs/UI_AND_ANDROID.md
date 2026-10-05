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

Deck building fits card names longer than five characters to the slot width
by reducing the name label's font size. Names of up to five characters keep
their existing size; deck-building names do not use ellipsis. Binding a reused
slot or resizing it recalculates the size. The name region retains the shaped
text height at the original font size, including Chinese system-font fallbacks,
and deck-building names align to its bottom. Using only `Font.get_height()` can miss a
taller Android fallback line: the short name then expands the Label while its
shrunk replacement does not, moving the replacement's center upward despite
a bottom-alignment flag.
This is enabled only by
`deck_builder_controller.gd`; reward and sect selection retain their original
name sizing, center alignment and trimming behavior.

`card_view.gd` owns:

- player/opponent face colors and borders;
- card-back styling;
- four directional power labels;
- centered card picture;
- ki bead visibility/animation;
- drag/tap gesture disambiguation;
- flip, draw, exile, invalid, and ability-loss effects.

The center art alone uses 30% opacity whenever the card's effective defending
power is overridden, whether that modifier belongs directly to the card or is
received from an owner-held aura such as `HuJiaDao2`. The controller obtains the
effective per-cell flags through the simulator's native, aura-aware modifier
query; it does not reconstruct aura selectors in presentation code. Borders,
power labels, ki, and interaction remain fully opaque.

Face-down cards normally retain their card back while showing the four power
labels. Identity, art, text, ki, tooltip, and inspection stay concealed. The
all-four-`-1` sentinel never shows powers, and difficulty 8 or above suppresses
all face-down power labels in battle, deck building, and reward selection.

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
- Tap face-down card: no inspection or identity metadata leak; visible powers
  below difficulty 8 are intentional.
- Tap a revealed card during resolution, including either replay mode: the
  inspector opens immediately. The current animation step finishes behind it;
  the next step waits until the inspector closes. A manual inspection during a
  replay action suppresses that action's enemy self-exile automatic inspection.
- During full-match or last-opponent-turn replay, an enemy-played card that
  self-exiles in that play automatically opens the inspector after reveal and
  before event animation when no manual inspection opened during that action.
  Closing it resumes playback; normal duels do not open it automatically.
- Inspector open: no duel action commits.
- AI may think in background, but its move waits to apply.
- Mouse must mirror touch.
- While a hand card is being dragged, board glow is derived from that exact
  runtime instance's current simulator-legal play actions. Empty cells forbidden
  by an owner aura or another placement rule do not glow; a conditionally
  forbidden cell may glow when the simulator reports that its fallback condition
  has become legal.
- During that same hand drag, a legal cell also covered by an enemy's current
  summon interception or adjacent Taiji redirection is shown with the red danger
  style instead of the normal blue legal style. The native visual query recognizes
  runtime trigger/modifier structure rather than card IDs. It follows current
  geometric range and intervening-card rules, but intentionally ignores whether
  powers or later gates would make the reaction succeed. Illegal cells never glow,
  friendly sources never create danger, and board-activation dragging never uses
  this overlay. Hover keeps the danger cell red, and every drag end/cancel clears
  the overlay.
- In deck building, tapping a card opens details. The upper hand row becomes
  same-tier, same-sect, and same-weapon filter buttons; filters are mutually
  exclusive, reselecting the active one cancels it, and every filter change
  returns the scroll to the top without saving or reordering profile data.
- The lower hand row becomes the applicable explicit action (`加入卡组`,
  `移出卡组`, `领取奖励`, or `拜入师门`). With a full deck and a collection card
  selected, the five deck cards remain visible as replacement targets instead.
  Registered action controls do not trigger the inspector's tap-outside close.
- Bottom ink-brush actions, including the post-match `打道回府`, occupy 60% of
  the hand-row width, use 1.3 times the original button height, and use 23-pixel
  text while retaining the hand row's center.
- Deck and collection cards use a roughly 0.25-second stationary hold as a
  shortcut for remove/add; reward cards use it to claim. Immediate movement
  still scrolls the library. Sect confirmation and all filters use explicit
  detail buttons instead of drag targets.
- Directly awarded cards use a slowly flowing gold border in deck building;
  inherited lower-tier namesakes do not. The gold effect replaces the ordinary
  red/blue owner border, keeps the same outer card dimensions, and extends
  slightly inward. Tapping or holding the exact card restores its owner border,
  while acquiring a later reward batch clears every older gold border. Rank-up
  audio is keyed to an actual character-level increase, plays as a sound effect
  over the existing music, and is consumed on entry.
- Deck building has a hidden enemy-reroll gesture: with all five opponent cards
  face down, tap physical slots `0,1,2,3,4,3,2,1,0`. Only the ninth completed
  tap requests a reroll. Wrong slots, outside clicks, drag/hold/cancel,
  multi-touch, focus loss and inspection clear the prefix; emulated mouse
  events do not double-count touches. The saved replacement is a different
  ordinary enemy at the same level, respecting difficulty/sect availability.
  Fixed beginner stages and explicit scene overrides do not reroll; with no
  alternative or a failed save the current enemy remains. Success refreshes
  only the opponent preview and first-player conditions, preserving library
  scroll/filter, gold highlights and music. See
  `docs/superpowers/specs/2026-10-01-deck-builder-hidden-enemy-reroll-design.md`.

## Beginner Tutorial

- A newly created Huashan difficulty-0 run opens
  `res://scenes/tutorial.tscn` before deck building. The scene displays
  `res://pics/tutorial/tutorial_01.png` through `tutorial_10.png` in fixed
  order.
- Artwork uses centered aspect-cover scaling. A `20:9` display shows the full
  `1080×2400` image; the reference `16:9` viewport crops equally from its top
  and bottom while retaining the authored central safe area.
- One mouse click or single-finger tap advances one page. There is no skip or
  back action. The final tap requests an atomic save; a failure leaves the last
  page visible and unlocks one retry.
- The scene belongs to the continuing menu music context, not the deck-builder
  story context. It loads all ten textures on entry for smooth paging and
  releases its references when replaced by the deck builder.

## Battle Animation Ordering

Simulator transition events form one presentation timeline. The duel controller
must await each visible step before advancing to the next event. Parallel motion
is reserved for one explicitly atomic visual group:

- every card in one `power_change_batch_id` changes together after the shared
  pre-change pause;
- every card in one discard batch fades together;
- all cards in one hand-slot shift move together;
- the two reciprocal movement legs of one swap move together;
- properties within one card animation (for example scale and color) may tween
  together internally.

A reciprocal swap may contain ability and power-change events between its two
logical `card_moved` records. Presentation defers the first movement, plays all
intervening effects in order, and only then animates both reciprocal legs as one
swap. This prevents the first view from occupying the second card's cell while
that card is still presenting its before-movement effects. Invalid-input shake
is interaction feedback outside the resolution timeline and is not part of this
queue.

## Android Environment

The current machine was previously found to have:

- JDK: Eclipse Temurin 21 at `C:\Program Files\Eclipse Adoptium\jdk-21.0.9.10-hotspot`
- Android SDK root configured as `C:\Games`
- adb/platform tools 36.0.0
- Android platform 36
- build-tools 36.0.0 (plus a 36.1.0 release candidate)

These are machine-specific facts, not portable project configuration. A replacement developer should inspect Godot Editor Settings → Export → Android rather than assuming the same paths.

Never commit keystore passwords or private signing material. Formal APK builds
use the repository-external release keystore; local-only builds may explicitly
fall back to Godot-managed debug signing.

## Export Preset Status

`export_presets.cfg` currently:

- is built through `tools/build_android_release.ps1`, whose default artifact is
  `build/android/WuxiaCard-android-arm64-1.0.7.apk`;
- uses the Gradle source-template export so the Android-to-Godot splash handoff
  can retain the original splash until engine setup completes;
- selects ARM64 only;
- leaves min/target SDK on automatic values;
- uses the permanent package ID `com.wuxiacard.jiugonglunjian`;
- declares Android Internet permission for completed-run balance telemetry;
- uses the release keystore supplied through `WUXIA_ANDROID_KEYSTORE_PATH` and
  its password environment variables for formal builds, while retaining an
  explicit debug-keystore fallback for local-only builds.

Latest local export (2026-10-05): version name `1.0.7`, version code `8`,
126,859,477-byte ARM64 APK at
`build/android/WuxiaCard-android-arm64-1.0.7-kunlun.apk`, including Kunlun and
Silent's updated allies-before-self attack order. APK v2/v3 signature verification
passes and the certificate matches the previous 1.0.7 package. The native source
matches Gradle's input; the packaged library matches Gradle's stripped Release
output. Tests/tools/docs/local development assets and Windows DLLs are excluded;
compiled catalog scripts are included. Manifest min/target SDK are 24/36.
The full suite passes 93/93; the affected normal-duration portrait controller
walkthrough passes 24 checks with muted audio. No Android device was connected,
so installation and on-device gameplay were not tested. Build and artifact
records live in `.summer/local/silent-order-*`, including
`silent-order-android-verification.json`. The exporter hit Summer's existing teardown
watchdog after Gradle completed; the build script continued only after its
completion checks, then signed and independently verified the finished APK.

Before distribution:

- retain the permanent reverse-domain package ID;
- continue monotonically increasing version code and version name;
- decide supported ABIs;
- back up the release keystore and its password separately before distribution;
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
- card-back identity concealment and difficulty-dependent power labels;
- long Chinese description/flavor wrapping;
- inspector scrolling and tap close;
- VFX timing and performance;
- lifecycle pause/resume;
- exit behavior;
- vibration behavior;
- AI responsiveness during a 5-second base search and a difficulty-9 10-second search.
