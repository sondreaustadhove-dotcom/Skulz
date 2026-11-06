// Supabase Edge Function: scan-receipt
// Leser en kvittering med Claude. Appen sender enten teksten telefonen allerede har
// lest (billigst) eller selve bildet. Haiku prøver først; stemmer ikke summen,
// prøver Sonnet én gang til.
//
// Hemmeligheter (settes med `supabase secrets set ...`, se README):
//   ANTHROPIC_API_KEY      nøkkelen fra console.anthropic.com (må aldri ligge i appen)
//   SCAN_MODEL             valgfri, standard claude-haiku-5-5
//   SCAN_FALLBACK_MODEL    valgfri, standard claude-sonnet-5-5 (sett til "none" for å skru av)
//   SCAN_DAILY_LIMIT       valgfri, maks skanninger per bruker per døgn, standard 40
import { createClient } from 'jsr:@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

// Instruksjonene ligger her på serveren, så funksjonen ikke kan brukes til noe annet enn kvitteringer.
const PROMPT = `Du leser en norsk butikkvittering (dagligvare, restaurant eller annen butikk).
Returner KUN JSON med denne formen:
{"store": "butikknavn eller tom streng", "date": "YYYY-MM-DD eller tom streng", "total": tall eller null, "items": [{"name": "varenavn, kort og lesbart med vanlig store/små bokstaver", "price": tall, "category": "mat" | "drikke" | "hygiene" | "husholdning" | "snus" | "pant" | "annet"}]}
Kategori: mat = matvarer, drikke = all drikke, hygiene = kroppspleie og apotekvarer, husholdning = vask, papir, poser og lignende, snus = snus og tobakk, pant = pant, annet = alt annet.
Regler:
- Ta med hver varelinje med sluttpris for linjen (antall ganger enhetspris hvis det står flere).
- Pant er en egen vare med navnet "Pant", og skal stå rett etter drikken den hører til. Behold rekkefølgen fra kvitteringen.
- Rabatter og tilbud: trekk dem fra prisen på varen de gjelder hvis det er tydelig, ellers egen linje med negativ pris.
- Ikke ta med totalsum, mva, betalingsmåte, kortnummer, bonus eller veksel som varer.
- Skriv forkortede varenavn ut slik de vanligvis heter (for eksempel "TINE LETTM 1L" -> "Tine lettmelk 1 l").
- Bruk punktum som desimaltegn i tall.
- Hvis dette ikke er en kvittering, returner {"store":"","date":"","total":null,"items":[]}.`;

type Item = { name: string; price: number; category?: string };
type Receipt = { store: string; date: string; total: number | null; items: Item[] };

function extractJson(text: string): Receipt {
  const a = text.indexOf('{'), b = text.lastIndexOf('}');
  if (a < 0 || b <= a) throw new Error('no_json');
  const r = JSON.parse(text.slice(a, b + 1));
  const items = Array.isArray(r.items)
    ? r.items.filter((x: Item) => x && x.name && isFinite(Number(x.price)))
        .map((x: Item) => ({ name: String(x.name).slice(0, 60), price: Number(x.price), ...(x.category ? { category: String(x.category) } : {}) }))
    : [];
  return { store: String(r.store || '').slice(0, 60), date: String(r.date || ''), total: r.total == null ? null : Number(r.total), items };
}
const sumMatches = (r: Receipt) =>
  r.items.length > 0 && r.total != null && Math.abs(r.items.reduce((s, i) => s + i.price, 0) - r.total) < 0.51;

async function askClaude(model: string, content: unknown[]): Promise<Receipt> {
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': Deno.env.get('ANTHROPIC_API_KEY') ?? '',
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: JSON.stringify({ model, max_tokens: 2500, messages: [{ role: 'user', content }] }),
  });
  if (!res.ok) throw new Error('claude_' + res.status + ': ' + (await res.text()).slice(0, 300));
  const data = await res.json();
  const text = (data.content || []).filter((c: { type: string }) => c.type === 'text').map((c: { text: string }) => c.text).join('\n');
  return extractJson(text);
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  // hvem spør? (Supabase sjekker også innloggingen før funksjonen kjøres)
  const auth = req.headers.get('Authorization') ?? '';
  const userClient = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: auth } },
  });
  const { data: u } = await userClient.auth.getUser();
  const user = u?.user;
  if (!user) return json({ error: 'not_authenticated' }, 401);

  let body: { mode?: string; text?: string; image?: string; mediaType?: string };
  try { body = await req.json(); } catch { return json({ error: 'bad_request' }, 400); }
  const mode = body.mode === 'text' ? 'text' : 'image';
  if (mode === 'text' && (!body.text || body.text.length > 20000)) return json({ error: 'bad_text' }, 400);
  if (mode === 'image' && (!body.image || body.image.length > 7_000_000)) return json({ error: 'bad_image' }, 400);

  // grense per bruker per døgn, så ingen kan bruke opp kvoten
  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const limit = Number(Deno.env.get('SCAN_DAILY_LIMIT') ?? 40);
  const since = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
  const { count } = await admin.from('scan_log').select('id', { count: 'exact', head: true })
    .eq('user_id', user.id).gte('at', since);
  if ((count ?? 0) >= limit) return json({ error: 'rate_limited' }, 429);
  await admin.from('scan_log').insert({ user_id: user.id, kind: mode });

  const content = mode === 'text'
    ? [{ type: 'text', text: PROMPT + '\n\nTeksten fra kvitteringen (lest av telefonen, kan ha småfeil):\n' + body.text }]
    : [
        { type: 'image', source: { type: 'base64', media_type: body.mediaType || 'image/jpeg', data: body.image } },
        { type: 'text', text: PROMPT },
      ];

  const main = Deno.env.get('SCAN_MODEL') || 'claude-haiku-5-5';
  const fallback = Deno.env.get('SCAN_FALLBACK_MODEL') || 'claude-sonnet-5-5';
  try {
    let r = await askClaude(main, content);
    if (!sumMatches(r) && r.items.length && fallback !== 'none') {
      try { const r2 = await askClaude(fallback, content); if (sumMatches(r2) || !r.items.length) r = r2; } catch (e) { console.warn(e); }
    }
    return json(r);
  } catch (e) {
    console.error(e);
    return json({ error: 'scan_failed' }, 502);
  }
});
