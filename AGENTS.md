# The hotel's interface — a guide for agents

Read this **before** writing any GUI: a popup, a toast, a HUD element, a
world-space label, a prompt panel. The place has a settled visual language and
the fastest way to make something look wrong is to invent a new one.

`CLAUDE.md` covers how to work in this repo. This file covers what things should
look like and where they go. Sections 1–7 are the screen; [section
8](#8-structure-in-the-world--props-sets-and-rooms) covers how physical props
and sets are structured in the Explorer — **read it before building any room,
set, or multi-part prop.**

The rule underneath everything: **this is a hotel, not a game HUD.** Notices are
brass signs screwed to walls. Documents are aged paper someone typed on. The
building talks to you in its own materials. When you are about to add a rounded
neon panel with a drop shadow, you are about to be wrong.

The one deliberate exception is the admin panel — see [Off-brand on
purpose](#off-brand-on-purpose).

---

## 1. The three materials

Every surface in the game is made of one of three things. Pick the one that
matches what the surface *is*, then copy its palette verbatim. Do not blend two
materials in one panel.

### Brass over lacquer — signage

Something the building is telling you. Fixed, official, engraved. Used by the
round timer plaque (`RoundTimerClient`), the mallet refusal notice
(`MalletPlaqueClient`), and the ledger's dock button (`CaseLedgerClient`).

```lua
local BRASS_LIGHT    = Color3.fromRGB(201, 171, 111)
local BRASS          = Color3.fromRGB(139, 111,  62)
local BRASS_DEEP     = Color3.fromRGB( 74,  57,  30)
local PANEL          = Color3.fromRGB( 47,  28,  25)
local PANEL_MID      = Color3.fromRGB( 36,  21,  19)
local PANEL_DEEP     = Color3.fromRGB( 23,  13,  12)
local ENGRAVED       = Color3.fromRGB(224, 212, 189)
local ENGRAVED_SOFT  = Color3.fromRGB(199, 185, 159)
local BLOOD          = Color3.fromRGB(227, 122,  96)  -- accent, warn
local MOSS           = Color3.fromRGB(158, 197, 148)  -- accent, calm
```

Construction, in order, outside in:

1. `Frame` filled `BRASS`, `UICorner` 7, `UIStroke` `BRASS_DEEP` 2.
2. `UIGradient` rotation **90**, `BRASS_LIGHT` → `BRASS` at 0.42 → `BRASS_DEEP`.
   This is the sheen and it is what stops the frame reading as flat orange.
3. A `Bevel` frame inset 3px, transparent fill, `UICorner` 5, `UIStroke`
   `BRASS_LIGHT` 1 at transparency 0.55.
4. A `Field` frame inset 9px filled `PANEL`, `UICorner` 4, `UIStroke`
   `BRASS_DEEP` 2, with its own `UIGradient` rotation 90 `PANEL` → `PANEL_MID`
   at 0.6 → `PANEL_DEEP`.
5. A `Hairline` frame inset 3px inside the field, `UIStroke` `BRASS` 1 at 0.62.
6. Rivets: 6×6 frames, `BRASS_LIGHT`, `UICorner` 3, `UIStroke` `BRASS_DEEP` 1,
   at 12px in from each end.
7. Engraved rules: 1px `ENGRAVED_SOFT` bars at transparency 0.55 running inward
   from each rivet, each with a 4×4 tip rotated 45°.

Text on lacquer always carries a dark `UIStroke` (`PANEL_DEEP`, 1.5, ~0.25–0.35).
That is legibility work, not decoration — it separates the strokes from the panel
so the words read as cut into it rather than laid on it.

`RoundTimerClient.client.luau` is the reference implementation. Copy from it.

### Paper and ink — documents

Something a person made: a case file, a clue, a wheel of fate, a hotel notice.
Used by `ClueClientUI`, `CaseLedgerClient` (the board), `RouletteClientUI`,
`IntroCardClient`, `CheckInClient`, `RescueClient`.

```lua
local INK         = Color3.fromRGB( 43,  36,  29)
local PAPER       = Color3.fromRGB(200, 181, 135)
local PAPER_LIGHT = Color3.fromRGB(226, 211, 172)
local PAPER_DARK  = Color3.fromRGB(126, 103,  68)
local BLOOD       = Color3.fromRGB(112,  43,  35)  -- accent, bad news
local MOSS        = Color3.fromRGB( 49,  67,  55)  -- accent, good news
local SHADOW      = Color3.fromRGB( 18,  14,  10)
```

`RouletteClientUI` runs a slightly warmer cut of the same set (`INK` 38/30/25,
`PAPER` 219/202/157) because its sheet is older. Match the file you are extending
rather than mixing the two.

The aged-paper gradient is a fixed recipe, copied identically in `ClueClientUI`
and `CaseLedgerClient`:

```lua
local function agedPaper(parent: GuiObject)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, PAPER_LIGHT),
		ColorSequenceKeypoint.new(0.58, PAPER),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(184, 158, 109)),
	})
	gradient.Rotation = 94   -- not 90: paper does not age square
	gradient.Parent = parent
end
```

Paper panels get:

- `UICorner` 8 (large sheets), 3 (ribbons and small slips).
- `UIStroke` `INK` 3 at transparency ~0.04 — an inked edge, not a border.
- A **`SHADOW` frame behind, offset (+8, +9) and transparency ~0.26**, same size
  and corner as the sheet. This is what puts the sheet above the table.
- **A degree of rotation off square.** `-0.35` on the clue modal, `-0.6` on the
  ledger ribbon, `-1` on Noel's bubble. Nothing on paper is level. One value,
  under a degree; more than that reads as broken layout, not as a prop.

Optional aging, all in `IntroCardClient`: `deckle()` cuts torn edges as a row of
random-depth slivers carrying the tone of the edge they stand on; `wash()` and
`burn()` lay stains and scorch. `RouletteClientUI` has `addStain()`. Reach for
these on hero surfaces only — a toast does not need torn edges.

### Bone and outline — the meter layer

The persistent survival readout: hearts, hunger, sprint, sack count. This layer
is **not** rustic; it is icon-and-bar and it stays legible on top of anything.
`SurvivalClient`, `SackClient`.

```lua
local OUTLINE   = Color3.fromRGB( 28,  26,  32)
local BONE      = Color3.fromRGB(240, 236, 228)
local SLOT      = Color3.fromRGB( 78,  73,  90)
-- meters carry a saturated base + light pair each
local HUNGER_BASE, HUNGER_LIGHT = Color3.fromRGB(198,120,38), Color3.fromRGB(244,178, 76)
local SPRINT_BASE, SPRINT_LIGHT = Color3.fromRGB( 58,156,190), Color3.fromRGB(124,220,242)
local ALARM_BASE,  ALARM_LIGHT  = Color3.fromRGB(168, 48, 36), Color3.fromRGB(214, 84, 60)
```

Do not put a popup in this material. It exists so the numbers survive a dark
corridor; borrowing it for a notice makes the notice look like a debug overlay.

`RescueClient` is the honest hybrid: a paper palette carrying a meter's job, with
`Antique` titles, `SourceSans` detail and `Code` input hints. It works because a
first-aid card *is* a printed thing. Treat it as the precedent for "a HUD element
that is also a prop", not as licence to mix freely.

### The accent trap

`BLOOD` and `MOSS` appear in both document palettes **at different values** —
dark on paper (112/43/35), light on lacquer (227/122/96). They are the same
*role* tuned for their ground. Take the pair from the material you are building
in. Pasting the paper `BLOOD` onto dark lacquer gives you an unreadable maroon
smudge.

---

## 2. Type

Four faces, each with a job. No others without a reason.

| Font | Job | Where |
|---|---|---|
| `Garamond` | Body voice — sentences the building or a person says | Round plaque numerals, mallet notice, ledger ribbon, clue banner, Noel's dialogue, the whole roulette sheet, clue prop labels |
| `SpecialElite` | Typewriter — a document someone typed | Clue riddles, case-file entries and headings |
| `RobotoMono` | Record-keeping — codes, digits, tabs, machine text | Ledger tab strip, digit rows, answer field, status lines |
| `Antique` | Heaviest serif available — engraved caps, and short display text that has to hold at small sizes | Plaque headers, sack count and hint, rescue bandage count and status title |
| `Creepster` | The horror title | `IntroCardClient` headline, nowhere else |

`GothamBold`/`GothamMedium` appear only on **close buttons and the admin panel**
— chrome, not voice. A `×` in Garamond looks like a typo. That is the whole of
their remit; do not let Gotham leak into body copy.

Two type rules that are easy to miss:

- **Antique for small caps headers, not Garamond.** Garamond is thin and
  high-contrast; at 15–17px on dark lacquer its hairlines drop out and the word
  stops reading at a glance. Antique holds its weight down there. Above ~30px
  Garamond is the better face and the plaque numerals use it.
- **Roblox has no letter tracking.** The engraved look lives entirely in the gaps
  between caps, so it is written into the string:
  `"— H U N T I N G —"`, `"— T O O   H E A V Y —"`. One space between letters,
  three between words, an em dash and a space at each end.

### Sizes that are already load-bearing

Plaque header 15–16 · plaque numerals 34 · notice body 21 · ribbon 17 · modal
riddle 19 · case-file body 15 · monospace metadata 10–13 · digits 18–22.

---

## 3. Where it goes

### DisplayOrder is a ladder, and it is full

Every `ScreenGui` in the place, in order. Adding one means picking a rung and
saying why.

| Order | Name | What |
|---|---|---|
| 4 | `SackHud` | sack counter |
| 6 | `SurvivalHUD` | hearts, hunger, sprint |
| 8 | `RescueHUD` | downed/carry state |
| 9 | `RoundTimerHUD` | the brass round plaque |
| 12 | `FirstStayOnboarding` | objective card, first stay only |
| 25 | `ClosetHidingGui` | hiding status |
| 30 | `CaseLedgerDock` | the magnifier button + ribbon |
| 38 | `CaseLedgerBoard` | the case board |
| 40 | `FateRouletteHUD` | roulette wheel |
| 41 | `ClueModal` | clue riddle modal |
| 45 | `CRTStatic` | the static wash — **over the HUD, under the aiming dot** |
| 50 | `Crosshair` | aiming dot |
| 70 | `ProwlerNotice` / `AdminControlPanel` | full-screen takeover |

Sitting **above 45** means CRT static no longer washes over your surface, which
breaks the horror grade. Everything diegetic belongs below it.

### `IgnoreGuiInset`

- `false` for anything pinned to a screen **edge** — Roblox's own inset is the
  only thing that reliably clears the topbar on a phone with a notch, where the
  inset is not the desktop's 36px.
- `true` for full-screen overlays and washes, which want the whole viewport.

### The screen is already spoken for

- **Top centre** — the round plaque owns it outright. The clue banner and the
  onboarding card were both moved down by its height to keep clear.
- **Bottom left** — `SurvivalHUD` owns the lowest 114px. The ledger dock sits at
  `DOCK_BOTTOM = 134` to clear it.
- **Left, above the dock** — the ledger ribbon, 320px wide, first thing to shrink
  on a narrow screen.
- **Row below the plaque** — the Superman cooldown card.

Before you place something, check what is already there. `CaseLedgerClient` has
the most complete map in its comments.

### Not everything is a ScreenGui

- **`BillboardGui`** for a message *about a specific object*: Noel's speech
  bubble (`CheckInClient`), the mallet refusal (`MalletPlaqueClient`).
  `Adornee` the part, parent to `PlayerGui` when only one player should see it.
  Set `AlwaysOnTop = true`, `LightInfluence = 0`, `MaxDistance` (60–80),
  `ResetOnSpawn = false`, `ZIndexBehavior = Sibling`, and lift it clear with
  `StudsOffsetWorldSpace` (~3 studs clears both the object and its
  ProximityPrompt bubble).
  **`Size` in pure pixel offset stays a constant size on screen**; the Scale
  component is studs and shrinks with distance. Paragraphs want offset.
- **`SurfaceGui`** for text that is physically painted on a part — plaques,
  stencils, keypad displays. See `addFrontLabel` in `BankVaultBuilder` and
  `addLabel` in `CluePropKit`: `SizingMode = PixelsPerStud`, `PixelsPerStud` 110,
  `LightInfluence = 0`, `ZOffset = 1`.

---

## 4. Construction idioms

Copy these helpers into any new UI file. They are duplicated across every
existing one on purpose — a UI file here is self-contained.

```lua
local function corner(object: GuiObject, pixels: number)
	local value = Instance.new("UICorner")
	value.CornerRadius = UDim.new(0, pixels)
	value.Parent = object
end

-- ALWAYS pin Border mode. UIStroke defaults to Contextual, which means "border"
-- on a Frame but "draw around every glyph" on anything holding text. The clue
-- announcement toast lost the counters of its letters to a 2px blood outline at
-- 21px Garamond and read as a solid red smear until this was pinned.
local function stroke(object: GuiObject, color: Color3, thickness: number, transparency: number?)
	local value = Instance.new("UIStroke")
	value.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	value.Color = color
	value.Thickness = thickness
	value.Transparency = transparency or 0
	value.LineJoinMode = Enum.LineJoinMode.Round
	value.Parent = object
end
```

Other conventions:

- **Text that must not clip.** Where a label's copy is close to its width, use
  `TextScaled = true` plus a `UITextSizeConstraint` with `MaxTextSize` at the
  authored size. Current copy renders at exactly the size it was designed at;
  anything reworded shrinks instead of wrapping into a row with no height for it.
  See `engrave()` in `MalletPlaqueClient`.
- **Fading a whole panel** — wrap it in a `CanvasGroup` and tween
  `GroupTransparency`. One property instead of a tween per frame, stroke and
  label.
- **Scale to viewport, do not reflow.** Author at one size, wrap in a `UIScale`,
  and clamp:
  `math.clamp(math.min((viewport.X - 32) / WIDTH, (viewport.Y - 32) / HEIGHT), 0.5, 1)`.
  `UIScale` works about the `AnchorPoint`, so a pinned panel stays pinned.
  `RoundTimerClient` uses the simpler two-step version — full size, or
  `COMPACT_SCALE = 0.72` below 600px wide or on touch-without-keyboard.
- **Clean up your own GUI at the top of the file**, before building:
  ```lua
  for _, existing in playerGui:GetChildren() do
      if existing.Name == GUI_NAME then existing:Destroy() end
  end
  ```
  With `ResetOnSpawn = false` on every persistent surface, this is what stops
  duplicates after a respawn or a live re-sync.
- **Yield to modals.** `CaseLedgerClient` keeps a `BLOCKERS` list and hides
  itself when a higher surface is showing. A `ScreenGui` that is merely `Enabled`
  is not necessarily showing anything — the clue and roulette screens stay
  enabled all round and toggle a full-screen child named `Overlay` — so check the
  overlay's `Visible`, not the `ScreenGui`'s `Enabled`.
- **Modal overlays** are a `TextButton` with `Modal = true`, `Active = true`,
  `AutoButtonColor = false`, black at transparency 0.28, `Text = ""`, filling the
  screen. Name it `Overlay` so the blocker convention above finds it.

---

## 5. Voice

The copy is part of the look. Two registers:

- **The building** — signage, terse, impersonal, present tense.
  `— H U N T I N G —`, `— R E S T I N G —`, `— T O O   H E A V Y —`. Spaced
  caps between em dashes.
- **The document** — a sentence someone wrote, in Garamond or SpecialElite, no
  full stop unless it is a paragraph. `Only thee who wield the might may lift it`.

Never write a system message. "You do not have the Muscle class" is the wrong
game. The hotel does not know what a class is; it knows the mallet is too heavy
for you.

Refusals live in config as data, not inline strings — see
`DisplayCaseConfig.Refusals`, which pairs a `header`, a `line` and an `accent`
role (`"warn"` / `"calm"`) that the client resolves to the right colour for its
material.

---

## 6. Recipes

**A refusal or a status notice over a world object** → brass BillboardGui.
Copy `MalletPlaqueClient.client.luau` wholesale, change the copy.

**A transient message on screen** → paper ribbon. Copy the `ribbon` +
`ribbonShadow` pair from `CaseLedgerClient` — `PAPER` fill, `INK` text at 17,
`agedPaper`, `UICorner` 3, rotation −0.6, `UIPadding` 12/10,
`TextTruncate.AtEnd`, a `SHADOW` frame behind it at 0.5.

**Something requiring an answer** → paper modal. Copy the `overlay` → `shadow` →
`panel` stack from `ClueClientUI`: `Modal` overlay, `SHADOW` at (+8,+9), `PAPER`
sheet rotated −0.35 with `INK` stroke 3 and `agedPaper`, `SpecialElite` title,
`RobotoMono` field, `GothamBold` close.

**A persistent counter or meter** → bone-and-outline. Extend `SurvivalClient`'s
row rather than starting a new `ScreenGui`.

**Text painted on a part** → `SurfaceGui` via `addFrontLabel`/`addLabel`.

**A dev tool** → see below.

### Off-brand on purpose

`AdminClientUI` is a flat dark utility panel — `Gotham`, `Color3.fromRGB(20,22,26)`
surfaces, plain borders, `DisplayOrder` 70. It is not in-fiction and should not
be made rustic: it is a control panel for two named accounts, and making it look
like hotel signage would make it harder to tell from the game. Any future
debug/dev surface belongs in this material, not the other three.

---

## 7. Checklist before you call a GUI done

- [ ] One material, its palette copied verbatim, accents taken from that
      material's cut.
- [ ] Fonts from the table; spaced caps hand-spaced; Gotham only on chrome.
- [ ] `UIStroke` pinned to `ApplyStrokeMode.Border`.
- [ ] Paper is rotated under a degree and has a shadow; brass has sheen, bevel,
      hairline, rivets.
- [ ] A `DisplayOrder` rung that is justified, and below 45 if it is diegetic.
- [ ] `IgnoreGuiInset` correct for edge-pinned vs full-screen.
- [ ] Does not collide with the top-centre plaque or the bottom-left meters.
- [ ] `ResetOnSpawn = false` + destroy-by-name cleanup at the top of the file.
- [ ] `UIScale` clamped to viewport; text guarded against clipping.
- [ ] Copy is in the building's voice, and lives in a config table if it varies.
- [ ] `bl_analyze` clean.

---

## 8. Structure in the world — props, sets, and rooms

Sections 1–7 are about screens. This one is about the parts they hang off, and
it has one rule:

**Never build a room, a set, or a scene as a single `Model`.** Group with
`Folder`s. Reach for `Model` only when the thing genuinely moves, pivots, or is
cloned as a unit.

### Why it matters

Studio's default click selects the **whole `Model`**, not the part you clicked.
So a room built as one Model cannot be edited: you click a lamp to nudge it and
you have selected the floor, the ceiling, every wall and all 300 parts with it.
Drag by one stud and the room comes along. There is no way to fix a chair
without a trip through the Explorer.

A `Folder` has no such behaviour. Clicking a part inside a Folder selects **that
part**. Folders nest as deep as you like at no cost — they are pure
organisation, invisible at runtime, with no pivot, no bounding box, no
selection footprint.

This is not hypothetical. `BankVault` is currently one Model holding **303
descendants**, and `VaultChamber` one Model holding **67**. Both are listed in
[Known gaps](#known-gaps).

### Model vs Folder

Use a **`Model`** only when at least one is true:

- It **moves or pivots as a unit** — `:PivotTo`, `:MoveTo`, a tweened door leaf.
  `VaultChamberBuilder`'s `door`, `leaf`, and `keypad` are correct Models: each
  has a `PrimaryPart` and swings.
- It is **cloned or destroyed as a unit** — a spawnable pickup, a loot crate.
  `StorageRoomLootService`'s `box`/`crate` and `RescueWorldBuilder`'s `pickup`
  are correct.
- Code needs **`PrimaryPart`, `:GetBoundingBox()`, or `:ScaleTo()`** on it.
- It carries a `Humanoid`.

Use a **`Folder`** for everything else — which is most of it. Static geometry,
room shells, decor, lighting props, anything that exists to be looked at and
never addressed as one object.

### The shape to build

Folders for the layout, small Models only at the leaves where something actually
articulates:

```
Workspace
└── BankVault                (Folder — the room)
    ├── Shell                (Folder — floor, ceiling, walls)
    ├── Decor                (Folder — individually selectable props)
    │   ├── DisplayCase_1    (Folder — its panes stay separate)
    │   └── Pedestal_3
    └── DoorAssembly         (Model — swings, has a PrimaryPart)
```

The room is a Folder, so every prop stays clickable. The door is a Model,
because it is the one thing that moves.

### Tests before you wrap things in a Model

- **"Does this ever move as one piece?"** No → `Folder`.
- **"Would I ever want to click one part of this in isolation?"** Yes →
  `Folder`. This is the one that catches rooms.
- **Count the descendants.** A Model past roughly 20 is worth a second look; one
  past 50 is almost certainly a Folder wearing the wrong hat.

Attributes, tags, and `CollectionService` all work identically on a `Folder`, so
tagging and lookups lose nothing in the swap. What you lose is `PrimaryPart` and
pivot helpers — which is precisely the signal that it should have been a Model.

---

## Known gaps

Recorded here rather than silently fixed:

- `CaseLedgerClient`'s `BLOCKERS` list contains `{ name = "DialogueUI" }`, but
  Noel's speech bubble is a `BillboardGui` named `NoelDialogue` parented to the
  adornee part, not a `ScreenGui` in `PlayerGui`. The check is
  `playerGui:FindFirstChild(name)` filtered by `IsA("ScreenGui")`, so that entry
  never matches and the ledger dock does not currently yield during Noel's
  dialogue.
- `BankVault` (`BankVaultBuilder`) is one `Model` with 34 direct children and
  **303 descendants**; `VaultChamber` (`VaultChamberBuilder`) is one `Model`
  with 18 direct children and **67 descendants**. Both should be `Folder`s per
  [section 8](#8-structure-in-the-world--props-sets-and-rooms) — as they stand,
  clicking any single part in either room selects the entire room. The nested
  door/leaf/keypad Models inside them are correct and should stay Models. Not
  changed yet because both builders set attributes on the room root and other
  services look it up by name, so the swap needs those call sites checked.
- The paper palette exists in two cuts (`ClueClientUI`/`CaseLedgerClient` vs
  `RouletteClientUI`) and the brass palette is copied into three files. Nothing
  shares a palette module. That is survivable, but a fourth brass surface is the
  point at which extracting one is worth it.
