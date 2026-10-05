# Native PDF controls

Authored **synthetic**, CC0-1.0 controls, not real business benefit truth.
ReportLab/PIL are existing offline fixture-authoring tools only, not product/CI
dependencies. `generate-fixtures.py` independently creates the committed PDF
bytes; CI never regenerates them. Korean CID text uses Adobe-Korea1 standard
font references, not a redistributed proprietary font file. No real Suwon PDF
is committed. `test-support.ps1` also authors a minimal ASCII PDF with real xref.

`fault-helper.ps1` is test-only process fault injection. Production dispatch
cannot select it via a public runtime parameter.
