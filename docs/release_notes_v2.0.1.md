Tags now land where you actually touch. A focused fix for the netcode behind tagging.

## Honest tags

A few players hit moments where a tag felt wrong — caught when no one seemed to be near them, or an ability that tagged out of nowhere. This release tracks those down:

- **No more phantom tags.** Tags are checked against where another player *really* was, not a smoothed-over guess. During a brief connection hiccup the game used to "predict" a player a little ahead of their last known spot; that guess could clip into a chaser and register a tag that never happened on either screen. The tagger now uses the last real position instead.
- **Teleports no longer invent a midpoint.** When a player blinks or gets swapped, they jump instantly — they were never in between. The host's tag check used to imagine them sliding across that gap, which could tag someone standing along the path. It now treats the jump as a jump.
- **Swapping no longer tags you.** Casting Swap while you're "it" dropped you right on top of your target, and for one frame the game read that as contact and bounced the tag straight back to you. There's now a short grace right after any teleport so landing next to someone doesn't count as tagging them. Normal chasing and Dash are unaffected.

## Notes

- This is a Windows and macOS update with no gameplay or content changes — same maps, classes, and feel, just fairer tagging. The browser version is unchanged for now.
- Windows: SmartScreen → *More info → Run anyway*. macOS: right-click → *Open* the first time.
