# Profiling on the N300

Recipes and method for JMH profiling and JIT inspection on the box. Run everything
from `~/projects/hardwood-benchmarks`; `./run-<bench>.sh --help` documents each
script's own flags.

## Before a profiling run

- **Pin the clock** for numbers that must be comparable: `sudo profiling-setup pin`
  (1.50 GHz, the box's saved calibration), after the idle gate in `SKILL.md`.
  `perfasm` alone is robust to clock wobble and needs no pin.
- **Kernel frames:** `sudo sysctl -w kernel.perf_event_paranoid=1` (add
  `kernel.kptr_restrict=0` for kernel symbols). Resets at boot.
- **hsdis** must be in the active JDK's `lib/`, or `perfasm` shows raw addresses.
  `java -XX:+UnlockDiagnosticVMOptions -XX:+PrintAssembly -version 2>&1 | grep -i hsdis`
  prints nothing when it loads; `profiling-setup check` reports it too.
- **Check the pin before trusting an absolute number:** `scaling_max_freq` vs
  `cpuinfo_max_freq` (3.8 GHz). A turbo-off `profiling-setup apply` that was never
  restored leaves the box at 0.80 GHz and every number ~2× slow, with nothing in the
  JMH output announcing it.
- **Did it throttle?** `sudo profiling-setup guard -- <run command>`; `SUSPECT`
  means power-limited (PL1), which leaves the thermal counters untouched.

## JMH profilers

`--prof` is passed to JMH verbatim; narrow with `--include REGEX`.

```sh
./run-filter.sh --warmup 2 --meas 5 --prof perfnorm                        # IPC, instructions, cache/branch misses per op
./run-filter.sh --prof "perfasm:hotThreshold=0.01;intelSyntax=true"        # annotated asm; default 2 % threshold hides small hot loops
./run-filter.sh --prof perfc2c                                             # false sharing
./run-filter.sh --prof "async:libPath=/opt/async-profiler-4.4-linux-x64/lib/libasyncProfiler.so;event=cpu;threads=true;output=collapsed;dir=$HOME/scratch/af-<name>"
```

- async-profiler `event=wall;threads=true` shows off-CPU and parked threads
  (producer/consumer starvation, backpressure); `event=lock` shows contention. The
  version under `/opt` follows `async_profiler_version` in the `base` role.
- `--pin-only` runs single-core under `taskset -c 0`; `--no-pin` runs the
  all-cores pass only; `--gate` checks correctness without timing.
- The box is slow: start with `--warmup 2 --meas 5`, scale up once the run works.
- Two JMH runs at once collide on `/tmp/jmh.lock`: add `-Djmh.ignoreLock=true` to each.
- System-wide `perf stat -a`, including the uncore memory-controller counters
  (`uncore_imc_free_running/data_read/`, `…/data_write/`), needs `sudo perf`.

## JIT inspection outside JMH

```sh
-XX:+UnlockDiagnosticVMOptions -XX:+PrintAssembly -XX:PrintAssemblyOptions=intel \
  -XX:CompileCommand=print,dev.hardwood.SomeClass::hotMethod                 # codegen for one method
-XX:+UnlockDiagnosticVMOptions -XX:+PrintInlining                            # inlining decisions
-XX:+UnlockDiagnosticVMOptions -XX:+LogCompilation -XX:+PrintAssembly        # JITWatch input (hotspot_pid*.log)
```

For run-to-run stability: `-Xms` equal to `-Xmx`, `-XX:+AlwaysPreTouch`, more forks.

## Method

Classify, then locate, then read instructions:

1. **`perfnorm`**: instructions/op, IPC and misses/op put the benchmark in compute-,
   memory- or branch-bound territory.
2. **async-profiler**: where the time goes, including native frames. Decide on-CPU
   vs off-CPU first: a `cpu`-mode profiler cannot see a parked thread, so anything
   blocked needs `event=wall`.
3. **`perfasm`**: the exact hot instructions: vectorized or not, bounds checks,
   spills.

Prove a suspected bottleneck by changing the supply of the resource (clock, cores,
buffer size), not only by reading the profile.

### Memory-bandwidth-bound?

- **Frequency test.** Run at two pinned clocks. Throughput that scales with the
  clock is compute-bound; flat throughput is memory-bound.
- **Scaling signature.** Sweep threads while reading aggregate memory traffic from
  the uncore IMC counters. Throughput and traffic that level off at the same thread
  count indicate a bandwidth limit.

The N300 has a single memory channel, so almost any parallel workload looks
bandwidth-bound here. Don't draw scaling conclusions from it; use a multi-channel
server.
