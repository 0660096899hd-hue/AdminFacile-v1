import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const jsonHeaders = {
  'Content-Type': 'application/json; charset=utf-8',
  'Cache-Control': 'no-store',
};
const maxRequestBytes = 64 * 1024;
const allowedModels = new Set(['gemini-3.5-flash-lite']);

function reply(status: number, code: string) {
  return new Response(JSON.stringify({ error: code }), {
    status,
    headers: jsonHeaders,
  });
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') return reply(405, 'method_not_allowed');

  const contentLength = Number(request.headers.get('content-length') ?? '0');
  if (contentLength > maxRequestBytes) return reply(413, 'request_too_large');

  const authorization = request.headers.get('authorization') ?? '';
  if (!authorization.startsWith('Bearer ')) return reply(401, 'unauthorized');

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const geminiKey = Deno.env.get('GEMINI_API_KEY');
  if (!supabaseUrl || !anonKey || !geminiKey) {
    return reply(503, 'service_unavailable');
  }

  const supabase = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) return reply(401, 'unauthorized');

  const rawBody = await request.text();
  if (new TextEncoder().encode(rawBody).byteLength > maxRequestBytes) {
    return reply(413, 'request_too_large');
  }

  let body: Record<string, unknown>;
  try {
    body = JSON.parse(rawBody);
  } catch {
    return reply(400, 'invalid_request');
  }
  const prompt = typeof body.prompt === 'string' ? body.prompt.trim() : '';
  const model = typeof body.model === 'string' ? body.model : '';
  const generationConfig = body.generationConfig;
  if (!prompt || prompt.length > 40000 || !allowedModels.has(model) ||
      typeof generationConfig !== 'object' || generationConfig === null) {
    return reply(400, 'invalid_request');
  }

  const { data: allowed, error: quotaError } = await supabase.rpc(
    'consume_gemini_quota',
    { p_minute_limit: 6, p_daily_limit: 50 },
  );
  if (quotaError) return reply(503, 'service_unavailable');
  if (allowed !== true) return reply(429, 'rate_limit_exceeded');

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 35000);
  try {
    const endpoint = new URL(
      `/v1beta/models/${encodeURIComponent(model)}:generateContent`,
      'https://generativelanguage.googleapis.com',
    );
    endpoint.searchParams.set('key', geminiKey);
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [{ role: 'user', parts: [{ text: prompt }] }],
        generationConfig,
      }),
      signal: controller.signal,
    });
    if (!response.ok) return reply(502, 'upstream_error');
    return new Response(await response.text(), {
      status: 200,
      headers: jsonHeaders,
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') {
      return reply(504, 'upstream_timeout');
    }
    return reply(502, 'upstream_error');
  } finally {
    clearTimeout(timeout);
  }
});
