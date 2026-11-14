import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { defineSecret } from 'firebase-functions/params';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { setGlobalOptions } from 'firebase-functions/v2';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import PDFDocument from 'pdfkit';
import XLSX from 'xlsx';

initializeApp();
setGlobalOptions({ region: 'asia-south1', maxInstances: 25 });
const db = getFirestore();
const auth = getAuth();
const developerKey = defineSecret('PLATFORM_DEVELOPER_KEY');
const FONT_PATH = path.join(process.cwd(), 'assets', 'NotoSansGujarati-Regular.ttf');

const PUBLIC_ACTIONS = new Set(['platformPing', 'getSchoolInfo', 'getTeachers', 'login', 'provisionSchool', 'createSchool']);
const ADMIN_ACTIONS = new Set([
  'updateSchoolConfig','createClass','createTeacher','deactivateTeacher','uploadSchoolLogo',
  'saveHoliday','deleteHoliday','saveMessage','deleteMessage','saveRegistrationCounts',
  'saveCustomHeaders','approveLeave','getPendingLeaves','toggleResultLock','changePassword',
  'saveClassSubjects','manageStudentProfile','bulkUploadRoster','exportStudentDataExcel'
]);
const READ_TTL_MS = {
  getSchoolInfo: 15 * 60_000, getTeachers: 3 * 60_000, getSchoolConfig: 5 * 60_000,
  getTodayMessage: 30_000, getHolidays: 5 * 60_000, getMessages: 2 * 60_000,
  getRowData: 60_000, getAttendance: 3 * 60_000, getResultData: 60_000,
  getTarijClassNames: 5 * 60_000, getTarijClassData: 60_000, getGenderSummary: 5 * 60_000,
  getPendingLeaves: 60_000, getUtilizedLeaves: 5 * 60_000, getStudentBirthdays: 30 * 60_000
};
// Small per-instance cache reduces repeated identical backend lookups. It is an
// optimization only; correctness never depends on the cache surviving a cold start.
const serverReadCache = new Map();
const loginFailures = new Map();

const text = (v, fallback = '') => (v === undefined || v === null ? fallback : String(v).trim());
const asInt = (v) => Number.isFinite(Number(v)) ? Math.trunc(Number(v)) : 0;
const parseJson = (v, fallback = null) => {
  if (v === undefined || v === null || v === '') return fallback;
  if (typeof v !== 'string') return v;
  try { return JSON.parse(v); } catch { return fallback; }
};
const normalizeCode = (v) => text(v).toUpperCase().replace(/\s+/g, '');
const normalizeName = (v) => text(v).toLocaleLowerCase('en').replace(/\s+/g, ' ');
const normalizeClass = (v) => text(v).replace(/^Class\s+/i, '').replace(/\s+/g, ' ').trim();
const classIdFor = (v) => {
  const clean = normalizeClass(v).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 64);
  return clean || `class-${crypto.createHash('sha1').update(text(v)).digest('hex').slice(0, 12)}`;
};
const teacherIdFor = (v) => `t_${crypto.createHash('sha256').update(normalizeName(v)).digest('hex').slice(0, 24)}`;
const hashPin = (pin, salt) => `HASH$${salt}$${crypto.createHash('sha256').update(`${salt}:${String(pin)}`).digest('hex')}`;
function checkPin(encoded, pin) {
  const m = String(encoded || '').match(/^HASH\$([^$]+)\$([a-f0-9]+)$/i);
  if (m) {
    const expected = crypto.createHash('sha256').update(`${m[1]}:${String(pin)}`).digest('hex');
    const a = Buffer.from(expected); const b = Buffer.from(m[2]);
    return a.length === b.length && crypto.timingSafeEqual(a, b);
  }
  return false;
}
const schoolRef = (schoolId) => db.collection('schools').doc(schoolId);
const classRef = (schoolId, className) => schoolRef(schoolId).collection('classes').doc(classIdFor(className));
const dayRef = (schoolId, className, date) => classRef(schoolId, className).collection('attendanceDays').doc(date);
const registeredRef = (schoolId, className, date) => classRef(schoolId, className).collection('registrationChanges').doc(date);
function publicSchool(s) {
  // JSON-safe, compact school profile. Do not expose teacher directory metadata or
  // full rosters through the public school-info action.
  return {
    schoolId: s.id || s.schoolId || '', schoolCode: s.schoolCode || '',
    schoolName: s.schoolName || '', schoolType: String(s.schoolType || 'coed').toLowerCase(),
    logoUrl: s.logoUrl || '', reportGenderSplitEnabled: s.reportGenderSplitEnabled !== false,
    village: s.village || '', taluka: s.taluka || '', district: s.district || '',
    schoolDiseCode: s.schoolDiseCode || '', educationAuthorityName: s.educationAuthorityName || '',
    centerName: s.centerName || '', crcName: s.crcName || '', medium: s.medium || 'Gujarati',
    academicYear: s.academicYear || '', resultDate: s.resultDate || '',
    active: String(s.status || 'active').toLowerCase() !== 'inactive',
  };
}
async function findSchoolByCode(code) {
  const normalized = normalizeCode(code);
  if (!normalized) return null;
  const snap = await db.collection('schools').where('schoolCode', '==', normalized).limit(1).get();
  if (snap.empty) return null;
  const doc = snap.docs[0];
  return { ref: doc.ref, id: doc.id, ...doc.data() };
}
function authContext(request, data, allowPublic = false) {
  const action = text(data.action);
  const code = normalizeCode(data.schoolCode || request.auth?.token?.schoolCode);
  if (PUBLIC_ACTIONS.has(action) && allowPublic) return { action, schoolCode: code, auth: null };
  if (!request.auth) throw new HttpsError('unauthenticated', 'AUTH_REQUIRED: Sign in again.');
  const token = request.auth.token || {};
  const schoolId = text(token.schoolId);
  const claimedCode = normalizeCode(token.schoolCode);
  if (!schoolId || !claimedCode) throw new HttpsError('unauthenticated', 'AUTH_REQUIRED: School membership is missing.');
  if (code && code !== claimedCode) throw new HttpsError('permission-denied', 'School code does not match the active login.');
  const role = text(token.role, 'teacher').toLowerCase();
  if (ADMIN_ACTIONS.has(action) && role !== 'admin' && role !== 'developer') {
    throw new HttpsError('permission-denied', 'આ કામગીરી માટે school admin અધિકાર જરૂરી છે.');
  }
  return { action, schoolId, schoolCode: claimedCode, role, teacherName: text(token.teacherName), classes: Array.isArray(token.classes) ? token.classes : [], schoolType: text(token.schoolType, 'coed').toLowerCase(), uid: request.auth.uid };
}
function ensureClassPermission(ctx, className) {
  if (ctx.role === 'admin' || ctx.role === 'developer' || ctx.classes.includes('__ALL__')) return;
  const wanted = normalizeClass(className).toLowerCase().replace(/\s+/g, '');
  const allowed = ctx.classes.map(v => normalizeClass(v).toLowerCase().replace(/\s+/g, ''));
  if (!allowed.includes(wanted)) throw new HttpsError('permission-denied', 'આ વર્ગ માટે તમને અધિકાર નથી.');
}
async function getSchool(ctx) {
  const snap = await schoolRef(ctx.schoolId).get();
  if (!snap.exists) throw new HttpsError('not-found', 'School was not found.');
  const school = { id: snap.id, ...snap.data() };
  if (school.status && String(school.status).toLowerCase() === 'inactive') throw new HttpsError('permission-denied', 'School account is inactive.');
  return school;
}
function classConfig(school, className) {
  const target = normalizeClass(className).toLowerCase().replace(/\s+/g, '');
  const list = Array.isArray(school.classes) ? school.classes : [];
  const found = list.find(c => [c.key, c.label, c.sheetName, `Class ${c.label || ''}`].some(v => normalizeClass(v).toLowerCase().replace(/\s+/g, '') === target));
  if (!found) throw new HttpsError('not-found', `Class '${className}' was not found in this school.`);
  return { ...found, id: found.id || classIdFor(found.label || found.key || className) };
}
function countsFrom(data, prefix) {
  return { SC: asInt(data[`${prefix}SC`]), ST: asInt(data[`${prefix}ST`]), OBC: asInt(data[`${prefix}OBC`]), OTHER: asInt(data[`${prefix}OTHER`]) };
}
function countTotal(x = {}) { return ['SC','ST','OBC','OTHER'].reduce((s, k) => s + asInt(x[k]), 0); }
function categoryFromStudent(s) {
  const raw = text(s.category || s.categoryEn || s.casteCategory || s.caste, 'OTHER').toUpperCase().replace(/\s+/g, ' ');
  if (raw === 'SC' || raw.includes('SCHEDULED CASTE') || raw.includes('અ.જા')) return 'SC';
  if (raw === 'ST' || raw.includes('SCHEDULED TRIBE') || raw.includes('અ.જ.જા')) return 'ST';
  if (raw === 'OBC' || raw.includes('OTHER BACKWARD') || raw.includes('બ.પ.')) return 'OBC';
  return 'OTHER';
}
function normalizeGender(gender, schoolType) {
  if (schoolType === 'boys') return 'BOYS';
  if (schoolType === 'girls') return 'GIRLS';
  const g = text(gender).toUpperCase();
  if (['BOYS','BOY','M','MALE','છોકરો','છોકરા','પુરુષ'].includes(g)) return 'BOYS';
  if (['GIRLS','GIRL','F','FEMALE','છોકરી','છોકરીઓ','સ્ત્રી'].includes(g)) return 'GIRLS';
  return 'UNSPECIFIED';
}
function blankGenderBreakdown() {
  const result = {};
  for (const gender of ['BOYS','GIRLS','UNSPECIFIED']) {
    result[gender] = {};
    for (const cat of ['SC','ST','OBC','OTHER']) result[gender][cat] = { registered: 0, present: 0, mdm: 0, breakfast: 0 };
    result[gender]._OVERALL = { registered: 0, present: 0, mdm: 0, breakfast: 0 };
  }
  return result;
}
function addBreakdown(breakdown, gender, category, metric, amount = 1) {
  breakdown[gender][category][metric] += amount;
  breakdown[gender]._OVERALL[metric] += amount;
}
function dayCounts(day) {
  return {
    registered: day?.registered || { SC: 0, ST: 0, OBC: 0, OTHER: 0 },
    present: day?.present || { SC: 0, ST: 0, OBC: 0, OTHER: 0 },
    mdm: day?.mdm || { SC: 0, ST: 0, OBC: 0, OTHER: 0 },
    breakfastTotal: asInt(day?.breakfastTotal),
    genderBreakdown: day?.genderBreakdown || {},
  };
}
async function effectiveRegistration(schoolId, className, date, dayData = null) {
  if (dayData && dayData.registered) return dayData.registered;
  const snap = await classRef(schoolId, className).collection('registrationChanges')
    .where('date', '<=', date).orderBy('date', 'desc').limit(1).get();
  if (!snap.empty) return snap.docs[0].data().registered || { SC: 0, ST: 0, OBC: 0, OTHER: 0 };
  return { SC: 0, ST: 0, OBC: 0, OTHER: 0 };
}
async function classRosters(ctx, school, className) {
  ensureClassPermission(ctx, className);
  const cfg = classConfig(school, className);
  const ref = schoolRef(ctx.schoolId).collection('classes').doc(cfg.id);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('not-found', 'Class configuration document is missing.');
  return { cfg, ref, data: snap.data() };
}
function hasChanges(a, b) { return JSON.stringify(sortDeep(a)) !== JSON.stringify(sortDeep(b)); }
function sortDeep(v) {
  if (Array.isArray(v)) return v.map(sortDeep);
  if (v && typeof v === 'object') return Object.fromEntries(Object.keys(v).sort().map(k => [k, sortDeep(v[k])]));
  return v;
}
function cacheReadKey(ctx, action, data) {
  return `${ctx?.schoolId || data.schoolCode || 'public'}:${ctx?.uid || 'anon'}:${action}:${JSON.stringify(sortDeep(data))}`;
}
async function doCachedRead(ctx, action, data, runner) {
  const ttl = READ_TTL_MS[action];
  if (!ttl) return runner();
  const key = cacheReadKey(ctx, action, data);
  const found = serverReadCache.get(key);
  if (found && found.expiry > Date.now()) return found.value;
  const value = await runner();
  serverReadCache.set(key, { expiry: Date.now() + ttl, value });
  if (serverReadCache.size > 800) {
    const now = Date.now();
    for (const [k, v] of serverReadCache) if (v.expiry <= now) serverReadCache.delete(k);
    if (serverReadCache.size > 800) serverReadCache.clear();
  }
  return value;
}
function invalidateServerCache(schoolId, schoolCode = '') {
  const codePrefix = normalizeCode(schoolCode);
  for (const [k, v] of serverReadCache) {
    if (k.startsWith(`${schoolId}:`) || (codePrefix && k.startsWith(`${codePrefix}:`))) serverReadCache.delete(k);
  }
}
function buildLiteStudent(s, id, schoolType = 'coed') {
  return {
    id: text(s.id, id), rollNumber: text(s.rollNumber || s.roll), gr: text(s.gr), dd: text(s.dd), mm: text(s.mm), yyyy: text(s.yyyy),
    name: text(s.name || s.studentName), caste: text(s.caste), category: categoryFromStudent(s), gender: normalizeGender(s.gender, schoolType),
    mobile: text(s.mobile || s.mobileNumber), enrollSchool: text(s.enrollSchool), enrollClass: text(s.enrollClass),
    present: false, mdm: false, breakfast: false, sheetRow: asInt(s.sheetRow),
    motherName: text(s.motherName), birthPlace: text(s.birthPlace), dobWords: text(s.dobWords), lastSchool: text(s.lastSchool),
    enrollSchClass: text(s.enrollSchClass), enrollSchClassWords: text(s.enrollSchClassWords), nameEn: text(s.nameEn), casteEn: text(s.casteEn),
    catEn: text(s.catEn), motherEn: text(s.motherEn), birthPlaceEn: text(s.birthPlaceEn), dobEn: text(s.dobEn),
    lastSchoolEn: text(s.lastSchoolEn), enrollSchClassEn: text(s.enrollSchClassEn), enrollSchClassWordsEn: text(s.enrollSchClassWordsEn),
    uid: text(s.uid), pen: text(s.pen), scholarshipDone: text(s.scholarshipDone, 'ના'), scholarshipReason: text(s.scholarshipReason),
    scholarshipOther: text(s.scholarshipOther), aadhaar: text(s.aadhaar), nameAsAadhaar: text(s.nameAsAadhaar), dobAsAadhaar: text(s.dobAsAadhaar),
    bankName: text(s.bankName), bankBranch: text(s.bankBranch), nameAsPassbook: text(s.nameAsPassbook), accountNumber: text(s.accountNumber),
    ifscCode: text(s.ifscCode), rationCardType: text(s.rationCardType), rationCardNo: text(s.rationCardNo), customFields: s.customFields || {},
  };
}
function summarizeStudentFlags(roster, flags, schoolType) {
  const registered = { SC: 0, ST: 0, OBC: 0, OTHER: 0 };
  const present = { SC: 0, ST: 0, OBC: 0, OTHER: 0 };
  const mdm = { SC: 0, ST: 0, OBC: 0, OTHER: 0 };
  let breakfastTotal = 0;
  const breakdown = blankGenderBreakdown();
  const map = {};
  for (const s0 of roster) {
    const s = buildLiteStudent(s0, text(s0.id), schoolType);
    const c = categoryFromStudent(s); const g = normalizeGender(s.gender, schoolType);
    registered[c]++;
    addBreakdown(breakdown, g, c, 'registered');
    const f = flags[s.id] || {};
    const isPresent = f.present === true;
    const isMdm = isPresent && f.mdm === true;
    const isBreakfast = isPresent && f.breakfast === true;
    if (isPresent) { present[c]++; addBreakdown(breakdown, g, c, 'present'); }
    if (isMdm) { mdm[c]++; addBreakdown(breakdown, g, c, 'mdm'); }
    if (isBreakfast) { breakfastTotal++; addBreakdown(breakdown, g, c, 'breakfast'); }
    map[s.id] = { present: isPresent, mdm: isMdm, breakfast: isBreakfast };
  }
  return { registered, present, mdm, breakfastTotal, genderBreakdown: breakdown, studentFlags: map };
}
function computeGenderBreakdownFromManual(genderBreakdown, registered, present, mdm, breakfastTotal) {
  const parsed = parseJson(genderBreakdown, null);
  if (parsed && typeof parsed === 'object') return parsed;
  const out = blankGenderBreakdown();
  for (const [metric, totals] of [['registered', registered], ['present', present], ['mdm', mdm]]) {
    for (const c of ['SC','ST','OBC','OTHER']) out.UNSPECIFIED[c][metric] = asInt(totals[c]);
    out.UNSPECIFIED._OVERALL[metric] = countTotal(totals);
  }
  out.UNSPECIFIED._OVERALL.breakfast = breakfastTotal;
  return out;
}
function dateIsValid(date) { return /^\d{4}-\d{2}-\d{2}$/.test(date) && !Number.isNaN(Date.parse(`${date}T12:00:00Z`)); }
function monthNumber(month) {
  const names = ['january','february','march','april','may','june','july','august','september','october','november','december'];
  const v = text(month).toLowerCase(); const named = names.indexOf(v);
  if (named >= 0) return named + 1;
  const m = v.match(/^(\d{4})[-/](\d{1,2})$/) || v.match(/^(\d{1,2})[-/](\d{4})$/);
  if (m) return Number(m[1]) > 12 ? Number(m[2]) : Number(m[1]);
  const dt = new Date(v); return Number.isNaN(dt.getTime()) ? 0 : dt.getMonth() + 1;
}
function monthBounds(monthValue) {
  const n = monthNumber(monthValue);
  if (!n) throw new HttpsError('invalid-argument', 'Select a valid month.');
  let year = new Date().getFullYear();
  const m = text(monthValue).match(/(\d{4})/); if (m) year = Number(m[1]);
  const start = `${year}-${String(n).padStart(2,'0')}-01`;
  const lastDate = new Date(Date.UTC(year, n, 0)).getUTCDate();
  return { year, month: n, start, end: `${year}-${String(n).padStart(2,'0')}-${String(lastDate).padStart(2,'0')}`, caption: `${new Date(Date.UTC(year,n-1,1)).toLocaleString('en',{month:'long',timeZone:'UTC'})} ${year}` };
}
function groupForClass(c) {
  const raw = text(c.reportGroup || '').toUpperCase().replace(/[\s-]+/g, '_');
  const aliases = {
    '1TO5':'CLASS_1_5', 'STD_1_TO_5':'CLASS_1_5', 'CLASS_1_TO_5':'CLASS_1_5',
    'CLASS_1_5':'CLASS_1_5', '6TO8':'CLASS_6_8', 'STD_6_TO_8':'CLASS_6_8',
    'CLASS_6_TO_8':'CLASS_6_8', 'CLASS_6_8':'CLASS_6_8', 'BV':'BALVATIKA',
    'BALVATIKA':'BALVATIKA'
  };
  if (raw) return aliases[raw] || raw;
  const label = normalizeClass(c.label || c.key || c.sheetName).toLowerCase();
  if (label.includes('balvatika') || label.includes('બાલવાટિકા')) return 'BALVATIKA';
  const match = label.match(/(?:class\s*)?(\d+)/i); const standard = match ? Number(match[1]) : 0;
  return standard >= 1 && standard <= 5 ? 'CLASS_1_5' : standard >= 6 && standard <= 8 ? 'CLASS_6_8' : 'OTHER';
}
function reportGenderEnabled(school) { return String(school.schoolType || 'coed').toLowerCase() === 'coed' && school.reportGenderSplitEnabled !== false; }
function categoryGenderTotals(day, metric, category, enabled) {
  const oldTotals = (day[metric] || {})[category] || 0;
  const bd = day.genderBreakdown || {};
  if (!enabled) return { total: asInt(oldTotals) };
  const b = asInt(bd.BOYS?.[category]?.[metric]);
  const g = asInt(bd.GIRLS?.[category]?.[metric]);
  const unknown = asInt(bd.UNSPECIFIED?.[category]?.[metric]);
  const hasBreakdown = bd.BOYS?.[category]?.[metric] !== undefined || bd.GIRLS?.[category]?.[metric] !== undefined;
  return hasBreakdown ? { boys: b, girls: g, total: b + g, unassigned: unknown } : { boys: null, girls: null, total: asInt(oldTotals), unassigned: asInt(oldTotals) };
}
function sumDays(days) {
  const result = { dayCount: days.length, registered: {SC:0,ST:0,OBC:0,OTHER:0}, presentSum:{SC:0,ST:0,OBC:0,OTHER:0}, mdmSum:{SC:0,ST:0,OBC:0,OTHER:0}, breakfastSum:0, latest:null, firstDate:'', lastDate:'', genderBreakdown:blankGenderBreakdown() };
  for (const d of days) {
    result.firstDate = result.firstDate || d.date; result.lastDate = d.date;
    for (const cat of ['SC','ST','OBC','OTHER']) {
      result.presentSum[cat] += asInt(d.present?.[cat]);
      result.mdmSum[cat] += asInt(d.mdm?.[cat]);
    }
    result.breakfastSum += asInt(d.breakfastTotal);
    result.latest = d;
    for (const g of ['BOYS','GIRLS','UNSPECIFIED']) for (const cat of ['SC','ST','OBC','OTHER']) for (const metric of ['registered','present','mdm','breakfast']) {
      result.genderBreakdown[g][cat][metric] += asInt(d.genderBreakdown?.[g]?.[cat]?.[metric]);
    }
    for (const g of ['BOYS','GIRLS','UNSPECIFIED']) for (const metric of ['registered','present','mdm','breakfast']) result.genderBreakdown[g]._OVERALL[metric] += asInt(d.genderBreakdown?.[g]?._OVERALL?.[metric]);
  }
  if (result.latest?.registered) result.registered = result.latest.registered;
  return result;
}
function drawCell(doc, x, y, w, h, textValue, opts = {}) {
  doc.rect(x, y, w, h).lineWidth(0.35).stroke('#8994A4');
  doc.font(opts.bold ? 'Gujarati-Bold' : 'Gujarati').fontSize(opts.fontSize || 7).fillColor(opts.color || '#111827');
  doc.text(String(textValue ?? ''), x + 3, y + 2, { width: Math.max(1,w-6), height: Math.max(1,h-4), ellipsis: true, align: opts.align || 'left', valign: 'center' });
}
async function createPdf({title, subtitle = '', sections = [], landscape = true, size = 'A4', fileName = 'Report.pdf'}) {
  return new Promise((resolve, reject) => {
    try {
      const doc = new PDFDocument({ size, layout: landscape ? 'landscape' : 'portrait', margin: 24, bufferPages: true, autoFirstPage: true });
      if (fs.existsSync(FONT_PATH)) {
        doc.registerFont('Gujarati', FONT_PATH);
        doc.registerFont('Gujarati-Bold', FONT_PATH);
        doc.font('Gujarati');
      }
      const chunks = []; doc.on('data', c => chunks.push(c)); doc.on('error', reject);
      doc.on('end', () => resolve({ result: 'success', fileName, pdfBase64: Buffer.concat(chunks).toString('base64') }));
      const pageMargin = 24; const width = doc.page.width - pageMargin * 2;
      doc.font(fs.existsSync(FONT_PATH) ? 'Gujarati-Bold' : 'Helvetica-Bold').fontSize(size === 'A3' ? 14 : 12).fillColor('#1E365D').text(title, pageMargin, pageMargin, { width, align: 'center' });
      if (subtitle) doc.font(fs.existsSync(FONT_PATH) ? 'Gujarati' : 'Helvetica').fontSize(8).fillColor('#344256').text(subtitle, { width, align:'center' });
      doc.moveDown(1);
      let y = doc.y + 4;
      for (const section of sections) {
        const headers = (section.headers || []).map(String);
        const rows = section.rows || [];
        if (!headers.length) continue;
        if (y + 20 > doc.page.height - 30) { doc.addPage({size, layout: landscape ? 'landscape':'portrait', margin:24}); y = pageMargin; }
        doc.font(fs.existsSync(FONT_PATH) ? 'Gujarati-Bold' : 'Helvetica-Bold').fontSize(8).fillColor('#1E365D').text(section.title || '', pageMargin, y, { width });
        y = doc.y + 3;
        const n = headers.length; const cellW = width / n; const headerH = section.headerHeight || 22; const rowH = section.rowHeight || 18;
        for (let i=0;i<n;i++) drawCell(doc,pageMargin+i*cellW,y,cellW,headerH,headers[i],{bold:true,align:'center',fontSize:Math.min(7,Math.max(4,cellW<28?4.5:6)),color:'#1E365D'});
        y += headerH;
        for (const row of rows) {
          if (y + rowH > doc.page.height - pageMargin) { doc.addPage({size, layout: landscape ? 'landscape':'portrait', margin:24}); y=pageMargin; for(let i=0;i<n;i++)drawCell(doc,pageMargin+i*cellW,y,cellW,headerH,headers[i],{bold:true,align:'center',fontSize:5.5}); y+=headerH; }
          for (let i=0;i<n;i++) drawCell(doc,pageMargin+i*cellW,y,cellW,rowH,row[i] ?? '',{fontSize:Math.min(7,Math.max(4,cellW<28?4.5:6))});
          y += rowH;
        }
        y += 12;
      }
      doc.end();
    } catch (e) { reject(e); }
  });
}

async function handlePublic(action, data, secretValue) {
  if (action === 'platformPing') return { result: 'success', api: 'Professional School Management Firebase', version: 1, backend: 'firestore' };
  if (action === 'getSchoolInfo') {
    const school = await findSchoolByCode(data.schoolCode);
    if (!school || String(school.status || 'active').toLowerCase() === 'inactive') return { result: 'error', message: 'School code not found or school inactive.' };
    return { result: 'success', school: publicSchool(school) };
  }
  if (action === 'getTeachers') {
    const school = await findSchoolByCode(data.schoolCode);
    if (!school || String(school.status || 'active').toLowerCase() === 'inactive') return { result:'error', message:'School code not found or school inactive.' };
    const teachers = Array.isArray(school.teacherDirectory) ? school.teacherDirectory.filter(t => t.active !== false).map(t => ({ name:t.name, role:t.role || 'teacher', classes:t.classes || [] })) : [];
    return { result:'success', school:publicSchool(school), teachers };
  }
  if (action === 'login') {
    const school = await findSchoolByCode(data.schoolCode);
    const name = text(data.teacherName || data.name); const pin = text(data.pin);
    if (!school || String(school.status || 'active').toLowerCase() === 'inactive') return { result:'error', message:'School code not found or school inactive.' };
    if (!name || !pin) return { result:'error', message:'Teacher name and PIN are required.' };
    const lockKey = `${school.id}:${normalizeName(name)}`; const lock = loginFailures.get(lockKey);
    if (lock && lock.until > Date.now()) return { result:'error', code:'LOGIN_LOCKED', message:'Too many unsuccessful attempts. Wait 15 minutes before trying again.' };
    const directory = Array.isArray(school.teacherDirectory) ? school.teacherDirectory : [];
    const entry = directory.find(t => normalizeName(t.name) === normalizeName(name) && t.active !== false);
    if (!entry?.id) { recordFailedLogin(lockKey); return { result:'error', message:'Invalid teacher name or PIN.' }; }
    const teacherSnap = await schoolRef(school.id).collection('teachers').doc(entry.id).get();
    if (!teacherSnap.exists) { recordFailedLogin(lockKey); return { result:'error', message:'Teacher account is not configured in Firestore yet.' }; }
    const teacher = teacherSnap.data();
    if (teacher.active === false || !checkPin(teacher.pinHash, pin)) { recordFailedLogin(lockKey); return { result:'error', message:'Invalid teacher name or PIN.' }; }
    loginFailures.delete(lockKey);
    const classes = Array.isArray(teacher.classes) ? teacher.classes : (teacher.classes === '__ALL__' ? ['__ALL__'] : []);
    const claims = { schoolId: school.id, schoolCode: school.schoolCode, role: text(teacher.role,'teacher').toLowerCase(), teacherName: teacher.name, classes, schoolType: text(school.schoolType,'coed').toLowerCase() };
    const customToken = await auth.createCustomToken(teacherSnap.id, claims);
    return { result:'success', customToken, sessionToken: teacherSnap.id, teacher:{ name:teacher.name, role:claims.role, classes:classes.includes('__ALL__') ? '__ALL__' : classes }, school:publicSchool(school) };
  }
  if (action === 'provisionSchool' || action === 'createSchool') {
    if (!secretValue || text(data.developerKey) !== secretValue) throw new HttpsError('permission-denied','Developer verification failed.');
    const name = text(data.schoolName); const type = text(data.schoolType,'coed').toLowerCase(); const adminName = text(data.adminName); const pin = text(data.adminPin);
    if (!name || !adminName || pin.length < 4) throw new HttpsError('invalid-argument','School name, admin name, and admin PIN (at least 4 characters) are required.');
    if (!['boys','girls','coed'].includes(type)) throw new HttpsError('invalid-argument','schoolType must be boys, girls or coed.');
    const schoolId = crypto.randomUUID(); const schoolCode = `SCH${crypto.randomBytes(4).toString('hex').toUpperCase()}`;
    const classesIn = parseJson(data.classes, []); const classes = Array.isArray(classesIn) ? classesIn : [];
    const classConfigs = classes.map((item,index) => normaliseClassInput(item,index)).filter(Boolean);
    const tid = teacherIdFor(adminName); const salt = crypto.randomBytes(16).toString('hex');
    const school = { schoolId, schoolCode, schoolName:name, schoolType:type, status:'active', logoUrl:'', reportGenderSplitEnabled:true, village:'', taluka:'', district:'', medium:'Gujarati', academicYear:'2026 - 27', resultDate:'30/04/2027', createdAt:FieldValue.serverTimestamp(), classes:classConfigs, teacherDirectory:[{id:tid,name:adminName,role:'admin',classes:['__ALL__'],active:true}] };
    const batch = db.batch(); batch.set(schoolRef(schoolId), school);
    for (const c of classConfigs) batch.set(schoolRef(schoolId).collection('classes').doc(c.id), {...c, rosterLite:[], createdAt:FieldValue.serverTimestamp()});
    batch.set(schoolRef(schoolId).collection('teachers').doc(tid), {name:adminName, normalizedName:normalizeName(adminName), role:'admin', classes:['__ALL__'], active:true, email:text(data.ownerEmail), pinHash:hashPin(pin,salt), pinSalt:salt, createdAt:FieldValue.serverTimestamp()});
    await batch.commit();
    return { result:'success', schoolId, schoolCode, schoolName:name, adminName, classes:classConfigs.map(c=>c.key), message:'School created in Firestore. Save the school code securely.' };
  }
  throw new HttpsError('invalid-argument', `Unsupported public action: ${action}`);
}
function recordFailedLogin(key) {
  const state = loginFailures.get(key) || { count:0, until:0 };
  state.count += 1; if (state.count >= 5) state.until = Date.now() + 15*60_000;
  loginFailures.set(key, state);
}
function normaliseClassInput(raw, index=0) {
  const c = typeof raw === 'string' ? { label:raw } : raw || {};
  const label = normalizeClass(c.label || c.name || c.className || c.key);
  if (!label) return null;
  const key = /^Class\s+/i.test(text(c.key)) ? text(c.key) : `Class ${label}`;
  const numeric = (label.match(/^\d+/) || [])[0];
  const standard = text(c.standard || numeric || (label.toLowerCase().includes('balvatika') || label.includes('બાલવાટિકા') ? 'BALVATIKA' : label.split(' ')[0]));
  const section = text(c.section || (label.match(/\b([A-Za-z])$/) || [,''])[1]).toUpperCase();
  const reportGroup = text(c.reportGroup || groupForClass({label,standard}));
  const id = classIdFor(label);
  return { id,key,label,sheetName:label,standard,section,reportGroup,active:true,sortOrder:asInt(c.sortOrder) || index+1 };
}
function normalizeProfile(payload, classCfg, schoolType) {
  const profile = { ...payload };
  profile.id = text(payload.id) || (text(payload.rollNumber || payload.roll) ? `r_${crypto.createHash('sha256').update(text(payload.rollNumber || payload.roll)).digest('hex').slice(0,20)}` : `s_${crypto.randomUUID().replace(/-/g,'').slice(0,20)}`);
  profile.classId = classCfg.id; profile.className = classCfg.key;
  profile.rollNumber = text(payload.rollNumber || payload.roll);
  profile.name = text(payload.name || payload.studentName);
  profile.category = categoryFromStudent(payload);
  profile.gender = normalizeGender(payload.gender, schoolType);
  profile.mobile = text(payload.mobile || payload.mobileNumber);
  profile.updatedAt = FieldValue.serverTimestamp();
  return profile;
}
function isAdmin(ctx) { return ctx.role === 'admin' || ctx.role === 'developer'; }
async function saveRegistrationIfChanged(schoolId, className, date, registered) {
  const ref = registeredRef(schoolId, className, date);
  const sameDay = await ref.get();
  if (sameDay.exists && !hasChanges(sameDay.data().registered || {}, registered)) return { changed:false };
  let previous = null;
  const prevSnap = await classRef(schoolId,className).collection('registrationChanges').where('date','<',date).orderBy('date','desc').limit(1).get();
  if (!prevSnap.empty) previous = prevSnap.docs[0].data().registered || null;
  if (!sameDay.exists && previous && !hasChanges(previous, registered)) return { changed:false };
  await ref.set({ date, registered, updatedAt:FieldValue.serverTimestamp() }, {merge:true});
  return { changed:true };
}
async function readDailyRows(ctx, school, date) {
  const classes = Array.isArray(school.classes) ? school.classes.filter(c=>c.active!==false) : [];
  const rows = await Promise.all(classes.filter(c=>isClassAllowed(ctx,c)).map(async c => {
    const snap = await dayRef(ctx.schoolId, c.label || c.key, date).get();
    return snap.exists ? { className:c.label || c.key, classKey:c.key, reportGroup:groupForClass(c), ...snap.data() } : null;
  }));
  return rows.filter(Boolean).sort((a,b)=>asInt(a.sortOrder)-asInt(b.sortOrder));
}
function isClassAllowed(ctx,c) {
  if (isAdmin(ctx) || ctx.classes.includes('__ALL__')) return true;
  const want = normalizeClass(c.label || c.key).toLowerCase().replace(/\s+/g,'');
  return ctx.classes.some(k => normalizeClass(k).toLowerCase().replace(/\s+/g,'') === want);
}
function tableForDateRows(date, rows, school) {
  const enabled = reportGenderEnabled(school);
  const metrics = [ ['registered','નોંધાયેલ'], ['present','હાજર'], ['mdm','PM Poshan'] ];
  const out = [];
  for (const [metric,label] of metrics) {
    const headers = ['ધોરણ','તારીખ'];
    for (const cat of ['SC','ST','OBC','OTHER','TOTAL']) {
      if (enabled) headers.push(`${cat} BOYS`,`${cat} GIRLS`,`${cat} TOTAL`); else headers.push(cat);
    }
    out.push([`${label} (${date})`]); out.push(headers);
    for (const row of rows) {
      const values = [row.className,date];
      for (const cat of ['SC','ST','OBC','OTHER']) {
        const v = categoryGenderTotals(row,metric,cat,enabled);
        if (enabled) values.push(v.boys === null ? '—' : v.boys, v.girls === null ? '—' : v.girls, v.total ?? 0);
        else values.push(asInt(row[metric]?.[cat]));
      }
      if (enabled) {
        const g = row.genderBreakdown || {}; const b = asInt(g.BOYS?._OVERALL?.[metric]); const girl = asInt(g.GIRLS?._OVERALL?.[metric]);
        const has = g.BOYS?._OVERALL?.[metric] !== undefined || g.GIRLS?._OVERALL?.[metric] !== undefined;
        values.push(has?b:'—',has?girl:'—',has?b+girl:countTotal(row[metric]));
      } else values.push(countTotal(row[metric]));
      out.push(values);
    }
    out.push([]);
  }
  out.push(['નાસ્તો']); out.push(['ધોરણ','તારીખ','BREAKFAST']);
  for (const row of rows) out.push([row.className,date,asInt(row.breakfastTotal)]);
  return out;
}
async function makeMonthlyReport(ctx, action, monthValue) {
  const school = await getSchool(ctx); const bounds = monthBounds(monthValue);
  const group = action === 'getBalvatikaEkandarPDF' ? 'BALVATIKA' : action === 'getStd1to5EkandarPDF' ? 'CLASS_1_5' : action === 'getStd6to8EkandarPDF' ? 'CLASS_6_8' : 'ALL';
  const classes = (school.classes || []).filter(c => c.active !== false && isClassAllowed(ctx,c) && (group==='ALL' || groupForClass(c)===group));
  const dataRows = [];
  for (const c of classes) {
    const snap = await schoolRef(ctx.schoolId).collection('classes').doc(c.id || classIdFor(c.label || c.key)).collection('attendanceDays')
      .where('date','>=',bounds.start).where('date','<=',bounds.end).orderBy('date','asc').get();
    for (const d of snap.docs) dataRows.push({ className:c.label || c.key, classKey:c.key, reportGroup:groupForClass(c), ...d.data() });
  }
  dataRows.sort((a,b)=>text(a.date).localeCompare(text(b.date)) || text(a.className).localeCompare(text(b.className)));
  if (!dataRows.length) return { result:'error', code:'NO_REPORT_DATA', message:`${bounds.caption} માટે ${group==='ALL'?'':group+' '} attendance data મળ્યો નથી.` };
  const enabled = reportGenderEnabled(school);
  const sections = [];
  for (const [metric,label] of [['registered','Registered / નોંધાયેલ'],['present','Present / હાજર'],['mdm','PM Poshan']]) {
    const headers = ['તારીખ','ધોરણ'];
    for (const cat of ['SC','ST','OBC','OTHER','TOTAL']) {
      if (enabled) headers.push(`${cat} B`,`${cat} G`,`${cat} T`); else headers.push(cat);
    }
    const rows = dataRows.map(d=>{
      const values=[d.date,d.className];
      for(const cat of ['SC','ST','OBC','OTHER']){
        const v=categoryGenderTotals(d,metric,cat,enabled);
        if(enabled) values.push(v.boys===null?'—':v.boys,v.girls===null?'—':v.girls,v.total??0); else values.push(asInt(d[metric]?.[cat]));
      }
      if(enabled){const gb=d.genderBreakdown||{};const b=asInt(gb.BOYS?._OVERALL?.[metric]);const g=asInt(gb.GIRLS?._OVERALL?.[metric]);const has=gb.BOYS?._OVERALL?.[metric]!==undefined||gb.GIRLS?._OVERALL?.[metric]!==undefined;values.push(has?b:'—',has?g:'—',has?b+g:countTotal(d[metric]));} else values.push(countTotal(d[metric]));
      return values;
    });
    sections.push({title:label,headers,rows});
  }
  sections.push({title:'Breakfast / નાસ્તો',headers:['તારીખ','ધોરણ','Breakfast'],rows:dataRows.map(d=>[d.date,d.className,asInt(d.breakfastTotal)])});
  const landscape = enabled || action === 'getTarijPDF';
  const result = await createPdf({title:`${school.schoolName || 'School'} — ${group==='ALL'?'TARIJ':`${group} EKANDAR`}`,subtitle:`Month: ${bounds.caption} | School type: ${school.schoolType || 'coed'} | Each visible Total = Boys + Girls when gender split is known`,sections,landscape,size:enabled?'A3':'A4',fileName:`${group}-${bounds.caption.replace(/\s+/g,'-')}.pdf`});
  return {...result, month:bounds.caption, group, recordCount:dataRows.length, message:`${dataRows.length} saved class/date records included.`};
}
async function handleAuthed(ctx, action, data) {
  if (action === 'validateSession') {
    const school = await getSchool(ctx);
    return { result:'success', school:publicSchool(school), teacher:{ name:ctx.teacherName, role:ctx.role, classes:ctx.classes.length===1&&ctx.classes[0]==='__ALL__'?'__ALL__':ctx.classes } };
  }
  if (action === 'logout') return { result:'success' };
  if (action === 'getSchoolConfig') {
    const school = await getSchool(ctx);
    const classes = (school.classes || []).filter(c=>c.active!==false).sort((a,b)=>asInt(a.sortOrder)-asInt(b.sortOrder));
    const safeKeys = ['schoolName','schoolType','logoUrl','reportGenderSplitEnabled','village','taluka','district','schoolDiseCode','educationAuthorityName','centerName','crcName','medium','academicYear','resultDate','customHeaders'];
    const settings = Object.fromEntries(safeKeys.filter(k => school[k] !== undefined).map(k => [k, school[k]]));
    return { result:'success', school:publicSchool(school), config:settings, classes };
  }
  if (action === 'updateSchoolConfig') {
    const school = await getSchool(ctx); const updates = {};
    const allowed = ['schoolName','village','taluka','district','schoolDiseCode','educationAuthorityName','centerName','crcName','medium','academicYear','resultDate','reportGenderSplitEnabled'];
    for (const k of allowed) if (data[k] !== undefined) updates[k] = k==='reportGenderSplitEnabled' ? (data[k]===true || text(data[k]).toLowerCase()==='true') : text(data[k]);
    if (data.schoolType && text(data.schoolType).toLowerCase() !== text(school.schoolType).toLowerCase()) throw new HttpsError('failed-precondition','School type is fixed during initial setup. Use a supervised migration to change it.');
    const changed = Object.fromEntries(Object.entries(updates).filter(([k,v]) => String(school[k] ?? '') !== String(v ?? '')));
    if (!Object.keys(changed).length) return { result:'success', noChanges:true, message:'No changes to save.' };
    changed.updatedAt=FieldValue.serverTimestamp();
    await schoolRef(ctx.schoolId).update(changed);
    invalidateServerCache(ctx.schoolId);
    return { result:'success', message:'School settings saved.', config:await getSchoolConfigFor(ctx.schoolId) };
  }
  if (action === 'createClass') {
    const school = await getSchool(ctx); const c = normaliseClassInput({ label:data.label || data.className || data.name, standard:data.standard, section:data.section, reportGroup:data.reportGroup, sortOrder:data.sortOrder }, (school.classes||[]).length);
    if (!c) throw new HttpsError('invalid-argument','Class name is required.');
    const same = (school.classes||[]).some(x=>classIdFor(x.label||x.key)===c.id || normalizeClass(x.label||x.key).toLowerCase()===c.label.toLowerCase());
    if (same) return { result:'success', class:classConfig(school,c.label), unchanged:true };
    const batch = db.batch(); batch.set(schoolRef(ctx.schoolId).collection('classes').doc(c.id),{...c,rosterLite:[],createdAt:FieldValue.serverTimestamp()});
    batch.update(schoolRef(ctx.schoolId),{classes:FieldValue.arrayUnion(c),updatedAt:FieldValue.serverTimestamp()}); await batch.commit(); invalidateServerCache(ctx.schoolId);
    return { result:'success', class:c };
  }
  if (action === 'createTeacher') {
    const name=text(data.name), pin=text(data.pin); if (!name||pin.length<4) throw new HttpsError('invalid-argument','Teacher name and PIN (at least 4 characters) are required.');
    const role=text(data.role,'teacher').toLowerCase(); if (!['admin','teacher','pm_poshan','office'].includes(role)) throw new HttpsError('invalid-argument','Invalid role.');
    const school=await getSchool(ctx); const dir=Array.isArray(school.teacherDirectory)?school.teacherDirectory:[];
    if (dir.some(t=>normalizeName(t.name)===normalizeName(name))) throw new HttpsError('already-exists','Teacher already exists.');
    const id=teacherIdFor(`${name}:${crypto.randomUUID()}`); const salt=crypto.randomBytes(16).toString('hex'); const classes=role==='admin'?['__ALL__']:(Array.isArray(data.classes)?data.classes:text(data.classes).split(',').map(text).filter(Boolean));
    const entry={id,name,role,classes,active:true};
    const batch=db.batch();batch.set(schoolRef(ctx.schoolId).collection('teachers').doc(id),{name,normalizedName:normalizeName(name),role,classes,active:true,email:text(data.email),displayName:text(data.displayName,name),pinHash:hashPin(pin,salt),pinSalt:salt,createdAt:FieldValue.serverTimestamp()});
    batch.update(schoolRef(ctx.schoolId),{teacherDirectory:[...dir,entry],updatedAt:FieldValue.serverTimestamp()});await batch.commit();invalidateServerCache(ctx.schoolId);return {result:'success',message:'Teacher account created.'};
  }
  if (action === 'getTeachers' || action === 'getTeachersRaw') {
    const school = await getSchool(ctx); const teachers=(school.teacherDirectory||[]).filter(t=>t.active!==false).map(t=>({name:t.name,role:t.role,classes:t.classes||[]}));
    return {result:'success',teachers};
  }
  if (action === 'deactivateTeacher') {
    const school=await getSchool(ctx);const name=text(data.name);const entry=(school.teacherDirectory||[]).find(t=>normalizeName(t.name)===normalizeName(name));if(!entry)throw new HttpsError('not-found','Teacher not found.');
    const batch=db.batch();batch.update(schoolRef(ctx.schoolId).collection('teachers').doc(entry.id),{active:false,updatedAt:FieldValue.serverTimestamp()});batch.update(schoolRef(ctx.schoolId),{teacherDirectory:school.teacherDirectory.map(t=>t.id===entry.id?{...t,active:false}:t),updatedAt:FieldValue.serverTimestamp()});await batch.commit();invalidateServerCache(ctx.schoolId);return {result:'success'};
  }
  if (action === 'changePassword') {
    const school=await getSchool(ctx);const name=text(data.teacherName || ctx.teacherName);if(!isAdmin(ctx)&&normalizeName(name)!==normalizeName(ctx.teacherName))throw new HttpsError('permission-denied','You can only change your own PIN.');
    const entry=(school.teacherDirectory||[]).find(t=>normalizeName(t.name)===normalizeName(name));if(!entry)throw new HttpsError('not-found','Teacher not found.');const pin=text(data.newPin);if(pin.length<4)throw new HttpsError('invalid-argument','PIN must contain at least 4 characters.');const salt=crypto.randomBytes(16).toString('hex');await schoolRef(ctx.schoolId).collection('teachers').doc(entry.id).update({pinHash:hashPin(pin,salt),pinSalt:salt,updatedAt:FieldValue.serverTimestamp()});return {result:'success',message:'Password changed.'};
  }
  if (action === 'getRowData') {
    const className=text(data.className);const date=text(data.date);if(!dateIsValid(date))throw new HttpsError('invalid-argument','Invalid date.');
    const {cfg,ref,data:klass}=await classRosters(ctx,await getSchool(ctx),className);const daySnap=await ref.collection('attendanceDays').doc(date).get();const day=daySnap.exists?daySnap.data():{};const registered=await effectiveRegistration(ctx.schoolId,cfg.label||cfg.key,date,day);
    const flags=day.studentFlags||{};const students=(klass.rosterLite||[]).map(s=>({...s,...(flags[s.id]||{}),present:flags[s.id]?.present===true,mdm:flags[s.id]?.mdm===true,breakfast:flags[s.id]?.breakfast===true}));
    return {registered,attendance:daySnap.exists?{present:day.present||{},mdm:day.mdm||{},breakfastTotal:asInt(day.breakfastTotal),registered,genderBreakdown:day.genderBreakdown||{}}:null,students,studentDetailsSaved:day.studentDetailsSaved===true,attendanceMode:text(day.attendanceMode,'none'),genderBreakdown:day.genderBreakdown||{}};
  }
  if (action === 'saveAttendance') {
    const className=text(data.className),date=text(data.date);ensureClassPermission(ctx,className);if(!dateIsValid(date))throw new HttpsError('invalid-argument','Invalid date.');
    const school=await getSchool(ctx);const cfg=classConfig(school,className);const ref=dayRef(ctx.schoolId,cfg.label||cfg.key,date);const oldSnap=await ref.get();const old=oldSnap.exists?oldSnap.data():{};
    const present=countsFrom(data,'pres'),mdm=countsFrom(data,'mdm');const breakfastTotal=asInt(data.breakfastTotal);let registered=old.registered||await effectiveRegistration(ctx.schoolId,cfg.label||cfg.key,date,old);
    const suppliedRegistered = ['regSC','regST','regOBC','regOTHER'].some(k=>data[k]!==undefined);
    let regChanged=false;
    if (suppliedRegistered) {
      const nextRegistered = countsFrom(data,'reg');
      // Avoid reading/writing RegistrationHistory again when this day's saved
      // registration is already identical. The Save button still persists any
      // other changed attendance fields below.
      if (!old.registered || hasChanges(old.registered, nextRegistered)) {
        registered = nextRegistered;
        const result = await saveRegistrationIfChanged(ctx.schoolId, cfg.label || cfg.key, date, nextRegistered);
        regChanged = result.changed;
      } else {
        registered = old.registered;
      }
    }
    const genderBreakdown=computeGenderBreakdownFromManual(data.genderBreakdown,registered,present,mdm,breakfastTotal);
    const next={date,classKey:cfg.key,className:cfg.label||cfg.key,reportGroup:groupForClass(cfg),registered,present,mdm,breakfastTotal,genderBreakdown,attendanceMode:'direct',studentDetailsSaved:false,updatedBy:ctx.teacherName,updatedAt:FieldValue.serverTimestamp()};
    const compare={...next,updatedAt:null};const previous={...old,updatedAt:null};delete previous.updatedAt;delete compare.updatedAt;
    if(oldSnap.exists&&!hasChanges(previous,compare))return {result:'success',noChanges:true,message:'No changes to save.'};
    await ref.set(next,{merge:true});invalidateServerCache(ctx.schoolId);return {result:'success',message:'Attendance saved.',date,registered,regChanged};
  }
  if (action === 'saveRegistrationCounts') {
    const className=text(data.className),date=text(data.date);ensureClassPermission(ctx,className);if(!dateIsValid(date))throw new HttpsError('invalid-argument','Invalid date.');
    const school=await getSchool(ctx);const cfg=classConfig(school,className);const registered={'SC':asInt(data.sc),'ST':asInt(data.st),'OBC':asInt(data.obc),'OTHER':asInt(data.other)};
    const ref=dayRef(ctx.schoolId,cfg.label||cfg.key,date);const snap=await ref.get();const old=snap.exists?snap.data():{};
    const nextGender=parseJson(data.genderBreakdown,old.genderBreakdown||{});
    const dayChanged=!old.registered||hasChanges(old.registered,registered)||hasChanges(old.genderBreakdown||{},nextGender);
    let regChanged=false;
    if (!old.registered || hasChanges(old.registered,registered)) {
      const result=await saveRegistrationIfChanged(ctx.schoolId,cfg.label||cfg.key,date,registered);
      regChanged=result.changed;
    }
    if(dayChanged){await ref.set({date,classKey:cfg.key,className:cfg.label||cfg.key,reportGroup:groupForClass(cfg),registered,genderBreakdown:nextGender,updatedBy:ctx.teacherName,updatedAt:FieldValue.serverTimestamp()},{merge:true});}
    if(dayChanged)invalidateServerCache(ctx.schoolId);
    return {result:'success',changed:dayChanged,regChanged,noChanges:!dayChanged,message:dayChanged?'Registration counts saved.':'No changes to save.'};
  }
  if (action === 'saveStudentAttendance') {
    const className=text(data.className),date=text(data.date);ensureClassPermission(ctx,className);if(!dateIsValid(date))throw new HttpsError('invalid-argument','Invalid date.');
    const school=await getSchool(ctx);const {cfg,ref,data:klass}=await classRosters(ctx,school,className);const dayRef_=ref.collection('attendanceDays').doc(date);const oldSnap=await dayRef_.get();const old=oldSnap.exists?oldSnap.data():{};
    const presentIds=new Set(text(data.presentIds).split(',').filter(Boolean));const mdmIds=new Set(text(data.mdmIds).split(',').filter(Boolean));const breakfastIds=new Set(text(data.breakfastIds).split(',').filter(Boolean));const flags={};for(const s of klass.rosterLite||[]){const id=text(s.id);const present=presentIds.has(id);flags[id]={present,mdm:present&&mdmIds.has(id),breakfast:present&&breakfastIds.has(id)};}
    const summary=summarizeStudentFlags(klass.rosterLite||[],flags,school.schoolType);let registered=old.registered||await effectiveRegistration(ctx.schoolId,cfg.label||cfg.key,date,old);const next={date,classKey:cfg.key,className:cfg.label||cfg.key,reportGroup:groupForClass(cfg),registered,present:summary.present,mdm:summary.mdm,breakfastTotal:summary.breakfastTotal,genderBreakdown:summary.genderBreakdown,studentFlags:flags,attendanceMode:'student',studentDetailsSaved:true,updatedBy:ctx.teacherName,updatedAt:FieldValue.serverTimestamp()};
    const cmp={...next,updatedAt:null};const prev={...old,updatedAt:null};delete cmp.updatedAt;delete prev.updatedAt;if(oldSnap.exists&&!hasChanges(cmp,prev))return {result:'success',noChanges:true,message:'No changes to save.'};await dayRef_.set(next,{merge:true});invalidateServerCache(ctx.schoolId);return {result:'success',message:'Student attendance saved.',date,summary};
  }
  if (action === 'getAttendance') {
    const className=text(data.className);ensureClassPermission(ctx,className);const cfg=classConfig(await getSchool(ctx),className);const snap=await classRef(ctx.schoolId,cfg.label||cfg.key).collection('attendanceDays').orderBy('date','desc').limit(180).get();const out={};for(const d of snap.docs){const x=d.data();out[x.date||d.id]={present:x.present||{},mdm:x.mdm||{},breakfastTotal:asInt(x.breakfastTotal),registered:x.registered||{},genderBreakdown:x.genderBreakdown||{}};}return out;
  }
  if (action === 'getDateWiseReportByDate') {
    const date=text(data.date);if(!dateIsValid(date))throw new HttpsError('invalid-argument','Date must be YYYY-MM-DD.');const school=await getSchool(ctx);const rows=await readDailyRows(ctx,school,date);if(!rows.length)return {result:'error',code:'NO_REPORT_DATA',message:`${date} માટે saved attendance data મળ્યો નથી.`};return {result:'success',date,schoolName:school.schoolName,values:tableForDateRows(date,rows,school),serial:'',recordCount:rows.length};
  }
  if (action === 'getDateWiseReport') return {result:'error',message:'Serial-number reports have been replaced by date-based reports. Use getDateWiseReportByDate.'};
  if (action === 'saveDateWisePDFByDate' || action === 'saveDateWisePDF') {
    const date=text(data.date||data.serial);if(!dateIsValid(date))throw new HttpsError('invalid-argument','Use a date in YYYY-MM-DD format.');const school=await getSchool(ctx);const rows=await readDailyRows(ctx,school,date);if(!rows.length)return {result:'error',message:`${date} માટે saved attendance data મળ્યો નથી.`};const metrics=[['registered','નોંધાયેલ'],['present','હાજર'],['mdm','PM Poshan']];const sections=[];const enabled=reportGenderEnabled(school);for(const [metric,title] of metrics){const headers=['ધોરણ','તારીખ'];for(const cat of ['SC','ST','OBC','OTHER','TOTAL'])enabled?headers.push(`${cat} Boys`,`${cat} Girls`,`${cat} Total`):headers.push(cat);const dataRows=rows.map(row=>{const v=[row.className,date];for(const cat of ['SC','ST','OBC','OTHER']){const c=categoryGenderTotals(row,metric,cat,enabled);enabled?v.push(c.boys===null?'—':c.boys,c.girls===null?'—':c.girls,c.total??0):v.push(asInt(row[metric]?.[cat]));}if(enabled){const g=row.genderBreakdown||{};const b=asInt(g.BOYS?._OVERALL?.[metric]);const gr=asInt(g.GIRLS?._OVERALL?.[metric]);const has=g.BOYS?._OVERALL?.[metric]!==undefined||g.GIRLS?._OVERALL?.[metric]!==undefined;v.push(has?b:'—',has?gr:'—',has?b+gr:countTotal(row[metric]));}else v.push(countTotal(row[metric]));return v;});sections.push({title,headers,rows:dataRows});}sections.push({title:'નાસ્તો / Breakfast',headers:['ધોરણ','તારીખ','Breakfast'],rows:rows.map(r=>[r.className,date,asInt(r.breakfastTotal)])});return await createPdf({title:`${school.schoolName} — DATE WISE`,subtitle:`Date: ${date} | Each Total = Boys + Girls where gender is recorded`,sections,landscape:true,size:enabled?'A3':'A4',fileName:`DATE-WISE-${date}.pdf`});
  }
  if (['getBalvatikaEkandarPDF','getStd1to5EkandarPDF','getStd6to8EkandarPDF','getTarijPDF'].includes(action)) return makeMonthlyReport(ctx,action,data.month);
  if (action === 'getTarijClassNames') { const school=await getSchool(ctx);return {result:'success',classes:(school.classes||[]).filter(c=>c.active!==false&&isClassAllowed(ctx,c)).map(c=>c.key||c.label)}; }
  if (action === 'getTarijClassData') {
    const className=text(data.className);ensureClassPermission(ctx,className);const school=await getSchool(ctx);const cfg=classConfig(school,className);const bounds=monthBounds(data.month);const snap=await classRef(ctx.schoolId,cfg.label||cfg.key).collection('attendanceDays').where('date','>=',bounds.start).where('date','<=',bounds.end).orderBy('date','asc').get();const days=snap.docs.map(d=>d.data());if(!days.length)return {result:'error',message:`${className} માટે ${bounds.caption} data મળ્યો નથી.`};const agg=sumDays(days);const totalReg=countTotal(agg.registered);const present=countTotal(agg.presentSum);const attendancePct=agg.dayCount?Math.round((present/(Math.max(1,totalReg*agg.dayCount)))*10000)/100:0;const headers=[['મહિનો',bounds.caption,'','ધોરણ',cfg.label||cfg.key],['વિગત','મૂલ્ય','','વિગત','મૂલ્ય'],['કુલ નોંધાયેલ',totalReg,'કુલ હાજરી',present,'હાજરી ટકા',attendancePct]];const row=[cfg.label||cfg.key,totalReg,0,0,countTotal(agg.presentSum),countTotal(agg.mdmSum),agg.breakfastSum,agg.dayCount,attendancePct];return {result:'success',className:cfg.label||cfg.key,month:bounds.caption,headers,row};
  }
  if (action === 'getGenderSummary') {
    const school=await getSchool(ctx);const bounds=monthBounds(data.month);const group=text(data.group,'ALL');const classes=(school.classes||[]).filter(c=>c.active!==false&&isClassAllowed(ctx,c)&&(group==='ALL'||groupForClass(c)===group));const rows=[];for(const c of classes){const snap=await schoolRef(ctx.schoolId).collection('classes').doc(c.id||classIdFor(c.label||c.key)).collection('attendanceDays').where('date','>=',bounds.start).where('date','<=',bounds.end).orderBy('date','asc').get();for(const d of snap.docs){const x=d.data();for(const gender of ['BOYS','GIRLS','UNSPECIFIED'])for(const category of ['SC','ST','OBC','OTHER'])rows.push({date:x.date,className:c.label||c.key,category,gender,...(x.genderBreakdown?.[gender]?.[category]||{})});}}
    return {result:'success',schoolName:school.schoolName,month:bounds.caption,rows,legacyNote:'Historical records without a recorded gender remain unassigned.'};
  }
  if (action === 'getGenderSummaryPDF') {
    const summary=await handleAuthed(ctx,'getGenderSummary',data);const rows=summary.rows||[];const sections=[{title:'Gender-wise Attendance',headers:['Date','Class','Category','Gender','Registered','Present','PM Poshan','Breakfast'],rows:rows.map(r=>[r.date,r.className,r.category,r.gender,asInt(r.registered),asInt(r.present),asInt(r.mdm),asInt(r.breakfast)])}];return await createPdf({title:`${summary.schoolName} — Gender-wise Summary`,subtitle:summary.month,sections,landscape:true,size:'A3',fileName:'Gender-Wise-Attendance.pdf'});
  }
  if (action === 'getTodayMessage') { const date=text(data.date);const snap=await schoolRef(ctx.schoolId).collection('messages').doc(date).get();return {result:'success',message:snap.exists?text(snap.data().message):''}; }
  if (action === 'getHolidays') { const snap=await schoolRef(ctx.schoolId).collection('holidays').limit(250).get();const out={};for(const d of snap.docs)out[d.id]=text(d.data().reason);return out; }
  if (action === 'saveHoliday') {
    const date=text(data.date); if(!dateIsValid(date)) throw new HttpsError('invalid-argument','Invalid holiday date.');
    const ref=schoolRef(ctx.schoolId).collection('holidays').doc(date); const nextReason=text(data.reason); const old=await ref.get();
    if(old.exists && text(old.data().reason)===nextReason) return {result:'success',noChanges:true,message:'No changes to save.'};
    await ref.set({date,reason:nextReason,updatedAt:FieldValue.serverTimestamp()},{merge:true});invalidateServerCache(ctx.schoolId);return {result:'success'};
  }
  if (action === 'deleteHoliday') {
    const ref=schoolRef(ctx.schoolId).collection('holidays').doc(text(data.date)); const old=await ref.get();
    if(!old.exists) return {result:'success',noChanges:true};
    await ref.delete();invalidateServerCache(ctx.schoolId);return {result:'success'};
  }
  if (action === 'saveMessage') {
    const date=text(data.date); if(!dateIsValid(date)) throw new HttpsError('invalid-argument','Invalid message date.');
    const ref=schoolRef(ctx.schoolId).collection('messages').doc(date); const nextMessage=text(data.message); const old=await ref.get();
    if(old.exists && text(old.data().message)===nextMessage) return {result:'success',noChanges:true,message:'No changes to save.'};
    await ref.set({date,message:nextMessage,updatedAt:FieldValue.serverTimestamp()},{merge:true});invalidateServerCache(ctx.schoolId);return {result:'success'};
  }
  if (action === 'getMessages') { const snap=await schoolRef(ctx.schoolId).collection('messages').orderBy('date','desc').limit(50).get();return {result:'success',messages:snap.docs.map(d=>d.data())}; }
  if (action === 'deleteMessage') {
    const ref=schoolRef(ctx.schoolId).collection('messages').doc(text(data.date)); const old=await ref.get();
    if(!old.exists) return {result:'success',noChanges:true};
    await ref.delete();invalidateServerCache(ctx.schoolId);return {result:'success'};
  }
  if (action === 'getResultData') {
    const school=await getSchool(ctx);const {cfg,ref,data:klass}=await classRosters(ctx,school,text(data.className));ensureClassPermission(ctx,cfg.label||cfg.key);const snap=await ref.collection('results').doc('current').get();const result=snap.exists?snap.data():{};return {result:'success',className:cfg.label||cfg.key,subjects:result.subjects||[],vvSentences:result.vvSentences||[],students:result.students||[],teacherName:ctx.teacherName,resultDate:school.resultDate||'30/04/2027',academicYear:school.academicYear||'2026 - 27',sem1Locked:result.sem1Locked===true,sem2Locked:result.sem2Locked===true};
  }
  if (action === 'saveSubjectMarks') {
    const className=text(data.className);ensureClassPermission(ctx,className);const school=await getSchool(ctx);const cfg=classConfig(school,className);const ref=classRef(ctx.schoolId,cfg.label||cfg.key).collection('results').doc('current');const payload=parseJson(data.payload,[]);const snap=await ref.get();const current=snap.exists?snap.data():{students:[],subjects:[]};const students=Array.isArray(current.students)?current.students.map(s=>({...s})):[];const sem=text(data.sem,'1')==='2'?'sem2':'sem1';const subject=text(data.subject);let changed=false;for(const entry of Array.isArray(payload)?payload:[]){const id=text(entry.id||entry.roll||entry.rollNumber||entry.sheetRow);let student=students.find(s=>text(s.id||s.roll||s.rollNumber||s.sheetRow)===id);if(!student){student={...entry};students.push(student);changed=true;continue;}const marks=entry.marks||entry[sem]||entry;student[sem]=student[sem]||{};if(hasChanges(student[sem][subject]||{},marks)){student[sem][subject]=marks;changed=true;}}if(!changed)return {result:'success',noChanges:true};await ref.set({students,updatedAt:FieldValue.serverTimestamp(),lastUpdatedBy:ctx.teacherName},{merge:true});invalidateServerCache(ctx.schoolId);return {result:'success',message:'Marks saved.'};
  }
  if (action === 'saveVvSentences' || action === 'saveClassSubjects') {
    const school=await getSchool(ctx);const cfg=classConfig(school,text(data.className));ensureClassPermission(ctx,cfg.label||cfg.key);
    const field=action==='saveVvSentences'?'vvSentences':'subjects'; const payload=parseJson(action==='saveVvSentences'?data.sentencesJson:data.subjectsJson,[]);
    const ref=classRef(ctx.schoolId,cfg.label||cfg.key).collection('results').doc('current'); const old=await ref.get();
    if(old.exists && !hasChanges(old.data()[field]||[],payload)) return {result:'success',noChanges:true,message:'No changes to save.'};
    await ref.set({[field]:payload,updatedAt:FieldValue.serverTimestamp()},{merge:true});invalidateServerCache(ctx.schoolId);return {result:'success'};
  }
  if (action === 'toggleResultLock') {
    const school=await getSchool(ctx);const cfg=classConfig(school,text(data.className));ensureClassPermission(ctx,cfg.label||cfg.key);const sem=text(data.sem)==='2'?'sem2Locked':'sem1Locked';const locked=text(data.locked).toLowerCase()==='true';
    const ref=classRef(ctx.schoolId,cfg.label||cfg.key).collection('results').doc('current');const old=await ref.get();
    if(old.exists && old.data()[sem]===locked) return {result:'success',noChanges:true};
    await ref.set({[sem]:locked,updatedAt:FieldValue.serverTimestamp()},{merge:true});invalidateServerCache(ctx.schoolId);return {result:'success'};
  }
  if (action === 'addNewStudent' || action === 'manageStudentProfile') {
    const school=await getSchool(ctx);const className=text(data.className);ensureClassPermission(ctx,className);const cfg=classConfig(school,className);const profile=parseJson(data.studentJson,{});const id=text(profile.id)||`s_${crypto.randomUUID().replace(/-/g,'').slice(0,20)}`;const normalized=normalizeProfile({...profile,id},cfg,school.schoolType);const ref=classRef(ctx.schoolId,cfg.label||cfg.key);const studentRef=ref.collection('students').doc(id);const old=await studentRef.get();const actionType=text(data.actionType,'upsert').toLowerCase();if(actionType==='delete'){if(old.exists)await studentRef.delete();const classSnap=await ref.get();if(classSnap.exists)await ref.update({rosterLite:(classSnap.data().rosterLite||[]).filter(s=>s.id!==id)});invalidateServerCache(ctx.schoolId);return {result:'success'};}await studentRef.set(normalized,{merge:true});const currentClass=await ref.get();const lite=buildLiteStudent(normalized,id,school.schoolType);const roster=(currentClass.data()?.rosterLite||[]).filter(s=>s.id!==id);roster.push(lite);roster.sort((a,b)=>asInt(a.rollNumber)-asInt(b.rollNumber));await ref.update({rosterLite:roster,updatedAt:FieldValue.serverTimestamp()});invalidateServerCache(ctx.schoolId);return {result:'success',student:lite};
  }
  if (action === 'setStudentGender') {
    const school=await getSchool(ctx);const className=text(data.className);ensureClassPermission(ctx,className);const cfg=classConfig(school,className);const ref=classRef(ctx.schoolId,cfg.label||cfg.key);const roll=text(data.rollNumber);const name=text(data.name);const cls=await ref.get();const roster=cls.data()?.rosterLite||[];const found=roster.find(s=>(roll&&text(s.rollNumber)===roll)||(!roll&&normalizeName(s.name)===normalizeName(name)));if(!found)throw new HttpsError('not-found','Student was not found.');const gender=normalizeGender(data.gender,school.schoolType);if(normalizeGender(found.gender,school.schoolType)===gender)return {result:'success',gender,noChanges:true};const nextRoster=roster.map(s=>s.id===found.id?{...s,gender}:s);await ref.update({rosterLite:nextRoster});await ref.collection('students').doc(found.id).set({gender,updatedAt:FieldValue.serverTimestamp()},{merge:true});invalidateServerCache(ctx.schoolId);return {result:'success',gender};
  }
  if (action === 'getCustomHeaders') { const school=await getSchool(ctx);return {result:'success',headers:school.customHeaders||[]}; }
  if (action === 'saveCustomHeaders') {
    const headers=parseJson(data.headers,[]);const next=Array.isArray(headers)?headers.map(text):[];const school=await getSchool(ctx);
    if(!hasChanges(school.customHeaders||[],next)) return {result:'success',noChanges:true,message:'No changes to save.'};
    await schoolRef(ctx.schoolId).update({customHeaders:next,updatedAt:FieldValue.serverTimestamp()});invalidateServerCache(ctx.schoolId);return {result:'success'};
  }
  if (action === 'uploadSchoolLogo') {
    const b64=text(data.base64).replace(/^data:image\/[^;]+;base64,/,'');const mime=text(data.mimeType,'image/png');if(!b64||!['image/png','image/jpeg','image/webp'].includes(mime))throw new HttpsError('invalid-argument','Use a PNG, JPEG or WebP logo.');const bytes=Buffer.from(b64,'base64');if(bytes.length>2*1024*1024)throw new HttpsError('invalid-argument','Logo must be 2 MB or smaller.');const bucket=getStorage().bucket();const file=bucket.file(`schools/${ctx.schoolId}/logo.${mime==='image/jpeg'?'jpg':mime==='image/webp'?'webp':'png'}`);await file.save(bytes,{metadata:{contentType:mime,cacheControl:'public,max-age=3600'}});const [url]=await file.getSignedUrl({action:'read',expires:Date.now()+365*24*60*60*1000});await schoolRef(ctx.schoolId).update({logoUrl:url,updatedAt:FieldValue.serverTimestamp()});invalidateServerCache(ctx.schoolId);return {result:'success',logoUrl:url};
  }
  if (action === 'getHajariFrontPagePDF' || action === 'getHajariPatrakPDF' || action === 'exportResultPdf') {
    return {result:'error',code:'REPORT_TEMPLATE_PENDING',message:'This legacy result/attendance certificate layout still needs to be ported and compared against the supplied school-specific PDF template. No blank or inaccurate PDF was generated.'};
  }
  if (action === 'getSavedPdfSettings') return {result:'success',customRowHeight:'',customFontSize:''};
  if (action === 'submitLeave') { const ref=schoolRef(ctx.schoolId).collection('leaveRecords').doc();await ref.set({...data,id:ref.id,teacherName:ctx.teacherName,status:'Pending',createdAt:FieldValue.serverTimestamp()});invalidateServerCache(ctx.schoolId);return {result:'success',id:ref.id}; }
  if (action === 'getPendingLeaves') { const snap=await schoolRef(ctx.schoolId).collection('leaveRecords').where('status','==','Pending').limit(100).get();return {result:'success',leaves:snap.docs.map(d=>d.data())}; }
  if (action === 'approveLeave') { const id=text(data.id);await schoolRef(ctx.schoolId).collection('leaveRecords').doc(id).update({status:text(data.status),approvedBy:ctx.teacherName,updatedAt:FieldValue.serverTimestamp()});invalidateServerCache(ctx.schoolId);return {result:'success'}; }
  if (action === 'getUtilizedLeaves') { const snap=await schoolRef(ctx.schoolId).collection('leaveRecords').where('teacherName','==',text(data.teacher)).where('status','==','Approved').limit(100).get();const days=snap.docs.reduce((sum,d)=>sum+asInt(d.data().days),0);return {result:'success',teacher:text(data.teacher),days,records:snap.docs.map(d=>d.data())}; }
  if (action === 'exportStudentDataExcel') {
    const school=await getSchool(ctx);const filter=text(data.classFilter,'ALL');const classes=(school.classes||[]).filter(c=>c.active!==false&&(filter==='ALL'||filter==='BLANK_TEMPLATE'||normalizeClass(c.label||c.key)===normalizeClass(filter))&&isClassAllowed(ctx,c));const headers=text(data.columns).split(',').filter(Boolean);const rows=[headers];for(const c of classes){const ref=classRef(ctx.schoolId,c.label||c.key);const roster=(await ref.get()).data()?.rosterLite||[];for(const s of roster){if(filter==='BLANK_TEMPLATE')continue;rows.push(headers.map(h=>s[h]??s[toCamel(h)]??''));}}const wb=XLSX.utils.book_new();const ws=XLSX.utils.aoa_to_sheet(filter==='BLANK_TEMPLATE'?[headers]:rows);XLSX.utils.book_append_sheet(wb,ws,'Students');const out=XLSX.write(wb,{bookType:'xlsx',type:'base64'});return {result:'success',base64:out,fileName:filter==='BLANK_TEMPLATE'?'Blank_Template.xlsx':'Student_Export.xlsx'};
  }
  if (action === 'bulkUploadRoster') {
    const school=await getSchool(ctx);const dataByClass=parseJson(data.data,{});if(!dataByClass||typeof dataByClass!=='object')throw new HttpsError('invalid-argument','Bulk upload data is invalid.');let saved=0;for(const [className,rawRows] of Object.entries(dataByClass)){ensureClassPermission(ctx,className);const cfg=classConfig(school,className);const rows=Array.isArray(rawRows)?rawRows:[];const ref=classRef(ctx.schoolId,cfg.label||cfg.key);const classSnap=await ref.get();let roster=(classSnap.data()?.rosterLite||[]).filter(s=>!rows.some(r=>text(r.rollNumber||r.roll)===text(s.rollNumber)));const batch=db.batch();for(const raw of rows){if(!raw||typeof raw!=='object')continue;const id=text(raw.id)||`r_${crypto.createHash('sha256').update(text(raw.rollNumber||raw.roll||raw.gr||raw.name)).digest('hex').slice(0,20)}`;const item=normalizeProfile({...raw,id},cfg,school.schoolType);batch.set(ref.collection('students').doc(id),item,{merge:true});roster=roster.filter(s=>s.id!==id);roster.push(buildLiteStudent(item,id,school.schoolType));saved++;}if(saved){batch.set(ref,{rosterLite:roster,updatedAt:FieldValue.serverTimestamp()},{merge:true});await batch.commit();}}invalidateServerCache(ctx.schoolId);return {result:'success',saved,message:`${saved} student records processed.`};
  }
  if (action === 'getStudentBirthdays') { const school=await getSchool(ctx);const classNames=text(data.classes).split(',').map(text).filter(Boolean);const date=new Date();const m=String(date.getMonth()+1).padStart(2,'0');const d=String(date.getDate()).padStart(2,'0');const birthdays=[];for(const name of classNames){if(!isAdmin(ctx))ensureClassPermission(ctx,name);const cfg=classConfig(school,name);const ref=classRef(ctx.schoolId,cfg.label||cfg.key);const snap=await ref.get();for(const s of snap.data()?.rosterLite||[])if(String(s.mm).padStart(2,'0')===m&&String(s.dd).padStart(2,'0')===d)birthdays.push({name:s.name,className:cfg.label||cfg.key});}return {result:'success',message:birthdays.map(b=>`${b.name} (${b.className})`).join(', '),birthdays}; }
  if (action === 'exportResultPdf') return {result:'error',code:'REPORT_TEMPLATE_PENDING',message:'Result PDF templates will be ported after result data migration and visual comparison.'};
  if (action === 'getDateWiseReportByDate') throw new HttpsError('internal','Unexpected routing');
  throw new HttpsError('unimplemented', `Firebase migration does not yet implement action '${action}'. Keep Apps Script mode for this feature until its migration test passes.`);
}
function toCamel(v) { return String(v).replace(/[_\s-]+(.)?/g,(_,c)=>c?c.toUpperCase():''); }
async function getSchoolConfigFor(schoolId) {
  const snap = await schoolRef(schoolId).get();
  if (!snap.exists) return { result: 'error', message: 'School not found.' };
  const d = snap.data();
  const safeKeys = ['schoolName','schoolType','logoUrl','reportGenderSplitEnabled','village','taluka','district','schoolDiseCode','educationAuthorityName','centerName','crcName','medium','academicYear','resultDate','customHeaders'];
  const config = Object.fromEntries(safeKeys.filter(k => d[k] !== undefined).map(k => [k, d[k]]));
  return { result: 'success', school: publicSchool({ id: snap.id, ...d }), config, classes: (d.classes || []).filter(c => c.active !== false) };
}

const HEAVY_ACTIONS = new Set([
  'saveDateWisePDFByDate','saveDateWisePDF','getBalvatikaEkandarPDF','getStd1to5EkandarPDF',
  'getStd6to8EkandarPDF','getTarijPDF','getGenderSummaryPDF','getHajariFrontPagePDF',
  'getHajariPatrakPDF','exportResultPdf','exportStudentDataExcel','bulkUploadRoster','uploadSchoolLogo'
]);
const WRITE_ACTIONS = new Set([
  'updateSchoolConfig','createClass','createTeacher','deactivateTeacher','changePassword',
  'saveAttendance','saveStudentAttendance','saveRegistrationCounts','saveHoliday','deleteHoliday',
  'saveMessage','deleteMessage','saveSubjectMarks','saveVvSentences','saveClassSubjects',
  'toggleResultLock','manageStudentProfile','setStudentGender','uploadSchoolLogo','submitLeave',
  'approveLeave','saveCustomHeaders','bulkUploadRoster'
]);
async function dispatchSchoolApi(request, channel) {
  const data = request.data && typeof request.data === 'object' ? request.data : {};
  const action = text(data.action);
  try {
    if (channel === 'standard' && HEAVY_ACTIONS.has(action)) {
      throw new HttpsError('failed-precondition', `API '${action}' must use reportApi.`);
    }
    if (channel === 'report' && !HEAVY_ACTIONS.has(action)) {
      throw new HttpsError('invalid-argument', `API '${action}' is not a report/export action.`);
    }
    if (PUBLIC_ACTIONS.has(action)) {
      return await doCachedRead(null, action, data, () => handlePublic(action, data, developerKey.value()));
    }
    const ctx = authContext(request, data, false);
    if (WRITE_ACTIONS.has(action)) {
      const result = await handleAuthed(ctx, action, data);
      invalidateServerCache(ctx.schoolId, ctx.schoolCode);
      return result;
    }
    return await doCachedRead(ctx, action, data, () => handleAuthed(ctx, action, data));
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.error(`${channel} API action failed`, action, e);
    throw new HttpsError('internal', `API '${action}' failed safely. Check Cloud Functions logs for details.`);
  }
}

// CRUD/auth endpoint uses 256 MiB. PDF, spreadsheet export and large upload
// actions use a separate 512 MiB endpoint so every attendance save does not pay
// the memory allocation of report generation.
export const schoolApi = onCall({ secrets:[developerKey], timeoutSeconds:60, memory:'256MiB' }, request => dispatchSchoolApi(request, 'standard'));
export const reportApi = onCall({ secrets:[developerKey], timeoutSeconds:120, memory:'512MiB' }, request => dispatchSchoolApi(request, 'report'));

const msg91AuthKey = defineSecret('MSG91_AUTHKEY');
const msg91TemplateId = defineSecret('MSG91_OTP_TEMPLATE_ID');

function indiaTodayIso() {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Kolkata',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date());
}

function normaliseIndianMobile(value) {
  let digits = text(value).replace(/\D/g, '');
  if (digits.startsWith('00')) digits = digits.slice(2);
  if (digits.length === 10) digits = `91${digits}`;
  else if (digits.length === 11 && digits.startsWith('0')) digits = `91${digits.slice(1)}`;
  if (!/^91[6-9]\d{9}$/.test(digits)) {
    throw new HttpsError('invalid-argument', 'A valid registered Indian mobile number is required.');
  }
  return digits;
}

async function handlePsmPasswordResetOtp(body) {
  const action = text(body.action);
  const schoolId = text(body.schoolId).replace(/\s+/g, '');
  const teacherId = text(body.teacherId);
  if (!/^\d{4,20}$/.test(schoolId) || !teacherId) {
    throw new HttpsError('invalid-argument', 'Unable to verify this account. Check the school and selected user.');
  }
  const sSnap = await db.collection('schools').where('school_id', '==', schoolId).limit(1).get();
  if (sSnap.empty) throw new HttpsError('permission-denied', 'Password recovery is not available for this school.');
  const school = { id: sSnap.docs[0].id, ...sSnap.docs[0].data() };
  if (school.is_active !== true || school.is_blocked === true || (school.validity_date && String(school.validity_date) < indiaTodayIso())) {
    throw new HttpsError('permission-denied', 'Password recovery is not available for this school. Contact the Developer.');
  }
  const tSnap = await db.collection('school_teachers').doc(teacherId).get();
  if (!tSnap.exists) throw new HttpsError('not-found', 'Teacher account was not found.');
  const teacher = { id: tSnap.id, ...tSnap.data() };
  if (teacher.is_active !== true || String(teacher.school_ref) !== String(school.id) || !text(teacher.auth_user_id)) {
    throw new HttpsError('invalid-argument', 'Unable to verify this account.');
  }
  const mobile = normaliseIndianMobile(teacher.mobile);

  if (action === 'request') {
    const authKey = text(msg91AuthKey.value());
    const templateId = text(msg91TemplateId.value());
    if (!authKey || !templateId) {
      throw new HttpsError('failed-precondition', 'SMS OTP is not configured. Set MSG91_AUTHKEY and MSG91_OTP_TEMPLATE_ID secrets.');
    }
    const challengeId = crypto.randomUUID();
    const now = new Date();
    const expiresAt = new Date(now.getTime() + 5 * 60 * 1000).toISOString();
    await db.collection('password_reset_otps').doc(challengeId).set({
      id: challengeId,
      school_ref: school.id,
      teacher_id: teacher.id,
      mobile_e164: `+${mobile}`,
      provider: 'msg91',
      expires_at: expiresAt,
      attempts: 0,
      used_at: null,
      created_at: now.toISOString(),
    });
    const query = new URLSearchParams({ template_id: templateId, mobile, otp_length: '6', otp_expiry: '5' });
    const resp = await fetch(`https://control.msg91.com/api/v5/otp?${query.toString()}`, {
      method: 'POST',
      headers: { authkey: authKey, accept: 'application/json', 'content-type': 'application/json' },
      body: JSON.stringify({}),
    });
    const payload = await resp.json().catch(() => ({}));
    if (!resp.ok || (payload.type && String(payload.type).toLowerCase() !== 'success')) {
      await db.collection('password_reset_otps').doc(challengeId).delete();
      throw new HttpsError('unavailable', 'SMS provider could not send the OTP.');
    }
    return {
      ok: true,
      challengeId,
      maskedMobile: `******${mobile.slice(-4)}`,
      expiresInSeconds: 300,
      message: `OTP sent to the registered mobile ending ${mobile.slice(-4)}.`,
    };
  }

  if (action === 'verify_and_reset') {
    const challengeId = text(body.challengeId);
    const otp = text(body.otp);
    const newPassword = String(body.newPassword ?? '');
    if (!challengeId || !/^\d{6}$/.test(otp)) throw new HttpsError('invalid-argument', 'Enter the 6-digit OTP.');
    if (newPassword.length < 4 || newPassword.length > 15) {
      throw new HttpsError('invalid-argument', 'New password must contain 4 to 15 characters.');
    }
    const chDoc = await db.collection('password_reset_otps').doc(challengeId).get();
    if (!chDoc.exists) throw new HttpsError('invalid-argument', 'OTP expired or invalid. Request a new code.');
    const ch = chDoc.data();
    if (ch.used_at || Date.parse(String(ch.expires_at)) <= Date.now() || String(ch.mobile_e164) !== `+${mobile}`) {
      throw new HttpsError('invalid-argument', 'OTP expired or invalid. Request a new code.');
    }
    const attempts = Number(ch.attempts ?? 0) + 1;
    await chDoc.ref.update({ attempts });
    const authKey = text(msg91AuthKey.value());
    const query = new URLSearchParams({ mobile, otp });
    const resp = await fetch(`https://control.msg91.com/api/v5/otp/verify?${query.toString()}`, {
      method: 'GET',
      headers: { authkey: authKey, accept: 'application/json' },
    });
    const payload = await resp.json().catch(() => ({}));
    const verified = resp.ok && (String(payload.type || '').toLowerCase() === 'success' || String(payload.message || '').toLowerCase().includes('verified'));
    if (!verified) {
      if (attempts >= 5) await chDoc.ref.update({ used_at: new Date().toISOString() });
      throw new HttpsError('invalid-argument', 'Incorrect OTP. Check the code and try again.');
    }
    await chDoc.ref.update({ used_at: new Date().toISOString() });
    const fbPassword = newPassword.length >= 6 ? newPassword : 'psm#' + newPassword + '#key';
    await auth.updateUser(String(teacher.auth_user_id), { password: fbPassword });
    return { ok: true, message: 'Password changed successfully. Sign in using your new password.' };
  }

  throw new HttpsError('invalid-argument', 'Unsupported password reset action.');
}

export const psmEdgeFunction = onCall(
  { secrets: [developerKey, msg91AuthKey, msg91TemplateId], timeoutSeconds: 60, memory: '256MiB' },
  async (request) => {
    const data = request.data && typeof request.data === 'object' ? request.data : {};
    const functionName = text(data.functionName);
    const body = data.body && typeof data.body === 'object' ? data.body : {};
    if (functionName === 'psm-password-reset-otp') {
      return await handlePsmPasswordResetOtp(body);
    }
    throw new HttpsError('unimplemented', `Handled directly via Firestore client: ${functionName}`);
  }
);
