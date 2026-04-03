# Task Index

**Total tasks:** 9
**Milestones:** 4

---

## Milestone Summary

| Milestone | Name | Tasks | Status |
|-----------|------|-------|--------|
| M1 | Plugin Scaffold & Pi Detection | TASK-001, TASK-002 | Complete |
| M2 | Inline Invocation | TASK-003, TASK-004 | In Progress |
| M3 | Minion File Support | TASK-005, TASK-006, TASK-007 | Not Started |
| M4 | Polish & Distribution | TASK-008, TASK-009 | Not Started |

---

## Task Status

| # | Task | Milestone | Estimate | Status | Blocked by |
|---|------|-----------|----------|--------|------------|
| TASK-001 | Plugin directory structure and manifest | M1 | S | Complete | None |
| TASK-002 | Pi availability check with install offer | M1 | S | Complete | TASK-001 |
| TASK-003 | minion-run.sh with inline mode | M2 | M | Complete | TASK-001 |
| TASK-004 | Skill inline invocation flow | M2 | M | Complete | TASK-002, TASK-003 |
| TASK-005 | Minion file resolution | M3 | S | In Progress | TASK-004 |
| TASK-006 | Frontmatter parsing and Pi flag mapping | M3 | M | Not Started | TASK-003 |
| TASK-007 | Prompt composition and minion-file mode end-to-end | M3 | M | Not Started | TASK-005, TASK-006 |
| TASK-008 | Example minion files and error UX | M4 | M | Not Started | TASK-007 |
| TASK-009 | README and marketplace distribution | M4 | S | Not Started | TASK-008 |

---

## Dependency Graph

```
M1: Plugin Scaffold & Pi Detection
├── TASK-001: Plugin scaffold ──────────────────────┐
└── TASK-002: Pi detection (depends: 001) ──────────┤
                                                    │
M2: Inline Invocation                               │
├── TASK-003: minion-run.sh inline (depends: 001) ──┤
└── TASK-004: Skill inline flow (depends: 002, 003) ┤
                                                    │
M3: Minion File Support                             │
├── TASK-005: File resolution (depends: 004) ───────┤
├── TASK-006: Frontmatter parsing (depends: 003) ───┤
└── TASK-007: Prompt composition (depends: 005, 006)┤
                                                    │
M4: Polish & Distribution                           │
├── TASK-008: Examples + error UX (depends: 007) ───┤
└── TASK-009: README + marketplace (depends: 008) ──┘
```

**Critical path:** TASK-001 → TASK-003 → TASK-006 → TASK-007 → TASK-008 → TASK-009

**Parallel opportunities:**
- TASK-002 and TASK-003 can run in parallel (both depend only on TASK-001)
- TASK-005 and TASK-006 can run in parallel (different dependency chains)
