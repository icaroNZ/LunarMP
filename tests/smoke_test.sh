#!/usr/bin/env bash
# Smoke test for the LunarMP CLI, exercising the commands Luban uses
# (modelcheck, modelrepair, modelsimplify) plus version/ptest and the
# settings-JSON error path. Meshes are generated on the fly (python3).
#
# Usage: tests/smoke_test.sh <path-to-LunarMP> [work-dir]
# Exit status 0 = all cases passed. Each case prints PASS/FAIL and, on failure,
# the captured stderr so CI logs are enough to diagnose it.
set -u

BIN="${1:?usage: $0 <path-to-LunarMP> [work-dir]}"
BIN="$(cd "$(dirname "$BIN")" && pwd)/$(basename "$BIN")"
WORK="${2:-$(mktemp -d "${TMPDIR:-/tmp}/lunarmp-smoke.XXXXXX")}"
mkdir -p "$WORK"
cd "$WORK" || exit 1
echo "LunarMP smoke test: bin=$BIN work=$WORK"

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() {
    echo "FAIL: $1"
    FAIL=$((FAIL + 1))
    if [ -f "$2" ]; then sed 's/^/    | /' "$2"; fi
}

# run <name> <args...>: runs the binary, stores stdout+stderr in <name>.log and exit code in RC
run() {
    local name="$1"; shift
    "$BIN" "$@" > "$name.log" 2>&1
    RC=$?
    echo "  [$name] exit=$RC: $BIN $*"
}

# --- test meshes -------------------------------------------------------------
# cube.stl: closed, outward-oriented 20 mm cube, every face split into an N x N grid
# open_cube.stl: same cube with the two triangles of one top grid cell removed
python3 - <<'PY'
N = 8
S = 20.0

def quads():
    r = range(N)
    d = S / N
    for i in r:
        for j in r:
            a, b = i * d, j * d
            c, e = a + d, b + d
            # (face name, quad corners counter-clockwise seen from outside)
            yield "z0", [(a, b, 0), (a, e, 0), (c, e, 0), (c, b, 0)]
            yield "z1", [(a, b, S), (c, b, S), (c, e, S), (a, e, S)]
            yield "y0", [(a, 0, b), (c, 0, b), (c, 0, e), (a, 0, e)]
            yield "y1", [(a, S, b), (a, S, e), (c, S, e), (c, S, b)]
            yield "x0", [(0, a, b), (0, a, e), (0, c, e), (0, c, b)]
            yield "x1", [(S, a, b), (S, c, b), (S, c, e), (S, a, e)]

def write(path, skip_first_top):
    skipped = False
    with open(path, "w") as f:
        f.write("solid cube\n")
        for name, q in quads():
            if skip_first_top and name == "z1" and not skipped:
                skipped = True
                continue
            for tri in ((q[0], q[1], q[2]), (q[0], q[2], q[3])):
                f.write("facet normal 0 0 0\n outer loop\n")
                for v in tri:
                    f.write("  vertex %.6f %.6f %.6f\n" % v)
                f.write(" endloop\nendfacet\n")
        f.write("endsolid cube\n")

write("cube.stl", False)
write("open_cube.stl", True)
PY
[ -s cube.stl ] && [ -s open_cube.stl ] || { echo "FAIL: could not generate test meshes"; exit 1; }

# A250T 3D-printing work volume in mm (what Luban passes for repair hole sizing)
cat > repair.def.json <<'J'
{"version":"4.x","config":{"machine_width":230,"machine_depth":250,"machine_height":235},"data":[]}
J
cat > simplify_ratio.def.json <<'J'
{"version":"","config":{"simplify_type":"edge_ratio_stop","edge_ratio_threshold":0.5,"edge_length_threshold":1.3,"edge_count_threshold":1000},"data":[]}
J
cat > simplify_length.def.json <<'J'
{"version":"","config":{"simplify_type":"edge_length_stop","edge_ratio_threshold":0.5,"edge_length_threshold":3.0,"edge_count_threshold":1000},"data":[]}
J
echo '{"version":"","config":{"machine_width":230}}' > no_data.def.json
echo '{"version": ' > bad_syntax.def.json

# --- cases -------------------------------------------------------------------
run version version
if [ "$RC" -eq 0 ] && grep -q "version" version.log; then pass "version"; else fail "version" version.log; fi

run ptest ptest
if [ "$RC" -eq 0 ] && [ "$(grep -cE '^[0-9]$' ptest.log)" -eq 10 ]; then pass "ptest prints 0..9"; else fail "ptest" ptest.log; fi

run check_closed modelcheck -v -p -l cube.stl -o cube_check
if [ "$RC" -eq 0 ] && grep -q "Status: 0;" check_closed.log && [ -s cube_check.stl ]; then
    pass "modelcheck closed cube -> Status 0, cube_check.stl written"
else fail "modelcheck closed cube" check_closed.log; fi

run check_open modelcheck -v -p -l open_cube.stl -o open_check
if [ "$RC" -eq 0 ] && grep -q "Status: 1;" check_open.log; then
    pass "modelcheck open cube -> Status 1"
else fail "modelcheck open cube" check_open.log; fi

run repair modelrepair -v -p -j repair.def.json -l open_cube.stl -o open_repaired
if [ "$RC" -eq 0 ] && grep -q "Step:7" repair.log && [ -s open_repaired.stl ]; then
    pass "modelrepair open cube -> Step:7, open_repaired.stl written"
else fail "modelrepair open cube" repair.log; fi

if [ -s open_repaired.stl ]; then
    run check_repaired modelcheck -v -p -l open_repaired.stl -o repaired_check
    if [ "$RC" -eq 0 ] && grep -q "Status: 0;" check_repaired.log; then
        pass "modelcheck repaired cube -> Status 0"
    else fail "modelcheck repaired cube" check_repaired.log; fi
else fail "modelcheck repaired cube (no repaired mesh)" /dev/null; fi

run simplify_ratio modelsimplify -v -p -j simplify_ratio.def.json -l cube.stl -o cube_ratio
if [ "$RC" -eq 0 ] && grep -q "Removed edges" simplify_ratio.log && [ -s cube_ratio.stl ]; then
    pass "modelsimplify edge_ratio_stop -> cube_ratio.stl written"
else fail "modelsimplify edge_ratio_stop" simplify_ratio.log; fi

run simplify_length modelsimplify -v -p -j simplify_length.def.json -l cube.stl -o cube_length
if [ "$RC" -eq 0 ] && grep -q "Removed edges" simplify_length.log && [ -s cube_length.stl ]; then
    pass "modelsimplify edge_length_stop -> cube_length.stl written"
else fail "modelsimplify edge_length_stop" simplify_length.log; fi

run compare modelcompare -v -l cube.stl -o cube_check.stl
if [ "$RC" -eq 0 ] && grep -q "Hausdorff" compare.log; then pass "modelcompare cube vs check output"; else fail "modelcompare" compare.log; fi

run missing_mesh modelcheck -v -l does_not_exist.stl -o nothing
if [ "$RC" -eq 2 ]; then pass "missing mesh -> exit 2"; else fail "missing mesh (want exit 2)" missing_mesh.log; fi

run no_data modelrepair -v -j no_data.def.json -l open_cube.stl -o nd
if [ "$RC" -eq 1 ] && grep -q "missing top-level 'data' or 'objects'" no_data.log; then
    pass "settings JSON without data/objects -> exit 1 with message (no crash)"
else fail "settings JSON without data/objects (want exit 1, got $RC)" no_data.log; fi

run bad_syntax modelrepair -v -j bad_syntax.def.json -l open_cube.stl -o bs
if [ "$RC" -eq 1 ] && grep -q "Error parsing JSON file" bad_syntax.log; then
    pass "settings JSON syntax error -> exit 1 with offset/message"
else fail "settings JSON syntax error (want exit 1, got $RC)" bad_syntax.log; fi

echo "LunarMP smoke test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
