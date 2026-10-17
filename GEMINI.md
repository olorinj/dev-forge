# Project Agent Configuration: dev-forge

This file defines the primary project persona, bound rules, and operating standards for agents working inside the `dev-forge` workspace.

## 1. Active Role & Rules
- **Dedicated Project Persona**: [.agents/roles/projects/dev-forge.md](.agents/roles/projects/dev-forge.md)
- **Project Business Rules**: [.agents/rules/projects/dev-forge.md](.agents/rules/projects/dev-forge.md)
- **Core Virtualization Standards**: [.agents/rules/core/virtualization.md](.agents/rules/core/virtualization.md)
- **Central Security Policy**: [.agents/rules/core/security.md](.agents/rules/core/security.md)

## 2. Core Operational Directives for dev-forge
- **100% Offline Builds**: All VM compilations MUST execute in local offline mode without pulling remote package updates unless explicitly requested via `--provision` or `--update`.
- **Target Isolation**: Guest target caches MUST be isolated (`/tmp/cargo-target`, `C:\target`), and final binaries MUST be deposited strictly into `/workspace/dist/`.
- **Dual-Shell Parity**: Maintain feature parity between `bin/dev-forge` (Bash) and `bin/dev-forge.ps1` (PowerShell with UTF-8 BOM and LF).
- **Toolchain Verification**: Validate multi-language toolchain health using the `HashForge` test suite (`examples/hashforge/test.sh` and `test.ps1`).

## 3. Cross-Project Learning Reference
When looking for established solutions or comparing implementations across sibling projects:
- Cryptographic Vaults & GUI Patterns: [.agents/rules/projects/lexishield.md](.agents/rules/projects/lexishield.md)
- Hypervisor CLI Management: [.agents/rules/projects/orquestador.md](.agents/rules/projects/orquestador.md)
- Document & XML Run Processing: [.agents/rules/projects/corrector-docx.md](.agents/rules/projects/corrector-docx.md)
- Domain Isolation & Spanish Docstrings: [.agents/rules/projects/academia.md](.agents/rules/projects/academia.md)
