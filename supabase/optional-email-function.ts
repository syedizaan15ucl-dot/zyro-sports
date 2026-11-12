// OPTIONAL. Supabase Edge Function that emails you each new order, message or design.
// Setup (only if you want this instead of Formspree):
//  1. resend.com: create a free account with your Gmail, create an API key.
//  2. Supabase > Edge Functions > Secrets: add RESEND_API_KEY (the key) and OWNER_EMAIL (your Gmail).
//     The key lives only inside Supabase. Do not put it in config.js or any public file.
//  3. Supabase > Edge Functions > Deploy a new function named notify-entry, paste this file.
//  4. Supabase > Database > Webhooks > Create: table `entries`, event INSERT, type Edge Function, pick notify-entry.
// Leave notifyUrl empty in config.js if you use this, or you will get two emails.

Deno.serve(async (req) => {
  const payload = await req.json();
  const e = payload.record;
  if (!e) return new Response('no record', { status: 400 });
  const d = e.data || {};
  let text = '';
  if (e.type === 'order') {
    const lines = (d.items || []).map((i: any) => `${i.qty} x ${i.name}${i.size ? ' (' + i.size + ')' : ''} - PKR ${i.price * i.qty}`).join('\n');
    text = `New ZYRO order ${e.id}\n\n${d.customer?.who}\n${d.customer?.phone}\n${d.customer?.address}\n\n${lines}\n\nTotal: PKR ${d.total}\nShipping: ${d.shipping}`;
  } else if (e.type === 'contact') {
    text = `Message ${e.id} from ${d.who}\n${d.phone || ''} ${d.email || ''}\n\n${d.msg}`;
  } else {
    text = `Custom design ${e.id}\nSize ${d.size}, quantity ${d.qty}\n${d.note || ''}\nOpen the Admin Portal to see the image.`;
  }
  const r = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + Deno.env.get('RESEND_API_KEY'), 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: 'ZYRO Orders <onboarding@resend.dev>', to: [Deno.env.get('OWNER_EMAIL')], subject: `ZYRO ${e.type} ${e.id}`, text }),
  });
  return new Response(r.ok ? 'sent' : 'failed', { status: r.ok ? 200 : 500 });
});
