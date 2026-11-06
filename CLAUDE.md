# LunarMP - CLAUDE.md

Workspace: `/Users/icaro/Documents/Projects/SnapMaker` (20 Snapmaker 2.0 repos, all on branch `a250t/main`).
Specialist agent: `sm-lunarmp` (`../.claude/agents/sm-lunarmp.md`). Facts file: `../.claude/knowledge/repos/LunarMP.json`.
Workspace dependency map: `../.claude/knowledge/DEPENDENCIES.md`. Repo review: `../_snapmaker2-review/repos/LunarMP.md`.
Dates dd/mm/yyyy, metric units. Notes written 07/11/2026 against `a250t/main` @ `9702593`.

## Purpose

LunarMP ("Lunar Mesh Processing") is a small C++14 command-line tool built on CGAL that checks, repairs, simplifies
and compares triangle meshes before slicing. Luban spawns it (via the npm package `@snapmaker/snapmaker-lunar`) for
"check model", "repair model", "simplify model" and to repair generated support meshes. It has no machine, G-code,
network or firmware knowledge: it reads a mesh file and writes an STL plus status lines on stderr.

## Tech stack

- C++14, CMake >= 3.16 (`CMakeLists.txt`: static lib `_LunarMP` + executable `LunarMP`).
- CGAL (Polygon Mesh Processing, Surface_mesh, Surface_mesh_simplification), Boost (graph), GMP, MPFR, Eigen3,
  vendored rapidjson (`src/rapidjson/`), optional OpenMP. Skeleton copied from CuraEngine/"LunarTPP"
  (Application/Communication/CommandLine/Settings), so headers still say "Ultimaker" / "LunarTPP".
- `deps/` = PrusaSlicer-style ExternalProject bundle, pinned: CGAL 5.4 (`deps/CGAL/CGAL.cmake:6`), Boost 1.75
  (`deps/Boost/Boost.cmake:131`), GMP 6.2.1 (`deps/GMP/GMP.cmake:46`), MPFR 3.1.6 (`deps/MPFR/MPFR.cmake:29`),
  Eigen 3.4.0 (`deps/EIGEN3/EIGEN3.cmake:3`). CI instead uses Homebrew `cgal@5.5 boost@1.83 mpfr eigen`.
- No tests (no ctest, no test data). No README, no LICENSE file (code headers claim AGPLv3).

## Build and test (NOT verified on this Mac)

This repo was **not built** in the workspace integration (`../_snapmaker2-review/integration/README.md:35`); on
07/11/2026 the Mac has no `cmake` and Homebrew has only `gmp`. Treat the following as the untested recipe:

```sh
brew install cmake cgal boost mpfr eigen        # CI pins cgal@5.5 boost@1.83 (build-on-create-release.yml)
cd /Users/icaro/Documents/Projects/SnapMaker/LunarMP
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release   # plain path; sh/cmake-build.sh does this on x86_64
cmake --build build -j "$(sysctl -n hw.ncpu)"
./build/LunarMP version && ./build/LunarMP ptest # the only "test" CI runs
```

- `sh/cmake-build.sh` on arm64 hard-codes `-DCGAL_DIR=/usr/local/lib/cmake/CGAL`, `arm64-libs/` and
  `deps/build/install/usr/local`; it also runs `patch-cgal.sh`, which edits the CGAL headers it finds under
  `deps/build/install`, `/usr` or `/opt` (it can modify Homebrew's CGAL in place - read it first).
- `sh/cmake-deps.sh` builds the pinned `deps/` bundle (downloads GMP, `git clone`s rapidjson into `deps/`).
- Known failure: newer Boost removed `boost::prior/next` used by CGAL 5.4 `Plane_3_Triangle_3_intersection.h`;
  the 2025 shims (`patch-cgal.sh`, `process-cgal.sh`, `create-compat-layer.sh`, `src/cgal_fixes.h`,
  `src/lunarmp/utils/CGALPatches.h`) all work around that. Pin CGAL >= 5.5 to avoid it.
- Working smoke test today: run the shipped binary
  `../Luban/node_modules/@snapmaker/snapmaker-lunar/engine/MacOS/LunarMP` (x86_64, runs under Rosetta).
  See skill `lunarmp-run-cli`. Full build steps: skill `lunarmp-build-test`.

## Directory map

| Path | Purpose |
|---|---|
| `src/lunarmp/main.cpp` | `main()` -> `Application::getInstance().run()` |
| `src/lunarmp/Application.{h,cpp}` | command dispatch (`Application.cpp:126-145`), `version`, `ptest` |
| `src/lunarmp/communication/CommandLine.cpp` | arg parsing (`-v -p -m<N> -j -l -o --next`), settings JSON loader |
| `src/lunarmp/controller/TaskWorker.cpp` | task queue, `str2int` switch -> `ModelController` (`:27-40`) |
| `src/lunarmp/controller/ModelController.cpp` | reads `input_path`/`output_path`, calls the model classes |
| `src/lunarmp/model/ModelCheck.cpp` | outward orientation, open border, self-intersection -> `Status: 0/1` |
| `src/lunarmp/model/ModelRepair.cpp` | soup repair, orient, manifoldness, stitch borders, fill holes, self-intersection count |
| `src/lunarmp/model/ModelSimplification.cpp` | edge-collapse (edge length / count / ratio) |
| `src/lunarmp/model/ModelCompare.cpp` | symmetric Hausdorff distance (error bound 0.01, log only) |
| `src/lunarmp/model/ModelBase.h` | CGAL typedefs (`Epick`, `Surface_mesh`), orientation `Visitor`, dihedral `Constraint` |
| `src/lunarmp/settings/` | `Settings` key/value store with parent lookup; Cura/TPP enum parsers (mostly unused) |
| `src/lunarmp/utils/` | `logoutput` (stderr logging), `SMProgress` (unused), `StringUtils` (`camel2snake`, `str2int`), `Enums.h` (`SimplifyType`) |
| `src/lunarmp/data/DataGroup.h` | `DataGroup{settings, data[]}` holder |
| `src/rapidjson/` | vendored rapidjson |
| `deps/`, `cmake/`, `sh/` | dependency bundle, `FindGMP/FindMPFR`, build scripts |
| root `*.sh` | arm64 / Boost compat shims added 11/04/2025 |
| `.github/workflows/` | `build-on-create-release.yml` (mac x86_64, mac arm64, win64 MSYS2, ubuntu), `build-arm64-only.yml` |

## CLI contract (what Luban depends on)

`LunarMP <cmd> -v -p [-j settings.json] -l <input mesh> -o <output basename>` (`snapmaker-lunar/src/slicer.js:72-76`).

- Commands (case-insensitive): `modelrepair`, `modelsimplify`, `modelcheck`, `modelcompare`, `version`, `ptest`,
  `help` (no-op). `modelcompare` uses `-l` as base mesh and `-o` as the mesh to compare (`ModelController.cpp:37-43`).
- Input: any format `CGAL::IO::read_polygon_soup` accepts (off/obj/stl/ply/ts/vtp; `ModelRepair.h:77`).
- Output: `-o` is a **basename**; the tool writes `<o>.stl` (`ModelRepair.cpp:27`, `ModelCheck.cpp:21`,
  `ModelSimplification.cpp:11`), **binary** STL (CGAL default; `stream_precision(17)` has no effect; verified on the
  shipped binary 07/11/2026). The shipped npm 1.4.9 binary also writes `<o>.ply`; HEAD has
  that line commented out, so the shipped binary was built from an older/unknown revision.
- `-v` enables `log()` output (needed for status lines). `-p` enables `logProgress`, but nothing calls it: no
  `Progress:` lines are ever printed. `-m<N>` sets OpenMP threads only when built with OpenMP (`#ifdef _OPENMP`, `CommandLine.cpp:72`); the shipped
  macOS binary rejects it (`Unknown option: -m`, exit 1). `--next` queues another task (same command).
- stderr protocol: check prints `Status: 0|1;` and `Message: Closed Model!|Broken Model!` (`ModelCheck.cpp:9-18`);
  repair prints `Step:0..7;Message:<text>` (`ModelRepair.cpp:12-14`). Luban parses `Status`/`Message`
  (`slicer.js:140-147`) and counts `Step:` lines for progress (`Luban/src/server/slicer/slice.js:220-226`, `/8`).
- Exit codes: 0 ok; 1 unknown command / bad short option / missing `-j|-l|-o` value / JSON load failure / caught
  exception (`CommandLine.cpp:59,88,93,101,111,121,129,151`, `Application.cpp:110,144`); unknown `--long` options
  are only logged; 2 cannot read mesh
  (`ModelRepair.cpp:343`, `ModelCheck.cpp:66`, `ModelSimplification.cpp:73`) **or** missing setting
  (`Settings.cpp:60-61`). Luban's map `{1:'Failed to load model', 2:'Error for Settings'}` (`slicer.js:172-175`) is
  inaccurate. Segfault -> Luban reports code 139.
- Settings JSON (`CommandLine.cpp:159-235`): top level must contain `data` or `objects`; if neither, the source
  intends exit 1 but `logError("Error parsing JSON (offset %u): %s\n")` has no varargs (`CommandLine.cpp:187`) and
  the shipped binary segfaults (exit 139, only `[ERROR] ` printed; verified 07/11/2026). Nested objects
  are flattened, arrays skipped, every key also stored in snake_case; numbers become `to_string(double)`, strings are
  lowercased. Keys read: `simplify_type` (`edge_length_stop|edge_count_stop|edge_ratio_stop`; an
  unrecognised value falls back to edge_length, a missing key exits 2; `Settings.cpp:568-578`), `edge_length_threshold`, `edge_count_threshold`, `edge_ratio_threshold`
  (`ModelSimplification.cpp:79-105`), `machine_width/depth/height` in mm (repair hole sizing, only read when borders
  remain after stitching, `ModelRepair.cpp:156-167,315-318`). `modelcheck` needs no `-j`.

## Algorithms (where to look)

- Check (`ModelCheck::checkModel`): soup -> mesh; broken if not `is_outward_oriented`, any border halfedge, or
  `does_self_intersect`. It always writes `<o>.stl` (Luban uploads `<name>_check.stl` on success).
- Repair (`ModelRepair::repairModel`, `:278-335`): `repair_polygon_soup` + `orient_polygon_soup` (unless already a
  mesh) -> `keep_large_connected_components` (>= 2 faces) if non-manifold -> `stitch_borders` -> fill holes
  (`triangulate_hole` for small, `triangulate_refine_and_fair_hole` for large; threshold scaled by
  `machine/mesh` bbox factor) -> self-intersections are only **counted**, not fixed (`:272-276`).
- Simplify: `edge_ratio_stop` uses Garland-Heckbert when target < 1000 edges, else Lindstrom-Turk with
  bounded-normal-change filter (`ModelSimplification.cpp:94-104`); `edge_length_stop` collapses edges shorter
  than the threshold (Luban passes the layer height, mm).

## Conventions

- Namespace `lunarmp`; classes PascalCase, methods camelCase, members snake_case; `.clang-format` in root.
- Logging (`utils/logoutput.h`): `logError` (`[ERROR] `), `logWarning`, `logAlways`, `log` (needs `-v`),
  `logDebug` (needs `-vv`), all to **stderr**; stdout is unused except `ptest`.
- Errors: no exceptions, functions call `exit(1|2)` directly; `SUCCESS 0` / `FAIL -1` in `utils/Constant.h`.
- Comments mix English and Chinese; much dead code (`test()` methods with `E:/Datasets/...` paths, Cura enums in
  `settings/EnumSettings.h`, laser/CNC enums in `utils/Enums.h`). LunarMP does not slice anything.

## How to extend

- **New command** (e.g. `modelfoo`): add a branch in `Application::run` (`Application.cpp:126-145`) that creates
  `CommandLine`; add `case str2int("modelfoo")` in `TaskWorker::runNext` (`TaskWorker.cpp:27-40`); add a
  `ModelController::foo` reading `input_path`/`output_path`; new `src/lunarmp/model/ModelFoo.{h,cpp}`; list the
  `.cpp` in `PROJECT_SRCS` (`CMakeLists.txt:10-29`). For Luban to call it, the npm package `slicer.js` needs a new
  type mapping (that package's source is not in this workspace). Reference: unmerged branch
  `origin/feature-model-nesting` (adds `modelnesting`, Clipper, `ModelNesting.cpp`, 19/08/2022).
- **New setting**: read it with `data_group.settings.get<double|int|bool|std::string>("snake_key")`; add a
  `Settings::get<YourEnum>` specialisation in `Settings.cpp` for enums; remember values arrive lowercased.
- **Change simplify defaults**: edit `../luban-print-settings/resources/printing/simplify_model.def.json`
  (not this repo); Luban overwrites `simplify_type` and the threshold per request (`slice.js:118-125`).

## A250T notes

Machine-agnostic: no A150/A250/A350 or toolhead code (`grep -rIn "A250\|A350\|snapmaker" src` = 0 hits). The only
machine input is the work-volume size Luban passes for repair (`machine_width/depth/height` from the active
machine, e.g. A250 3D printing volume). It runs on the Mac as x86_64 under Rosetta; no arm64 build ships in Luban.

## Cross-repo interfaces (details: `../.claude/knowledge/DEPENDENCIES.md`)

- **Luban** (`sm-luban`): `src/server/slicer/slice.js:96` simplify, `:178` repair, `:254` check; support-mesh repair
  `src/server/services/socket/socket-slice.js:107-129`; socket events `simplify-model`, channels `repair-model`,
  `check-model` (`src/server/services/index.ts:34-37`). Dependency `@snapmaker/snapmaker-lunar ^1.4.9`
  (`Luban/package.json:82`, `Luban/src/package.json:22`).
- Support STLs that LunarMP repairs are generated by `LubanEngine modelsupport` from the separate external npm
  `snapmaker-luban-engine` ^0.9.1 (`Luban/src/server/slicer/slice.js:3,63`), not by LunarSlicer (its lineage is unverified).
- **npm `@snapmaker/snapmaker-lunar`** (external, not a workspace repo): ships prebuilt `engine/MacOS/LunarMP`
  next to `LunarSlicer` (`sm-lunarslicer`) and closed-source `LunarTPP`; `getpath.js` maps `MP` -> binary.
- **luban-print-settings** (`sm-luban-print-settings`): `resources/printing/simplify_model.def.json` defaults.
- No dependency on firmware, profiles, SACP or OrcaSlicer.

## What NOT to do

- Never push, never change remotes, never commit build output (`build/`, `deps/build/`, `arm64-libs/`).
- Do not run `patch-cgal.sh` / `process-cgal.sh` / `fix-*.sh` blindly: they rewrite CGAL headers system-wide and
  `fix-arch-mismatch.sh` builds deps in place.
- Do not replace the binary inside `Luban/node_modules/@snapmaker/snapmaker-lunar/engine/` without telling the
  owner (it is reinstalled by `npm install`; postinstall deletes other-platform engines).
- Do not assume `Progress:` output, JSON result files, or `.ply` output from HEAD source - see CLI contract.
- No submodules here (the CI `git submodule` steps are no-ops).
