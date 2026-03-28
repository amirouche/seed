# Seed2 Checks

End-to-end tests for the Seed2 compiler. Each test is a `.seed2.scm`
program compiled through `seedink2.scm` and compared against expected
output.

## File conventions

| Extension | Contents |
|---|---|
| `*.seed2.scm` | Seed2 source program |
| `*.compiled.scm` | Compiled Chez Scheme output (`seedink2.scm --dump`) |
| `*.expected.txt` | Expected stdout when the program is run |

## Tests

| Test | Description |
|---|---|
| `provide-simple` | Single-binding operative with eval |
| `frob` | Operative that extends caller env and returns a value |
| `runtime-dispatch` | Single-define operative at statement level |
| `multi-define` | Operative that defines multiple bindings in caller env |
| `eval-news` | `seed-eval` begin threads env through operative calls |
| `provide-address` | `provide` macro with encapsulation-based record type |
| `provide-with-eval` | `provide` macro via runtime eval fallback path |
| `define-record-type` | `define-record-type` as a vau macro |

## Running

```bash
bash run-checks.sh
```

## Regenerating compiled output

```bash
# From the src/ directory:
for f in src/seed2/checks/*.seed2.scm; do
  name="$(basename "$f" .seed2.scm)"
  scheme --script seedink2.scm --dump "$f" \
    > "src/seed2/checks/${name}.compiled.scm"
done
```
