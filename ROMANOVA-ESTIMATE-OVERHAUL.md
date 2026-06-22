# ROMANOVA.CARDS — ESTIMATE ENGINE OVERHAUL
Delta spec v2 · 2026-06-21 · Scope: the estimate engine and its display only

---

## 0. ONE PRINCIPLE

**Exact card information or bust.** The engine never guesses a card's printing and never trusts a price from an uploaded file. A card is either identified precisely enough to price, or it is routed to a section that asks the seller for the exact missing details. There is no third behavior — no cheapest-printing fallback, no price range, no "best guess."

---

## 1. WHAT THIS SUPERSEDES

This overrides the earlier "hybrid pricing" decision and §3.1/§3.3 of the original delta spec:
- **Old:** on-page estimate sourced from Scryfall (TCGplayer market price); ManaPool used only offline.
- **New:** on-page estimate sourced from **ManaPool market price**, fetched live. Scryfall/TCGplayer prices are no longer shown or used for the seller-facing number.
- **Old:** display showed market total → 60% figure.
- **New:** display shows **the estimate only** (see §6). Market price is never shown to the seller.

Everything else in the original spec (no accounts, INSERT-only RLS, persistence, mobile, contact channels, humor/policy slots) stands unchanged.

---

## 2. REQUIRED FIELDS — THE FIXED SET

Any Magic printing is uniquely priceable from this fixed set of fields. The engine requires all identity fields below before it will produce an estimate for a card:

| Field | Required | Notes |
|---|---|---|
| Card name | Yes | Human anchor + cross-check |
| Set code | Yes | e.g. `MH3`, `2X2`, `NEO`. Pins the printing with collector number. |
| Collector number | Yes | e.g. `117`. Set code + collector number = one exact card object (covers borderless/extended/showcase, which have distinct numbers). |
| Finish | Yes | One of: `nonfoil`, `foil`, `etched`. Same card+number can exist in multiple finishes at different prices. |
| Language | Defaults to English | If absent, assume `EN`. Seller may change it. |
| Quantity | Yes | For line and grand total. Not an identity field. |

**Condition is deliberately NOT collected.** The estimate always assumes Near Mint. The real amount is set after Roman physically inspects the cards. Every estimate carries the disclaimer in §6.

A card is **complete** when name + set code + collector number + finish are all present (language defaults to EN). Anything missing any of these is **incomplete** and goes to §5.

---

## 3. INPUT PARSING

Two input paths, same destination logic:

**A) Pasted text lines.** Parse each line for name, and optional set/collector/finish if the seller typed them (e.g. `2 Lightning Bolt (2X2) 117 foil`). A bare `Lightning Bolt` parses to name-only → **incomplete** → §5. Do not auto-select a printing. Ever.

**B) CSV upload.** Detect columns (ManaBox, Moxfield, TCGplayer, Deckbox, generic). Extract name, set, collector number, finish, language, quantity per row.
- **Ignore any price column in the file completely.** Prices come only from the ManaPool lookup (§4). A file's price is never used or shown.
- A row missing any identity field → **incomplete** → §5, same as a pasted line.
- ManaBox rows include a Scryfall ID; when present, use it as the exact identifier (it encodes set+collector+finish) — those rows are **complete**.

---

## 4. PRICING — MANAPOOL

1. Read the live ManaPool API docs at `https://manapool.com/api/docs/v1` and `https://manapool.com/api/docs`. Determine the pricing endpoint and its authentication requirement. **Audit and report this before implementing** — it decides the architecture.
2. **If the pricing endpoint is public (no auth):** fetch client-side directly from the static site.
3. **If it requires the seller API key:** the key must NOT go in client-side code (static GitHub Pages source is world-readable). Route through a **Supabase Edge Function** that holds the key server-side and returns only the market price to the client. Roman already has the Supabase project; use it.
4. Map each complete card to its ManaPool price. Identifier mapping path: Scryfall ID or set+collector+finish → ManaPool product. (Third-party tools map via MTGJSON UUID; use whatever the ManaPool API accepts.)
5. Pull the **Near Mint** market price for the exact finish/language.
6. **Estimate per card = 60% × ManaPool NM market price × quantity.** This 60% figure is the only number computed for display.
7. Respect ManaPool rate limits; batch or throttle large lists per the API docs. Report the limits you find.

If a complete card returns no ManaPool price (not in their catalog), list it under "couldn't price this one — we'll review it manually," excluded from the total. Do not substitute a TCGplayer price.

---

## 5. THE "MORE INFO NEEDED" SECTION

This is the core new UI. A distinct section/panel titled to the effect of **"More info needed to finish your estimate."**

**Behavior:**
1. Every incomplete card appears here as a row with **input boxes for exactly the missing fields** (and the fields already known shown as filled/read-only context). If only the set code and collector number are missing, show only those two boxes.
2. The seller fills the boxes and submits. The engine re-checks completeness.
3. **First pass:** ask for all identity fields a card is missing.
4. **Second pass:** if the seller's filled values still don't resolve to an exact card (e.g. that collector number doesn't exist in that set, or the finish isn't valid for that printing), re-prompt for the specific field(s) still wrong or missing — with a brief reason ("no foil printing exists for this card"). Loop until complete or the seller leaves it.
5. A card stays in this section until it is complete. Complete cards move into the estimate.
6. Nothing is silently dropped and nothing is silently guessed: a card is in the estimate, in "more info needed," or in "couldn't price — manual review."

**Validation:** completeness and validity should be checked against a real card database (Scryfall's `/cards` lookups are fine for *validation/identity* even though pricing comes from ManaPool — Scryfall confirms "does 2X2 #117 exist, does it have a foil printing"). Use Scryfall for identity validation, ManaPool for price.

---

## 6. DISPLAY RULE — ESTIMATE ONLY

The seller sees **one number: the estimate** (what Roman pays).

- **Never show ManaPool market price.** Never show the 60% math, the multiplier, or any "market value." No "market $X → you get $Y."
- Per complete card: name + the exact printing identified (set, number, finish) + quantity + that line's estimate.
- Grand total labeled **"Your estimate"** (or equivalent). No second number beside it.
- Required disclaimer near the total: the estimate assumes Near Mint condition and exact card match; the final amount is confirmed after the cards are received and inspected.
- The word is **"estimate,"** never "offer," never "market price."

---

## 7. SUBMISSION PAYLOAD

When the seller submits, write to the `submissions` table (INSERT-only, as already built):
- The full resolved card list with exact identifiers (set, collector number, finish, language, quantity) per complete card.
- The estimate figure (write to `estimate_low` and `estimate_high` both, per existing column mapping).
- Incomplete/unpriceable cards may be included as notes so Roman sees the full picture.
- No market-price fields are stored as seller-facing values.

---

## 8. AUDIT FIRST

Before changing code, report:
1. ManaPool pricing endpoint + auth requirement + rate limits (§4.1).
2. Whether a Supabase Edge Function proxy is therefore required.
3. Current state of the parser and display vs. this spec (what already trusts file prices / shows market price / auto-picks printings).

Then implement, one commit per section. Hard stops unchanged: pause before anything touching Supabase keys/RLS or deploy/DNS.
