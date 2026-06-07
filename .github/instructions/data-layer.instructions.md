---
applyTo: "**/data/**,**/api/**,**/lib/data/**"
---

When working on files in the data layer, always read `_working-memory/dataContracts.md` first.
All data-consuming code must conform to the interfaces defined there.
If you need to change a data shape, update `dataContracts.md` before modifying code.
