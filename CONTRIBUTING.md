# Contributing to UpackX

Thank you for your interest in contributing to **UpackX**! We welcome bug reports, documentation enhancements, and feature suggestions.

---

## Development Principles

1. **Native & Lightweight First:**
   - Pure Swift and AppKit.
   - Zero background daemons.
   - Minimal memory footprint and fast startup.
2. **Target Platform Focus:**
   - Optimized and verified for **Intel x86_64** running macOS 14.0 Sonoma or newer.
   - Do not claim support for untested configurations.
3. **Safety & Non-Destructive Operation:**
   - Never silently overwrite existing files.
   - Never replace whole folders destructively (preserve existing folders and merge safely).
   - Strict defense against path traversal / Zip-Slip vulnerabilities.

---

## Local Development Workflow

### Prerequisites
- macOS 14.0 or newer (Intel x86_64 or Rosetta 2 environment).
- Swift 5.9+ / Xcode Command Line Tools.
- `libarchive` and `sevenzip` installed locally via Homebrew:
  ```bash
  brew install libarchive sevenzip
  ```

### Build & Test Commands
```bash
# 1. Compile the application
make build

# 2. Run the automated QA test suite (24 tests)
make test

# 3. Clean reinstall and test Finder Services locally
make reinstall

# 4. Build distribution packages (.dmg, .pkg, .zip)
make package

# 5. Run pre-flight release verification
make release-check
```

---

## Submitting Pull Requests

1. Fork the repository and create a descriptive branch:
   ```bash
   git checkout -b fix/your-bug-fix
   ```
2. Ensure all tests pass:
   ```bash
   make test
   make release-check
   ```
3. Commit with clear, descriptive messages following conventional commit guidelines (e.g. `fix: ...`, `feat: ...`, `docs: ...`).
4. Submit a Pull Request targeting the `master` branch.
