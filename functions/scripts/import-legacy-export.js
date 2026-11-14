#!/usr/bin/env node
/**
 * One-time importer for EXPORT_FOR_FIREBASE_MIGRATION.gs bundles.
 *
 * Usage (from functions/):
 *   node scripts/import-legacy-export.js ../school-export.json.gz --dry-run
 *   node scripts/import-legacy-export.js ../school-export.json.gz
 *
 * Requires GOOGLE_APPLICATION_CREDENTIALS and GCLOUD_PROJECT. The import is
 * create-only: it refuses to overwrite an existing school code/document.
 */
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import zlib from 'node:zlib';
import { promisify } from 'node:util';
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const gunzip = promisify(zlib.gunzip);
const inputPath = process.argv[2];
const dryRun = process.argv.includes('--dry-run');
const help = !inputPath || process.argv.includes('--help');
if (help) {
  console.log('Usage: node scripts/import-legacy-export.js <export.json|export.json.gz> [--dry-run]');
  process.exit(inputPath ? 0 : 2);
}
if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error('Set GOOGLE_APPLICATION_CREDENTIALS to a private service-account JSON file. Never put that file in your app or project ZIP.');
  process.exit(2);
}
if (!process.env.GCLOUD_PROJECT && !process.env.GOOGLE_CLOUD_PROJECT) {
  console.error('Set GCLOUD_PROJECT to the target Firebase project ID.');
  process.exit(2);
}

initializeApp({ credential: applicationDefault(), projectId: process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT });
const db = getFirestore();

const txt = v => v === null || v === undefined ? '' : String(v).trim();
const headerKey = v => txt(v).toLowerCase().normalize('NFKC').replace(/[^\p{L}\p{N}]+/gu, '');
const normalizeName = v => txt(v).toLocaleLowerCase('en').replace(/\s+/g, ' ');
const normalizeClass = v => txt(v).replace(/^Class\s+/i, '').replace(/\s+/g, ' ').trim();
const classIdFor = v => {
  const original = normalizeClass(v);
  const clean = original.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 64);
  return clean || `class-${crypto.createHash('sha1').update(txt(v)).digest('hex').slice(0, 12)}`;
};
const hash = v => crypto.createHash('sha256').update(String(v)).digest('hex');
const studentIdFor = (roll, className, name) => txt(roll)
  ? `r_${hash(txt(roll)).slice(0, 20)}`
  : `s_${hash(`${normalizeClass(className)}:${normalizeName(name)}`).slice(0, 20)}`;
const asInt = v => Number.isFinite(Number(v)) ? Math.trunc(Number(v)) : 0;
const blankCats = () => ({ SC: 0, ST: 0, OBC: 0, OTHER: 0 });
const blankBreakdown = () => {
  const out = {};
  for (const g of ['BOYS', 'GIRLS', 'UNSPECIFIED']) {
    out[g] = {};
    for (const c of ['SC', 'ST', 'OBC', 'OTHER']) out[g][c] = { registered: 0, present: 0, mdm: 0, breakfast: 0 };
    out[g]._OVERALL = { registered: 0, present: 0, mdm: 0, breakfast: 0 };
  }
  return out;
};
const normalizeCategory = v => {
  const s = txt(v).toUpperCase().replace(/\s+/g, ' ');
  if (s === 'SC' || s.includes('SCHEDULED CASTE') || s.includes('અ.જા')) return 'SC';
  if (s === 'ST' || s.includes('SCHEDULED TRIBE') || s.includes('અ.જ.જા')) return 'ST';
  if (s === 'OBC' || s.includes('OTHER BACKWARD') || s.includes('બ.પ.')) return 'OBC';
  return 'OTHER';
};
const normalizeGender = (v, schoolType) => {
  const type = txt(schoolType).toLowerCase();
  if (type === 'boys') return 'BOYS';
  if (type === 'girls') return 'GIRLS';
  const g = txt(v).toUpperCase();
  if (['BOYS', 'BOY', 'M', 'MALE', 'છોકરો', 'છોકરા', 'પુરુષ'].includes(g)) return 'BOYS';
  if (['GIRLS', 'GIRL', 'F', 'FEMALE', 'છોકરી', 'છોકરીઓ', 'સ્ત્રી'].includes(g)) return 'GIRLS';
  return 'UNSPECIFIED';
};
const normalizeGroup = (v, label) => {
  const r = txt(v).toUpperCase().replace(/[\s-]+/g, '_');
  if (['BALVATIKA', 'BV'].includes(r)) return 'BALVATIKA';
  if (['1TO5', 'STD_1_TO_5', 'CLASS_1_TO_5', 'CLASS_1_5'].includes(r)) return 'CLASS_1_5';
  if (['6TO8', 'STD_6_TO_8', 'CLASS_6_TO_8', 'CLASS_6_8'].includes(r)) return 'CLASS_6_8';
  const l = normalizeClass(label).toLowerCase();
  if (l.includes('balvatika') || l.includes('બાલવાટિકા')) return 'BALVATIKA';
  const m = l.match(/(?:class\s*)?(\d+)/i); const n = m ? Number(m[1]) : 0;
  if (n >= 1 && n <= 5) return 'CLASS_1_5';
  if (n >= 6 && n <= 8) return 'CLASS_6_8';
  return 'OTHER';
};
function findSheet(workbook, name) {
  return (workbook?.sheets || []).find(s => txt(s.name).toLowerCase() === name.toLowerCase()) || null;
}
function headerIndexes(sheet) {
  const first = (sheet?.values || [])[0] || [];
  const out = {};
  first.forEach((v, i) => { const k = headerKey(v); if (k && out[k] === undefined) out[k] = i; });
  return out;
}
function valueAt(row, indexes, ...names) {
  for (const name of names) {
    const i = indexes[headerKey(name)];
    if (i !== undefined && row[i] !== undefined && row[i] !== null) return row[i];
  }
  return '';
}
function cell(row, i) { return i >= 0 && i < (row || []).length ? row[i] : ''; }
function dateIso(v) {
  if (v instanceof Date && !Number.isNaN(v.getTime())) return v.toISOString().slice(0, 10);
  const s = txt(v);
  const iso = s.match(/^(\d{4}-\d{2}-\d{2})/);
  if (iso) return iso[1];
  const dmy = s.match(/^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$/);
  if (dmy) return `${dmy[3]}-${String(Number(dmy[2])).padStart(2, '0')}-${String(Number(dmy[1])).padStart(2, '0')}`;
  return '';
}
function boolValue(v) {
  const s = txt(v).toLowerCase();
  return v === true || v === 1 || ['true', 'yes', 'y', '1', 'હા', 'હાજર'].includes(s);
}
function workbookConfig(workbook) {
  const sh = findSheet(workbook, 'SchoolConfig'); const out = {};
  for (const row of (sh?.values || []).slice(1)) if (txt(row[0])) out[txt(row[0])] = row[1];
  return out;
}
function readClasses(workbook) {
  const sh = findSheet(workbook, 'Classes');
  const rows = (sh?.values || []).slice(1);
  const idx = headerIndexes(sh || { values: [] });
  const result = [];
  for (const row of rows) {
    const key = txt(valueAt(row, idx, 'classKey', 'key'));
    const sheetName = txt(valueAt(row, idx, 'sheetName', 'className'));
    const rawLabel = sheetName || txt(valueAt(row, idx, 'label')) || normalizeClass(key);
    if (!rawLabel) continue;
    const activeCell = valueAt(row, idx, 'active', 'status');
    const active = activeCell === '' ? true : !['false', 'inactive', '0', 'no'].includes(txt(activeCell).toLowerCase());
    const m = rawLabel.match(/^\s*(\d+)/);
    const standard = txt(valueAt(row, idx, 'standard')) || (m ? m[1] : (rawLabel.toLowerCase().includes('balvatika') || rawLabel.includes('બાલવાટિકા') ? 'BALVATIKA' : rawLabel.split(' ')[0]));
    const section = txt(valueAt(row, idx, 'section')) || ((rawLabel.match(/\b([A-Za-z])$/) || [,''])[1]);
    const reportGroup = normalizeGroup(valueAt(row, idx, 'reportGroup'), rawLabel);
    result.push({ id: classIdFor(rawLabel), key: key || `Class ${rawLabel}`, label: rawLabel, sheetName, standard, section: section.toUpperCase(), reportGroup, active, sortOrder: asInt(valueAt(row, idx, 'sortOrder')) || result.length + 1 });
  }
  return result.sort((a, b) => a.sortOrder - b.sortOrder);
}
function findClassSheet(workbook, c) {
  const names = new Set([txt(c.sheetName).toLowerCase(), txt(c.label).toLowerCase(), txt(c.key).toLowerCase(), `class ${txt(c.label)}`.toLowerCase()]);
  return (workbook?.sheets || []).find(s => names.has(txt(s.name).toLowerCase())) || null;
}
function findHeaderRowAndStart(sheet, schoolType) {
  const rows = sheet?.values || [];
  const expectedStart = String(schoolType).toLowerCase() === 'coed' ? 49 : 26;
  for (let r = 0; r < Math.min(12, rows.length); r++) {
    const row = rows[r] || [];
    for (let c = 20; c < row.length; c++) {
      const h = headerKey(row[c]);
      if (['rollnumber', 'rollno', 'રોલનંબર'].includes(h)) return { headerRow: r, startColumn: c };
    }
  }
  return { headerRow: -1, startColumn: expectedStart };
}
function getProfileValue(headers, row, aliases) {
  const aliasSet = new Set(aliases.map(headerKey));
  for (let i = 0; i < headers.length; i++) if (aliasSet.has(headerKey(headers[i]))) return cell(row, i);
  // Gujarati headers are preserved in their original spelling; aliases may be
  // split over words in older custom templates, so use a soft matching fallback.
  const softAliases = aliases.map(a => txt(a).toLowerCase()).filter(Boolean);
  for (let i = 0; i < headers.length; i++) {
    const h = txt(headers[i]).toLowerCase();
    if (softAliases.some(a => h === a || (a.length > 3 && h.includes(a)))) return cell(row, i);
  }
  return '';
}
function parseStudentProfile(sheet, c, schoolType, genderByClassRoll) {
  const found = findHeaderRowAndStart(sheet, schoolType);
  if (found.headerRow < 0) return [];
  const wholeHeader = sheet.values[found.headerRow] || [];
  const headers = wholeHeader.slice(found.startColumn);
  const students = [];
  for (let r = found.headerRow + 1; r < sheet.values.length; r++) {
    const row = sheet.values[r] || []; const cells = row.slice(found.startColumn);
    const roll = txt(getProfileValue(headers, cells, ['Roll Number', 'Roll No', 'રોલ નંબર', 'રોલનંબર']));
    const name = txt(getProfileValue(headers, cells, ['વિદ્યાર્થીનું નામ', 'Student Name', 'Name', 'નામ']));
    if (!roll && !name) continue;
    const genderLookup = genderByClassRoll.get(`${normalizeClass(c.label).toLowerCase()}|${roll}`) || genderByClassRoll.get(`${normalizeClass(c.label).toLowerCase()}|${normalizeName(name)}`);
    const profile = {
      id: studentIdFor(roll, c.label, name), rollNumber: roll,
      gr: txt(getProfileValue(headers, cells, ['GR નંબર', 'GR Number', 'GR No', 'GR નંબર'])),
      dd: txt(getProfileValue(headers, cells, ['DD', 'જન્મ તારીખ'])),
      mm: txt(getProfileValue(headers, cells, ['MM', 'જન્મ મહિનો'])),
      yyyy: txt(getProfileValue(headers, cells, ['YYYY', 'Year', 'જન્મ વર્ષ'])),
      name,
      caste: txt(getProfileValue(headers, cells, ['પેટા જ્ઞાતિ', 'Caste', 'Sub Caste'])),
      category: normalizeCategory(getProfileValue(headers, cells, ['કેટેગરી', 'Category', 'Category in English'])),
      gender: normalizeGender(getProfileValue(headers, cells, ['Gender', 'લિંગ', 'Sex']) || genderLookup, schoolType),
      mobile: txt(getProfileValue(headers, cells, ['મોબાઈલ નંબર', 'Mobile Number', 'Mobile', 'મોબાઈલ નંબર'])),
      motherName: txt(getProfileValue(headers, cells, ['માતાનું નામ', 'Mother Name'])),
      birthPlace: txt(getProfileValue(headers, cells, ['જન્મ સ્થળ', 'Birth Place'])),
      dobWords: txt(getProfileValue(headers, cells, ['જન્મ તારીખ શબ્દોમાં', 'DOB in Words'])),
      lastSchool: txt(getProfileValue(headers, cells, ['પૂર્વ શાળાનું નામ', 'Last School'])),
      enrollClass: txt(getProfileValue(headers, cells, ['વર્ગ પ્રવેશ', 'Enroll Class'])),
      nameEn: txt(getProfileValue(headers, cells, ['NAME IN ENGLISH', 'Name English'])),
      casteEn: txt(getProfileValue(headers, cells, ['CASTE IN ENGLISH', 'Caste English'])),
      catEn: txt(getProfileValue(headers, cells, ['CATEGORY IN ENG', 'Category English'])),
      motherEn: txt(getProfileValue(headers, cells, ['MOTHER IN ENGLISH', 'Mother English'])),
      birthPlaceEn: txt(getProfileValue(headers, cells, ['BIRTH PLACE IN ENG', 'Birth Place English'])),
      dobEn: txt(getProfileValue(headers, cells, ['DOB IN ENGLISH', 'DOB English'])),
      uid: txt(getProfileValue(headers, cells, ['UID નંબર', 'UID Number', 'UID'])),
      pen: txt(getProfileValue(headers, cells, ['PEN નંબર', 'PEN Number', 'PEN'])),
      aadhaar: txt(getProfileValue(headers, cells, ['આધાર નંબર', 'Aadhaar Number', 'Aadhaar'])),
      bankName: txt(getProfileValue(headers, cells, ['બેંકનું નામ', 'Bank Name'])),
      bankBranch: txt(getProfileValue(headers, cells, ['બેંક બ્રાન્ચ', 'Bank Branch'])),
      accountNumber: txt(getProfileValue(headers, cells, ['એકાઉન્ટ નંબર', 'Account Number'])),
      ifscCode: txt(getProfileValue(headers, cells, ['IFSC કોડ', 'IFSC Code'])),
      customFields: {}, legacyFields: {}
    };
    const knownKeys = new Set(['rollnumber','rollno','રોલનંબર','વિદ્યાર્થીનુંનામ','studentname','name','grનંબર','grnumber','grno','dd','mm','yyyy','year','પેટાજ્ઞાતિ','caste','subcaste','કેટેગરી','category','categoryinenglish','categoryineng','gender','લિંગ','sex','મોબાઈલનંબર','mobilenumber','mobile','માતાનુંનામ','mothername','જન્મસ્થળ','birthplace','જન્મતારીખશબ્દોમાં','dobinwords','પૂર્વશાળાનુંનામ','lastschool','વર્ગપ્રવેશ','enrollclass','nameinenglish','casteinenglish','motherinenglish','birthplaceineng','dobinenglish','uidનંબર','uidnumber','uid','penનંબર','pennumber','pen','આધારનંબર','aadhaarnumber','aadhaar','બેંકનુંનામ','bankname','બેંકબ્રાન્ચ','bankbranch','એકાઉન્ટનંબર','accountnumber','ifsccode','ifscકોડ']);
    headers.forEach((h, i) => {
      const value = cells[i]; if (value === '' || value === null || value === undefined) return;
      const k = headerKey(h);
      if (!knownKeys.has(k)) profile.customFields[txt(h) || `Column ${found.startColumn + i + 1}`] = value;
      profile.legacyFields[txt(h) || `Column ${found.startColumn + i + 1}`] = value;
    });
    profile.className = c.label; profile.classId = c.id; profile.active = true;
    students.push(profile);
  }
  return students;
}
function parseDayFromClassRow(row, schoolType, c) {
  const coed = String(schoolType).toLowerCase() === 'coed';
  const date = dateIso(cell(row, coed ? 0 : 1));
  if (!date) return null;
  const registered = blankCats(), present = blankCats(), mdm = blankCats();
  const bd = blankBreakdown();
  let breakfastTotal = 0;
  if (coed) {
    const starts = { registered: 1, present: 16, mdm: 31 };
    for (const [metric, start] of Object.entries(starts)) {
      const target = metric === 'registered' ? registered : metric === 'present' ? present : mdm;
      const categories = ['SC', 'ST', 'OBC', 'OTHER', 'TOTAL'];
      for (let ci = 0; ci < categories.length; ci++) {
        const groupStart = start + ci * 3;
        const b = asInt(cell(row, groupStart)); const g = asInt(cell(row, groupStart + 1)); const official = asInt(cell(row, groupStart + 2));
        const cat = categories[ci];
        if (cat !== 'TOTAL') target[cat] = official;
        const unknown = Math.max(0, official - b - g);
        bd.BOYS[cat === 'TOTAL' ? '_OVERALL' : cat][metric] = b;
        bd.GIRLS[cat === 'TOTAL' ? '_OVERALL' : cat][metric] = g;
        bd.UNSPECIFIED[cat === 'TOTAL' ? '_OVERALL' : cat][metric] = unknown;
        if (cat !== 'TOTAL') {
          bd.BOYS._OVERALL[metric] += b; bd.GIRLS._OVERALL[metric] += g; bd.UNSPECIFIED._OVERALL[metric] += unknown;
        }
      }
    }
    const bb = asInt(cell(row, 46)), bg = asInt(cell(row, 47)), bt = asInt(cell(row, 48));
    breakfastTotal = bt || (bb + bg);
    bd.BOYS._OVERALL.breakfast = bb; bd.GIRLS._OVERALL.breakfast = bg; bd.UNSPECIFIED._OVERALL.breakfast = Math.max(0, breakfastTotal - bb - bg);
  } else {
    const gender = String(schoolType).toLowerCase() === 'girls' ? 'GIRLS' : 'BOYS';
    ['SC', 'ST', 'OBC', 'OTHER'].forEach((cat, i) => {
      registered[cat] = asInt(cell(row, 2 + i));
      present[cat] = asInt(cell(row, 7 + i));
      mdm[cat] = asInt(cell(row, 12 + i));
      bd[gender][cat].registered = registered[cat]; bd[gender][cat].present = present[cat]; bd[gender][cat].mdm = mdm[cat];
      bd[gender]._OVERALL.registered += registered[cat]; bd[gender]._OVERALL.present += present[cat]; bd[gender]._OVERALL.mdm += mdm[cat];
    });
    breakfastTotal = asInt(cell(row, 17)); bd[gender]._OVERALL.breakfast = breakfastTotal;
  }
  return { date, classKey: c.key, className: c.label, reportGroup: c.reportGroup, registered, present, mdm, breakfastTotal, genderBreakdown: bd, attendanceMode: 'imported', studentDetailsSaved: false, source: 'google-sheets-migration' };
}
function mergeGenderSummary(day, entry, schoolType) {
  const category = normalizeCategory(entry.category); const gender = normalizeGender(entry.gender, schoolType);
  day.genderBreakdown ||= blankBreakdown();
  day.genderBreakdown[gender] ||= {};
  day.genderBreakdown[gender][category] ||= { registered: 0, present: 0, mdm: 0, breakfast: 0 };
  const map = { registered: entry.registered, present: entry.present, mdm: entry.mdm, breakfast: entry.breakfast };
  for (const [k, v] of Object.entries(map)) {
    if (v === undefined || v === '') continue;
    day.genderBreakdown[gender][category][k] = asInt(v);
    if (day.summaryOnly && ['registered','present','mdm'].includes(k)) day[k][category] += asInt(v);
    if (day.summaryOnly && k === 'breakfast') day.breakfastTotal += asInt(v);
  }
}
function parseTeachers(workbook) {
  const sh = findSheet(workbook, 'Teachers'); const idx = headerIndexes(sh || { values: [] }); const out = [];
  for (const row of (sh?.values || []).slice(1)) {
    const name = txt(valueAt(row, idx, 'Name', 'Teacher Name'));
    if (!name) continue;
    const status = txt(valueAt(row, idx, 'Status', 'Active')).toLowerCase();
    const role = txt(valueAt(row, idx, 'Role'), 'teacher').toLowerCase();
    const rawClasses = valueAt(row, idx, 'Classes', 'Assigned Class');
    const classes = txt(rawClasses) === '__ALL__' || role === 'admin' ? ['__ALL__'] : txt(rawClasses).split(/[,;]+/).map(txt).filter(Boolean);
    const pinHash = txt(valueAt(row, idx, 'PIN', 'pinHash'));
    out.push({ id: `t_${hash(normalizeName(name)).slice(0, 24)}`, name, normalizedName: normalizeName(name), role, classes, active: !['inactive','false','0','no'].includes(status), email: txt(valueAt(row, idx, 'Email')), displayName: txt(valueAt(row, idx, 'Display Name') || name), pinHash: /^HASH\$[^$]+\$[a-f0-9]+$/i.test(pinHash) ? pinHash : '', pinSalt: (pinHash.match(/^HASH\$([^$]+)\$/i) || [,''])[1] || '', requiresPinReset: !/^HASH\$[^$]+\$[a-f0-9]+$/i.test(pinHash) });
  }
  return out;
}

const DEFAULT_SUBJECTS_PRIMARY = ['ગુજરાતી', 'ગણિત', 'હિન્દી', 'પર્યાવરણ', 'અંગ્રેજી'];
const DEFAULT_SUBJECTS_UPPER = ['ગુજરાતી', 'ગણિત', 'હિન્દી', 'સામાજિક વિજ્ઞાન', 'અંગ્રેજી', 'વિજ્ઞાન', 'સંસ્કૃત'];
const DEFAULT_VV_SENTENCES = [
  'શાળામાં નિયમિત આવે છે.', 'પ્રાર્થના સંમેલનમાં નિયમિત સામેલ થાય છે.', 'શાળાની સ્વચ્છતા જાળવે છે.',
  'બીજા વિદ્યાર્થીઓને મદદરૂપ થાય છે.', 'સોંપેલું કાર્ય સારી રીતે કરે છે.', 'કોઈપણ કાર્ય કરવામાં તત્પરતા દાખવે છે.',
  'નવીન બાબત ઉત્સાહપૂર્વક શીખે છે.', 'દરેક કાર્યમાં સમયનું પાલન કરે છે.', 'શિક્ષણ પ્રત્યે હકારાત્મક વલણ ધરાવે છે.',
  'શાળા મિલકતની જાળવણી રાખે છે.', 'સહાધ્યાયી પ્રત્યે સહયોગ દાખવે છે.', 'વ્યક્તિગત સ્વચ્છતા અને સુઘડતા જાળવે છે.',
  'પર્યાવરણની સમતુલા જાળવવામાં ઉપયોગી થાય છે.', 'શિક્ષકનો આદર જાળવે છે.', 'ઈતર વાંચન',
  'ભાષા શુદ્ધિ સાથેનું મરોડદાર અક્ષરલેખન', 'મૌલિક વાર્તા કથન / વક્તવ્ય', 'સર્જનાત્મક લેખન',
  'ગાન / વાદન (અભિનય, બાળગીત વગેરે)', 'નાટ્ય / નૃત્ય / વેશભૂષા / અભિનય',
  'ચિત્રમાં રેખાંકન સ્પષ્ટ અને સુંદર કરે છે.', 'ચિત્રમાં રંગપૂરણી સારી રીતે કરે છે.', 'ચિટક કામ કરે છે.',
  'યૌગિક ક્રિયાઓ ઉત્સાહપૂર્વક કરે છે.', 'સરળ આસનો ઉત્સાહપૂર્વક કરે છે.', 'સાંઘિક રમતો કૌશલ્યપૂર્વક રમે છે.',
  'ખેલકૂદ અને જિમ્નાસ્ટિક ગતિમેળ અને લયબદ્ધ રીતે કરે છે.', 'ઈનડોર રમત રમવામાં રસ ધરાવે છે.', 'ઉત્સવ ઉજવણી',
  'વિશેષ દિન ઉજવણી', 'કાર્યક્રમનું સંચાલન કરવામાં ઉત્સુકતા દાખવે છે.', 'પ્રશ્નમંચ (ક્વિઝ) માં ભાગીદારી',
  'મૂલ્ય શિક્ષણની પ્રવૃત્તિમાં ભાગીદારી', 'વિવિધ સ્પર્ધાઓ', 'હસ્ત લિખિત અંકો બનાવવા, પ્રદર્શનમાં ભાગીદારી',
  'ઈકો ક્લબની પ્રવૃત્તિ', 'પ્રવાસ પર્યટન / મુલાકાત', 'માટીકામ / બાગકામ / શાળા સુશોભન',
  'કાગળકામ / ટી. એલ. એમ. નિર્માણમાં સહયોગ', 'વડીલો, અશક્તો અને બિમાર વ્યક્તિને મદદરૂપ થાય'
];
function resultSheetCandidates(className, suffix = '') {
  const cleaned = normalizeClass(className);
  const noSpace = cleaned.replace(/\s+/g, '');
  return suffix
    ? [`${cleaned} ${suffix}`, `${noSpace} ${suffix}`, `Class ${cleaned} ${suffix}`, `Class ${noSpace} ${suffix}`].map(x=>x.toLowerCase())
    : [cleaned, noSpace, `Class ${cleaned}`, `Class ${noSpace}`].map(x=>x.toLowerCase());
}
function findResultSheet(workbook, className, suffix = '') {
  const candidates = new Set(resultSheetCandidates(className, suffix));
  return (workbook?.sheets || []).find(s => candidates.has(txt(s.name).toLowerCase())) || null;
}
function parseSubjectList(config, className) {
  const code = normalizeClass(className);
  let raw = config[`SUBJECTS_${code}`] ?? config[`SUBJECTS_${code.replace(/\s+/g, '')}`];
  if (typeof raw === 'string') { try { raw = JSON.parse(raw); } catch { raw = null; } }
  if (Array.isArray(raw) && raw.length) return raw.map(txt).filter(Boolean);
  const m = code.match(/(\d+)/); const n = m ? Number(m[1]) : 0;
  return (n >= 6 && n <= 8 ? DEFAULT_SUBJECTS_UPPER : DEFAULT_SUBJECTS_PRIMARY).slice();
}
function parseBool(v, fallback = true) {
  if (v === undefined || v === null || v === '') return fallback;
  const s = txt(v).toLowerCase();
  return !['false','no','0','ના','n'].includes(s);
}
function intCell(row, index) { return asInt(cell(row,index)); }
function migrateResultForClass(resultWorkbook, classCfg, school, genderByClassRoll) {
  const config = workbookConfig(resultWorkbook);
  const className = classCfg.label;
  const subjects = parseSubjectList(config, className);
  const master = findResultSheet(resultWorkbook, className);
  const s1 = findResultSheet(resultWorkbook, className, 'FIRST SEM RESULT');
  const s2 = findResultSheet(resultWorkbook, className, 'SECOND SEM RESULT');
  const vv1 = findResultSheet(resultWorkbook, className, 'FIRST SEM VYAKTITV VIKAS');
  const vv2 = findResultSheet(resultWorkbook, className, 'SECOND SEM VYAKTITV VIKAS');
  const front1 = findResultSheet(resultWorkbook, className, 'FIRST SEM FRONT PAGE');
  if (!master && !s1 && !s2) return null;
  const masterRows = (master?.values || []).slice(1).map((r,i)=>({r,sourceIndex:i})).filter(o=>txt(cell(o.r,1)) && !txt(cell(o.r,1)).toUpperCase().includes('STUDENT NAME') && !txt(cell(o.r,0)).toUpperCase().includes('ROLL'));
  const s1Rows = (s1?.values || []).slice(6);
  const s2Rows = (s2?.values || []).slice(6);
  const vv1Rows = (vv1?.values || []).slice(5);
  const vv2Rows = (vv2?.values || []).slice(5);
  const studentCount = Math.max(masterRows.length, s1Rows.filter(r=>txt(cell(r,1))).length, s2Rows.filter(r=>txt(cell(r,1))).length);
  const s1SentencesRaw = (vv1?.values || [])[4] || [];
  const vvSentences = Array.from({length:40},(_,i)=>txt(cell(s1SentencesRaw,3+i)) || DEFAULT_VV_SENTENCES[i] || `વ્યક્તિત્વ વિકાસ ${i+1}`);
  const genderByRollName = genderByClassRoll || new Map();
  const students = [];
  for (let i=0;i<studentCount;i++) {
    const m = masterRows[i]?.r || []; const r1=s1Rows[i]||[]; const r2=s2Rows[i]||[]; const v1=vv1Rows[i]||[]; const v2=vv2Rows[i]||[];
    const roll=txt(cell(m,0)||cell(r1,0)||cell(r2,0)||String(i+1));
    const name=txt(cell(m,1)||cell(r1,1)||cell(r2,1)); if(!name) continue;
    const studiedInSem2=parseBool(cell(m,12), true);
    const sem1={}; const sem2={};
    for(let si=0;si<subjects.length;si++) {
      const sub=subjects[si]; const b1=8+si*5; const b2=8+si*8;
      sem1[sub]={a:intCell(r1,b1) || intCell(r2,b2),s:intCell(r1,b1+1)||intCell(r2,b2+1),sw:intCell(r1,b1+2)||intCell(r2,b2+2)};
      sem2[sub]=studiedInSem2?{a:intCell(r2,b2+3),s:intCell(r2,b2+4),sw:intCell(r2,b2+5)}:{a:0,s:0,sw:0};
    }
    let s1SentenceMarks=Array.from({length:40},(_,j)=>intCell(v1,3+j));
    let s2SentenceMarks=Array.from({length:40},(_,j)=>studiedInSem2?intCell(v2,3+j):0);
    const vv1Total=intCell(v1,43)||intCell(r1,8+subjects.length*5);
    const vv2Total=studiedInSem2?intCell(v2,43):0;
    // Do not fabricate individual sentence marks from the legacy total; retain the exact total and available marks only.
    const genderKeyRoll=`${normalizeClass(className).toLowerCase()}|${roll}`;
    const genderKeyName=`${normalizeClass(className).toLowerCase()}|${normalizeName(name)}`;
    const gender=normalizeGender(genderByRollName.get(genderKeyRoll)||genderByRollName.get(genderKeyName)||'', school.schoolType);
    students.push({
      id:studentIdFor(roll,className,name), sheetRow:7+i, masterRow:2+(masterRows[i]?.sourceIndex??i),
      roll,name,category:txt(cell(m,2)||cell(r1,2)||cell(r2,2),'બક્ષીપંચ'),gender,
      dd:txt(cell(m,3)||cell(r1,4)||cell(r2,4)),mm:txt(cell(m,4)||cell(r1,5)||cell(r2,5)),yyyy:txt(cell(m,5)||cell(r1,6)||cell(r2,6)),
      uid:txt(cell(m,6)),pen:txt(cell(m,7)),mobile:txt(cell(m,8)),fatherName:txt(cell(m,9)),motherName:txt(cell(m,10)),address:txt(cell(m,11)),
      studiedInSem2,gr:txt(cell(m,13)||cell(r1,3)||cell(r2,3)),presentDays:intCell(m,14)||intCell(r1,7),presentDays2:intCell(m,15)||intCell(r2,7),
      standard:txt(cell(m,16)||className),isDivyang:['yes','y','true','1','હા'].includes(txt(cell(m,17)).toLowerCase()),
      sem1,sem2,vv1:vv1Total,vv2:vv2Total,vv1Sentences:s1SentenceMarks,vv2Sentences:s2SentenceMarks,
      caste:'',birthPlace:'',dobWords:'',lastSchool:''
    });
  }
  const front1Values=front1?.values||[];
  const teacherName=txt(cell(front1Values[9],1)).replace('વર્ગ શિક્ષકનું નામ :-','').trim();
  const resultDate=txt(cell(front1Values[7],7)).replace('પરિણામની તારીખ :-','').trim() || txt(config.resultDate, school.resultDate||'30/04/2027');
  const academicYear=txt(cell(front1Values[10],13)).replace('વર્ષ :-','').trim() || txt(config.academicYear,school.academicYear||'2026 - 27');
  return {
    className,subjects,vvSentences,students,teacherName,resultDate,academicYear,
    sem1Locked:txt(config[`LOCK_1_${className}`]).toLowerCase()==='true'||txt(config.LOCK_1_ALL).toLowerCase()==='true',
    sem2Locked:txt(config[`LOCK_2_${className}`]).toLowerCase()==='true'||txt(config.LOCK_2_ALL).toLowerCase()==='true',
    updatedAt:FieldValue.serverTimestamp(), migratedAt:FieldValue.serverTimestamp(), source:'apps-script-migration'
  };
}

async function loadBundle() {
  const fullPath = path.resolve(inputPath);
  let buffer = fs.readFileSync(fullPath);
  if (fullPath.toLowerCase().endsWith('.gz')) buffer = await gunzip(buffer);
  const bundle = JSON.parse(buffer.toString('utf8'));
  if (bundle.format !== 'professional-school-management-firebase-migration' || bundle.version !== 1) throw new Error('Unsupported export format or version.');
  if (!bundle.school?.schoolCode || !bundle.attendanceWorkbook || !bundle.resultWorkbook) throw new Error('Export is missing a school code or workbook data.');
  return bundle;
}
async function commitOps(ops) {
  for (let offset = 0; offset < ops.length; offset += 400) {
    const batch = db.batch();
    for (const op of ops.slice(offset, offset + 400)) batch.set(op.ref, op.data, op.options || { merge: true });
    await batch.commit();
  }
}
async function main() {
  const bundle = await loadBundle();
  const source = bundle.school;
  const schoolCode = txt(source.schoolCode).toUpperCase();
  const existing = await db.collection('schools').where('schoolCode', '==', schoolCode).limit(1).get();
  let schoolId = txt(source.schoolId) && !txt(source.schoolId).includes('/') ? txt(source.schoolId) : crypto.randomUUID();
  let resumeMigration = false;
  if (!existing.empty) {
    const current = existing.docs[0]; const currentData = current.data();
    if (currentData.source === 'apps-script-migration' && currentData.migrationVersion === 1) {
      schoolId = current.id; resumeMigration = true;
      console.warn(`Found an incomplete migration for ${schoolCode}; safely resuming with merge writes.`);
    } else {
      throw new Error(`School code ${schoolCode} already exists in Firestore. Import aborted; this script never overwrites a non-migration school.`);
    }
  } else {
    const idSnap = await db.collection('schools').doc(schoolId).get();
    if (idSnap.exists) {
      const existingData = idSnap.data();
      if (existingData.source === 'apps-script-migration' && existingData.migrationVersion === 1 && txt(existingData.schoolCode).toUpperCase() === schoolCode) {
        resumeMigration = true;
      } else {
        throw new Error(`Firestore document ID ${schoolId} is already occupied by another school. Import aborted.`);
      }
    }
  }
  const schoolType = ['boys','girls','coed'].includes(txt(source.schoolType).toLowerCase()) ? txt(source.schoolType).toLowerCase() : 'coed';
  const attConfig = workbookConfig(bundle.attendanceWorkbook);
  const schoolConfig = { ...source, ...Object.fromEntries(Object.entries(attConfig).filter(([k]) => ['village','taluka','district','schoolDiseCode','educationAuthorityName','centerName','crcName','medium','academicYear','resultDate','reportGenderSplitEnabled'].includes(k))) };
  const classes = readClasses(bundle.attendanceWorkbook);
  if (!classes.length) throw new Error('No Classes sheet rows were found; import aborted instead of guessing class names.');
  const teachers = parseTeachers(bundle.attendanceWorkbook);
  const adminWithHash = teachers.some(t => t.active && t.role === 'admin' && t.pinHash);
  if (!adminWithHash) throw new Error('No active administrator has a recognised HASH$salt$sha256 PIN. Import stopped to avoid locking the school out. Reset the admin PIN in Apps Script first, export again, and retry.');
  const teacherDirectory = teachers.map(t => ({ id: t.id, name: t.name, role: t.role, classes: t.classes, active: t.active }));
  const schoolDoc = {
    schoolCode, schoolName: txt(schoolConfig.schoolName, 'School'), schoolType,
    status: txt(schoolConfig.status, 'active').toLowerCase() === 'inactive' ? 'inactive' : 'active',
    logoUrl: txt(schoolConfig.logoUrl), reportGenderSplitEnabled: schoolConfig.reportGenderSplitEnabled === false || String(schoolConfig.reportGenderSplitEnabled).toLowerCase() === 'false' ? false : true,
    ownerName: txt(schoolConfig.ownerName), ownerEmail: txt(schoolConfig.ownerEmail), plan: txt(schoolConfig.plan, 'Standard'),
    village: txt(schoolConfig.village), taluka: txt(schoolConfig.taluka), district: txt(schoolConfig.district),
    schoolDiseCode: txt(schoolConfig.schoolDiseCode), educationAuthorityName: txt(schoolConfig.educationAuthorityName),
    centerName: txt(schoolConfig.centerName), crcName: txt(schoolConfig.crcName), medium: txt(schoolConfig.medium, 'Gujarati'),
    academicYear: txt(schoolConfig.academicYear, '2026 - 27'), resultDate: txt(schoolConfig.resultDate, '30/04/2027'),
    classes, teacherDirectory, source: 'apps-script-migration', migrationVersion: 1,
    createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()
  };
  const classDocs = classes.map(c => ({ ref: db.collection('schools').doc(schoolId).collection('classes').doc(c.id), data: { ...c, rosterLite: [], migratedAt: FieldValue.serverTimestamp() } }));
  const teacherDocs = teachers.map(t => ({ ref: db.collection('schools').doc(schoolId).collection('teachers').doc(t.id), data: { name:t.name, normalizedName:t.normalizedName, role:t.role, classes:t.classes, active:t.active, email:t.email, displayName:t.displayName, pinHash:t.pinHash, pinSalt:t.pinSalt, requiresPinReset:t.requiresPinReset, createdAt:FieldValue.serverTimestamp(), migratedAt:FieldValue.serverTimestamp() } }));
  const attendanceSheetByClass = new Map();
  for (const c of classes) attendanceSheetByClass.set(c.id, findClassSheet(bundle.attendanceWorkbook, c));
  const genderByClassRoll = new Map();
  const genderSheet = findSheet(bundle.attendanceWorkbook, 'StudentGender');
  const gIdx = headerIndexes(genderSheet || { values: [] });
  for (const row of (genderSheet?.values || []).slice(1)) {
    const className = normalizeClass(valueAt(row, gIdx, 'Class', 'Class Name')).toLowerCase();
    const roll = txt(valueAt(row, gIdx, 'Roll Number', 'Roll')); const name = normalizeName(valueAt(row, gIdx, 'Student Name', 'Name'));
    const gender = txt(valueAt(row, gIdx, 'Gender'));
    if (className && roll) genderByClassRoll.set(`${className}|${roll}`, gender);
    if (className && name) genderByClassRoll.set(`${className}|${name}`, gender);
  }
  const ops = [{ ref: db.collection('schools').doc(schoolId), data: schoolDoc, options: { merge: resumeMigration } }, ...classDocs, ...teacherDocs];
  const counts = { classes: classes.length, teachers: teachers.length, students: 0, attendanceDays: 0, registrationChanges: 0, resultClasses: 0, resultStudents: 0, sheetsWithoutClassMatch: 0 };
  const classRuntime = new Map();
  for (const c of classes) {
    const sheet = attendanceSheetByClass.get(c.id);
    const students = sheet ? parseStudentProfile(sheet, c, schoolType, genderByClassRoll) : [];
    if (!sheet) counts.sheetsWithoutClassMatch++;
    counts.students += students.length;
    const rosterLite = students.map(s => ({ id:s.id, rollNumber:s.rollNumber, gr:s.gr, dd:s.dd, mm:s.mm, yyyy:s.yyyy, name:s.name, caste:s.caste, category:s.category, gender:s.gender, mobile:s.mobile, motherName:s.motherName, birthPlace:s.birthPlace, dobWords:s.dobWords, lastSchool:s.lastSchool, enrollClass:s.enrollClass, nameEn:s.nameEn, casteEn:s.casteEn, catEn:s.catEn, motherEn:s.motherEn, birthPlaceEn:s.birthPlaceEn, dobEn:s.dobEn, uid:s.uid, pen:s.pen, aadhaar:s.aadhaar, bankName:s.bankName, bankBranch:s.bankBranch, accountNumber:s.accountNumber, ifscCode:s.ifscCode, customFields:s.customFields }));
    classRuntime.set(c.id, { c, students, rosterLite, days: new Map(), rollToId: new Map() });
    students.forEach(s => { if (s.rollNumber) classRuntime.get(c.id).rollToId.set(s.rollNumber, s.id); });
    const classRef = db.collection('schools').doc(schoolId).collection('classes').doc(c.id);
    ops.push({ ref: classRef, data: { ...c, rosterLite, migratedStudentCount: students.length, migratedAt: FieldValue.serverTimestamp() }, options: { merge:true } });
    for (const s of students) ops.push({ ref: classRef.collection('students').doc(s.id), data: { ...s, migratedAt:FieldValue.serverTimestamp() }, options:{ merge:true } });
    if (sheet) {
      for (const row of (sheet.values || [])) {
        const day = parseDayFromClassRow(row, schoolType, c);
        if (!day) continue;
        const key = day.date;
        const previous = classRuntime.get(c.id).days.get(key);
        if (!previous) classRuntime.get(c.id).days.set(key, day);
        else classRuntime.get(c.id).days.set(key, day);
      }
    }
  }
  // Migrate the current result state (master roster, semester marks and VV data)
  // into each class's results/current document. Raw result workbook sheets remain
  // inside the restricted source export so unusual legacy templates can be audited.
  
  for (const c of classes) {
    const resultData = migrateResultForClass(bundle.resultWorkbook, c, { ...schoolConfig, schoolType }, genderByClassRoll);
    if (!resultData) continue;
    const resultRef = db.collection('schools').doc(schoolId).collection('classes').doc(c.id).collection('results').doc('current');
    ops.push({ ref: resultRef, data: resultData, options: { merge: true } });
    counts.resultClasses++;
    counts.resultStudents += resultData.students.length;
  }
  // Prefer explicit saved gender summaries where they exist, without guessing a
  // missing gender split from aggregate-only historic values.
  const gs = findSheet(bundle.attendanceWorkbook, 'AttendanceGenderSummary');
  const gsIdx = headerIndexes(gs || { values: [] });
  for (const row of (gs?.values || []).slice(1)) {
    const date = dateIso(valueAt(row, gsIdx, 'Date')); const className = normalizeClass(valueAt(row, gsIdx, 'Class', 'Class Name'));
    if (!date || !className) continue;
    const c = classes.find(x => normalizeClass(x.label).toLowerCase() === className.toLowerCase() || normalizeClass(x.key).toLowerCase() === className.toLowerCase());
    if (!c) continue;
    const rt = classRuntime.get(c.id); let day = rt.days.get(date);
    if (!day) { day = { date, classKey:c.key, className:c.label, reportGroup:c.reportGroup, registered:blankCats(), present:blankCats(), mdm:blankCats(), breakfastTotal:0, genderBreakdown:blankBreakdown(), attendanceMode:'imported-summary', source:'google-sheets-migration', summaryOnly:true }; rt.days.set(date,day); }
    const cat = normalizeCategory(valueAt(row, gsIdx, 'Category'));
    mergeGenderSummary(day, { category:cat, gender:valueAt(row, gsIdx, 'Gender'), registered:valueAt(row, gsIdx, 'Registered'), present:valueAt(row, gsIdx, 'Present'), mdm:valueAt(row, gsIdx, 'PM Poshan', 'MDM'), breakfast:valueAt(row, gsIdx, 'Breakfast') }, schoolType);
  }
  // Add per-student attendance flags, when the legacy AttendanceDetails sheet exists.
  const details = findSheet(bundle.attendanceWorkbook, 'AttendanceDetails'); const dIdx = headerIndexes(details || { values: [] });
  for (const row of (details?.values || []).slice(1)) {
    const date = dateIso(valueAt(row,dIdx,'Date')); const className = normalizeClass(valueAt(row,dIdx,'Class','Class Name'));
    if (!date || !className) continue;
    const c = classes.find(x => normalizeClass(x.label).toLowerCase() === className.toLowerCase() || normalizeClass(x.key).toLowerCase() === className.toLowerCase());
    if (!c) continue;
    const rt = classRuntime.get(c.id); let day = rt.days.get(date);
    if (!day) { day = {date,classKey:c.key,className:c.label,reportGroup:c.reportGroup,registered:blankCats(),present:blankCats(),mdm:blankCats(),breakfastTotal:0,genderBreakdown:blankBreakdown(),attendanceMode:'student',studentDetailsSaved:true,source:'google-sheets-migration'}; rt.days.set(date,day); }
    const roll = txt(valueAt(row,dIdx,'Roll Number','Roll')); const studentId = txt(valueAt(row,dIdx,'Student ID','Student Id')) || rt.rollToId.get(roll) || studentIdFor(roll,c.label,valueAt(row,dIdx,'Name','Student Name'));
    day.studentFlags ||= {}; const present = boolValue(valueAt(row,dIdx,'Present')); day.studentFlags[studentId] = {present,mdm:present && boolValue(valueAt(row,dIdx,'MDM','PM Poshan')),breakfast:present && boolValue(valueAt(row,dIdx,'Breakfast'))};
    day.attendanceMode = 'student'; day.studentDetailsSaved = true;
  }
  // Convert history to sparse change points: only write a RegistrationHistory
  // document when the registration value differs from the last saved effective value.
  for (const rt of classRuntime.values()) {
    const sortedDays = [...rt.days.values()].sort((a,b) => a.date.localeCompare(b.date));
    let previousRegistration = null;
    for (const day of sortedDays) {
      if (!day.genderBreakdown) day.genderBreakdown = blankBreakdown();
      const classRef = db.collection('schools').doc(schoolId).collection('classes').doc(rt.c.id);
      const dayRef = classRef.collection('attendanceDays').doc(day.date);
      const { summaryOnly, ...dayToSave } = day;
      ops.push({ ref:dayRef, data:{...dayToSave, updatedAt:FieldValue.serverTimestamp(), migratedAt:FieldValue.serverTimestamp()}, options:{merge:true} });
      counts.attendanceDays++;
      if (!previousRegistration || JSON.stringify(previousRegistration)!==JSON.stringify(day.registered)) {
        ops.push({ ref:classRef.collection('registrationChanges').doc(day.date), data:{date:day.date,registered:day.registered,updatedAt:FieldValue.serverTimestamp(),source:'apps-script-migration'}, options:{merge:true} });
        counts.registrationChanges++;
        previousRegistration = day.registered;
      }
    }
  }
  console.log('Migration plan:', JSON.stringify({ schoolCode, schoolId, ...counts, dryRun }, null, 2));
  if (dryRun) {
    console.log('Dry run only. No Firestore documents were written. Fix any warnings before rerunning without --dry-run.');
    return;
  }
  // One create-only import. Firestore writes are batched below the 500-op cap.
  if (ops.length > 0) {
    // Create the school doc in its own first batch; nested refs then become available.
    const schoolOp = ops.shift(); await commitOps([schoolOp]);
    await commitOps(ops);
  }
  const warnings = (bundle.pinWarnings || []).length;
  await db.collection('schools').doc(schoolId).collection('migrationMetadata').doc('initialImport').set({
    importedAt: FieldValue.serverTimestamp(), sourceFormat: bundle.format, sourceExportedAt: bundle.exportedAt,
    importedCounts: counts, teacherPinWarnings: warnings,
    resultsWorkbookArchivedInLocalExport: true,
    importedResultState: true,
    note: 'A structured current result snapshot was imported where legacy class result sheets could be matched. Keep the full JSON.GZ restricted archive until legacy PDF/template parity is validated.'
  });
  console.log('Import completed. School code was preserved:', schoolCode);
  console.log('Do not disable Apps Script until login, attendance, history, DATE WISE, EKANDAR, TARĲ and result workflows have been compared.');
}

main().catch(err => { console.error(err?.stack || err); process.exitCode = 1; });
