# AGENTS

We value contributions from our robot friends — we just ask that they carefully and thoughtfully adhere to the best practices listed below.

## Code Quality

We prefer code that embodies clear, concise mental models. We prefer to think deeply about the problem we are solving and find the solution that best fits.

- Example 1: a file with many boolean variables might be implemented more cleanly as a state machine (using a bloc, cubit, or other package/pattern).
- Example 2: a file with a series of complex async operations may be better described as a series of stream transforms, an observable primitive, or even a composite.

If you recognize a key insight that would clean something up but do not have what you need on hand to implement it, please just say so. Adding a package reference is easy.

Our criteria for good code also enables us to achieve 100% test coverage.

Good code has...

- as few branches as possible
- injectable dependencies
- well-named identifiers
- no sibling dependencies in the same architectural layer

To avoid sibling dependencies, state must either be lifted up to a common ancestor and passed down, or pushed down and subscribed to.

See README.md for full development setup and contributing guidelines.

## Developer Scripts

All scripts are in `./tool/` and accept an optional package name (e.g., `cow_brain`, `blocterm`).

```bash
dart tool/test.dart [pkg]         # run Dart tests (one or all)
dart tool/analyze.dart [pkg]      # dart analyze --fatal-infos
dart tool/format.dart [pkg]       # dart format (add --check for CI mode)
dart tool/coverage.dart [pkg]     # tests + lcov coverage report
dart tool/codegen.dart [pkg]      # build_runner for JSON serialization
dart tool/build_mlx.dart          # build CowMLX Swift library
dart tool/checks.dart             # full CI check (format → analyze → build → test → coverage)
```
