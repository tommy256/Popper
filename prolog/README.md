# Popper (Prolog rewrite)

This document explains the architecture, setup, usage, and extension points of the Prolog-based reimplementation of Popper that lives in the `prolog/` directory. It is intended as the primary reference for developers and researchers who want to understand, run, or extend the system.

## 1. Overview

The Prolog rewrite mirrors the original Python Popper pipeline:

1. **Solver** (`solver.pl`) launches Clingo with the bias/mode files for a given example and retrieves candidate programs (as ASP models).
2. **Generator** (`generate.pl`) converts each ASP model into Popper-style clause/program data structures.
3. **Orderer** (`order.pl`) imposes a literal ordering so that clauses become executable Prolog rules.
4. **Tester** (`tester.pl`) asserts the ordered program into SWI-Prolog, evaluates it against the background knowledge and examples, and reports the outcome (`all/some/none`).
5. **Controller** (`popper.pl`) orchestrates the above, iterating over clause-size bounds, enumerating models, and returning discovered programs.

All modules are pure Prolog (SWI-Prolog 9.x recommended) and communicate via structured terms. External dependencies are limited to Clingo (>= 5.8.0) and the existing Popper ASP biases under `popper/alan/` plus example folders in `examples/`.

## 2. Repository Layout (Prolog rewrite)

```
prolog/
  README.md          ← this document
  core.pl            ← shared data structures (variables, literals, clauses)
  solver.pl          ← Clingo integration and JSON parsing
  generate.pl        ← model-to-program conversion
  order.pl           ← selection closure & ordering logic
  tester.pl          ← program assertion, evaluation, and cleanup
  popper.pl          ← main control loop, CLI utilities
  tests.pl           ← plunit regression checks
```

In addition, the top-level `examples/` directory holds example tasks (e.g., `addlast/`, `find-dupl/`), each containing `bk.pl`, `modes.pl`, and `exs.pl`.

## 3. Dependencies

- **SWI-Prolog** (tested with 9.2.x; earlier 8.x should work if it includes `library(http/json)` and `library(pcre)`).
- **Clingo** 5.8.0+. Ensure the `clingo` executable is on `$PATH`.
- Python bindings are *not* required; all logic runs inside SWI-Prolog plus the external Clingo binary.

Optional: When running tests or large enumerations, increase the Prolog stack limit if needed (e.g., `swipl --stack_limit=2g`).

## 4. Building Blocks

### 4.1. `core.pl`
Defines the core data structures:
- `make_literal/5`: constructs `literal/4` terms with predicate, arguments, mode, and polarity.
- `make_unordered_clause/4`, `make_ordered_clause/4`, `make_ordered_program/3`: constructors for clauses and programs.
- Helper predicates for extracting inputs/outputs, converting to source code strings, etc.

### 4.2. `solver.pl`
Responsibilities:
- Launch Clingo with `--outf=2` (JSON), `--models=0` (all models), and optional `--time-limit=N`.
- Feed the current literal bound via stdin (`size_in_literals(N).`).
- Parse the JSON response into lists of atom strings (e.g., `"head_literal(0,f,2,(0,1))"`).
- Expose two public API families:
  - `clingo_model(KbDir, LiteralCount, ModelAtoms)` and `clingo_model/4` (with time limit).
  - `clingo_models(KbDir, LiteralCount, Models)` and `clingo_models/4` (time-limited), returning *all* witness `Value` lists.
- Guard against Clingo exit codes: 10 (SAT), 20 (UNSAT), 30 (SAT with `--models=0`), and 11 (timeout/interruption).

### 4.3. `generate.pl`
- Consumes the atom strings from Clingo and categorises them (`head_literal/4`, `body_literal/4`, `direction/3`, `before/2`, `min_clause/2`).
- Builds head/body literals with proper variable names and mode annotations using mappings from `direction/3` atoms.
- Produces an `unordered_program/2` term comprising a list of `unordered_clause/4` and a `before/2` partial order map.

### 4.4. `order.pl`
- Implements the Rolf-style selection closure to order body literals such that inputs are grounded before use.
- `unordered_to_ordered/2` converts an unordered program into `ordered_program/2` by iteratively picking groundable literals, preferring non-recursive ones before recursive ones.
- Throws `error(cannot_ground(Body, Grounded))` if no suitable literal is available; the controller catches this and skips the candidate.

### 4.5. `tester.pl`
- Loads the background knowledge (`bk.pl`), test harness (`popper/test.pl`), and examples (`exs.pl`), asserting them into the `user` module.
- Options:
  - `timeout(Seconds)` (default `60`): Prolog evaluation timeout per query, passed to `popper/test.pl`.
  - `minimal(Boolean)` (default `true`): choose between `do_test_minimal/4` or `do_test/4`.
- Provides `tester_initialise/2`, `tester_evaluate/2`, and formatting helpers.
- Manages assertion and retraction of candidate clauses via `setup_call_cleanup/3`.

### 4.6. `popper.pl`
- External API:
  - `popper/2`, `popper/3`, `popper/4`: search for programs satisfying desired outcomes. On success, returns an `ordered_program/2` term.
  - `run/1`, `run/2`: convenience predicates to stream programs and outcomes to stdout.
  - `program_clauses/2`: returns a list of clause strings (`Predicate(Args) :- ... .`).
- Options recognized:
  - `max_literals(N)` (default `3`): upper bound on clause body size explored.
  - `max_models(N)` (default `0` = unlimited): limit how many Clingo models to evaluate per literal count.
  - `clingo_timeout(N)` (default `0` = none): pass `--time-limit=N` to Clingo.
  - `timeout(N)`, `minimal(Boolean)`: forwarded to `tester.pl`.
  - `skip_duplicates(Boolean)` (default `true`): avoid evaluating identical programs by memoizing clause signatures.
- Tracks visited programs using `program_signature/2` (sorted clause strings) and a dynamic `seen_program/1` predicate.

### 4.7. `tests.pl`
- Contains plunit tests. Currently exercises `examples/addlast`:
  - Verifies that a complete and consistent program (`outcome(all, none)`) is found and includes `last/2` as expected.
  - Ensures enumeration without duplicates when `skip_duplicates(true)` is enabled.
- Provides a `run_tests/0` helper that delegates to `plunit:run_tests/1`.

## 5. Usage Guide

### 5.1. Running Popper from SWI-Prolog REPL

```
$ cd Popper
$ swipl
?- [prolog/popper].
?- popper:run('examples/addlast', [max_literals(3), max_models(50)]).
```

This prints each candidate program and its outcome (e.g., `Outcome: all/none`). Adjust options as needed:

- Limit Clingo runtime: `clingo_timeout(60)`.
- Use full testing instead of minimal: `minimal(false)`.
- Disable duplicate filtering: `skip_duplicates(false)`.

### 5.2. Querying for the First Successful Program

```
?- [prolog/popper].
?- popper:popper('examples/addlast', [max_literals(3)], Program).
Program = ordered_program([...], ...).
?- popper:program_clauses(Program, Clauses).
Clauses = ['f(A,B) :- cons(C,A,B), last(A,C).']. 
```

### 5.3. Handling Timeouts

- **Prolog evaluation timeout**: set via `timeout(N)` option when initialising the tester (default 60 seconds).
- **Clingo timeout**: use `clingo_timeout(N)` (integer seconds). If Clingo exceeds the limit, `error(time_limit_exceeded(N), context(clingo, ...))` is thrown.

Example:
```
?- catch(popper:run('examples/addlast', [clingo_timeout(10)]), E, writeln(E)).
```

### 5.4. Running Regression Tests

```
$ swipl -q -s prolog/tests.pl -t run_tests
```

This command runs all plunit tests defined in `tests.pl`. Ensure `clingo` is on the PATH; the test defaults are chosen to keep runtime reasonable (~10 seconds on a modern laptop).

## 6. Extending the System

### 6.1. Supporting New Examples

1. Create a new folder under `examples/EXAMPLE/` with `bk.pl`, `modes.pl`, and `exs.pl`.
2. Run Popper:
   ```
   ?- popper:run('examples/EXAMPLE', [max_literals(4), max_models(200)]).
   ```
3. Optionally add plunit test cases in `tests.pl` to cover the new example.

### 6.2. Custom Constraints

- To prune search space, modify or extend the ASP biases under `popper/alan/`. These are consumed unchanged by the Prolog rewrite.
- For Prolog-side constraints (e.g., rejecting clauses with certain predicates), add checks in `generate.pl`, `order.pl`, or `popper.pl` before programs reach the tester.

### 6.3. Alternative Backends

`solver.pl` is the only module tied to Clingo. Replacing it with another ASP system (or a pure Prolog search) would require implementing the same exported API.

### 6.4. Integrating Learned Constraints

The current rewrite does not yet mimic Popper's iterative constraint learning. To emulate it:
- After `tester:tester_evaluate/2`, collect counterexamples or unsatisfied conditions.
- Generate and assert new ASP constraints (typically `#show` statements) before the next call to `solver:clingo_models/4`.
- The infrastructure readily allows it; you’d extend `popper.pl` to maintain a constraint state and re-ground Clingo as needed.

## 7. Troubleshooting

| Symptom | Likely Cause | Resolution |
|---------|--------------|------------|
| `permission_error(execute, clingo, ...)` | Clingo not installed or not in PATH | Install Clingo and ensure the binary is accessible |
| `Syntax error: End of file in quoted codes` when loading modules | Trailing stray characters (often from copy/paste) | Check file endings, ensure ASCII only |
| `time_limit_exceeded(N)` error | Clingo reached the specified time limit | Increase `clingo_timeout` or simplify modes/constraints |
| Prolog stack overflow during enumeration | Too many models without bounding | Use `max_models(N)`, tighten modes, or add constraints |
| No programs with `outcome(all, none)` | Task is too hard or requires bigger search | Increase `max_literals`, `max_models`, or adjust background knowledge |

## 8. Command Reference

| Command | Purpose |
|---------|---------|
| `swipl -q -s prolog/tests.pl -t run_tests` | Run regression suite |
| `swipl -q -g "[prolog/popper], popper:run('examples/addlast', [max_literals(3)])" -t halt` | Batch run Popper on `addlast` |
| `swipl -q -g "[prolog/popper], popper:popper('examples/addlast', [max_literals(3)], Program, Outcome)" -t halt` | Query first program/outcome |
| `swipl -q -g "[prolog/popper], popper:run('examples/addlast', [max_literals(4), clingo_timeout(60), skip_duplicates(false)])" -t halt` | Exhaustive listing with relaxed filters |

## 9. Future Improvements

- Implement Popper’s full constraint learning cycle (adding constraints back into Clingo).
- Persist discovered programs and learned constraints between runs.
- Improve performance with caching or incremental grounding.
- Add more regression tests (e.g., `find-dupl`, negative-only tasks).
- Provide a higher-level CLI wrapper (e.g., shell script) for running multiple examples sequentially.

## 10. Contact and Contribution

1. Ensure your changes pass `swipl -q -s prolog/tests.pl -t run_tests`.
2. Document new options or behaviours in this `README.md`.
3. Submit pull requests or patches following the repository’s contribution guidelines.

---

Happy inductive logic programming!
