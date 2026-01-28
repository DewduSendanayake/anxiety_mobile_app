/**
 * Optimized High-Concurrency Logger
 * - Parses data OUTSIDE the lock (faster)
 * - Prepares rows OUTSIDE the lock (faster)
 * - Uses incoming timestamps if available (better for offline sync)
 */

function doPost(e) {
  // Parse incoming data
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

  var entries = Array.isArray(payload) ? payload : [payload];
  if (entries.length === 0) return jsonResponse("success");

  var tz = Session.getScriptTimeZone() || "UTC";
  var grouped = {};

  function sanitizeSheetName(id) {
    if (!id) return "Unknown";
    var s = String(id)
      .replace(/[:\\\/?*\[\]]/g, "_")
      .substring(0, 90);
    return "User_" + s;
  }

  // Prepare grouped rows
  for (var i = 0; i < entries.length; i++) {
    var item = entries[i] || {};
    var ts = item.timestamp ? new Date(item.timestamp) : new Date();
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

    var userId = item.userId || "Unknown";
    var sheetName = sanitizeSheetName(userId);
    if (!grouped[sheetName]) grouped[sheetName] = [];

    grouped[sheetName].push([
      ts,
      userId,
      item.dataType || "",
      valueStr,
      dateReadable,
      timeReadable,
    ]);
  }

  // Critical section: write to spreadsheets inside lock
  var lock = LockService.getScriptLock();
  try {
    lock.waitLock(10000);

    var props = PropertiesService.getScriptProperties();
    var usePerUserSpreadsheets =
      (props.getProperty("USE_PER_USER_SPREADSHEETS") || "false") === "true";
    var sheetId = props.getProperty("SHEET_ID");
    var headers = [
      "Timestamp",
      "User ID",
      "Data Type",
      "Value",
      "Date",
      "Time",
    ];

    if (usePerUserSpreadsheets) {
      for (var sheetName in grouped) {
        var rowsToWrite = grouped[sheetName];
        if (!rowsToWrite || rowsToWrite.length === 0) continue;

        var propKey = "SPREADSHEET_FOR_" + sheetName;
        var userSpreadsheetId = props.getProperty(propKey);
        var userSS = null;
        if (userSpreadsheetId) {
          try {
            userSS = SpreadsheetApp.openById(userSpreadsheetId);
          } catch (e) {
            userSS = null;
          }
        }

        if (!userSS) {
          var title = sheetName + "_Data";
          userSS = SpreadsheetApp.create(title);
          userSpreadsheetId = userSS.getId();
          props.setProperty(propKey, userSpreadsheetId);
        }

        var userSheet = userSS.getSheets()[0];
        if (!userSheet) userSheet = userSS.insertSheet("Data");
        if (userSheet.getLastRow() === 0) {
          userSheet.appendRow(headers);
          userSheet.getRange(1, 1, 1, headers.length).setFontWeight("bold");
          userSheet.setFrozenRows(1);
        }

        userSheet
          .getRange(
            userSheet.getLastRow() + 1,
            1,
            rowsToWrite.length,
            rowsToWrite[0].length,
          )
          .setValues(rowsToWrite);
      }
    } else {
      var ss = sheetId
        ? SpreadsheetApp.openById(sheetId)
        : SpreadsheetApp.getActiveSpreadsheet();
      var existingSheets = ss.getSheets();
      var userSheetCount = 0;
      var existingNames = {};
      for (var s = 0; s < existingSheets.length; s++) {
        var nm = existingSheets[s].getName();
        existingNames[nm] = true;
        if (nm.indexOf("User_") === 0) userSheetCount++;
      }

      var overflowName =
        props.getProperty("OVERFLOW_SHEET_NAME") || "Other_Users";
      var maxUserSheets = Number(props.getProperty("SHEET_USER_LIMIT")) || 20;

      for (var sheetName in grouped) {
        var targetName = sheetName;
        if (!existingNames[targetName] && userSheetCount >= maxUserSheets) {
          targetName = overflowName;
        }

        var sheet = ss.getSheetByName(targetName);
        if (!sheet) {
          sheet = ss.insertSheet(targetName);
          sheet.appendRow(headers);
          sheet.getRange(1, 1, 1, headers.length).setFontWeight("bold");
          sheet.setFrozenRows(1);
          existingNames[targetName] = true;
          if (targetName.indexOf("User_") === 0) userSheetCount++;
        } else if (sheet.getLastRow() === 0) {
          sheet.appendRow(headers);
          sheet.getRange(1, 1, 1, headers.length).setFontWeight("bold");
          sheet.setFrozenRows(1);
        }

        var rowsToWrite = grouped[sheetName];
        if (rowsToWrite.length > 0) {
          sheet
            .getRange(
              sheet.getLastRow() + 1,
              1,
              rowsToWrite.length,
              rowsToWrite[0].length,
            )
            .setValues(rowsToWrite);
        }
      }
    }
  } catch (err) {
    console.error(err);
    return jsonError("Server Lock/Write Error: " + err.toString());
  } finally {
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

/**
 * Helper to set common script properties.
 * Run once in the Apps Script editor to configure behavior.
 */
function setProperties() {
  var props = PropertiesService.getScriptProperties();
  // Number of per-user sheets allowed when not using per-user spreadsheets
  props.setProperty("SHEET_USER_LIMIT", "20");
  // Overflow sheet name when per-user sheet limit exceeded
  props.setProperty("OVERFLOW_SHEET_NAME", "Other_Users");
  // When true, create and use separate spreadsheets per user (recommended for scale)
  props.setProperty("USE_PER_USER_SPREADSHEETS", "true");
  Logger.log(
    "Properties set: SHEET_USER_LIMIT=20, OVERFLOW_SHEET_NAME=Other_Users, USE_PER_USER_SPREADSHEETS=true",
  );
}
