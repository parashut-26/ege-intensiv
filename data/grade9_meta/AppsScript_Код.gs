function doPost(e) {
  try {
    const data = JSON.parse(e.postData.contents);
    if (!data.name || !data.game) {
      return jsonResp({ok: false, error: 'missing fields'});
    }

    const ss = SpreadsheetApp.getActiveSpreadsheet();
    const sheet = ss.getSheetByName(data.game);
    if (!sheet) {
      return jsonResp({ok: false, error: 'Tab not found: ' + data.game});
    }

    // Read header row to know which columns hold which FIPI IDs
    const lastCol = sheet.getLastColumn();
    const headers = sheet.getRange(1, 1, 1, lastCol).getValues()[0];

    // Build the new row
    const row = new Array(lastCol).fill('');
    row[0] = new Date();
    row[1] = String(data.name).substring(0, 30);
    row[2] = (data.score || 0) + '/' + (data.total || 0);
    const pct = data.total > 0 ? Math.round((data.score / data.total) * 100) : 0;
    row[3] = pct + '%';

    // Fill answer columns by matching FIPI IDs from headers like "[F150FD]"
    const answers = data.answers || {};
    for (let i = 4; i < lastCol; i++) {
      const h = String(headers[i] || '');
      const match = h.match(/\[([0-9A-Fa-f]+)\]/);
      if (match) {
        const fipiId = match[1].toUpperCase();
        if (answers[fipiId]) {
          row[i] = answers[fipiId];
        }
      }
    }

    sheet.appendRow(row);
    return jsonResp({ok: true});
  } catch (err) {
    return jsonResp({ok: false, error: err.toString()});
  }
}

function doGet(e) {
  try {
    const ss = SpreadsheetApp.getActiveSpreadsheet();
    const game = e.parameter.game;
    if (!game) return jsonResp({ok: false, error: 'game param required'});

    const sheet = ss.getSheetByName(game);
    if (!sheet) return jsonResp({ok: true, top: []});

    const data = sheet.getDataRange().getValues();
    if (data.length < 2) return jsonResp({ok: true, top: []});

    // Columns: A=date, B=name, C=score (e.g. "6/8"), D=%
    const rows = data.slice(1)
      .filter(r => r[1] && r[1] !== 'пример')
      .map(r => {
        const scoreStr = String(r[2] || '0/0');
        const scoreNum = parseInt(scoreStr.split('/')[0]) || 0;
        return { name: r[1], score: scoreNum, scoreStr: scoreStr, date: r[0] };
      });

    // Best score per player
    const best = {};
    rows.forEach(r => {
      if (!best[r.name] || r.score > best[r.name].score) {
        best[r.name] = r;
      }
    });

    const top = Object.values(best)
      .sort((a, b) => b.score - a.score)
      .slice(0, 10);

    return jsonResp({ok: true, top: top});
  } catch (err) {
    return jsonResp({ok: false, error: err.toString()});
  }
}

function jsonResp(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

// =================================================================
// ОДНОРАЗОВЫЕ СЕТАПЫ ВКЛАДОК.
// Запускать вручную из редактора Apps Script: выбрать функцию
// в выпадающем списке и нажать «Run» / «Выполнить».
// Если такая вкладка уже есть — функция её НЕ трогает (idempotent).
// =================================================================

function setupTabsForKrepost() {
  // 5-й сайт — Крепость грамотности. 5 игр.
  const TABS = [
    { name: 'Рыцари правды и лжи', ids: ['DA2800', '3CFD06', '5B061D', '93361B', 'EB5527'] },
    { name: 'Снайпер букв',        ids: ['E7025A', '90F970', 'EFFD08', 'AF2C36', 'AB433D'] },
    { name: 'Перевёртыш',          ids: ['62C34C', 'DDCC01', 'A8E929', '298830', '9DE7BD'] },
    { name: 'Форма-мастер',        ids: ['3769DF', '9C7608', '9CE3F5', '6E63C0', '83CB2A'] },
    { name: 'Финал-микс',          ids: ['EB892C', '842CD9', '6D761E', '57623D', '5E14EC', '3F5BC2', 'B73096', '7D4031'] }
  ];
  return createTabsFromSpec_(TABS);
}

function setupTabsForPalitra() {
  // 4-й сайт — Палитра выразительности. Все 5 игр.
  const TABS = [
    {
      name: 'Палитра художника',
      ids: ['B6EA56', '45C7CD', 'E9AF26', '243E3D', '378DF0', 'CE41AB', '909EAC', 'DFFB52']
    },
    {
      name: 'Радуга средств',
      ids: ['2E3089', '1F4932', '75794E', '0CEDC6', 'DCB1A7']
    },
    {
      name: 'Словарь-открытие',
      ids: ['1230A5', 'DAB3AA', '036CE8', '16374D', '4B61DD']
    },
    {
      name: 'Синонимы-близнецы',
      ids: ['0BBC3B', '8316F7', '358D72', '9EAD52', 'F67409']
    },
    {
      name: 'Театр контекстов',
      ids: ['4cD9B6', 'B2D602', 'B65794', '44C089', '6E646D']
    }
  ];
  return createTabsFromSpec_(TABS);
}

function setupTabsForDetektiv() {
  // 3-я игра — Синтаксический детектив. Создаёт 5 вкладок (3 первые + 2 новые).
  const TABS = [
    {
      name: 'Поиск основ',
      ids: ['3212D2', '3C015C', '1F9CF5', 'C4D7E0', 'F0DCC0']
    },
    {
      name: 'Колонны характеристик',
      ids: ['70D356', 'DE5B28', 'DE2E98', '5CCA94', '96F6B0']
    },
    {
      name: 'Правило-сыщик',
      ids: ['06134B', '068B4E', '213749', 'F29B08', '0AA97B']
    },
    {
      name: 'Пунктуация-мозаика',
      ids: ['A70F86', '2B3453', '7C8E12', '3B5CA0', '31A878']
    },
    {
      name: 'Снайпер запятых',
      ids: ['679445', 'A860F6', '9ECF78', '4E4044', 'D90352']
    }
  ];
  return createTabsFromSpec_(TABS);
}

function addNavigationLinks() {
  // Вставляет в верх вкладки «📖 Инструкция» блок-навигатор:
  // 4 столбца по сайтам, в каждом по 5 игр-ссылок.
  // Идемпотентно: при повторном вызове перезаписывает старый блок.
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const baseUrl = ss.getUrl();

  const instr = ss.getSheetByName('📖 Инструкция') || ss.getSheets()[0];

  const SITES = [
    {
      title: '1️⃣ Игротека ОГЭ',
      games: ['Верные характеристики', '5 лишний', 'Крестики-нолики', 'Пунктуация-пазл', 'Правило-пример']
    },
    {
      title: '2️⃣ Лексика',
      games: ['Цветочное поле', 'Лабиринт форм', 'Сборка улья', 'Аквариум', 'Собери котят']
    },
    {
      title: '3️⃣ Детектив',
      games: ['Поиск основ', 'Колонны характеристик', 'Правило-сыщик', 'Пунктуация-мозаика', 'Снайпер запятых']
    },
    {
      title: '4️⃣ Палитра',
      games: ['Палитра художника', 'Радуга средств', 'Словарь-открытие', 'Синонимы-близнецы', 'Театр контекстов']
    }
  ];

  // Если блок уже есть — снести его (заголовок + подзаголовки + 5 игр + разделитель = 8 строк).
  const firstCell = String(instr.getRange(1, 1).getValue() || '');
  if (firstCell.indexOf('Перейти к вкладке') !== -1) {
    instr.deleteRows(1, 8);
  }

  // Вставляем 8 пустых строк в самом верху
  instr.insertRowsBefore(1, 8);

  // Заголовок (объединяем 4 колонки)
  const headerRange = instr.getRange(1, 1, 1, 4);
  headerRange.merge();
  headerRange.setValue('🎯 Перейти к вкладке (тапни на название игры)')
    .setFontWeight('bold')
    .setFontSize(14)
    .setHorizontalAlignment('center')
    .setBackground('#3D2817')
    .setFontColor('#FFE38A');

  // Подзаголовки сайтов
  SITES.forEach((s, col) => {
    instr.getRange(2, col + 1)
      .setValue(s.title)
      .setFontWeight('bold')
      .setBackground('#FFE38A')
      .setHorizontalAlignment('center')
      .setBorder(true, true, true, true, false, false);
  });

  // Игры с гиперссылками
  SITES.forEach((s, col) => {
    s.games.forEach((name, idx) => {
      const sh = ss.getSheetByName(name);
      const cell = instr.getRange(3 + idx, col + 1);
      if (!sh) {
        cell.setValue('(нет вкладки: ' + name + ')').setFontColor('#999').setFontStyle('italic');
        return;
      }
      const url = baseUrl + '#gid=' + sh.getSheetId();
      const rt = SpreadsheetApp.newRichTextValue()
        .setText(name)
        .setLinkUrl(url)
        .build();
      cell.setRichTextValue(rt)
        .setBackground('#FFF8E7')
        .setFontColor('#2A1810')
        .setBorder(true, true, true, true, false, false);
    });
  });

  // Пустая строка-разделитель (строка 8) уже есть.
  // Ширина колонок
  for (let c = 1; c <= 4; c++) instr.setColumnWidth(c, 200);

  Logger.log('✓ Навигационный блок добавлен в верх вкладки «📖 Инструкция».');
  return 'OK';
}

// Универсальная фабрика: создаёт вкладки по спецификации.
// Спецификация: [{name: 'Имя вкладки', ids: ['ID1', 'ID2', ...]}, ...]
function createTabsFromSpec_(spec) {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const log = [];
  spec.forEach(tab => {
    if (ss.getSheetByName(tab.name)) {
      log.push('SKIP (already exists): ' + tab.name);
      return;
    }
    const sheet = ss.insertSheet(tab.name);
    const headers = ['Дата', 'Имя', 'Балл', '% правильных']
      .concat(tab.ids.map(id => '[' + id + ']'));
    sheet.getRange(1, 1, 1, headers.length).setValues([headers]);
    // Шапка жирная + закреплена + узкие колонки ID
    sheet.getRange(1, 1, 1, headers.length).setFontWeight('bold');
    sheet.setFrozenRows(1);
    sheet.setColumnWidth(1, 130); // Дата
    sheet.setColumnWidth(2, 130); // Имя
    sheet.setColumnWidth(3, 80);  // Балл
    sheet.setColumnWidth(4, 90);  // %
    for (let i = 0; i < tab.ids.length; i++) {
      sheet.setColumnWidth(5 + i, 110);
    }
    log.push('CREATED: ' + tab.name + ' (' + tab.ids.length + ' ID-колонок)');
  });
  Logger.log(log.join('\n'));
  return log;
}
