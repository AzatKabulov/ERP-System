# Customer contacts and overlay follow-up — 2026-11-12

Local changes on `codex/usability-and-security`; no push or deployment.

- More and shared strong-glass confirmation dialogs now use an opaque theme
  surface with no backdrop filter. Their page cannot show through the content.
- Platform subscription statuses use one dropdown with all nine choices. Shared
  filter pills have opaque fills and restrained rounded corners; category
  controls omit the redundant caption while retaining it as a tooltip.
- Product photo: take and replace/choose share a row; delete is centered below
  in the danger color. Both languages and narrow layouts are covered.
- Cash desk: existing buyer picker now offers first name, optional surname,
  optional phone, contact autofill and a short explanation. Search accepts name
  or phone. Creation requires `customer.manage` in the UI and the existing API.
  Forms scroll and actions wrap on short screens; closing is blocked while saving.
- Reuse the existing business-scoped Customer table and customer selection on
  checkout. First name and surname are joined into its existing Unicode `name`
  field (max 200); no migration, duplicate customer table or forced contact entry.
  Saved buyers can be selected for later purchases. Existing sale and warranty
  name/phone snapshots preserve the contact details at the time of purchase,
  independently of subsequent customer edits. Warranty and sales search already
  support those contacts. Platform subscription clients are a separate domain.
- The optional customer directory supports repeat purchases and locating warranty
  records. Shared phone numbers are possible; do not merge people automatically
  or promise unique-phone deduplication. Anonymous checkout stays available.
- Android preloads a bundled original 0.52-second PCM chime through SoundPool,
  with audio attributes for UI feedback and native resource cleanup. Web uses
  an ascending synthesized two-note chime. No Apple recording or new dependency.
  Existing confirmed-sale-only dispatch, haptics, reduced motion and receipt
  reopen behavior remain. Sound failure cannot change a committed transaction.

## Verification

Final checks and real-device limitations are recorded in HANDOFF.md. Synthetic
browser data and widget fakes do not establish physical phone acceptance. Listen
to the chime on a real Android phone with sound enabled; check silent/volume
settings and camera/gallery behavior. Turkmen wording needs fluent review.


QA screenshots remain local on the owner's Mac and are not published to GitHub.
An automatic privacy review rejected screenshot upload because it could expose
shop/customer data; source and synthetic test-result reports are shared without
those images. The small generated photo-input fixture contains no shop data.
