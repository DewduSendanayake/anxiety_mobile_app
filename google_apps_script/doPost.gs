/**
 * Optimized High-Concurrency Logger
 * - Parses data OUTSIDE the lock (faster)
 * - Prepares rows OUTSIDE the lock (faster)
 * - Uses incoming timestamps if available (better for offline sync)
 */

function doPost(e) {
  // 1. PRE-LOCK PREPARATION
  // Do all the heavy lifting here so we don't block other users.

  // A. Parse the incoming data
  var payload;
  try {
    if (e && e.postData && e.postData.contents) {
      payload = JSON.parse(e.postData.contents);
    } else {
      payload = e.parameter || {};
    }
  } catch (err) {
    return jsonError("JSON Parse Error: " + err.toString());
  }

  // B. Normalize to array (handle single object or batch array)
  var entries = Array.isArray(payload) ? payload : [payload];
  if (entries.length === 0) return jsonResponse("success"); // Nothing to do

  // C. Prepare the rows in memory (Formatting dates, etc.)
  var rows = [];
  var tz = Session.getScriptTimeZone() || "UTC";

  for (var i = 0; i < entries.length; i++) {
    var item = entries[i] || {};

    // IMPORTANT: Use the device timestamp if available, otherwise use Server time
    // This ensures offline data has the correct time when it finally syncs.
    var ts;
    if (item.timestamp) {
      ts = new Date(item.timestamp);
    } else {
      ts = new Date();
    }

    var dateReadable = Utilities.formatDate(ts, tz, "yyyy-MM-dd");
    var timeReadable = Utilities.formatDate(ts, tz, "HH:mm:ss");

    var value = item.value;
    var valueStr = "";
    if (value === null || value === undefined) {
      valueStr = "";
    } else if (typeof value === "object") {
      valueStr = JSON.stringify(value);
    } else {
      valueStr = String(value);
    }

    rows.push([
      ts, // Timestamp Object (for sorting)
      item.userId || "", // User ID
      item.dataType || "", // Data Type
      valueStr, // Value
      dateReadable, // Readable Date
      timeReadable, // Readable Time
    ]);
  }

  // 2. CRITICAL SECTION (The "Traffic Jam" area)
  // We keep this part as short as humanly possible.
  var lock = LockService.getScriptLock();

  try {
    // Wait up to 10 seconds for other processes to finish
    lock.waitLock(10000);

    // Get the Sheet
    var props = PropertiesService.getScriptProperties();
    var sheetId = props.getProperty("SHEET_ID");
    var sheetName = props.getProperty("SHEET_NAME") || "Responses";

    var ss;
    if (sheetId) {
      ss = SpreadsheetApp.openById(sheetId);
    } else {
      ss = SpreadsheetApp.getActiveSpreadsheet();
    }
    var sheet = ss.getSheetByName(sheetName);
    if (!sheet) sheet = ss.insertSheet(sheetName);

    // Ensure Headers (Lightweight check)
    if (sheet.getLastRow() === 0) {
      var headers = [
        "Timestamp",
        "User ID",
        "Data Type",
        "Value",
        "Date",
        "Time",
      ];
      sheet.appendRow(headers);
      sheet.getRange(1, 1, 1, headers.length).setFontWeight("bold");
      sheet.setFrozenRows(1);
    }

    // WRITE DATA
    // We already prepared 'rows' outside the lock, so this is instant.
    sheet
      .getRange(sheet.getLastRow() + 1, 1, rows.length, rows[0].length)
      .setValues(rows);
  } catch (err) {
    // Log error manually if possible
    console.error(err);
    return jsonError("Server Lock/Write Error: " + err.toString());
  } finally {
    // Always release the lock
    lock.releaseLock();
  }

  return jsonResponse("success");
}

function jsonResponse(status) {
  return ContentService.createTextOutput(
    JSON.stringify({ status: status }),
  ).setMimeType(ContentService.MimeType.JSON);
}

function jsonError(msg) {
  return ContentService.createTextOutput(
    JSON.stringify({ status: "error", message: msg }),
  ).setMimeType(ContentService.MimeType.JSON);
}
