/**
 * Generate a fresh @macadam.app test account for sign-up flows.
 *
 * Sets output (available as env in subsequent steps):
 *   MAESTRO_EMAIL    — random e2e address (or reuse MAESTRO_EMAIL if already set)
 *   MAESTRO_PASSWORD — from env or default Test123!
 *
 * Format: maestro.e2e.<timestamp>.<random>@macadam.app
 * (dots instead of + to avoid Firebase alias restrictions on some projects)
 */

var DEFAULT_PASSWORD = "Test123!";
var forceFresh =
  FORCE_FRESH_ACCOUNT === "true" || FORCE_FRESH_ACCOUNT === true;

if (
  !forceFresh &&
  MAESTRO_EMAIL &&
  String(MAESTRO_EMAIL).trim() !== ""
) {
  output.MAESTRO_EMAIL = String(MAESTRO_EMAIL).trim();
  console.log("Using provided email: " + output.MAESTRO_EMAIL);
} else {
  var random = Math.floor(Math.random() * 1000000);
  var timestamp = Date.now();
  output.MAESTRO_EMAIL =
    "maestro.e2e." + timestamp + "." + random + "@macadam.app";
  console.log("Generated email: " + output.MAESTRO_EMAIL);
}

output.MAESTRO_PASSWORD =
  MAESTRO_PASSWORD && String(MAESTRO_PASSWORD).trim() !== ""
    ? String(MAESTRO_PASSWORD).trim()
    : DEFAULT_PASSWORD;

console.log("Password: (set via MAESTRO_PASSWORD or default)");
