# Professional School Management — Firebase / Node.js migration

## What this update does

This package adds a Node.js 22 Firebase Cloud Functions backend while retaining the existing Apps Script source and URL as a transition option. Flutter chooses the backend from the URL entered in the setup screen:

- Existing Apps Script: `https://script.google.com/macros/s/.../exec`
- Firebase Functions: `firebase://asia-south1`

The Flutter `ApiService` still exposes the same service methods to the screens. In Firebase mode it calls the callable `schoolApi` or `reportApi` function; the browser/mobile client does **not** read Firestore documents directly. Firestore and Storage rules deliberately deny direct client access, and the callable backend validates the Firebase identity, school membership, role and class permissions.

## Read / write minimisation

- Form edits stay in Flutter widget/state memory. Existing Save buttons remain the commit boundary; merely typing into a field does not write to Firestore.
- Flutter has a per-`ApiService` RAM cache with action-specific TTLs. It includes school code, session UID, action and sorted parameters in the key, so cache entries cannot be shared between schools, users, classes or dates. The cache clears after a successful changed save, after a school/session change, and on logout. A confirmed no-op save keeps the cache.
- Cloud Functions also use a short per-instance read cache as an optimization. A cold start can lose that cache; correctness does not depend on it.
- One class/day uses one `attendanceDays/{YYYY-MM-DD}` summary document. Student-wise status flags are saved together when the teacher clicks Save, not one write per toggle.
- `registrationChanges` stores only effective change dates. Opening a later date looks up the last change at or before that date. It does not write a new history record every day when registration is unchanged.
- Students are stored as individual documents, with a compact `rosterLite` on the class document to serve the common attendance picker in a single class-document read.
- Save handlers compare relevant values and avoid writes for known no-change submissions.

RAM cache is temporary and disappears on app restart. A small amount of non-secret school configuration and session metadata remains in SharedPreferences for faster launch; the cache does not persist student data to disk. No client-side Firestore persistent cache is configured.

## Before you begin

1. Keep your existing Apps Script project and both Google workbooks. Do not delete or rename them.
2. Create a **separate development Firebase project** for the first test. Do not import into a project that already contains a school document with the same school code.
3. Back up the attendance and results workbooks.
4. For a first test, use copied/dummy school data. Switching a teacher to Firebase does not automatically synchronise new Firebase writes back into Google Sheets.

## A. Create the Firebase project

1. In Firebase Console, create a new project for development.
2. Create a Cloud Firestore database in Native mode. Use `asia-south1` to match the configured functions region.
3. Enable Firebase Authentication and create/enable Cloud Storage for the project. The app authenticates using a custom token minted by the trusted function; teacher PINs are never stored in the Flutter app.
4. Link billing (Cloud Functions deployment requires the Blaze/pay-as-you-go plan). Create a budget alert before production testing.
5. Install the Firebase CLI if needed:

   ```powershell
   npm install -g firebase-tools
   firebase login
   dart pub global activate flutterfire_cli
   ```

## B. Configure Flutter for Firebase

Run this from the project root `ProfessionalSchoolManagement`:

```powershell
flutterfire configure --project YOUR_FIREBASE_PROJECT_ID --platforms web,android
flutter pub get
```

`flutterfire configure` replaces the deliberately safe placeholder `lib/firebase_options.dart` with the real platform configuration. Do not choose Firebase mode before this step is complete. If you also build Windows or iOS, include those platforms in the configure command.

## C. Configure Node.js functions and deploy

From the project root:

```powershell
cd functions
npm install
npm run check
cd ..
firebase use --add
```

Select the development Firebase project when prompted. Generate a strong random developer secret locally (do not send it in chat or put it into Dart source):

```powershell
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
firebase functions:secrets:set PLATFORM_DEVELOPER_KEY
```

Paste the generated random value into the Firebase CLI prompt. Then deploy the backend and deny-by-default security rules:

```powershell
firebase deploy --only firestore:rules,firestore:indexes,storage,functions
```

The source defines `schoolApi` (256 MiB) for normal authenticated CRUD and `reportApi` (512 MiB) for PDF / XLSX / large operations. The report function is given a longer timeout. Both functions use the `PLATFORM_DEVELOPER_KEY` secret because school provisioning is a restricted developer action.

## D. Export the current Google Sheets school

The new export helper is `apps_script/EXPORT_FOR_FIREBASE_MIGRATION.gs`.

1. Open the **existing** Apps Script project (the project that owns your Schools registry), add a new script file, and paste this file's contents. Save.
2. Apps Script's Run button does not prompt for function arguments. Add a temporary wrapper at the bottom, replacing the code with the school code you are exporting:

   ```javascript
   function exportCurrentSchoolForFirebaseMigration() {
     return exportSchoolBundleForFirebaseMigration('YOUR_SCHOOL_CODE');
   }
   ```

3. Select `exportCurrentSchoolForFirebaseMigration` and click Run. Authorise read access if Google requests it.
4. Check the execution log for the private Drive export. Download the `.json.gz` file from that Drive entry and store it outside the Flutter project in a restricted backup folder.
5. Do not share the exported file publicly. It includes student data and the source workbook snapshots. Existing PINs are kept only if they are already `HASH$...$...` salted hashes; plaintext PINs are redacted and those teachers must have their PIN reset after migration.

The exporter reads both workbooks and writes a new private backup file. It does not change the source sheets. Keep the old Apps Script deployment available while testing.

## E. Dry-run then import

Create/download a Firebase service-account key for the **development** project and store it outside the source tree, for example `D:\secure\psm-firebase-service-account.json`. Never commit this file, add it to the ZIP, or send it in chat.

In PowerShell:

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS = 'D:\secure\psm-firebase-service-account.json'
$env:GCLOUD_PROJECT = 'YOUR_FIREBASE_PROJECT_ID'
cd 'D:\path\to\ProfessionalSchoolManagement\functions'
node scripts/import-legacy-export.js 'D:\migration\PSM-Firebase-Migration-SCH....json.gz' --dry-run
```

Review the reported counts (classes, teachers, students, attendance days, registration changes, result classes and result students) and any warnings. The script refuses to overwrite an unrelated existing school, and it requires at least one active administrator with a recognised hashed PIN. If the hash check fails, stop and resolve the administrator PIN in the old backend before exporting again.

When the dry-run looks correct, run the same command **without** `--dry-run`:

```powershell
node scripts/import-legacy-export.js 'D:\migration\PSM-Firebase-Migration-SCH....json.gz'
```

The importer retains the old school code, creates isolated class/teacher/student/attendance/result data, stores only hashed PIN data, imports daily class summaries and student attendance flags when present, and builds sparse registration change points. It imports matched master/semester result sheets into each class's `results/current` document. If interrupted, it can resume the migration-created school by merging the same version's data. Keep the source `.json.gz` as a restricted rollback/archive copy.

## F. Point Flutter at the migrated school

1. Start the updated Flutter project locally after `flutterfire configure`:

   ```powershell
   flutter clean
   flutter pub get
   flutter analyze
   flutter run -d chrome
   ```

2. On the setup screen, enter `firebase://asia-south1` as the backend URL.
3. Enter the same school code, select the teacher, and use the existing PIN **only if it was exported as a `HASH$...$...` hash**.
4. Confirm the school name and class list load before testing attendance.
5. Test a date with existing data, then edit a dummy day's values without saving and verify the cloud does not change; click Save and verify exactly the intended class/date changes.

## Current scope and important limitations

This is a migration baseline, not yet proof that every old Apps Script report template is equivalent.

- Core backend paths are ported for login, configuration, classes/teachers, student profile, direct and student-wise attendance, dated registration carry-forward, school summary, date-wise reports, basic monthly reports, gender summary and current result marks.
- The old result workbook is fully kept in the private export. A structured result state is imported where the six legacy result sheets can be matched, but custom formulas/formatting from the workbook do not migrate as formulas.
- Legacy front-page / Hajari Patrak / school-specific certificate PDF templates return an explicit `REPORT_TEMPLATE_PENDING` response instead of pretending to generate an identical PDF.
- `getTarijPDF` currently uses the Firebase monthly-report engine; it is **not yet visually and mathematically verified against every old special Tarij calculation**. Verify it side by side with a reference PDF before enabling Firebase as the live reporting backend.
- The Firebase provisioning endpoint exists, but the old HTML developer console is still Apps Script-based. Do not expose the developer secret inside Flutter; the developer-console UI must be ported separately before making Firebase the only school-provisioning path.
- Flutter SDK, Firebase credentials, a live Firestore database and an actual school workbook were not available in the packaging environment, so this bundle's source checks are not a live deployment or full Flutter-build certification.

## Rollback strategy

During the pilot, the old Apps Script URL remains usable for records that are still in Sheets. However, a write made in Firebase does not automatically sync back to Sheets. If you switch back to Apps Script after making new Firebase writes, those new writes will not appear in Google Sheets. For that reason, pilot with a test copy first and do not cut over the live school until attendance, registration carry-forward, results, DATE WISE, monthly EKANDAR and TARĲ have been compared and any remaining report templates are ported.

## Official Firebase documentation

- [Flutter setup](https://firebase.google.com/docs/flutter/setup)
- [Cloud Functions for Firebase setup and Node runtime](https://firebase.google.com/docs/functions/get-started)
- [Callable Functions and authentication context](https://firebase.google.com/docs/functions/callable)
- [Cloud Functions deployment, quotas and billing](https://firebase.google.com/docs/functions/quotas)
