# Manual Windows-effect tests

These tests may open Windows applications, write Desktop shortcuts, request elevation, change mounts, adjust time, or drop caches. Run only in an explicitly disposable WSL environment:

```bash
WSLU_RUN_MANUAL_TESTS=1 make test-manual
```

They are intentionally excluded from routine CI.
