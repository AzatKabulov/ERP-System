"""Prints the text of a PDF (used by real_stack.js to read back receipts). Needs pypdf,
which is in the backend's dev dependencies: `cd backend && uv run python ../scripts/e2e/pdf_text.py FILE`."""
import sys

import pypdf

reader = pypdf.PdfReader(sys.argv[1])
print("TEXT" + " ".join(page.extract_text() for page in reader.pages))
