/**
 * Deletes Firestore data the app never uses again, to cut storage and read
 * charges. Nothing school-related (students, attendance, results, rojmel,
 * library, settings…) is touched.
 *
 *   1. file_beam_rooms (+ their chunks)  — File Share transfers older than
 *      --days (default 7). Shared files are stored as chunks inside
 *      Firestore and were never removed, so this is usually the biggest win.
 *   2. password_reset_otps               — used or expired OTPs.
 *   3. school_registration_requests      — approved / rejected requests
 *      older than 30 days.
 *
 * Usage (from the functions folder):
 *   gcloud auth application-default login
 *   set GOOGLE_CLOUD_PROJECT=professional-school-management      (PowerShell: $env:GOOGLE_CLOUD_PROJECT="...")
 *   node scripts/cleanup-firestore.js                 # report only, deletes nothing
 *   node scripts/cleanup-firestore.js --apply         # really delete
 *   node scripts/cleanup-firestore.js --apply --days 15
 */
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

const args = process.argv.slice(2);
const apply = args.includes('--apply');
const daysIdx = args.indexOf('--days');
const days = daysIdx >= 0 ? Math.max(1, Number(args[daysIdx + 1]) || 7) : 7;
const projectId = process.env.GOOGLE_CLOUD_PROJECT || process.env.GCLOUD_PROJECT || 'professional-school-management';

initializeApp({ credential: applicationDefault(), projectId });
const db = getFirestore();

const now = Date.now();
const roomCutoff = now - days * 86400000;
const requestCutoff = now - 30 * 86400000;
const t = (v) => {
  if (!v) return NaN;
  if (typeof v.toDate === 'function') return v.toDate().getTime();
  return Date.parse(String(v));
};
const mb = (b) => (b / 1048576).toFixed(1);

async function cleanRooms() {
  const snap = await db.collection('file_beam_rooms').get();
  let count = 0;
  let bytes = 0;
  for (const doc of snap.docs) {
    const d = doc.data();
    const created = t(d.created_at || d.updated_at);
    // Rooms without a readable date are old test data: also removed.
    if (!Number.isNaN(created) && created >= roomCutoff) continue;
    count++;
    bytes += Number(d.total_bytes) || 0;
    if (apply) await db.recursiveDelete(doc.ref); // room + all its chunks
  }
  console.log(`File Share rooms older than ${days} days: ${count} of ${snap.size} (≈ ${mb(bytes)} MB of files)`);
}

async function cleanOtps() {
  const snap = await db.collection('password_reset_otps').get();
  let count = 0;
  for (const doc of snap.docs) {
    const d = doc.data();
    const exp = t(d.expires_at);
    if (d.used_at || Number.isNaN(exp) || exp <= now) {
      count++;
      if (apply) await doc.ref.delete();
    }
  }
  console.log(`Used / expired password OTPs: ${count} of ${snap.size}`);
}

async function cleanRequests() {
  const snap = await db.collection('school_registration_requests').get();
  let count = 0;
  for (const doc of snap.docs) {
    const d = doc.data();
    if (d.status !== 'approved' && d.status !== 'rejected') continue;
    const when = t(d.updated_at || d.created_at);
    if (!Number.isNaN(when) && when >= requestCutoff) continue;
    count++;
    if (apply) await doc.ref.delete();
  }
  console.log(`Closed registration requests older than 30 days: ${count} of ${snap.size}`);
}

console.log(`Project: ${projectId}  •  Mode: ${apply ? 'DELETE' : 'REPORT ONLY (add --apply to delete)'}`);
await cleanRooms();
await cleanOtps();
await cleanRequests();
console.log(apply ? 'Done — items above were deleted.' : 'Nothing was deleted. Run again with --apply to delete the items above.');
