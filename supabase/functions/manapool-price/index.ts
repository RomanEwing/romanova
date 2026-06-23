// Supabase Edge Function: manapool-price
//
// Why this exists: ManaPool's pricing API (https://manapool.com/api/v1/products/singles)
// is PUBLIC (no auth), but it sends no Access-Control-Allow-Origin header, so a browser
// fetch from the static romanova.cards site is blocked by CORS. This function relays the
// request server-side (no CORS there) and returns the result WITH CORS headers.
//
// It holds NO secrets and touches NO Supabase tables, keys, or RLS — it only forwards
// public price data. JWT verification stays ON; the client calls it with the project anon
// key (sb.functions.invoke handles that automatically).
//
// Deploy (Roman):  supabase functions deploy manapool-price
//
// Request  (POST JSON): { "scryfall_ids": ["<uuid>", ...] }   // max 100
// Response (JSON):      { "data": [ <manapool single>, ... ] } // [] on any upstream error

const MANAPOOL = "https://manapool.com/api/v1/products/singles";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...CORS, "content-type": "application/json" },
  });
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ data: [], error: "method not allowed" }, 405);

  try {
    const body = await req.json().catch(() => ({}));
    const raw = Array.isArray(body?.scryfall_ids) ? body.scryfall_ids : [];
    // De-dupe, drop falsy, cap at the API's 100-identifier limit.
    const ids = [...new Set(raw.filter((x: unknown) => typeof x === "string" && x))].slice(0, 100);
    if (!ids.length) return json({ data: [] });

    const qs = ids.map((id) => `scryfall_ids=${encodeURIComponent(id as string)}`).join("&");
    const res = await fetch(`${MANAPOOL}?${qs}`, { headers: { accept: "application/json" } });
    if (!res.ok) return json({ data: [], error: `manapool ${res.status}` });

    const payload = await res.json();
    return json({ data: Array.isArray(payload?.data) ? payload.data : [] });
  } catch (e) {
    return json({ data: [], error: String((e as Error)?.message ?? e) });
  }
});
