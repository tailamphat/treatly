# Pet packs

A pet pack is a folder containing `pet.json`. Built-in packs are in `Pets/`; your own go in `~/Library/Application Support/Treatly/Pets/` (menu bar > **Open Pets Folder**). A user pack with the same `id` replaces the built-in one. Restart Treatly after adding a pack.

```json
{
  "id": "corgi",
  "name": "Corgi",
  "species": "dog",
  "defaultName": "Biscuit",
  "treat": { "name": "bone", "image": "treat.png" },
  "sprite": { "palette": { "o": "#3A2414", "b": "#E89B4A" }, "rows": ["..."] },
  "personality": { "walkSpeed": 90, "runSpeed": 240, "energy": 0.6, "sleepiness": 0.2, "rest": [0.5, 2], "nagSeconds": 25, "patience": 0.7 },
  "phrases": {
    "carry": ["{task}"],
    "drop": ["*herds you toward* {task}"],
    "yell": ["BORK! {task}!"],
    "whine": ["{name} is sad about {task}"],
    "happy": ["Zoomies!"],
    "bury": ["Saving it for later."]
  },
  "sound": "Funk"
}
```

## Sprite sheets (recommended)

```json
"sheet": {
  "image": "sheet.png",
  "frameWidth": 52, "frameHeight": 42,
  "scale": 2,
  "footPadding": 3,
  "mouth": [45, 21],
  "animations": {
    "idle":  { "row": 0, "count": 4, "fps": 3 },
    "walk":  { "row": 1, "count": 4, "fps": 7 },
    "bark":  { "row": 2, "count": 2, "fps": 6 },
    "sit":   { "row": 3, "count": 1 },
    "sleep": { "row": 4, "count": 2, "fps": 1 }
  }
}
```

- Frames are a grid; each animation is a run of `count` frames on `row`, starting at column `start` (default 0). `once: true` holds the last frame.
- Only `idle` is required. Missing animations fall back: run -> walk -> idle, walk -> idle, bark -> sit -> idle, sleep -> lie -> sit -> idle, beg -> lie -> sit -> idle, eat -> sit, dig -> sit, held -> idle.
- `scale` is points per sheet pixel (default 2). `facing` is `"right"` (default) or `"left"`. `footPadding` is blank rows under the feet. `mouth` is where the treat is held, in frame pixels from the top-left of a right-facing frame.
- `wardrobe` (optional) lists items the pet can wear, such as `["party-hat", "bow"]`. Each item `x` is an overlay `wear-x.png` with exactly the same layout as the sheet, drawn on top of the pet. Ids are lowercase letters, digits and dashes. Built-in names: `party-hat`, `bow`, `crown`, `bandana`, `glasses`, `flower`; any other id is shown title-cased.
- `treat.image` is a PNG in the pack folder.
- `container` is `"bowl"` (default) or `"tree"` (banana trees, used by King Kong).
- `credit` names the artist and license.

## Text sprites

Pixel art is written as text. Each character is one pixel, `.` is transparent, and every other character must be in `palette` (hex `#RRGGBB` or `#RRGGBBAA`). All rows must be the same width. Sprites face **right**; Treatly mirrors them when walking left. The pet is drawn at 4x and the treat at 2x. Simple motion (a walking bob, a sleeping squash, eating and burying) are applied by the app, so one frame is enough.

## Fields

- `personality.walkSpeed` - points per second (required)
- `personality.sleepiness` - chance (0 to 1) of napping when it stops (required); much lower while it has a task
- `personality.runSpeed` - points per second when running to a bowl, to you, or on zoomies (default 2.2x walk)
- `personality.energy` - chance (0 to 1) that a stroll becomes a run (default 0.15)
- `personality.rest` - `[min, max]` seconds it stands around between moves (default `[1.5, 4.5]`)
- `personality.nagSeconds` - how long each nagging burst lasts (default 20)
- `personality.patience` - scales the breaks between nagging bursts; above 1 is more patient (default 1)
- `phrases` - speech bubble templates; `{task}` and `{name}` are filled in
- `sound` - a macOS system sound name (Basso, Funk, Pop, Purr, Sosumi, Tink...), played when it starts yelling or whining if sound is on

Run `swift run TreatlyChecks` to validate the built-in packs.
