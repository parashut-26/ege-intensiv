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
