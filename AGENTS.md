# Code Quality

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

See CONTRIBUTING.md for development details.

# Developer Scripts

All scripts are in `./tool/` and accept an optional package name (e.g., `cow_brain`, `blocterm`).

```bash
tool/test.sh [pkg]         # run Dart tests (one or all)
tool/analyze.sh [pkg]      # dart analyze --fatal-infos
tool/format.sh [pkg]       # dart format (add --check for CI mode)
tool/coverage.sh [pkg]     # tests + lcov coverage report
tool/codegen.sh [pkg]      # build_runner for JSON serialization
tool/build_mlx.sh          # build CowMLX Swift library
tool/checks.sh             # full CI check (format → analyze → build → test → coverage)
```
