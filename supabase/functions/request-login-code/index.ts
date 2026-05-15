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
        /* Тема нейтральная — без слова «код» и без цифр. В шторке/локскрине
           телефона пользователь не должен видеть код, пока не откроет письмо. */
        subject: 'Вход в ЗебРус',
        html: `
          <div style="font-family: Manrope, Arial, sans-serif; max-width: 480px; margin: auto; padding: 24px; background: #fff; color: #1f2937;">
            <!-- Невидимый preheader — первое, что показывается в превью почты.
                 Заполняем нейтральным текстом, чтобы код не светился в уведомлении. -->
            <div style="display:none; max-height:0; overflow:hidden; visibility:hidden; opacity:0; color:transparent; mso-hide:all;">
              Подтверждение входа в личный кабинет. Откройте письмо, чтобы продолжить.
            </div>
            <div style="font-size: 28px; margin-bottom: 16px;">🐝 ЗебРус</div>
            <p style="color: #1f2937; font-size: 15px; line-height: 1.5; margin: 0 0 14px 0;">
              Здравствуйте! Вы запросили вход в личный кабинет ЗебРус.
              Чтобы продолжить — откройте приложение и введите одноразовый код,
              указанный ниже. Если вы не запрашивали вход, просто проигнорируйте это письмо.
            </p>
            <div style="font-size: 36px; font-weight: 800; letter-spacing: 6px; padding: 18px; background: #FEF3C7; border-radius: 12px; text-align: center; color: #78350F; margin: 16px 0;">
              ${code}
            </div>
            <p style="color: #6B7280; font-size: 13px; line-height: 1.5;">
              Код действителен 15 минут.
            </p>
            <hr style="border:none; border-top:1px solid #E5E7EB; margin: 20px 0;">
            <p style="color: #9CA3AF; font-size: 12px; line-height: 1.5;">
              <b>Не нашли это письмо?</b> Загляни в папку «Спам» или «Промоакции».
              Если оно там — нажми «Не спам», и следующие письма придут прямо в инбокс.
            </p>
          </div>
        `,
        text: `Здравствуйте!\n\nВы запросили вход в личный кабинет ЗебРус. Чтобы продолжить — откройте приложение и введите одноразовый код, указанный ниже.\n\nКод: ${code}\n\nКод действителен 15 минут.\n\nЕсли вы не запрашивали вход — просто проигнорируйте это письмо.`,
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
