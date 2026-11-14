/**
 * PSM School — Hajari Patrak / Result / Vyaktitva Vikas PDF service.
 *
 * The app sends the filled Excel template (same sheet names as the app's
 * templates) together with a "plan": which rows and columns go on every
 * printed page, their sizes, font size and logo position. This script opens
 * the workbook in Google Sheets, builds one sheet per printed page, exports
 * the PDF and deletes the temporary file at once. Nothing is kept in Drive.
 *
 * Deploy: Deploy ▸ New deployment ▸ Web app
 *         Execute as: Me      Who has access: Anyone
 * Paste the Web app URL (ends with /exec) in the app's Developer screen.
 * Several URLs (from different Google accounts) can be entered separated by
 * commas — the app spreads the work over them.
 */

var API = 'https://www.googleapis.com';

function doGet() {
  return json_({ ok: true, service: 'psm-pdf', version: 1 });
}

function doPost(e) {
  var fileId = null;
  try {
    var body = JSON.parse(e.postData.contents);
    if (!body || !body.xlsx || !body.plan) throw new Error('Missing workbook or plan.');
    var token = ScriptApp.getOAuthToken();
    fileId = uploadAsSheet_(body.xlsx, body.plan.title || 'psm-print', token);
    var ss = SpreadsheetApp.openById(fileId);
    applyEdits_(ss, body.plan.edits || {});
    var pages = body.plan.pages || [];
    if (!pages.length) throw new Error('The plan has no pages.');
    var pageSheets = [];
    for (var i = 0; i < pages.length; i++) {
      pageSheets.push(buildPage_(ss, pages[i], i + 1));
    }
    // Only the page sheets go into the PDF, in plan order.
    ss.getSheets().forEach(function (sh) {
      if (pageSheets.indexOf(sh.getName()) < 0) ss.deleteSheet(sh);
    });
    pageSheets.forEach(function (name, i) {
      ss.setActiveSheet(ss.getSheetByName(name));
      ss.moveActiveSheet(i + 1);
    });
    SpreadsheetApp.flush();
    var pdf = exportPdf_(fileId, pages[0], token, pages.every(function (p) { return p.vCenter; }));
    return json_({ ok: true, pages: pages.length, pdf: Utilities.base64Encode(pdf) });
  } catch (err) {
    return json_({ ok: false, error: String(err && err.message ? err.message : err) });
  } finally {
    if (fileId) deleteFile_(fileId);
  }
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}

/** Uploads the .xlsx and converts it to a Google Sheet; returns the file id. */
function uploadAsSheet_(base64, title, token) {
  var boundary = 'psm' + Utilities.getUuid().replace(/-/g, '');
  var meta = JSON.stringify({ name: title + ' (temp ' + new Date().toISOString() + ')', mimeType: 'application/vnd.google-apps.spreadsheet' });
  var xlsx = Utilities.base64Decode(base64);
  var head = '--' + boundary + '\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n' + meta + '\r\n--' + boundary +
    '\r\nContent-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\r\n\r\n';
  var tail = '\r\n--' + boundary + '--';
  var payload = Utilities.newBlob(head).getBytes().concat(xlsx).concat(Utilities.newBlob(tail).getBytes());
  var res = UrlFetchApp.fetch(API + '/upload/drive/v3/files?uploadType=multipart&fields=id', {
    method: 'post',
    contentType: 'multipart/related; boundary=' + boundary,
    payload: payload,
    headers: { Authorization: 'Bearer ' + token },
    muteHttpExceptions: true,
  });
  if (res.getResponseCode() >= 300) throw new Error('Drive upload failed: ' + res.getContentText().slice(0, 300));
  return JSON.parse(res.getContentText()).id;
}

function deleteFile_(id) {
  try {
    UrlFetchApp.fetch(API + '/drive/v3/files/' + id, {
      method: 'delete',
      headers: { Authorization: 'Bearer ' + ScriptApp.getOAuthToken() },
      muteHttpExceptions: true,
    });
  } catch (e) {
    try { DriveApp.getFileById(id).setTrashed(true); } catch (e2) {}
  }
}

function color_(c) {
  return !c || c === 'none' ? null : c;
}

function applyEdits_(ss, edits) {
  var values = edits.values || {};
  Object.keys(values).forEach(function (name) {
    var sh = ss.getSheetByName(name);
    if (!sh) return;
    var cells = values[name];
    Object.keys(cells).forEach(function (a1) {
      var v = cells[a1];
      sh.getRange(a1).setValue(v === '' ? '' : (/^-?\d+(\.\d+)?$/.test(v) ? Number(v) : v));
    });
  });
  var fills = edits.fills || {};
  Object.keys(fills).forEach(function (name) {
    var sh = ss.getSheetByName(name);
    if (!sh) return;
    Object.keys(fills[name]).forEach(function (a1) {
      sh.getRange(a1).setBackground(color_(fills[name][a1]));
    });
  });
  (edits.rangeFills || []).forEach(function (f) {
    var sh = ss.getSheetByName(f.sheet);
    if (!sh) return;
    var range = sh.getRange(f.range);
    if (f.color === 'cleargrey') {
      var bg = range.getBackgrounds();
      var changed = false;
      for (var r = 0; r < bg.length; r++) {
        for (var c = 0; c < bg[r].length; c++) {
          if (String(bg[r][c]).toLowerCase() === '#d9d9d9') { bg[r][c] = null; changed = true; }
        }
      }
      if (changed) range.setBackgrounds(bg);
    } else {
      range.setBackground(color_(f.color));
    }
  });
}

/** Calls fn(start, count) for each run of consecutive numbers. */
function runs_(list, fn) {
  list = list.slice().sort(function (a, b) { return a - b; });
  var i = 0;
  while (i < list.length) {
    var j = i;
    while (j + 1 < list.length && list[j + 1] === list[j] + 1) j++;
    fn(list[i], j - i + 1);
    i = j + 1;
  }
}

function buildPage_(ss, page, index) {
  var src = ss.getSheetByName(page.sheet);
  if (!src) throw new Error('Sheet not found: ' + page.sheet);
  var sh = src.copyTo(ss).setName('P' + index);
  sh.setFrozenRows(0);
  sh.setFrozenColumns(0);
  var maxCol = sh.getMaxColumns();
  var maxRow = sh.getMaxRows();
  var keepCols = {};
  page.cols.forEach(function (c) { keepCols[c] = true; });
  var keepRows = {};
  page.rows.forEach(function (r) { keepRows[r] = true; });

  sh.showColumns(1, maxCol);
  sh.showRows(1, maxRow);
  var hideC = [];
  for (var c = 1; c <= maxCol; c++) if (!keepCols[c]) hideC.push(c);
  runs_(hideC, function (s, n) { sh.hideColumns(s, n); });
  var hideR = [];
  for (var r = 1; r <= maxRow; r++) if (!keepRows[r]) hideR.push(r);
  runs_(hideR, function (s, n) { sh.hideRows(s, n); });

  page.cols.forEach(function (c) {
    sh.setColumnWidth(c, Math.max(2, Math.round(page.colPx[String(c)])));
  });
  // Rows with the same height are set together.
  var byHeight = {};
  page.rows.forEach(function (r) {
    var h = Math.max(2, Math.round(page.rowPx[String(r)]));
    (byHeight[h] = byHeight[h] || []).push(r);
  });
  Object.keys(byHeight).forEach(function (h) {
    runs_(byHeight[h], function (s, n) { sh.setRowHeights(s, n, Number(h)); });
  });

  (page.blankCols || []).forEach(function (c) {
    if (c <= maxCol) sh.getRange(1, c, maxRow, 1).clear();
  });

  if (page.font && page.font.to >= page.font.from) {
    var from = Math.max(1, page.font.from), to = Math.min(maxRow, page.font.to);
    if (to >= from) sh.getRange(from, 1, to - from + 1, maxCol).setFontSize(Math.max(4, Math.round(page.font.pt)));
  }

  if (page.dropSheetImages) {
    sh.getImages().forEach(function (img) { img.remove(); });
  }
  (page.images || []).forEach(function (im) {
    var col = page.cols[0], row = page.rows[0], x = im.x, y = im.y;
    for (var i = 0; i < page.cols.length; i++) {
      var w = page.colPx[String(page.cols[i])];
      if (x < w || i === page.cols.length - 1) { col = page.cols[i]; break; }
      x -= w;
    }
    for (var k = 0; k < page.rows.length; k++) {
      var h = page.rowPx[String(page.rows[k])];
      if (y < h || k === page.rows.length - 1) { row = page.rows[k]; break; }
      y -= h;
    }
    var blob = Utilities.newBlob(Utilities.base64Decode(im.data), im.mime || 'image/png', 'logo');
    var img = sh.insertImage(blob, col, row, Math.round(x), Math.round(y));
    img.setWidth(Math.round(im.w)).setHeight(Math.round(im.h));
  });
  return sh.getName();
}

function exportPdf_(id, first, token, middle) {
  var m = first.margins || { left: 0.2, right: 0.2, top: 0.2, bottom: 0.2 };
  var params = {
    format: 'pdf',
    size: first.paper === 'legal' ? 'legal' : (first.paper === 'letter' ? 'letter' : 'A4'),
    portrait: first.landscape ? 'false' : 'true',
    scale: '4', // fit every page sheet to one page
    top_margin: m.top, bottom_margin: m.bottom, left_margin: m.left, right_margin: m.right,
    horizontal_alignment: 'CENTER',
    vertical_alignment: middle ? 'MIDDLE' : 'TOP',
    gridlines: 'false',
    printtitle: 'false',
    sheetnames: 'false',
    pagenum: 'UNDEFINED',
    fzr: 'false',
    printnotes: 'false',
    attachment: 'false',
  };
  var q = Object.keys(params).map(function (k) { return k + '=' + encodeURIComponent(params[k]); }).join('&');
  var url = 'https://docs.google.com/spreadsheets/d/' + id + '/export?' + q;
  for (var attempt = 0; attempt < 4; attempt++) {
    var res = UrlFetchApp.fetch(url, { headers: { Authorization: 'Bearer ' + token }, muteHttpExceptions: true });
    var code = res.getResponseCode();
    if (code === 200) return res.getBlob().getBytes();
    if (code !== 429 && code < 500) throw new Error('PDF export failed (' + code + ')');
    Utilities.sleep(1500 * (attempt + 1));
  }
  throw new Error('Google is busy. Please try again in a minute.');
}

/** Run once from the editor to grant permissions (Drive + Sheets). */
function authorize() {
  DriveApp.getRootFolder();
  SpreadsheetApp.create('psm-auth-check').getId();
}
