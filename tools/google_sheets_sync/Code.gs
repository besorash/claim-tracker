/**
 * Claim Tracker <-> Google Sheets sync (server side).
 *
 * Paste this whole file into the sheet's Extensions -> Apps Script, run
 * `setup` once, then deploy as a Web app (Execute as: Me, Who has access:
 * Anyone). See README.md next to this file.
 *
 * The app talks to it with POST {token, action: 'pull' | 'push', ...}.
 * The token is a random secret stored in Script Properties by `setup`.
 */

const SHEET_NAME = ''; // empty = the first sheet tab
const STAMP = 'updated_at';
const DATETIME_COLS = ['next_follow_up'];

/** Run once by hand: creates the secret key and the updated_at column. */
function setup() {
  const token =
    Utilities.getUuid().replace(/-/g, '') + Utilities.getUuid().replace(/-/g, '');
  PropertiesService.getScriptProperties().setProperty('SYNC_TOKEN', token);
  ensureStampColumn_(sheet_());
  Logger.log('Sync key (copy it into the app): ' + token);
}

/** Simple trigger: stamps the edit time on every row the user changes. */
function onEdit(e) {
  const sh = e.range.getSheet();
  if (sh.getSheetId() !== sheet_().getSheetId()) return;
  const keys = headers_(sh).map(key_);
  const col = keys.indexOf(STAMP);
  if (col < 0) return;
  if (e.range.getNumColumns() === 1 && e.range.getColumn() === col + 1) return;
  const start = Math.max(e.range.getRow(), 2);
  const count = e.range.getRow() + e.range.getNumRows() - start;
  if (count <= 0) return;
  const now = "'" + new Date().toISOString(); // ' keeps it text
  sh.getRange(start, col + 1, count, 1)
    .setValues(Array.from({ length: count }, () => [now]));
}

function doPost(e) {
  let out;
  try {
    const body = JSON.parse(e.postData.contents);
    const token = PropertiesService.getScriptProperties().getProperty('SYNC_TOKEN');
    if (!token || body.token !== token) throw new Error('unauthorized');
    const lock = LockService.getScriptLock();
    lock.waitLock(30000);
    try {
      if (body.action === 'pull') out = pull_();
      else if (body.action === 'push') out = push_(body);
      else throw new Error('unknown action');
    } finally {
      lock.releaseLock();
    }
    out.ok = true;
  } catch (err) {
    out = { ok: false, error: String((err && err.message) || err) };
  }
  return ContentService.createTextOutput(JSON.stringify(out))
    .setMimeType(ContentService.MimeType.JSON);
}

/** Every row as text: dates as yyyy-MM-dd, numbers as plain digits. */
function pull_() {
  const sh = sheet_();
  ensureStampColumn_(sh);
  const tz = SpreadsheetApp.getActiveSpreadsheet().getSpreadsheetTimeZone();
  const header = headers_(sh);
  const keys = header.map(key_);
  const last = sh.getLastRow();
  const rows = last < 2 ? [] : sh.getRange(2, 1, last - 1, header.length).getValues();
  return {
    header: header,
    rows: rows.map((r) => r.map((v, i) => cellOut_(v, keys[i], tz))),
  };
}

/**
 * body.setIds:  [{row, old, id}] write the app's id into a row (only if the
 *               row still holds `old`, so a row moved meanwhile is not hit).
 * body.upserts: [{id: '12', customer_name: ..., ...}] update the row with
 *               that id, or append a new row.
 * body.deletes: ['12', ...] remove the rows with those ids.
 */
function push_(body) {
  const sh = sheet_();
  ensureStampColumn_(sh);
  const header = headers_(sh);
  const keys = header.map(key_);
  const idCol = keys.indexOf('id');
  if (idCol < 0) throw new Error('the sheet has no id column');

  // Columns the app sends that the sheet does not have yet.
  (body.upserts || []).forEach((u) => Object.keys(u).forEach((k) => {
    if (keys.indexOf(key_(k)) < 0) {
      keys.push(key_(k));
      header.push(k);
      sh.getRange(1, header.length).setValue(k);
    }
  }));

  const last = sh.getLastRow();
  const ids = last < 2
    ? []
    : sh.getRange(2, idCol + 1, last - 1, 1).getValues().map((r) => String(r[0]).trim());

  let idMisses = 0;
  (body.setIds || []).forEach((s) => {
    const i = s.row - 2;
    if (i >= 0 && i < ids.length && ids[i] === String(s.old || '').trim()) {
      sh.getRange(s.row, idCol + 1).setValue(Number(s.id));
      ids[i] = String(s.id);
    } else {
      idMisses++;
    }
  });

  const appended = [];
  (body.upserts || []).forEach((u) => {
    const i = ids.indexOf(String(u.id));
    if (i < 0) {
      appended.push(keys.map((k) => textIn_(valueFor_(u, k))));
      return;
    }
    const r = i + 2;
    const range = sh.getRange(r, 1, 1, keys.length);
    const values = range.getValues()[0];
    const formulas = range.getFormulas()[0];
    const row = keys.map((k, c) => {
      const v = valueFor_(u, k);
      if (v !== undefined) return textIn_(v);
      if (formulas[c]) return formulas[c];
      return typeof values[c] === 'string' ? textIn_(values[c]) : values[c];
    });
    range.setValues([row]);
  });
  if (appended.length) {
    sh.getRange(sh.getLastRow() + 1, 1, appended.length, keys.length).setValues(appended);
  }

  const doomed = [];
  (body.deletes || []).forEach((id) => {
    const i = ids.indexOf(String(id));
    if (i >= 0) doomed.push(i + 2);
  });
  doomed.sort((a, b) => b - a).forEach((r) => sh.deleteRow(r));

  return { idMisses: idMisses };
}

function sheet_() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const sh = SHEET_NAME ? ss.getSheetByName(SHEET_NAME) : ss.getSheets()[0];
  if (!sh) throw new Error('sheet not found: ' + SHEET_NAME);
  return sh;
}

function headers_(sh) {
  const n = sh.getLastColumn();
  return n ? sh.getRange(1, 1, 1, n).getValues()[0].map((h) => String(h).trim()) : [];
}

function key_(h) {
  return String(h).trim().toLowerCase();
}

function ensureStampColumn_(sh) {
  const h = headers_(sh);
  if (h.map(key_).indexOf(STAMP) < 0) sh.getRange(1, h.length + 1).setValue(STAMP);
}

function valueFor_(u, key) {
  for (const k in u) if (key_(k) === key) return u[k];
  return undefined;
}

function cellOut_(v, key, tz) {
  if (v instanceof Date) {
    if (key === STAMP) return v.toISOString();
    const fmt = DATETIME_COLS.indexOf(key) >= 0 ? 'yyyy-MM-dd HH:mm' : 'yyyy-MM-dd';
    return Utilities.formatDate(v, tz, fmt);
  }
  return v === null || v === undefined ? '' : String(v);
}

/**
 * Text going into a cell. Sheets would turn `0501234567` into a number (losing
 * the 0) and `=...` into a formula, so those are written as plain text.
 */
function textIn_(v) {
  const s = v === null || v === undefined ? '' : String(v);
  if (/^[=+@]/.test(s) || /^0\d+$/.test(s) || /^\d{16,}$/.test(s)) return "'" + s;
  return s;
}
