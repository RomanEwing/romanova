# ROMANOVA.CARDS — ESTIMATE ENGINE OVERHAUL
Delta spec v2 · 2026-06-21 · Scope: the estimate engine and its display only

---

## 0. ONE PRINCIPLE

**Exact card information or bust.** The engine never guesses a card's printing and never trusts a price from an uploaded file. A card is either identified precisely enough to price, or it is routed to a section that asks the seller for the exact missing details. There is no third behavior — no cheapest-printing fallback, no price range, no "best guess." *(Identity only. Once a card is exactly identified, its price is a blend of multiple real sources per the amended §4 — that is pricing, not a guess at which card it is.)*

---

## 1. WHAT THIS SUPERSEDES

This overrides the earlier "hybrid pricing" decision and §3.1/§3.3 of the original delta spec:
- **Old:** on-page estimate sourced from Scryfall (TCGplayer market price); ManaPool used only offline.
- **New:** on-page estimate sourced from live **ManaPool** pricing. *(Amended 2026-06-23 — see §4: the estimate now blends ManaPool low, ManaPool market, and TCGplayer market. TCGplayer is used as a price source and fallback again, but — like every component, market, and average figure — it is never **shown** to the seller.)*
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

## 4. PRICING — BLENDED (MANAPOOL + TCGPLAYER)

**Amended 2026-06-23.** This replaces the original "ManaPool market price only; never substitute TCGplayer" rule. The estimate is now a **blended average** of ManaPool and TCGplayer prices. Identity stays exact-or-bust (§0) — this changes only how an *already-identified* card is priced, never whether it's identified.

### 4.0 API findings (verified live, 2026-06-23)
- **Endpoint:** `GET https://manapool.com/api/v1/products/singles` — **public, no auth**. Identifiers are repeated bare query params, e.g. `?scryfall_ids=<uuid>&scryfall_ids=<uuid>`, **max 100 per request** (comma-joined values and `[]` brackets are rejected). No Supabase Edge Function is needed (see §8.2).
- **ManaPool exposes a market price distinct from the lowest listing.** Per card, per finish, the response carries both, as **integer cents** (÷100):
  - Lowest NM listing: `price_cents_nm` · foil `price_cents_nm_foil` · etched `price_cents_nm_etched`
  - Market price: `price_market` · foil `price_market_foil`
- **Gap — etched has no market field:** there is `price_market` / `price_market_foil` but **no `price_market_etched`**. For etched, ManaPool contributes only its low.
- TCGplayer market is **not** in ManaPool's payload; it comes from Scryfall `usd` / `usd_foil` / `usd_etched` (TCGplayer-derived), keyed by Scryfall ID. (ManaPool also returns `tcgplayer_product_id` for cross-reference; top-level price fields are EN — non-EN lives in the `variants[]` array.)
- No official rate limit is documented; batch ≤100 ids/request and throttle to ~10 req/s.

### 4.1 Sources per complete card (NM assumed, exact finish/language)
Gather up to three prices, in dollars:
1. **ManaPool low** — `price_cents_nm[_foil/_etched]` ÷ 100
2. **ManaPool market** — `price_market[_foil]` ÷ 100 *(absent for etched)*
3. **TCGplayer market** — Scryfall `usd` / `usd_foil` / `usd_etched`

### 4.2 Fallback chain
- Card **not on ManaPool at all** (not returned, or the finish's fields are null) → use **TCGplayer market** (Scryfall) alone.
- **Neither** source has a price for the finish → **manual-review bucket** (excluded from the total, surfaced to Roman).
- Scryfall stays identity-validation (§5); here it doubles as the TCGplayer price source.

### 4.3 The estimate
- Average the **present** real sources (2 or 3 — **never invent a missing value**; for etched or ManaPool-absent cards the average is over whatever real sources exist).
- **Per-card unit estimate = 0.6 × average.** Line total = unit estimate × quantity.
- Capture, per card: **each raw source price and its 0.6 multiple**, the **average**, and **0.6 × average**. The customer sees **only 0.6 × average** (§6), described as based on the card's **"current price."** Component prices, the average, and the 0.6 multiplier are never shown.

### 4.4 Outlier flag (internal only)
- If any one present source is **≥30% below** the others, **keep it in the average anyway** (do **not** exclude it) and **flag the card for Roman's review**.
- The estimate is computed identically whether or not a card is flagged — the customer is unaffected by the flag.

### 4.5 Minimum
- Apply the **$10 minimum to the final 0.6-average unit estimate.** A card whose unit estimate is **below $10** goes to the **below-minimum bucket**, not the offer. *(Threshold interpreted per-unit, not per-line × qty — see open note in §4.7.)*

### 4.6 Captured metrics → submission record
- Write all captured values + flags to a **clean, structured store on the submission record**, **not** in display logic — a later dashboard phase reads it.
- Per card, store: sources present, each raw price + its 0.6 value, average, unit estimate (0.6 × avg), price basis (`manapool+tcgplayer`, `tcgplayer-only`, `manapool-only`), outlier flag (which source, the deltas), and bucket (`priced` / `below_min` / `manual_review`).
- **Location:** a dedicated `pricing` structure **inside the existing `card_list` JSON** column — **no DB schema/RLS change**, so this stays clear of the Supabase hard stop. A dedicated column/table for the dashboard would be a schema change → pause for Roman first.

### 4.7 Open note — $10 basis changed
The original spec and the live site copy say the minimum is on **TCGplayer market price** ("cards priced at $10 or more"); this amendment moves it to the **0.6-average estimate**. That materially shifts which cards qualify (a card now needs ≈$16.67 average to clear a $10 estimate) and contradicts the public copy at `index.html` §3/§9 and the "60% of TCGPlayer market price" wording. **Reconcile the site copy when implementing §6.**

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

- **Never show ManaPool market price.** Never show the 60% math, the multiplier, the component prices, or the average. No "market $X → you get $Y." The single estimate is described to the seller as based on the card's **"current price."**
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
- Store the full per-card pricing metrics + flags described in §4.6 as a structured `pricing` object inside `card_list` JSON (internal, for the later dashboard) — never surfaced in the seller UI.

---

## 8. AUDIT FIRST

Before changing code, report:
1. ManaPool pricing endpoint + auth requirement + rate limits (§4.1).
2. Whether a Supabase Edge Function proxy is therefore required.
3. Current state of the parser and display vs. this spec (what already trusts file prices / shows market price / auto-picks printings).

Then implement, one commit per section. Hard stops unchanged: pause before anything touching Supabase keys/RLS or deploy/DNS.
