# Barcode lookup reliability and automotive coverage — 2026-11-14

Local diagnostics fetched GitHub references without merging or overwriting the
existing working tree. Main remains at the secure-startup change; the barcode
provider implementation is unchanged there. A direct read-only request from this
Mac found CeraVe 3337875597210 in Open Beauty Facts. This does not verify the live
server, camera decoding, or the user's particular Old Spice barcode.

## Confirmed defects and local corrections

- Partial upstream failure plus an ordinary miss incorrectly cached a definitive
  miss for three days. A miss now requires all sources to answer; any unresolved
  failure is unavailable and is not negative-cached. Complete misses expire in
  five minutes; successful suggestions retain their 30-day cache.
- Cache namespace advances to avoid inheriting historical false negatives.
- Non-object upstream JSON no longer crashes the lookup.
- The client previously discarded `unavailable`, and receiving swallowed failures.
  Receiving now shows the lookup-unavailable state, a retry inside the form, and
  retries failed enrichment on reconnection. Entered values are retained and
  never overwritten by a later suggestion. Saving manually remains possible.
- The existing review dialog waits for search to finish before showing its form.
  Existing manual and scan entry points and field positions remain.
- UPCitemdb public trial is a fourth, server-only exact-code fallback, bounded
  to one call per 11 seconds and 100/day using the shared cache. Prices/offers
  are ignored; incomplete, mismatched or throttled replies never become cached
  misses. `ERP_BARCODE_LOOKUP_UPCITEMDB=false` disables this extra source.
- GTINHub is a fifth, verified no-key fallback, capped to its documented ten
  requests/day; mismatched identifiers are refused. Its actual control request
  returned the same CeraVe GTIN. Availability is not automotive coverage proof.
- Shared successful-cache keys normalize standard zero-padding (UPC/EAN/GTIN),
  preserving nonzero carton indicator digits. Missing generic names can fall
  back to the returned Russian, Turkmen or English product name.
- A ten-second remaining-request budget prevents blindly starting a chain of
  five full four-second requests. Per-source timeouts use the remaining budget;
  this is not a measured hardware latency guarantee. Exhaustion is unavailable.
- Existing shop-first lookup, arbitrary local barcode identifiers, tenant
  isolation, review before product creation and no price autofill remain.

## Proposed automotive coverage (not implemented or contracted)

First use the shop's existing catalog. Existing CSV import supports brand,
article, name and barcode mappings (new products only, up to 2,000 rows/1 MB;
its existing required price column needs consideration before a supplier-feed
workflow). Do not import supplier prices into stock costs without review.

Evaluate a licensed automotive source against representative supplier EANs,
part numbers, Chinese brands, lubricants and mixed packaging. TecAlliance
advertises EAN/OE/part-number lookup:
https://www.tecalliance-apac.com/solution/api . Verify commercial permission,
coverage and API access before implementation; do not assume that every Chinese
part is included. A general source such as UPCitemdb can complement it, but its
free documented allowance is only 100 requests/day, with additional burst
limits: https://www.upcitemdb.com/wp/docs/main/development/plan/ . No accounts,
subscriptions, paid requests, automotive provider connections or shared tenant
catalog were created. UPCitemdb and GTINHub public tiers are the added sources; their allowances
do not establish production-scale coverage. GTINHub documentation:
https://gtinhub.com/api . Datakick returned a CAPTCHA instead of JSON,
barcode.monster returned 404, and BarcodeFinder did not resolve from this Mac;
these were evaluated and not added. No access controls or TLS checks were bypassed.
A direct read-only trial request from this Mac returned an exact matching CeraVe
record. It does not verify automotive coverage, the deployed backend or hardware.

Measure exact-code hit rate, wrong-match rate and end-to-end lookup latency on
real supplier samples. Distinguish valid GTINs from proprietary article codes;
never invent compatibility, OEM references or product identity from a plausible
text search. Unknown items need one-time manual mapping, retained in that shop.
A dependable catalog cannot guarantee universal recognition from barcode digits.


## Validation

- Flutter analysis: no issues; all **634** unit/widget tests passed. Tests cover
  loading before review, manual prices, retry after an unavailable search and
  preservation of entered names. No full-layout redesign was introduced.
- **37 focused PostgreSQL barcode API tests passed** with fake upstream responses:
  partial failure, malformed JSON, cache recovery, extra-source hits, exact-code
  checks, daily/burst quota, upstream 429, genuine misses and tenant permissions.
- The full backend suite passed **968** PostgreSQL tests. Web release and Android
  debug APK builds passed; the APK is version 0.1.0+2 with the same local debug
  certificate as the previous testing APK.
- Ruff lint/format and diff whitespace checks pass. Real scanning hardware,
  the specific Old Spice barcode, broad Chinese-parts coverage and deployment
  remain unverified. Deployment status is recorded in HANDOFF.md.


## Guardrails for future changes

The owner requested a permanent development rule on 2026-11-14. AGENTS.md now
requires the barcode regressions when the affected lookup/receiving paths change
and links to the acceptance checklist in ARCHITECTURE.md. This is a maintenance
rule backed by the existing regression tests, not a guarantee that documentation
alone can prevent bugs. Client logic is shared by web and Android; deployment of
backend changes, rebuilding the website and distributing a newly signed APK are
separate steps. No follow-up build or deployment is implied by this document edit.


## Latest delivery evidence

See `docs/qa/scanner-2026-11-14/`: the receiving browser test uses controlled
metadata replies and real product/stock HTTP operations in disposable PostgreSQL.
It verifies loading, review, 50 received units, a genuine unknown barcode retained
for manual naming, and unavailable/retry preserving input. Three expected local
barcode 404 responses are counted explicitly; unrelated missing resources fail
the test. Phone/tablet sales, quota tests and restore evidence are separate.

The owner authorized website deployment and a new APK. Current build artifacts
and deployment results are listed in HANDOFF.md; real hardware and country-network
acceptance are not implied. Installers belong in GitHub Actions artifacts or
GitHub Releases, not a second source repository or Git history.


QA screenshots remain local on the owner's Mac and are not published to GitHub.
An automatic privacy review rejected screenshot upload because it could expose
shop/customer data; source and synthetic test-result reports are shared without
those images. The small generated photo-input fixture contains no shop data.
