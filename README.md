# Zygor Guides Viewer Remaster for Playerbots Portable

A guide viewer, waypoint arrow and Gear Finder for **WoW 3.3.5a, build 12340**
(Interface `30300`), adapted to each character's earned progression in
[Playerbots Portable](https://github.com/Syntax555/mod-playerbots-portable).
This maintained fork uses the `main` branch.

## Install or update

1. Download [Zygor-IP-latest.zip](https://github.com/Syntax555/ZygorGuidesRemaster-3.3.5a_WOTLK/releases/latest/download/Zygor-IP-latest.zip)
   from this fork's [Latest release](https://github.com/Syntax555/ZygorGuidesRemaster-3.3.5a_WOTLK/releases/latest).
2. Extract it to a writable folder outside WoW, then close WoW completely.
3. Run `Install-Zygor.cmd` and select your client's `Interface\AddOns` folder.
   Internet access and Windows PowerShell 5.1 or later are required; no
   administrator rights are needed.
4. Enable Zygor Guides Viewer in the addon list. Disable separate
   `ZygorGuidesViewer` and `ZygorTalentAdvisor` addons; the installed
   `ZygorGuidesViewerRM` already contains the advisor.

The ZIP contains an **installer, not the addon**. It downloads its exact fork
commit from GitHub, verifies every addon file against SHA-256 hashes and
installs `Interface/AddOns/ZygorGuidesViewerRM/ZygorGuidesViewerRM.toc`. It backs
up an existing addon folder and preserves account and character SavedVariables
in `WTF/`. Use the same steps for updates; do not mix versions or nest folders.
`SOURCE_REVISION.txt` and `SOURCE_MANIFEST.json` identify the installed source.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-Zygor.ps1 -AddOnsPath 'C:\Games\WoW\Interface\AddOns'
```

## mod-playerbots-portable fork

With the matching server's MultiBot Bridge, guides, guide chains, quest goals,
Gear Finder sources and Wrath best-in-slot lists follow the character's own
Individual Progression tier. The addon reads server state and cannot grant
gear, progression or access. Open **Progress** with `/zgprogress`, inspect
state with `/zygorip`, or request it again with `/zygorip refresh`.

Automatic mode follows server progression when available and uses ordinary
realm behavior without bridge support. On keeps later content locked while no
answer is available; Off disables the addon's progression filters. Server
access rules apply in every mode. While progression filters apply, transition
quests remain manual.
The bundled Talent Advisor knows Wrath trees only and stays inactive before
Wrath or while the era is unknown when progression filters apply, and always
for EraTalents characters.

The Gear Finder uses historical talent data for the player's profile when
available. `/zygortank`, `/zygordps` and `/zygorheal` select role weights;
`/zygorrole auto` restores automatic selection. These are the viewer's stat
weights, not a historical combat simulation.

On a controlled altbot's Blizzard or DragonUI **equipment inspect tab**, click
the Zygor button for that bot's Gear Finder. The bot must be online, in your
group and within normal inspect range, with matching inspected-bot server
support. Recommendations use its equipment, effective combat profile and own
progression. Unknown sources remain unavailable; bot crafting recommendations
are excluded because learned recipes are not reported. Changing tabs or the
inspected character closes the view. This only recommends sources; normal bot
loot and equipment evaluation remain server behavior.

Imported guides and source tables can differ from realm data. Full client
interaction, guide routes and every addon combination have not been verified
in game. See the [integration guide](https://github.com/Syntax555/mod-playerbots-portable/blob/main/docs/zygor-progression.md)
for supported behavior and limits. For viewer controls, left-click the minimap
icon to toggle the viewer, right-click for the Guide Manager, or Shift-right-click
for options.

## Source and contributions

Changes belong on this fork's `main` branch. Its
[Latest workflow](https://github.com/Syntax555/ZygorGuidesRemaster-3.3.5a_WOTLK/blob/main/.github/workflows/latest.yml)
checks Lua and the installer before publishing the rolling release. The
server's [manifest](https://github.com/Syntax555/mod-playerbots-portable/blob/main/versions.lock.json)
pins its tested fork commit; Latest may be newer. Follow the
[contributing guide](https://github.com/Syntax555/mod-playerbots-portable/blob/main/CONTRIBUTING.md)
for source updates and checks. Report fork problems in
[this issue tracker](https://github.com/Syntax555/ZygorGuidesRemaster-3.3.5a_WOTLK/issues)
with the installed revision, client build, reproduction and complete first Lua
error (`/console scriptErrors 1`).

## Provenance, credits and license

Based on [ErebusAres's remaster](https://github.com/ErebusAres/ZygorGuidesRemaster-3.3.5a_WOTLK),
last imported at
[`d2aae8d0f1f3`](https://github.com/ErebusAres/ZygorGuidesRemaster-3.3.5a_WOTLK/commit/d2aae8d0f1f3782d964e4179907b215aab484787).
The [original README](https://github.com/ErebusAres/ZygorGuidesRemaster-3.3.5a_WOTLK/blob/d2aae8d0f1f3782d964e4179907b215aab484787/README.md)
provides general viewer features and upstream credits. Original Zygor Guides
concept and content belong to their creators. Community credit includes
[mikki33](https://github.com/mikki33) for Russian localization,
[yad](https://github.com/yad) for localized quest databases and their generator,
and [SnaxxNZ](https://github.com/SnaxxNZ) for profession and Gear Finder data.

The viewer retains upstream's `GPL` designation without an identified version.
It does not license every guide, database, image or bundled library. Preserve
component notices and read the [licensing notice](https://github.com/Syntax555/ZygorGuidesRemaster-3.3.5a_WOTLK/blob/main/LICENSE).
The installer's [MIT license](https://github.com/Syntax555/ZygorGuidesRemaster-3.3.5a_WOTLK/blob/main/.github/installer/LICENSE)
covers its tooling only; the installer ZIP contains no addon files.
