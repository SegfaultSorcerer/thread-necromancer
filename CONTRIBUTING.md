# Contributing to thread-necromancer

Thanks for your interest in contributing!

## How to Contribute

1. **Bug reports** — Open an issue with the thread dump (or a sanitized version) that caused unexpected results
2. **New patterns** — Know a thread dump anti-pattern we don't detect? Open a PR adding it to `skills/thread-dump/references/common-patterns.md`
3. **Spring thread mappings** — New Spring component with a distinct thread naming pattern? Add it to `spring-thread-patterns.md`
4. **Script improvements** — Better parsing, new platform support, performance improvements

## Development Setup

```bash
git clone https://github.com/SegfaultSorcerer/thread-necromancer.git
cd thread-necromancer
./scripts/check-prerequisites.sh
```

## Testing Changes

### Scripts
```bash
# Use the benchmark fixture app
cd benchmark/fixture-app
mvn spring-boot:run

# In another terminal
curl -X POST http://localhost:8080/api/issues/trigger-all
sleep 3
../../scripts/dump-collector.sh list
../../scripts/dump-collector.sh capture <PID>
../../scripts/dump-parser.sh .thread-necromancer/dumps/<dump-file>
```

### Skills
Test skills by using them in Claude Code against the fixture app's thread dumps.

## Code Style

- Shell scripts: POSIX-compatible where possible, bash extensions only when necessary
- Use `set -euo pipefail` in all bash scripts
- macOS `awk` compatibility (no gawk-specific features like `match()` with array capture)
- PowerShell scripts should mirror bash script functionality

## License

By contributing, you agree that your contributions will be dual-licensed under MIT and Apache 2.0.
