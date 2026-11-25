# Virtuous Companion WoW addon

The in-game Virtuous guild client. It adds Tickets and Raid Signups tabs to the right side of Blizzard's Guild & Communities window. Officers also receive a server-authorised Guild Ranks tab. Material and absence forms live together under Tickets. Use `/virtuous` or `/vt` to open that window on the Companion tabs.

## Install

Copy this folder as `VirtuousCompanion` inside the target client's addon directory, for example:

```text
World of Warcraft/_forever_/Interface/AddOns/VirtuousCompanion/
```

The addon targets the Forever/Camelot client with interface `16001`.

The official source is [Warriorcatzz/virtuous-companion-addon](https://github.com/Warriorcatzz/virtuous-companion-addon). Download the packaged ZIP from [GitHub Releases](https://github.com/Warriorcatzz/virtuous-companion-addon/releases), not GitHub's source-code ZIP. Extract its `VirtuousCompanion` folder into `Interface/AddOns`. The separate desktop Companion is required for Discord sign-in and guild sync. **Log in to the [Virtuous website](https://virtuous.dk), then download the Windows desktop app from [virtuous.dk/companion](https://virtuous.dk/companion).** Desktop installers are available only through the website after login. Once installed and connected to Discord, the app receives automatic updates privately.

The project's CurseForge description is maintained in [docs/curseforge-description.md](docs/curseforge-description.md).

## Automatic releases

Pushes to `main` and pull requests check all Lua files, run the addon tests against pinned Forever client UI sources, and build an installable ZIP. These checks have no publishing credentials. The build artifact is available under the workflow run's **Artifacts**.

For a public release:

1. Set `## Version` in `VirtuousCompanion.toc` to the new version, for example `0.8.6`.
2. Commit and push, then create a matching GitHub release/tag such as `v0.8.6`.
3. GitHub Actions runs checks, attaches the addon ZIP to the GitHub release and uploads it to CurseForge when configured. Tags ending in `-alpha.1` or `-beta.1` publish the corresponding prerelease type; the TOC version must match.

The workflow uses [BigWigs Packager v2.7.0](https://github.com/BigWigsMods/packager/releases/tag/v2.7.0), pinned to its commit. It detects Forever `1.60.1` from interface `16001`; do not substitute a Retail or Classic interface merely for packaging.

### One-time CurseForge setup

The addon and release workflow are connected to **Virtuous Companion**, CurseForge project **1831149**, for the Forever client. In this GitHub repository's **Settings → Secrets and variables → Actions**, add:

| Type | Name | Value |
| --- | --- | --- |
| Repository secret | `CF_API_TOKEN` | An upload token generated at [CurseForge API tokens](https://www.curseforge.com/account/api-tokens) |
| Optional repository variable | `CURSEFORGE_PROJECT_ID` | Overrides the configured project ID `1831149` |

Enter the token directly in GitHub Secrets. It does not belong in source files or chat. Without the token, GitHub releases still work and the workflow summary explicitly says CurseForge publishing is pending. To publish an existing tag after adding the token, open **Actions → Check and release addon → Run workflow**, enter that tag in `release_tag`, and run it. A successful upload is recorded on the GitHub release so normal retries skip publishing it again. Actual upload failures fail the job.

On the CurseForge project's **Source** tab, set the source URL to `https://github.com/Warriorcatzz/virtuous-companion-addon`. This displays the GitHub link; automatic file uploads are handled by the release workflow above. The first uploaded addon file starts CurseForge's project moderation process.

Only the main addon is distributed. The desktop-generated `VirtuousCompanion_Data` addon, SavedVariables, member data, credentials, tests and development files are excluded from the ZIP. CurseForge updates therefore leave the generated inbox in its separate folder.

## In-game features

- Create structured guild-bank material requests.
- Create structured absence tickets with first/last dates and a private reason.
- Open any synced ticket to see its status and recent replies from Discord, virtuous.dk, or WoW, then queue an answer back to the same private Discord channel.
- View upcoming raids for the teams assigned to your account in the database, plus signup totals, roster names, and your current signup state.
- Sign up with the Main assigned to that raid's team in the database, regardless of the currently logged-in WoW character, or withdraw the signup.
- Choose Tank or Melee when signing up a Feral Combat Druid.
- Persist actions in a retry-safe SavedVariables outbox with stable IDs.
- Import the authorised ticket, character, raid, and signup snapshots.
- Show a Discord column to the right of Note in the normal guild roster. Known character owners use their synced Discord server display name; unknown or ambiguous names stay blank. Hover a row to read the full Discord name. Native chat and profession/achievement views keep their existing layout.
- Review confirmed guild-rank mismatches in a compact Character / Current / Expected list. Correct ranks, missing characters and ambiguous assignments are omitted. Full roleplay names resolve through a unique first name when needed, while Guild Master and Guild Officer ranks remain independent. Officers can promote or demote one rank step at a time.
- Rank changes use Blizzard's out-of-combat action-button template and native guild commands, recheck the current rank when clicked, and report success only after the live roster confirms a change.
- Keep the protocol ready for future versioned loot/mail events.

## Important sync behaviour

WoW addons cannot call the guild HTTPS API. WoW writes SavedVariables during `/reload` or logout, and can overwrite external edits while running. Therefore:

1. Queue a ticket or signup change in game.
2. Use `/reload` or log out so WoW saves it.
3. The running desktop helper detects and uploads the changed file automatically.
4. The helper writes acknowledgements and incoming data to the separate `VirtuousCompanion_Data` addon, like TSM AppHelper.
5. Use `/reload` again to import tickets, raids, and signup changes. Closing WoW is not required.

The desktop application is intentionally only a secure transport helper. Guild workflows stay inside this addon. Loot fulfillment should be added as a new event type only after the Forever mail events and attachment APIs are verified in the actual client.

## Tests

On Linux, install Lua 5.1 and run `bash scripts/test.sh`. It syntax-checks the Lua files, downloads the unmodified Forever [SecureTemplates.lua](https://raw.githubusercontent.com/Gethe/wow-ui-source/c01a87b549bbc19e0f284c1616d18654c91297de/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua) and corresponding XML at that pinned commit, then runs `tests/*.test.lua`. The fixtures live in ignored `.test-fixtures/`. Direct Lua test runs can set `VIRTUOUS_WOW_UI_FIXTURES` to that directory; the existing workspace cache in `../.tools` remains the fallback. Rank-changing commands are mocked; the tests never change a live guild rank.
