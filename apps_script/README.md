# PDF service (Google Apps Script) — free, no Cloud Run

Website: **Browser Print** works without any setup (Hajari Patrak, Result,
Vyaktitva Vikas). The Apps Script is only needed for **PDF download** and
for printing from the **mobile app**.

## Set up one web app (5 minutes)

1. Open https://script.google.com → **New project**. Name it `PSM PDF`.
2. Delete the sample code, paste all of `Code.gs` from this folder, **Save**.
3. Choose the function `authorize` at the top and press **Run** once.
   Allow the permissions (Drive + Sheets). ("Google hasn't verified this
   app" → Advanced → Go to PSM PDF.)
4. **Deploy ▸ New deployment** → type **Web app**
   - Execute as: **Me**
   - Who has access: **Anyone**
   → **Deploy** and copy the **Web app URL** (ends with `/exec`).
5. In the app: **Developer screen ▸ PDF service — Google Apps Script URLs**,
   paste the URL, press **Save URLs**, then **Test** (should say `1: OK`).

## More teachers at the same time

One Google account runs about 30 scripts at the same time. Repeat steps 1–4
with other Google accounts and paste all URLs separated by commas. The app
spreads the work and moves to the next URL if one is busy.

## Updating the script later

Paste the new code, **Save**, then **Deploy ▸ Manage deployments ▸ ✏️ ▸
Version: New version ▸ Deploy**. The URL stays the same.

The workbook is converted to a temporary Google Sheet, exported as PDF and
the temporary file is deleted immediately — nothing stays in Drive.
