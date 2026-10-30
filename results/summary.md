| bug | before fix | after fix | run time, s (before / after) | marker in failing output |
|---|---|---|---|---|
| cpp-fmt-error-code-oob | FAIL | PASS | 8.0 / 5.9 | `heap-buffer-overflow` |
| cpp-json-update-self-alias | FAIL | PASS | 16.7 / 16.3 | `heap-use-after-free` |
| go-flate-preset-dict | FAIL | PASS | 7.1 / 7.5 | `dictionary leaked into output` |
| go-http-body-close-deadlock | FAIL | PASS | 17.7 / 13.1 | `DEADLOCK` |
| py-asyncio-close-during-accept | FAIL | PASS | 6.4 / 1.4 | `Error on transport creation for incoming connection: AssertionError` |
| py-asyncio-sync-callback-leak | FAIL | PASS | 4.3 / 0.9 | `transport leaked` |
