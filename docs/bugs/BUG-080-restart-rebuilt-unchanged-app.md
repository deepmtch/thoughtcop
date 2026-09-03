# BUG-080: Restart rebuilt the unchanged app

## Symptom

`./restart.sh` printed only the code-signing message and then appeared frozen
before the replacement app became visible.

## Evidence

The script unconditionally called `build.sh`. That invokes one optimized
`swiftc` command over every source and test file, copies the binary, and signs
the bundle. A measured rebuild-and-restart took 27.44 seconds.

## Fix

`build.sh` now writes a completion stamp after successful signing. `restart.sh`
checks the stamp against the build script, plist, sources, and tests; unchanged
restarts skip compilation. It also prints separate building, launching, and
verification phases. Replacement verification waits for both a single new
process and a responding `/ui` endpoint, avoiding a false-ready race. A measured
unchanged restart takes well under one second on this machine.
