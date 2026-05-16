// Edge Function: tg-payment-webhook
//
// Принимает webhook от Telegram-бота @ZebrusPayBot.
// Если пришло сообщение от учителя/куратора (по telegram_chat_id в profiles),
// парсит как уведомление об оплате и создаёт запись в payment_suggestions.
//
// Поддерживаемые форматы (примерно):
//   "Перевод 5000 ₽ от ИВАН И."
//   "Зачисление 5000 руб от Иванов И."
//   "Поступление: 5000.00 RUB · от Иван И. Иванов"
//
// После создания suggestion — бот отвечает учителю в Telegram:
//   «🤖 Зафиксировано: 5000₽ от Иван И. → найдено: Иван Петров.
//    Подтверди в кабинете → /students»

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const TG_PAY_BOT_TOKEN = Deno.env.get('TG_PAY_BOT_TOKEN');

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

/* ------------------------- ПАРСЕР СООБЩЕНИЯ ------------------------- */
interface ParsedPayment {
  amount: number;
  payerName: string | null;
  payerEmail: string | null;
  payerPhone: string | null;
  operationId: string | null;
  orderDescription: string | null;
  date: Date | null;
}

function parsePayment(text: string): ParsedPayment | null {
  if (!text) return null;

  // СУММА: «Итого: 1500 руб.» или «5000 ₽» — поддерживаем оба
  let amount = 0;
  const totalRe = /Итого\s*:?\s*(\d[\d\s]*(?:[.,]\d{1,2})?)\s*(?:руб|₽|RUB|р\.)/i;
  const tm = text.match(totalRe);
  if (tm) {
    amount = Math.round(parseFloat(tm[1].replace(/\s/g, '').replace(',', '.')));
  }
  if (!amount){
    const amountRe = /(\d[\d\s]*(?:[.,]\d{1,2})?)\s*(?:₽|руб(?:\.|лей|ля|ль)?|RUB|р\.)/i;
    const m = text.match(amountRe);
    if (m) amount = Math.round(parseFloat(m[1].replace(/\s/g, '').replace(',', '.')));
  }
  if (!amount || amount < 100 || amount > 10_000_000) return null;

  // ФИО — два варианта:
  //   а) Формат tb.ru: «Имя Фамилия: Татьяна Мудрак»
  //   б) Банковский: «от Иван И.»
  let payerName: string | null = null;
  const nameRe1 = /Имя\s+Фамилия\s*:?\s*([А-ЯЁA-Z][\wА-яёA-Z\.\s\-]+?)(?:\n|$)/u;
  const nm = text.match(nameRe1);
  if (nm) {
    payerName = nm[1].trim().replace(/\s+/g, ' ');
  } else {
    const fromRe = /от\s+([А-ЯЁA-Z][\wА-яёA-Z\.\s\-]+?)(?=[.,;\n!?]|\sпо\sСБП|\sкарта|\sсчёт|\sбаланс|$)/iu;
    const f = text.match(fromRe);
    if (f) {
      payerName = f[1].trim().replace(/\s+/g, ' ');
      payerName = payerName.replace(/\s+по\s+.*$/i, '').trim();
    }
  }

  // EMAIL: «Почта: pona19@yandex.ru»
  let payerEmail: string | null = null;
  const em = text.match(/Почта\s*:?\s*([\w.+\-]+@[\w.\-]+\.[a-zа-я]{2,})/i)
          || text.match(/([\w.+\-]+@[\w.\-]+\.[a-zа-я]{2,})/i);
  if (em) payerEmail = em[1].trim().toLowerCase();

  // ТЕЛЕФОН: «Контактный телефон: +7 909 978 47 01»
  let payerPhone: string | null = null;
  const ph = text.match(/(?:Телефон|телефон|тел\.?)[^\d+]*((?:\+7|8)[\d\s\-()]{9,})/i)
          || text.match(/((?:\+7|8)[\d\s\-()]{9,})/);
  if (ph){
    payerPhone = ph[1].replace(/[^\d+]/g, '');
    if (payerPhone.startsWith('8')) payerPhone = '+7' + payerPhone.slice(1);
  }

  // НОМЕР ОПЕРАЦИИ — для дедупликации
  let operationId: string | null = null;
  const op = text.match(/Номер\s+операции\s*:?\s*([a-f0-9\-]{8,})/i);
  if (op) operationId = op[1].trim().toLowerCase();

  // ОПИСАНИЕ ЗАКАЗА — иногда родитель пишет «за Иванова Петю», там имя ребёнка
  let orderDescription: string | null = null;
  const od = text.match(/Описание\s+заказа\s*:?\s*([^\n]+)/i);
  if (od) orderDescription = od[1].trim();

  // ДАТА: «14:30 16.05» или «16.05.2026 14:30»
  let date: Date | null = null;
  const dt1 = text.match(/(\d{1,2}):(\d{2})[\s,]+(\d{1,2})\.(\d{1,2})(?:\.(\d{2,4}))?/);
  const dt2 = text.match(/(\d{1,2})\.(\d{1,2})(?:\.(\d{2,4}))?[\s,]+(\d{1,2}):(\d{2})/);
  const now = new Date();
  if (dt1) {
    const [_, hh, mm, dd, mo, yy] = dt1;
    const year = yy ? (yy.length === 2 ? 2000 + parseInt(yy) : parseInt(yy)) : now.getFullYear();
    date = new Date(year, parseInt(mo) - 1, parseInt(dd), parseInt(hh), parseInt(mm));
  } else if (dt2) {
    const [_, dd, mo, yy, hh, mm] = dt2;
    const year = yy ? (yy.length === 2 ? 2000 + parseInt(yy) : parseInt(yy)) : now.getFullYear();
    date = new Date(year, parseInt(mo) - 1, parseInt(dd), parseInt(hh), parseInt(mm));
  }

  return { amount, payerName, payerEmail, payerPhone, operationId, orderDescription, date };
}

/* Корень русской фамилии: «Халиулина» → «Халиулин», «Петрова» → «Петров», «Иванов» → «Иван».
   Снимаем -ова/-ева/-ина/-а/-я в конце; берём слово минимум 4 символов. */
function _surnameRoot(surname: string): string {
  if (!surname) return surname;
  let s = surname.trim();
  if (s.length < 4) return s;
  // -ова/-ева/-ёва (Петрова → Петров), -ина (Халиулина → Халиулин), -ская/-цкая
  s = s.replace(/(ова|ева|ёва|ина|ская|цкая)$/iu, (m) => m.slice(0, -1));
  // окончание -а/-я (Лиса → Лис, Маня → Ман) — рискованно для коротких слов
  if (s.length >= 5) s = s.replace(/[ая]$/iu, '');
  return s;
}

/* ----------------- MATCH ученика по email + ФИО + описанию заказа ----------------- */
async function findStudents(
  supabase: any,
  payerName: string | null,
  payerEmail: string | null,
  orderDescription: string | null
): Promise<{ matches: any[]; reason: string }> {
  const select = 'id, full_name, role, s_status, s_type, email';
  const tryDedup = (arr: any[]): any[] => {
    const seen = new Set<string>();
    return (arr || []).filter((p) => {
      if (!p || !p.id || seen.has(p.id)) return false;
      seen.add(p.id);
      return true;
    });
  };

  // 1) По email — самый надёжный
  if (payerEmail) {
    const { data: byEmail } = await supabase
      .from('profiles')
      .select(select)
      .eq('email', payerEmail)
      .in('role', ['student'])
      .limit(5);
    if (Array.isArray(byEmail) && byEmail.length) {
      return { matches: tryDedup(byEmail), reason: 'email' };
    }
  }

  // 2) По корню фамилии плательщика («Халиулина» → «Халиулин»)
  if (payerName) {
    const parts = payerName.trim().split(/\s+/);
    const surname = parts[0];
    if (surname && surname.length >= 3) {
      const root = _surnameRoot(surname);
      const { data: byName } = await supabase
        .from('profiles')
        .select(select)
        .ilike('full_name', '%' + root + '%')
        .in('role', ['student'])
        .limit(10);
      if (Array.isArray(byName) && byName.length) {
        return { matches: tryDedup(byName), reason: 'name' };
      }
    }
  }

  // 3) По имени из описания заказа («за Ивана Петрова» — иногда родители так пишут)
  if (orderDescription) {
    // Берём слова с заглавной буквы длиной ≥3 (имена/фамилии)
    const tokens = (orderDescription.match(/[А-ЯЁA-Z][а-яёa-z]{2,}/gu) || [])
      .filter((t) => !['Образовательная', 'Программа', 'Программу', 'Урок', 'Уроки', 'Класс',
                       'Пробный', 'Пробного', 'Экзамен', 'Экзамена', 'Русскому', 'Русский',
                       'Языку', 'Язык', 'Литература', 'Литературе'].includes(t));
    if (tokens.length) {
      // ilike OR по каждому токену
      const orFilter = tokens.map((t) => 'full_name.ilike.%' + t + '%').join(',');
      const { data: byDesc } = await supabase
        .from('profiles')
        .select(select)
        .or(orFilter)
        .in('role', ['student'])
        .limit(10);
      if (Array.isArray(byDesc) && byDesc.length) {
        return { matches: tryDedup(byDesc), reason: 'description' };
      }
    }
  }

  return { matches: [], reason: 'none' };
}

/* ----------------- TELEGRAM HTTP CLIENT ----------------- */
async function sendTgMessage(chatId: number | string, text: string) {
  if (!TG_PAY_BOT_TOKEN) return;
  try {
    await fetch('https://api.telegram.org/bot' + TG_PAY_BOT_TOKEN + '/sendMessage', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        chat_id: chatId,
        text,
        parse_mode: 'HTML',
        disable_web_page_preview: true,
      }),
    });
  } catch (e: any) {
    console.error('sendTgMessage:', e.message);
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    // Стандартный webhook Telegram: { message: { text, from: { id }, chat: { id }, forward_from } }
    const msg = body.message || body.edited_message;
    if (!msg) {
      return new Response(JSON.stringify({ ok: true, skip: 'no message' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    const chatId = msg.chat?.id;
    const fromId = msg.from?.id;
    const text: string = msg.text || msg.caption || '';

    if (!text) {
      return new Response(JSON.stringify({ ok: true, skip: 'no text' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    // Авторизация: разрешено только если from_id связан в profiles.telegram_id
    const { data: profile } = await supabase
      .from('profiles')
      .select('id, full_name, role')
      .eq('telegram_id', String(fromId))
      .maybeSingle();

    if (!profile || (profile.role !== 'teacher' && profile.role !== 'curator')) {
      await sendTgMessage(chatId, '❌ Бот принимает пересылки только от учителя/куратора. Привяжи свой Telegram-аккаунт в кабинете → Профиль → Telegram.');
      return new Response(JSON.stringify({ ok: true, skip: 'not-teacher' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Парсим
    const parsed = parsePayment(text);
    if (!parsed) {
      await sendTgMessage(chatId, '⚠️ Не получилось распарсить как уведомление об оплате. Перешли мне образец, я подстрою парсер.');
      return new Response(JSON.stringify({ ok: true, skip: 'unparsed' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Дедуп по operation_id (если та же операция уже была переслана)
    if (parsed.operationId) {
      const { data: existing } = await supabase
        .from('payment_suggestions')
        .select('id, status')
        .eq('operation_id', parsed.operationId)
        .maybeSingle();
      if (existing) {
        await sendTgMessage(chatId,
          'ℹ️ Этот платёж уже зафиксирован (#' + existing.id + ', статус: ' + existing.status + ').\n' +
          'Смотри в кабинете → 💰 Оплаты');
        return new Response(JSON.stringify({ ok: true, skip: 'dup', existing_id: existing.id }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
    }

    // Ищем кандидатов по 3 каналам (email → корень фамилии → имена в описании)
    const { matches: candidates, reason: matchReason } = await findStudents(
      supabase, parsed.payerName, parsed.payerEmail, parsed.orderDescription
    );
    const matched = candidates.length === 1 ? candidates[0] : null;

    // Создаём suggestion
    const { data: created, error: cErr } = await supabase
      .from('payment_suggestions')
      .insert({
        raw_message: text,
        amount: parsed.amount,
        payer_name: parsed.payerName,
        payer_email: parsed.payerEmail,
        payer_phone: parsed.payerPhone,
        operation_id: parsed.operationId,
        order_description: parsed.orderDescription,
        payment_date: parsed.date ? parsed.date.toISOString() : null,
        matched_student_id: matched ? matched.id : null,
        candidates: candidates.map(c => ({ id: c.id, name: c.full_name, type: c.s_type, email: c.email })),
        source: 'telegram',
      })
      .select('id')
      .single();

    if (cErr) {
      await sendTgMessage(chatId, '❌ Ошибка БД: ' + cErr.message);
      return new Response(JSON.stringify({ error: cErr.message }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Человекочитаемый «канал совпадения»
    const reasonLabel: Record<string, string> = {
      email:       'по почте',
      name:        'по фамилии плательщика',
      description: 'по имени в описании заказа',
      none:        '',
    };

    // Ответ учителю
    let reply = '✅ Зафиксировано: <b>' + parsed.amount + '₽</b>';
    if (parsed.payerName)  reply += ' от ' + parsed.payerName;
    if (parsed.payerEmail) reply += '\n📧 ' + parsed.payerEmail;
    if (matched) {
      const lbl = reasonLabel[matchReason] ? ' (' + reasonLabel[matchReason] + ')' : '';
      reply += '\n\n🔍 Найден ученик' + lbl + ': <b>' + matched.full_name + '</b>';
      reply += '\n\nПодтверди в кабинете → 💰 Оплаты';
    } else if (candidates.length > 1) {
      reply += '\n\n⚠️ Несколько кандидатов ' + (reasonLabel[matchReason] || '') + ':\n' +
        candidates.slice(0, 5).map((c, i) => (i+1) + ') ' + c.full_name).join('\n');
      reply += '\n\nВыбери в кабинете → 💰 Оплаты';
    } else {
      reply += '\n\n❓ Ученик не найден. Можно привязать вручную в кабинете → 💰 Оплаты';
    }
    await sendTgMessage(chatId, reply);

    return new Response(JSON.stringify({ ok: true, suggestion_id: created.id, matched: !!matched }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (e: any) {
    console.error('tg-payment-webhook fatal:', e);
    return new Response(JSON.stringify({ error: String(e?.message || e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
