/**
 * ============================================================================
 * PROFESSIONAL SCHOOL MANAGEMENT — UNIFIED GOOGLE SHEETS PDF & SHEET GENERATOR
 * (Single Combined File: replaces both `Code.gs` and `google_sheets_pdf_converter.gs`)
 * ============================================================================
 * Features:
 * 1. Single Unified Script:
 *    - Works with `TemplatePrintService` (Hajari Patrak, Result, Vyaktitva Vikas
 *      multi-page plan printing via `{ xlsx, plan }`).
 *    - Works with `GoogleSheetsPdfService` / `XlsxBrowserPrintService` (direct
 *      `.xlsx` workbook-to-PDF conversion via `{ action: 'convertToPdf', workbookBase64 }`).
 *    - Passes both Developer Panel "Test" checks (`ok: true, service: 'psm-pdf'`
 *      AND `status: 'ok'`).
 * 2. Automatic Required Sheets Generator:
 *    - Run `authorize()` (or `setupRequiredSheets()`) once from the Apps Script
 *      editor toolbar to grant permissions AND automatically create all required
 *      school management tabs with formatted Gujarati/English headers.
 *    - During PDF conversion, if any requested sheet tab is missing in an
 *      uploaded workbook, it is automatically created on the fly so printing
 *      never fails with "Sheet not found".
 * 3. Zero Drive Clutter & 50+ Concurrent Teachers Support:
 *    - Every PDF request creates an isolated temporary Google Sheet and deletes
 *      it immediately in the `finally` block.
 * ============================================================================
 */

var API = 'https://www.googleapis.com';
var MASTER_SPREADSHEET_PROP = 'PSM_MASTER_SPREADSHEET_ID';

/**
 * STEP 1 (RUN ONCE IN APPS SCRIPT EDITOR):
 * Select `authorize` in the top toolbar dropdown and click "Run".
 * Grants Drive + Sheets + UrlFetch permissions and automatically generates
 * the required school sheets.
 */
function authorize() {
  DriveApp.getRootFolder();
  UrlFetchApp.fetch('https://www.google.com');
  var result = setupRequiredSheets();
  Logger.log('Authorization & Required Sheets Setup Complete: ' + JSON.stringify(result));
  return result;
}

/**
 * Alias kept for backward compatibility with older instructions.
 */
function _ensureOAuthScopes() {
  return authorize();
}

/**
 * Automatically creates (or updates) a Google Spreadsheet containing all
 * required school management sheets with clean headers and column formatting.
 * If this script is bound to an existing Google Sheet, it adds the sheets there;
 * otherwise it creates/reuses "PSM_School_Required_Sheets" in Google Drive.
 */
function setupRequiredSheets(customTitle) {
  var ss = null;
  try {
    ss = SpreadsheetApp.getActiveSpreadsheet();
  } catch (_) {}

  var props = PropertiesService.getScriptProperties();
  if (!ss) {
    var savedId = props.getProperty(MASTER_SPREADSHEET_PROP);
    if (savedId) {
      try {
        var existingFile = DriveApp.getFileById(savedId);
        if (!existingFile.isTrashed()) {
          ss = SpreadsheetApp.openById(savedId);
        }
      } catch (_) {
        ss = null;
      }
    }
  }

  if (!ss) {
    var title = String(customTitle || 'PSM_School_Required_Sheets');
    ss = SpreadsheetApp.create(title);
    props.setProperty(MASTER_SPREADSHEET_PROP, ss.getId());
  }

  var requiredSpecs = getRequiredSheetSpecs_();
  var createdOrUpdated = [];

  for (var i = 0; i < requiredSpecs.length; i++) {
    var spec = requiredSpecs[i];
    var sh = ss.getSheetByName(spec.name);
    if (!sh) {
      sh = ss.insertSheet(spec.name);
    }
    if (sh.getLastRow() === 0 && spec.headers && spec.headers.length > 0) {
      var headerRange = sh.getRange(1, 1, 1, spec.headers.length);
      headerRange.setValues([spec.headers]);
      headerRange.setFontWeight('bold');
      headerRange.setBackground('#0B4F6C');
      headerRange.setFontColor('#FFFFFF');
      headerRange.setHorizontalAlignment('center');
      headerRange.setVerticalAlignment('middle');
      sh.setRowHeight(1, 28);
      sh.setFrozenRows(1);
      for (var c = 1; c <= spec.headers.length; c++) {
        sh.setColumnWidth(c, spec.colWidth || 145);
      }
    }
    createdOrUpdated.push(spec.name);
  }

  // Remove default blank "Sheet1" if our required sheets exist
  var defaultSheet = ss.getSheetByName('Sheet1');
  if (defaultSheet && ss.getSheets().length > 1 && defaultSheet.getLastRow() === 0) {
    try {
      ss.deleteSheet(defaultSheet);
    } catch (_) {}
  }

  SpreadsheetApp.flush();
  return {
    ok: true,
    status: 'ok',
    spreadsheetId: ss.getId(),
    spreadsheetUrl: ss.getUrl(),
    sheets: createdOrUpdated
  };
}

/**
 * Definitions of all required sheets automatically generated for easy use.
 */
function getRequiredSheetSpecs_() {
  return [
    {
      name: 'School',
      colWidth: 165,
      headers: [
        'શાળાનું નામ (School Name)',
        'ડાયેસ કોડ (UDISE Code)',
        'શાળાનો પ્રકાર (Boys/Girls/Co-Ed)',
        'ગામ / શહેર (Village/City)',
        'તાલુકો (Taluka)',
        'જિલ્લો (District)',
        'આચાર્યનું નામ (Principal Name)',
        'મોબાઈલ નંબર (Mobile)'
      ]
    },
    {
      name: 'Classes',
      colWidth: 150,
      headers: [
        'ધોરણ (Standard)',
        'વર્ગ / વિભાગ (Section)',
        'વર્ગનું નામ (Class Label)',
        'વર્ગ શિક્ષકનું નામ (Class Teacher)',
        'રિપોર્ટ ગ્રુપ (Report Group)',
        'સ્થિતિ (Active Status)'
      ]
    },
    {
      name: 'Students',
      colWidth: 150,
      headers: [
        'ધોરણ-વર્ગ (Class)',
        'રોલ નંબર (Roll No)',
        'વિદ્યાર્થીનું પૂરું નામ (Student Name)',
        'જાતિ (Boys/Girls)',
        'કેટેગરી (SC/ST/OBC/General)',
        'જન્મ તારીખ (DOB DD/MM/YYYY)',
        'GR નંબર (GR No)',
        'આધાર ડાયેસ UID (Aadhaar UID)',
        'વાલીનો મોબાઈલ (Mobile)',
        'દાખલ તારીખ (Admission Date)',
        'સ્થિતિ (Active/Deactivated)',
        'કમી તારીખ (Leaving Date)',
        'કમી કારણ (Hajari Patrak Reason)'
      ]
    },
    {
      name: 'Teachers',
      colWidth: 165,
      headers: [
        'શિક્ષકનું નામ (Teacher Name)',
        'હોદ્દો / Role (Admin/Teacher)',
        'વર્ગ શિક્ષક વર્ગ (Class Teacher Of)',
        'સોંપેલ વિષયો (Assigned Subjects)',
        'મોબાઈલ નંબર (Mobile)',
        'ઈમેલ (Email)',
        'સ્થિતિ (Status)'
      ]
    },
    {
      name: 'Hajari_Patrak_Tarij',
      colWidth: 155,
      headers: [
        'માસ અને વર્ષ (Month-Year)',
        'ધોરણ-વર્ગ (Class)',
        'ગયા માસને આખરે બાકી (Opening)',
        'ચાલુ માસમાં નવા આવેલ (Admissions)',
        'ચાલુ માસમાં લિ. સર્ટી. લઈ ગયેલ (LC Exits)',
        'સતત ગેરહાજરીથી નામ કમી કરેલ (Absence Exits)',
        'ચાલુ માસને આખરે બાકી (Closing)',
        'કામના દિવસો (Working Days)',
        'કુલ હાજરી (Total Present)',
        'સરેરાશ હાજરી (Avg Attendance)'
      ]
    },
    {
      name: 'PM_POSHAN_MDM',
      colWidth: 150,
      headers: [
        'તારીખ (Date DD/MM/YYYY)',
        'વિભાગ (Group: બાલવાટિકા / ૧ થી ૫ / ૬ થી ૮)',
        'નોંધાયેલ કુમાર (Reg Boys)',
        'નોંધાયેલ કન્યા (Reg Girls)',
        'નોંધાયેલ કુલ (Reg Total)',
        'હાજર કુમાર (Pres Boys)',
        'હાજર કન્યા (Pres Girls)',
        'હાજર કુલ (Pres Total)',
        'MDM લાભાર્થી કુલ (MDM Total)',
        'નાસ્તો લાભાર્થી કુલ (Breakfast Total)'
      ]
    },
    {
      name: 'Result_Summary',
      colWidth: 140,
      headers: [
        'સત્ર (Semester)',
        'ધોરણ (Standard)',
        'વર્ગ (Section)',
        'નોંધાયેલ કુમાર',
        'નોંધાયેલ કન્યા',
        'નોંધાયેલ કુલ',
        'હાજર કુમાર',
        'હાજર કન્યા',
        'હાજર કુલ',
        'ગેરહાજર કુલ',
        'પાસ કુલ',
        'નાપાસ કુલ',
        'ગ્રેડ A કુલ',
        'ગ્રેડ B કુલ',
        'ગ્રેડ C કુલ',
        'ગ્રેડ D કુલ',
        'ગ્રેડ E કુલ'
      ]
    },
    {
      name: 'Rojmel_Cashbook',
      colWidth: 155,
      headers: [
        'તારીખ (Date DD/MM/YYYY)',
        'વાઉચર નંબર (Voucher No)',
        'જમા (આવક) વિગત (Credit Particulars)',
        'જમા રકમ ₹ (Credit Amount)',
        'ઉધાર (જાવક) વિગત (Debit Particulars)',
        'ઉધાર રકમ ₹ (Debit Amount)',
        'ખાતાવહી પાના નં. (Ledger Folio)',
        'સિલક ₹ (Closing Balance)'
      ]
    },
    {
      name: 'Library_Register',
      colWidth: 150,
      headers: [
        'પુસ્તક ક્રમાંક (Book No)',
        'પુસ્તકનું નામ (Book Title)',
        'લેખક (Author)',
        'વિદ્યાર્થીનું નામ (Student Name)',
        'ધોરણ-વર્ગ (Class)',
        'રોલ નંબર (Roll No)',
        'આપ્યા તારીખ (Issue Date)',
        'પરત તારીખ (Return Date)',
        'સ્થિતિ (Status)'
      ]
    },
    {
      name: 'PDF_Logs',
      colWidth: 155,
      headers: [
        'Timestamp',
        'Engine Mode',
        'Document Title',
        'Page Count',
        'Paper Size',
        'Status'
      ]
    }
  ];
}

/**
 * GET handler — answers both `TemplatePrintService.testUrl` (`ok: true, service: 'psm-pdf'`)
 * and `GoogleSheetsPdfService` (`status: 'ok'`), plus optional `?action=setupSheets`.
 */
function doGet(e) {
  var action = (e && e.parameter && e.parameter.action) ? String(e.parameter.action) : 'ping';
  if (action === 'setupSheets') {
    var setupRes = setupRequiredSheets();
    return json_({
      ok: true,
      service: 'psm-pdf',
      version: 2,
      status: 'ok',
      action: action,
      spreadsheetId: setupRes.spreadsheetId,
      spreadsheetUrl: setupRes.spreadsheetUrl,
      sheets: setupRes.sheets,
      message: 'Required sheets generated automatically.'
    });
  }

  return json_({
    ok: true,
    service: 'psm-pdf',
    version: 2,
    status: 'ok',
    action: action,
    message: 'PSM Unified Google Sheets PDF & Sheet Generator is active and ready.'
  });
}

/**
 * POST handler — automatically routes between:
 * 1. Ping / Health Check (`action === 'ping'`)
 * 2. Auto Sheet Setup (`action === 'setupSheets'`)
 * 3. Multi-Page Plan Print (`payload.xlsx && payload.plan` from `TemplatePrintService`)
 * 4. Direct Workbook-to-PDF / Open-in-Sheets (`payload.workbookBase64` from `GoogleSheetsPdfService`)
 */
function doPost(e) {
  var tempFileId = null;
  var keepSheet = false;
  try {
    if (!e || !e.postData || !e.postData.contents) {
      return json_({ ok: false, status: 'error', error: 'Empty POST body.', message: 'Empty POST body.' });
    }

    var payload = JSON.parse(e.postData.contents);
    var action = String(payload.action || '');

    // 1. Health check ping
    if (action === 'ping') {
      return json_({
        ok: true,
        service: 'psm-pdf',
        version: 2,
        status: 'ok',
        message: 'PSM Unified Google Sheets PDF Converter connected successfully!'
      });
    }

    // 2. Automatic required sheets generation
    if (action === 'setupSheets') {
      var info = setupRequiredSheets(payload.title);
      return json_(info);
    }

    var token = ScriptApp.getOAuthToken();

    // 3. Mode A: Multi-page Plan Mode (`Code.gs` / `TemplatePrintService`)
    if (payload.xlsx && payload.plan) {
      var planTitle = String(payload.plan.title || 'psm-print');
      tempFileId = uploadAsSheet_(payload.xlsx, planTitle, token, false);
      var ssPlan = SpreadsheetApp.openById(tempFileId);
      applyEdits_(ssPlan, payload.plan.edits || {});
      var pages = payload.plan.pages || [];
      if (!pages.length) {
        throw new Error('The print plan has no pages.');
      }

      var pageSheets = [];
      for (var i = 0; i < pages.length; i++) {
        pageSheets.push(buildPage_(ssPlan, pages[i], i + 1));
      }

      // Keep only the generated page sheets in the exact plan order
      ssPlan.getSheets().forEach(function (sh) {
        if (pageSheets.indexOf(sh.getName()) < 0 && ssPlan.getSheets().length > 1) {
          ssPlan.deleteSheet(sh);
        }
      });
      pageSheets.forEach(function (name, idx) {
        var target = ssPlan.getSheetByName(name);
        if (target) {
          ssPlan.setActiveSheet(target);
          ssPlan.moveActiveSheet(idx + 1);
        }
      });

      SpreadsheetApp.flush();
      var allVCenter = pages.every(function (p) { return p.vCenter; });
      var pdfBytes = exportPlanPdf_(tempFileId, pages[0], token, allVCenter);
      var encodedPdf = Utilities.base64Encode(pdfBytes);

      return json_({
        ok: true,
        status: 'ok',
        pages: pages.length,
        pdf: encodedPdf,
        pdfBase64: encodedPdf
      });
    }

    // 4. Mode B: Direct Workbook Conversion Mode (`google_sheets_pdf_converter.gs` / `GoogleSheetsPdfService`)
    var workbookBase64 = String(payload.workbookBase64 || payload.xlsx || '').trim();
    if (!workbookBase64) {
      return json_({
        ok: false,
        status: 'error',
        error: 'Missing workbookBase64 or xlsx payload.',
        message: 'Missing workbookBase64 or xlsx payload.'
      });
    }

    var baseName = String(payload.filename || 'PSM_Document')
      .replace(/\.pdf$/i, '')
      .replace(/\.xlsx$/i, '');
    var paperSize = String(payload.paperSize || 'a4').toLowerCase();
    var portrait = payload.portrait === true || String(payload.portrait) === 'true';
    keepSheet = payload.keepSheetInDrive === true || String(payload.keepSheetInDrive) === 'true';
    var onlyOpenSheet = payload.onlyOpenSheet === true || String(payload.onlyOpenSheet) === 'true';

    tempFileId = uploadAsSheet_(workbookBase64, baseName, token, keepSheet);
    var sheetUrl = 'https://docs.google.com/spreadsheets/d/' + tempFileId + '/edit';

    // Ensure at least one sheet exists and insert optional school logo
    var logoBase64 = String(payload.logoBase64 || '').trim();
    if (logoBase64) {
      try {
        var ssDirect = SpreadsheetApp.openById(tempFileId);
        var firstSheet = ssDirect.getSheets()[0] || ssDirect.insertSheet('Sheet1');
        var logoBytes = Utilities.base64Decode(logoBase64);
        var logoBlob = Utilities.newBlob(logoBytes, 'image/png', 'school_logo.png');
        var targetRow = Number(payload.logoRow || 4);
        var targetCol = Number(payload.logoCol || 4);
        var offsetX = Number(payload.logoOffsetX || 12);
        var offsetY = Number(payload.logoOffsetY || 6);
        var img = firstSheet.insertImage(logoBlob, targetCol, targetRow, offsetX, offsetY);
        if (payload.logoWidthPx && payload.logoHeightPx) {
          img.setWidth(Number(payload.logoWidthPx));
          img.setHeight(Number(payload.logoHeightPx));
        }
        SpreadsheetApp.flush();
      } catch (_) {}
    }

    if (keepSheet) {
      try {
        DriveApp.getFileById(tempFileId).setSharing(
          DriveApp.Access.ANYONE_WITH_LINK,
          DriveApp.Permission.EDIT
        );
      } catch (_) {}
    }

    if (onlyOpenSheet) {
      return json_({
        ok: true,
        status: 'ok',
        sheetId: tempFileId,
        sheetUrl: sheetUrl
      });
    }

    var sizeParam = (paperSize === 'legal') ? '5' : '7';
    var scaleParam = String(payload.scale || '4');
    var topMargin = String(payload.topMargin || '0.16');
    var bottomMargin = String(payload.bottomMargin || '0.16');
    var leftMargin = String(payload.leftMargin || '0.16');
    var rightMargin = String(payload.rightMargin || '0.16');

    var exportUrl = 'https://docs.google.com/spreadsheets/d/' + tempFileId + '/export'
      + '?format=pdf'
      + '&size=' + sizeParam
      + '&portrait=' + (portrait ? 'true' : 'false')
      + '&scale=' + scaleParam
      + '&top_margin=' + topMargin
      + '&bottom_margin=' + bottomMargin
      + '&left_margin=' + leftMargin
      + '&right_margin=' + rightMargin
      + '&gridlines=false'
      + '&printtitle=false'
      + '&sheetnames=false'
      + '&pagenum=UNDEFINED'
      + '&horizontal_alignment=CENTER'
      + '&vertical_alignment=TOP';

    var pdfResp = fetchPdfWithRetry_(exportUrl, token);
    var directPdfB64 = Utilities.base64Encode(pdfResp);

    return json_({
      ok: true,
      status: 'ok',
      filename: baseName + '.pdf',
      pdf: directPdfB64,
      pdfBase64: directPdfB64,
      sheetId: keepSheet ? tempFileId : null,
      sheetUrl: keepSheet ? sheetUrl : null
    });
  } catch (err) {
    var msg = String(err && err.message ? err.message : (err && err.stack ? err.stack : err));
    return json_({
      ok: false,
      status: 'error',
      error: msg,
      message: msg
    });
  } finally {
    if (tempFileId && !keepSheet) {
      deleteFile_(tempFileId);
    }
  }
}

/**
 * Uploads a Base64 `.xlsx` workbook to Google Drive and converts it to a Google Sheet.
 */
function uploadAsSheet_(base64, title, token, keepCleanName) {
  var uniqueSuffix = new Date().getTime() + '_' + Math.floor(Math.random() * 1000000);
  var sheetName = keepCleanName ? title : (title + '_temp_' + uniqueSuffix);
  var boundary = '-------psm_xlsx_boundary_' + uniqueSuffix;
  var meta = JSON.stringify({
    name: sheetName,
    mimeType: 'application/vnd.google-apps.spreadsheet'
  });
  var xlsxBytes = Utilities.base64Decode(base64);
  var head = '--' + boundary + '\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n'
    + meta + '\r\n--' + boundary
    + '\r\nContent-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\r\n\r\n';
  var tail = '\r\n--' + boundary + '--';
  var payload = Utilities.newBlob(head).getBytes()
    .concat(xlsxBytes)
    .concat(Utilities.newBlob(tail).getBytes());

  var res = UrlFetchApp.fetch(API + '/upload/drive/v3/files?uploadType=multipart&fields=id,webViewLink', {
    method: 'post',
    contentType: 'multipart/related; boundary=' + boundary,
    payload: payload,
    headers: { Authorization: 'Bearer ' + token },
    muteHttpExceptions: true
  });

  if (res.getResponseCode() < 200 || res.getResponseCode() >= 300) {
    throw new Error('Drive XLSX-to-Sheet upload failed (' + res.getResponseCode() + '): ' + res.getContentText().slice(0, 300));
  }
  return JSON.parse(res.getContentText()).id;
}

/**
 * Ensures a sheet exists by name. If the workbook doesn't have that tab yet,
 * automatically creates it (cloning the first template sheet or creating a new sheet)
 * so the user never gets a "Sheet not found" error.
 */
function ensureSheetByName_(ss, sheetName) {
  var cleanName = String(sheetName || '').trim();
  if (!cleanName) {
    return ss.getSheets()[0] || ss.insertSheet('Sheet1');
  }
  var sh = ss.getSheetByName(cleanName);
  if (sh) return sh;

  // Try case-insensitive match first
  var allSheets = ss.getSheets();
  for (var i = 0; i < allSheets.length; i++) {
    if (allSheets[i].getName().trim().toLowerCase() === cleanName.toLowerCase()) {
      return allSheets[i];
    }
  }

  // Auto-generate the missing sheet by cloning the first sheet if available, or inserting a fresh tab
  if (allSheets.length > 0) {
    try {
      return allSheets[0].copyTo(ss).setName(cleanName);
    } catch (_) {}
  }
  return ss.insertSheet(cleanName);
}

/**
 * Ensures the sheet has at least `minRows` rows and `minCols` columns before setting ranges.
 */
function ensureGridCapacity_(sh, minRows, minCols) {
  var maxR = sh.getMaxRows();
  if (minRows > maxR) {
    sh.insertRowsAfter(maxR, minRows - maxR);
  }
  var maxC = sh.getMaxColumns();
  if (minCols > maxC) {
    sh.insertColumnsAfter(maxC, minCols - maxC);
  }
}

function color_(c) {
  return !c || c === 'none' ? null : c;
}

/**
 * Applies cell values, background fills, and range fills from `plan.edits`.
 * Automatically creates any referenced sheet that is missing.
 */
function applyEdits_(ss, edits) {
  var values = edits.values || {};
  Object.keys(values).forEach(function (name) {
    var sh = ensureSheetByName_(ss, name);
    var cells = values[name];
    Object.keys(cells).forEach(function (a1) {
      var v = cells[a1];
      sh.getRange(a1).setValue(v === '' ? '' : (/^-?\d+(\.\d+)?$/.test(v) ? Number(v) : v));
    });
  });

  var fills = edits.fills || {};
  Object.keys(fills).forEach(function (name) {
    var sh = ensureSheetByName_(ss, name);
    Object.keys(fills[name]).forEach(function (a1) {
      sh.getRange(a1).setBackground(color_(fills[name][a1]));
    });
  });

  (edits.rangeFills || []).forEach(function (f) {
    var sh = ensureSheetByName_(ss, f.sheet);
    var range = sh.getRange(f.range);
    if (f.color === 'cleargrey') {
      var bg = range.getBackgrounds();
      var changed = false;
      for (var r = 0; r < bg.length; r++) {
        for (var c = 0; c < bg[r].length; c++) {
          if (String(bg[r][c]).toLowerCase() === '#d9d9d9') {
            bg[r][c] = null;
            changed = true;
          }
        }
      }
      if (changed) range.setBackgrounds(bg);
    } else {
      range.setBackground(color_(f.color));
    }
  });
}

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

/**
 * Builds a single printed page sheet (`P1`, `P2`, ...) according to `page` specification.
 */
function buildPage_(ss, page, index) {
  var src = ensureSheetByName_(ss, page.sheet);
  var pageSheetName = 'P' + index;
  var existingPageSheet = ss.getSheetByName(pageSheetName);
  if (existingPageSheet) {
    ss.deleteSheet(existingPageSheet);
  }
  var sh = src.copyTo(ss).setName(pageSheetName);
  sh.setFrozenRows(0);
  sh.setFrozenColumns(0);

  var maxNeededRow = 1;
  (page.rows || []).forEach(function (r) { if (r > maxNeededRow) maxNeededRow = r; });
  var maxNeededCol = 1;
  (page.cols || []).forEach(function (c) { if (c > maxNeededCol) maxNeededCol = c; });
  ensureGridCapacity_(sh, maxNeededRow, maxNeededCol);

  var maxCol = sh.getMaxColumns();
  var maxRow = sh.getMaxRows();
  var keepCols = {};
  (page.cols || []).forEach(function (c) { keepCols[c] = true; });
  var keepRows = {};
  (page.rows || []).forEach(function (r) { keepRows[r] = true; });

  sh.showColumns(1, maxCol);
  sh.showRows(1, maxRow);

  var hideC = [];
  for (var c = 1; c <= maxCol; c++) {
    if (!keepCols[c]) hideC.push(c);
  }
  runs_(hideC, function (s, n) { sh.hideColumns(s, n); });

  var hideR = [];
  for (var r = 1; r <= maxRow; r++) {
    if (!keepRows[r]) hideR.push(r);
  }
  runs_(hideR, function (s, n) { sh.hideRows(s, n); });

  (page.cols || []).forEach(function (c) {
    var w = page.colPx && page.colPx[String(c)] ? Number(page.colPx[String(c)]) : 60;
    sh.setColumnWidth(c, Math.max(2, Math.round(w)));
  });

  var byHeight = {};
  (page.rows || []).forEach(function (r) {
    var rawH = page.rowPx && page.rowPx[String(r)] ? Number(page.rowPx[String(r)]) : 20;
    var h = Math.max(2, Math.round(rawH));
    (byHeight[h] = byHeight[h] || []).push(r);
  });
  Object.keys(byHeight).forEach(function (h) {
    runs_(byHeight[h], function (s, n) { sh.setRowHeights(s, n, Number(h)); });
  });

  (page.blankCols || []).forEach(function (c) {
    if (c <= maxCol) sh.getRange(1, c, maxRow, 1).clear();
  });

  if (page.font && page.font.to >= page.font.from) {
    var from = Math.max(1, page.font.from);
    var to = Math.min(maxRow, page.font.to);
    if (to >= from) {
      sh.getRange(from, 1, to - from + 1, maxCol).setFontSize(Math.max(4, Math.round(page.font.pt)));
    }
  }

  if (page.dropSheetImages) {
    sh.getImages().forEach(function (img) { img.remove(); });
  }

  (page.images || []).forEach(function (im) {
    var col = page.cols[0] || 1;
    var row = page.rows[0] || 1;
    var x = im.x || 0;
    var y = im.y || 0;
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

function exportPlanPdf_(id, first, token, middle) {
  var m = (first && first.margins) ? first.margins : { left: 0.2, right: 0.2, top: 0.2, bottom: 0.2 };
  var paper = (first && first.paper) ? String(first.paper).toLowerCase() : 'a4';
  var params = {
    format: 'pdf',
    size: paper === 'legal' ? 'legal' : (paper === 'letter' ? 'letter' : 'A4'),
    portrait: (first && first.landscape) ? 'false' : 'true',
    scale: '4',
    top_margin: m.top,
    bottom_margin: m.bottom,
    left_margin: m.left,
    right_margin: m.right,
    horizontal_alignment: 'CENTER',
    vertical_alignment: middle ? 'MIDDLE' : 'TOP',
    gridlines: 'false',
    printtitle: 'false',
    sheetnames: 'false',
    pagenum: 'UNDEFINED',
    fzr: 'false',
    printnotes: 'false',
    attachment: 'false'
  };
  var q = Object.keys(params).map(function (k) {
    return k + '=' + encodeURIComponent(params[k]);
  }).join('&');
  var url = 'https://docs.google.com/spreadsheets/d/' + id + '/export?' + q;
  return fetchPdfWithRetry_(url, token);
}

function fetchPdfWithRetry_(url, token) {
  for (var attempt = 0; attempt < 4; attempt++) {
    var res = UrlFetchApp.fetch(url, {
      method: 'get',
      headers: { Authorization: 'Bearer ' + token },
      muteHttpExceptions: true
    });
    var code = res.getResponseCode();
    if (code === 200) {
      return res.getBlob().getBytes();
    }
    if (code !== 429 && code < 500) {
      throw new Error('Google Sheets PDF export failed (' + code + '): ' + res.getContentText().slice(0, 250));
    }
    Utilities.sleep(1500 * (attempt + 1));
  }
  throw new Error('Google Sheets PDF service is busy. Please try again in a moment.');
}

function deleteFile_(id) {
  try {
    UrlFetchApp.fetch(API + '/drive/v3/files/' + id, {
      method: 'delete',
      headers: { Authorization: 'Bearer ' + ScriptApp.getOAuthToken() },
      muteHttpExceptions: true
    });
  } catch (e) {
    try {
      DriveApp.getFileById(id).setTrashed(true);
    } catch (_) {}
  }
}

function json_(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}