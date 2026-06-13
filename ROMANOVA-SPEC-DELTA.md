# ROMANOVA.CARDS — DELTA SPEC
Version: 2026-06-12 · Scope: sell page (index.html) only

---

## 0. HOW TO USE THIS SPEC (Claude Code: read first)

1. **Audit before touching anything.** Compare every numbered item below against the current codebase. Produce a gap report: `IMPLEMENTED / PARTIAL / MISSING / CONFLICTS` per item. Change no files during the audit.
2. Wait for Roman's approval of the gap report.
3. Implement in spec order. One section per commit.
4. Items marked `[ROMAN: ...]` are placeholders Roman fills. Build around them; never invent values for them.
5. The existing Void/Arcane design system (palette, Playfair Display + Outfit, physical-button spec, nebula/star background) is locked. Follow it exactly. Do not introduce new colors, fonts, or passive animations.

---

## 1. LOCKED DECISIONS

1. **No required accounts.** The sell funnel collects name + contact method at submission only. Existing Supabase auth code may remain in the repo but must be invisible and unreachable from the funnel (no login buttons, no signup prompts, no dashboard links).
2. **Hybrid pricing.** On-page instant number = Scryfall-sourced TCGplayer market price, labeled **estimate**. Roman generates the formal **offer** off-site using ManaPool market prices after physical review. The site never promises the estimate is the payout.
3. **Sell page only.** `shop.html` is out of scope. Do not link to it from the funnel.

---

## 2. EXPECTED BASELINE (audit verifies)

- Single-page `index.html`: snap-scroll sections Hero → How It Works → What We Buy → Submit → Ask a Question → FAQ
- Scryfall live estimates; paste-list + file upload inputs
- Post-submit confirmation screen with packing/shipping instructions
- localStorage persistence of form state
- `faq.json` loaded dynamically, all questions fully expanded (no accordion)
- Supabase project wired with `submissions` table (config already in repo — reuse, do not regenerate keys)
- Deploy target: GitHub Pages, domain romanova.cards

---

## 3. CHANGES TO EXISTING FEATURES

### 3.1 Rates
- Replace all range language (50–60%, 60–70%) with flat rates: **60% cash / 70% store credit** of market price.
- Both numbers always shown side by side wherever a total appears.
- Terminology is strict everywhere (UI, confirmation, FAQ shell):
  - "estimate" = the on-page Scryfall number
  - "offer" = Roman's number after physical review, based on ManaPool market prices
- Required disclaimer near every estimate total: estimate assumes Near Mint condition; the final offer is set after Roman physically reviews the cards.

### 3.2 Remove accounts from the funnel
- Strip login/signup/dashboard UI from index.html.
- Submission form collects: name, email (required), optional phone, payout choice (cash | store credit).
- Submissions insert anonymously into Supabase `submissions` (see §10).

### 3.3 Estimate engine

**Input parsing — accept all of the following, auto-detected:**
- ManaBox CSV export. If a `Scryfall ID` column exists, use it as the identifier (exact match, zero ambiguity). Also read: Quantity, Foil, Condition, Language.
- Moxfield CSV (Count, Name, Edition, Foil, Condition)
- TCGplayer app collection export (Quantity, Name, Set Code, Card Number, Printing, Condition)
- Deckbox CSV (Count, Name, Edition, Foil, Condition)
- Generic CSV: case-insensitive header mapping for Name/Card Name, Set/Set Code/Edition, Collector Number/Card Number, Quantity/Count/Qty, Foil/Finish/Printing, Condition
- Plain text lines: `4 Lightning Bolt`, `4x Lightning Bolt`, `Lightning Bolt`, optionally with `(NEO) 123` set/collector suffix
- No header detected → treat as plain text lines.

**Scryfall lookup:**
- Use `POST https://api.scryfall.com/cards/collection` — batch of up to 75 identifiers per request, ≥100ms gap between requests.
- Identifier priority per row: Scryfall ID → set + collector_number → exact name.
- Rows in the `not_found` response: retry once via `GET /cards/named?fuzzy=`.
- Price field: `prices.usd`; if row is foil, `prices.usd_foil`; etched finish, `prices.usd_etched`. Null price → Unmatched bucket.

**Estimate output — three buckets, all visible:**
1. **Priced** — table: qty · name · set · market each · line total. Non-NM condition (when provided) is flagged visually but not price-adjusted.
2. **Below minimum** — excluded from totals, listed so the seller sees nothing was silently dropped. Threshold: keep the current implemented value. `[ROMAN: confirm minimum card value $___]`
3. **Unmatched** — listed with copy stating these get manually reviewed and included in the offer if identifiable.

**Totals row:** market total → 60% cash figure → 70% credit figure.

**Submission payload:** full parsed list (including condition/foil/language per row) serialized into `card_list`, plus the chosen payout type and the estimate figure.

---

## 4. NEW FEATURES

### 4.1 Contact channel menu ("Ask a Question" section rework)
A visible menu of ways to reach Roman. Each channel is a card in the existing design language:

| Channel | Value |
|---|---|
| Email | `[ROMAN: address]@romanova.cards` |
| Discord (chat or call) | `lombax_roman` `[ROMAN: DM directly, or provide server invite link?]` |
| Phone call / text | `[ROMAN: number — consider a Google Voice number instead of personal]` |
| Video call | `[ROMAN: Discord video, or a Google Meet scheduling link]` |
| Carrier pigeon | Joke entry, visually styled like the others. Copy: `TODO-HUMOR` |

**Question form** (works without accounts): name, preferred channel, contact handle, message.
- Endpoint: Formspree or Web3Forms (both work on static GitHub Pages). `[ROMAN: create the account, provide the form key]`
- Must deliver to the romanova.cards inbox.
- Include a hidden honeypot field for spam.

### 4.2 ManaPool block (footer-adjacent, secondary visual weight)
Two purposes, two links:
1. **Trust:** link to the Romanova ManaPool seller page — copy angle: see live inventory and seller ratings. `[ROMAN: store URL + QR image file]`
2. **Referral:** ManaPool signup link that credits Roman as referrer. `[ROMAN: referral URL + QR image file]`
- QR images go in `/assets/`. Block must not compete visually with the Submit funnel.

### 4.3 Humor hooks
Do not write jokes. Insert `TODO-HUMOR` markers at these slots; content arrives in a later pass:
- Empty estimate state (before any cards entered)
- Estimate loading state
- Unmatched-cards bucket copy
- Confirmation screen sign-off line
- Carrier pigeon channel card
- 404 page

### 4.4 Policies
- FAQ section doubles as the policy page. Add a `policies` category to the `faq.json` schema (categories render as labeled groups, still fully expanded).
- Content arrives in a later pass; ship the schema + rendering now with 2 placeholder entries marked `TODO-CONTENT`.

---

## 5. PERSISTENCE (hard requirement)

- localStorage, keys namespaced `romanova.*`: raw pasted text, parsed card list, contact/submission form fields, question form fields, last-active section, per-section scroll offsets.
- Restore everything on page load. Switching sections or refreshing loses nothing.
- A visible "clear my list" control wipes the card-list keys only.

## 6. MOBILE (hard requirement)

- Primary test width: 390px. The flow link/QR → understand → paste → estimate → submit must be completable one-handed on a phone.
- On mobile: paste box is the primary input; file upload is secondary.
- Touch targets ≥ 44px. Estimate table collapses to stacked rows. Sticky "Get my estimate" / "Submit list" CTA while the card-input section is in view.

## 7. COPY RULES

- The word is **"cards"** — never "singles."
- Never offer or mention prepaid shipping labels.
- Buttons state exactly what happens: "Get my estimate," "Submit my list" — not "Go" or "Submit."
- Errors say what happened and what to do next. No apologies, no vagueness.
- estimate / offer terminology per §3.1, everywhere, no exceptions.

## 8. SUPABASE

- Reuse existing project config in the repo. Do not print or rotate keys.
- Verify RLS: anonymous role may INSERT into `submissions` only; no SELECT/UPDATE/DELETE.
- Column mapping: write the single estimate figure to both `estimate_low` and `estimate_high` (legacy columns; renaming is post-launch cleanup, not now). `payout_type` ∈ {`cash`, `credit`}. `status` defaults `pending`.

## 9. DEPLOY CHECKLIST

1. Confirmation screen contains Roman's real mailing name/address (audit: placeholder may remain from earlier build).
2. Push to GitHub → enable Pages → add `CNAME` file containing `romanova.cards`.
3. DNS at the registrar: A records `185.199.108.153 / .109.153 / .110.153 / .111.153` for apex, CNAME `www` → the GitHub Pages hostname. Enforce HTTPS once the cert issues.
4. Phone test the full funnel on a real device before sharing the link.

## 10. ROMAN'S FILL-IN LIST

- [ ] Minimum card value threshold (§3.3)
- [ ] Contact email address at romanova.cards (§4.1)
- [ ] Discord: DM vs server invite (§4.1)
- [ ] Phone/text number — Google Voice decision (§4.1)
- [ ] Video call method (§4.1)
- [ ] Form endpoint key — Formspree or Web3Forms (§4.1)
- [ ] ManaPool store URL + QR file (§4.2)
- [ ] ManaPool referral URL + QR file (§4.2)
- [ ] Confirm mailing address in confirmation screen (§9)

## 11. OUT OF SCOPE (do not build)

- shop.html, Stripe, accounts/auth UI, store-credit dashboard
- Store-credit redemption mechanics (handled as FAQ/policy content later)
- Live ManaPool pricing on the site (possible later via Supabase Edge Function proxy; revisit after launch)
- Advertising/marketing assets
