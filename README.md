# Eat The Cube

A Roblox place where you are a cube: eat smaller cubes to grow, eat smaller
players to take a slice of their size, and rebirth to multiply everything.

`eat the cube.rbxlx` is the game. Everything in `src/` and `tools/` exists to
build that file reproducibly - you can edit the place directly in Studio, or edit
the sources and rebuild.

```
python3 tools/build.py      # src/ + base_cube.rbxlx  ->  eat the cube.rbxlx
python3 tools/verify.py     # round trip, syntax, references, asset contract
```

The build is deterministic (fixed RNG seed), validates the XML, refuses to write
a place with dangling references, and is idempotent: rebuilding from the same
inputs produces the same file.

---

## Architecture: one Script, one LocalScript, everything else a module

The place contains exactly **two** runnable scripts. Nothing else executes on its
own, so there is no hidden startup order and no script to hunt down when
something misbehaves.

| Instance | Kind | What it does |
| --- | --- | --- |
| `ServerScriptService/Server` | **Script** | requires and initialises the server modules in dependency order |
| `ReplicatedFirst/Client` | **LocalScript** | shows the loading screen, waits for content, initialises the client modules |

Everything else is a `ModuleScript` with an `Init()` (or plain data) and no side
effects at require time.

```
ServerScriptService/
  Server                      the only Script
  Modules/
    Remotes                   one defensive accessor for every RemoteEvent
    DataManager               ProfileService profiles, leaderstats, pre-release hooks
    Players                   join/leave, gamepass caching, session playtime
    Characters                spawning, per-cube wiring, kills, autofarm, eating
    Food                      the cube economy: regions, spawning, pickup
    Progression               rebirths, skins, daily quests, zone gating, visuals
    Leaderboards              ordered data stores, cached + throttled
    Shop                      developer products, receipts, the VIP door prompt
    Codes                     one-shot redeemable codes
    Gifts                     playtime rewards
    Admin                     UserId-gated console commands
    ProfileService            third party, untouched

ReplicatedStorage/
  GameData/                   ALL game content, as instances (see below)
  Events/                     the 15 RemoteEvents
  Modules/GameConfig          reads GameData + workspace/Zones into plain tables
  UiModule                    button animation, menu toggling, number formatting
  Modules/FormatNumberAlt     third party, untouched

ReplicatedFirst/
  Client                      the only LocalScript
  Client/Loading              loading screen template (asset)
  Client/Notifier             toast template (asset)
  Client/ClientModules/
    LoadingScreen  Notifier  Hud  DeathScreen  Camera  Chat  CoreGui
    UiScaler  VipDoor  Popups
    Menus/
      MenuUi                  button <-> frame wiring, row/list API
      Rebirth  Skins  Quests  Zones  Leaderboard  Admin  Codes  Shop
      Rewards  UpdateLog
```

`tools/tree.py eat\ the\ cube.rbxlx` prints the instance tree, `--scripts` only
the scripts.

---

## Content lives in the place, not in code

Every number, name, colour and rule is an instance you can edit in Studio. Code
only reads them (through `GameConfig`) and never generates gameplay content at
runtime.

| Where | Contents |
| --- | --- |
| `ReplicatedStorage/GameData/Settings` | 59 scalars: food targets, spawn interval, rebirth curve, kill rewards, camera, notify timing, spawn regions, zone arena wall/floor sizes, store name, game name |
| `GameData/Admins` | who gets the console - a Folder per person with `UserId` + `Role` (currently `7362557250`) |
| `GameData/Ranks` | rank name -> size threshold |
| `GameData/Rarities` | `Weight`, `Value`, `Size`, `Color` per food tier |
| `GameData/Skins` | `Color`, `Unlock` (`start`/`cash`/`size`/`rebirth`), `Req`, `Order` |
| `GameData/Quests` | `Type`, `Goal`, `RewardCash`, `RewardSkin`, `Text`, `Order` |
| `GameData/Gifts` | `RequiredTime`, `Reward`, `Type` per playtime gift (button `RewardN` in `Frames/Rewards/Rewards` shows gift `N`) |
| `GameData/Codes` | code name -> cash |
| `GameData/Products` | `ProductId`, `Kind`, `Amount`, `Label` |
| `GameData/Gamepasses` | `GamePassId`, `Kind` (`speed`/`cash`/`vip`) |
| `GameData/UpdateLog` | ordered StringValues shown in the update log menu |
| `Workspace/Zones/<Name>` | every zone **is** its own arena: a Model holding a `Floor` slab (its position/size define the food pool), four walls, a `Sign`, and `Id`/`Rarity`/`ReqSize`/`ReqRebirth`/`Color` children that define the rules |
| `StarterGui/Buttons`, `StarterGui/Frames` | the HUD/menu bar and every menu panel, including their templates (`RowTemplate`, `SectionTemplate`) |

Common edits:

* **Add a code** - a NumberValue in `GameData/Codes` named after the code.
* **Add a skin** - a Folder in `GameData/Skins` with `Color`/`Unlock`/`Req`/`Order`.
* **Add a zone** - copy an arena Model in `Workspace/Zones`, move it somewhere
  with clear ground, set `Id`/`Rarity`/`ReqSize`/`ReqRebirth`/`Color`. The food
  pool, the sign, the menu row and the server gate all follow. Resize its `Floor`
  and the food pool resizes with it.
* **Retune the economy** - `GameData/Settings`.
* **Add a menu** - a TextButton in `StarterGui/Buttons` and a Frame with the same
  name in `StarterGui/Frames`; `MenuUi` wires the toggle with no code at all.

The content contract is `src/gamedata.json`; `tools/content.py` turns it into the
instances above and `tools/build.py` injects them. Editing the place in Studio is
always fine - a rebuild only adds instances that are not already there, so your
Studio edits are not clobbered.

---

## The map

Six arenas, all built the same way (16 stud floor slabs whose top face is
`FloorY`, walls 4 studs thick and `ZoneWallHeight` tall, 40% see through, the
shipped wall and floor textures):

| Arena | Centre (X, Z) | Floor | Cubes | Gate |
| --- | --- | --- | --- | --- |
| hub (shipped) | 0, 0 | 561 x 661 | `BaseFoodTarget`, mixed rarity | none - everybody starts here |
| Greenfield | 0, 1500 | 400 x 400 | `ZoneFoodTarget`, Common | none |
| Crystal Cave | 1500, 0 | 440 x 440 | Rare | Size 300 |
| Lava Forge | -1500, 0 | 480 x 480 | Epic | Size 1500 |
| Frozen Peak | 0, -1500 | 520 x 520 | Legendary | 2 Rebirths |
| Void Core | 0, 3200 | 560 x 560 | Mythic | 5 Rebirths |
| VIP wing (shipped) | 347, 2 | behind `Workspace/VIPDoor` | `VipFoodTarget`, Rare+ | VIP gamepass |

Travel between them is the Zones menu (`ZoneTeleport`, throttled by
`ZoneTeleportCooldown`); the arenas are walled, so there is no walking between
them, and dying inside one respawns you inside it while you still meet its gate.
Zone Models are `ModelStreamingMode.Persistent` - they never stream out, which is
what lets the client list all five arenas while the player stands in the hub.
`tools/verify.py` fails the build if an arena loses a wall, is repainted, stops
being Persistent, or is dragged within 100 studs of another arena.

---

## How a round works

1. `DataManager` loads the profile, creates `leaderstats` (`Cash`, `Size`) and
   sets `DataLoaded`.
2. `Characters` clones `ServerStorage/Character`, parents it and wires it once -
   name tag, skin, size tween, `Died`, `Touched`, `Size.Changed`. Join, free
   respawn and paid revive all go through the same path.
3. `Food` fills every region (hub arena, each zone arena's floor, VIP wing) and
   keeps them topped up. Pickup claims the cube first (`CanTouch = false`), then grows
   the player, then shrinks it out - a throwing handler can no longer leave an
   inedible cube on the map.
4. Bigger cube touches smaller cube: the victim dies, the killer absorbs
   `KillSizeTransfer` of their size (capped) plus `KillCash`.
5. `Progression` handles rebirths, skins, daily quests and zone travel. Zone
   gating is shared by the teleport remote **and** the food handler, so an admin
   teleport into a locked arena still does not hand out its rarity for free.

Death is explicit: `CharacterAutoLoads` and `ResetPlayerGuiOnSpawn` are **off** in
the place, because the cube is assigned by `Characters` and the client is a single
LocalScript that cannot survive a PlayerGui reset. `tools/verify.py` fails the
build if either setting drifts.

---

## Repo layout

```
eat the cube.rbxlx     the game (build output, committed)
base_cube.rbxlx        build input: the rebranded place with food stripped
eat the traingles.rbxlx  the original place, for reference
src/gamedata.json      the content contract
src/**.lua             every script the build writes into the place
tools/rbxlx.py         .rbxlx parsing/editing/validation toolkit
tools/content.py       gamedata.json -> GameData/Events/Buttons/Frames/Zones XML
tools/build.py         the build plan (keep, move, convert, delete, inject)
tools/verify.py        post-build checks
tools/diff_place.py    reads the place back and diffs it against gamedata.json
tools/tree.py          instance tree dump
tools/tests/           pytest suite for the tools themselves
.github/workflows/     CI: build, hash-compare, verify, tests, content diff
```

## Checks

| Check | Where | What it catches |
| --- | --- | --- |
| `python3 tools/build.py` | local + CI | refuses to write a place with dangling refs, an undefined SharedString md5, or the wrong script count |
| `python3 tools/verify.py` | local + CI | a committed place that no longer matches `src/`, unparseable Lua, a remote/setting/product/menu the code uses but the asset lacks, place settings drifting back to Roblox defaults |
| `python3 tools/diff_place.py` | local (advisory) | content drift between `src/gamedata.json` and the asset, in either direction. `--strict` (CI) fails on any difference |
| `python3 -m pytest tools/tests -q` | local + CI | the tools themselves: build determinism, and mutation tests proving verify fails when the place is broken |

```
python3 tools/diff_place.py            # what does the place say right now?
python3 tools/diff_place.py --json place.json
```

Read the report as a direction: "missing from the place" means `gamedata.json` is
ahead, so rebuild; "not in `gamedata.json`" means the place is ahead, so copy the
Studio edit back into `src/gamedata.json` before the next regeneration.

`*.rbxlx` files are marked binary in `.gitattributes` (no diff, no merge, no line
ending normalisation - a rewritten line ending invalidates the file). They are not
in Git LFS: `git lfs` is not available in every environment that builds this repo,
and a `.gitattributes` LFS filter that cannot run breaks clones. If history size
becomes a problem, migrate with `git lfs migrate import --include='*.rbxlx'`.

`tools/verify.py` is the safety net: it re-extracts every script from the built
place and compares it byte for byte with `src/`, parses each module as Lua, and
cross-checks that every remote name, setting key, product kind, gamepass kind,
menu frame and `require` target the code uses actually exists in the asset - plus
the asset contract listed in `REQUIRED_ASSETS`.
