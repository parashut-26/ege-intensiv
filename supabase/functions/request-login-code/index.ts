// Edge Function: request-login-code
// Принимает email, генерирует 6-значный код, кладёт в auth_codes,
// отправляет письмо через Resend.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')!;
const FROM_EMAIL = Deno.env.get('FROM_EMAIL') || 'ZebRus <onboarding@resend.dev>';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const email = String(body.email || '').trim().toLowerCase();

    if (!email || !email.includes('@')) {
      return new Response(JSON.stringify({ error: 'Неверный email' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // 6-значный код
    const code = String(Math.floor(100000 + Math.random() * 900000));
    const expiresAt = new Date(Date.now() + 15 * 60 * 1000).toISOString();

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    // Сохраняем код
    const { error: dbErr } = await supabase
      .from('auth_codes')
      .insert({ email, code, expires_at: expiresAt });

    if (dbErr) {
      console.error('DB insert error:', dbErr);
      return new Response(JSON.stringify({ error: 'Ошибка БД: ' + dbErr.message }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Отправляем письмо
    const emailResp = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: FROM_EMAIL,
        to: email,
        subject: 'Код для входа · ЗебРус',
        html: `
          <div style="font-family: Manrope, Arial, sans-serif; max-width: 480px; margin: auto; padding: 24px; background: #fff; color: #1f2937;">
            <div style="font-size: 28px; margin-bottom: 16px;">🐝 ЗебРус</div>
            <h2 style="margin: 0 0 12px 0; color: #1f2937;">Ваш код для входа</h2>
            <div style="font-size: 36px; font-weight: 800; letter-spacing: 6px; padding: 18px; background: #FEF3C7; border-radius: 12px; text-align: center; color: #78350F; margin: 16px 0;">
              ${code}
            </div>
            <p style="color: #6B7280; font-size: 14px; line-height: 1.5;">
              Введите этот код в приложении в течение 15 минут.
              Если вы не запрашивали код — просто проигнорируйте письмо.
            </p>
          </div>
        `,
        text: `Ваш код для входа в ЗебРус: ${code}\n\nКод действителен 15 минут.`,
      }),
    });

    if (!emailResp.ok) {
      const errText = await emailResp.text();
      console.error('Resend error:', errText);
      return new Response(JSON.stringify({ error: 'Не удалось отправить письмо: ' + errText }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    return new Response(JSON.stringify({ ok: true }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e?.message || e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
