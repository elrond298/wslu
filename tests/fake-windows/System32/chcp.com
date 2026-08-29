#!/bin/bash
printf 'chcp.com %s\n' "$*" >> "${WSLU_TEST_LOG:?}"
printf 'unexpected chcp.com call: %s\n' "$*" >&2
exit 97
