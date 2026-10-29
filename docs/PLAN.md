# Treatly - plan

## Concept

An open-source macOS desktop pet that nags you about your todos. Tasks are treats; the pet wants to eat them.

- The pet roams the bottom of the screen (above the Dock) on the menu bar display.
- Each connected task source has a **bowl** on the ground: Apple Reminders (orange, left) and Google Tasks (blue, right). Bowls show how many treats they hold.
- The pet walks to the right bowl, takes out the current treat, and carries it around.
- Finishing a task means the pet eats the treat. Snoozing means it buries it.

## Decisions

| Topic | Decision |
|---|---|
| Platform | macOS 14+, Swift + AppKit (native transparent overlay windows, EventKit) |
| Distribution | Open source, MIT |
| Name | Treatly |
| Task sources | Apple Reminders (EventKit) and Google Tasks (REST + OAuth loopback/PKCE, user-supplied client) |
| Art | Placeholder pixel art as text sprites in JSON packs |
| Sound | Opt-in, macOS system sounds |
| Pets (MVP) | Shiba Inu, Golden Retriever, Orange Tabby, Black Cat, King Kong |
| Tests | `swift run TreatlyChecks` (Command Line Tools have no working XCTest/Swift Testing) |

## Behaviour

**Current task**: overdue first (most overdue first), then higher priority, then earliest due date, then title. Clicking a task in a bowl pins it. Snoozed and skipped tasks are hidden until their time is up.

**Escalation** (every *step*, default 10 min, starting at the due date or when the task became current):

1. Carrying - trots around with the treat, flashes the task title now and then
2. Dropping - walks to the middle of the screen, drops the treat, sits
3. Barking - yells the task in a speech bubble
4. Whining - sad phrases

Overdue treats are stinky (green cloud). Treat size follows priority.

**Actions**: click the pet for Done / Snooze 10 min / Snooze 1 hour / Next treat. Drag the pet to move it.

**Sync**

| | Apple Reminders | Google Tasks |
|---|---|---|
| Done | marks completed | marks completed |
| Snooze | moves due date + hides locally | hides locally (Google stores dates only) |
| Updates | EventKit change notifications + 60 s poll | 60 s poll |
| Priority | `!`/`!!`/`!!!` | none |

Note: EventKit does not expose the Reminders "flagged" state, so priority is used instead.

## MVP status (done)

- [x] Core logic with checks: selector, escalation, pet brain, bowls, packs, OAuth helpers
- [x] Overlay pet window, pixel sprite renderer, speech bubbles, procedural animations
- [x] Bowls per source with treat counts and task menus
- [x] Apple Reminders source with list picking
- [x] Google Tasks source with OAuth sign-in and list picking (not yet tested against a real account)
- [x] Menu bar: pet picker, rename, lists, nag speed, sound, pets folder
- [x] Pet packs loaded from the app bundle and `~/Library/Application Support/Treatly/Pets`

## Roadmap

1. Real sprite sheets per animation state (walk cycle, sleep, eat, yell) with a `sprites.png` + frames format alongside text sprites
2. Walk to the focused window instead of screen center when dropping the treat
3. Walking on window edges and the Dock, climbing screen sides; resting in the notch
4. Mood and stats: happy when tasks get eaten, droopy when bowls overflow; daily "bones chewed" count
5. More pets: Corgi, Husky, Pug, Siamese, Persian, Tuxedo, Dragon; coat colour variants
6. Multiple pets at once, each guarding a different source or list
7. Launch at login, signed and notarized releases, Homebrew cask
8. More sources: Markdown `TODO.md`, Todoist, Things, GitHub issues
9. Swift Testing suite once building with Xcode
