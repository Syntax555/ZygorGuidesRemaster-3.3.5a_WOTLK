# Zygor Guides Viewer installer

This installer adds Zygor Guides Viewer for the
[mod-playerbots-portable](https://github.com/Syntax555/mod-playerbots-portable) server to WoW 3.3.5a build 12340. It
installs the commit of [Syntax555/ZygorGuidesRemaster-3.3.5a_WOTLK](https://github.com/Syntax555/ZygorGuidesRemaster-3.3.5a_WOTLK) that this
ZIP was built from. Internet access and Windows PowerShell 5.1 or later are
required.

1. Extract this ZIP to a writable folder outside your WoW installation.
2. Close WoW completely. Run `Install-Zygor.cmd`.
3. Enter your client's `Interface\AddOns` folder when prompted.
4. Enable Zygor Guides Viewer in the character selection screen. Disable a separate `ZygorGuidesViewer` or `ZygorTalentAdvisor` addon if present; `ZygorGuidesViewerRM` already contains them.

The installer downloads the source archive of that commit directly from
GitHub and checks every file of `ZygorGuidesViewerRM` against the SHA-256 hashes in
`ADDON_FILES.json` before installing it. An existing `ZygorGuidesViewerRM` folder is
backed up; account and character SavedVariables are preserved.

For a noninteractive installation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-Zygor.ps1 -AddOnsPath 'C:\Games\WoW\Interface\AddOns'
```

`SOURCE_MANIFEST.json` records the repository and commit. The addon, its
guides, graphics and libraries are not redistributed in this ZIP; their
original terms and notices remain applicable. The included MIT license covers
the installer tooling only.

Automated source and installation checks do not replace an in-game test. See
the [integration guide](https://github.com/Syntax555/mod-playerbots-portable/blob/main/docs/zygor-progression.md) for supported behaviour and the
remaining live validation.
