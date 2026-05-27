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
