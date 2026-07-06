/**
 * Fetch a Firebase custom token for the fixed E2E test user.
 *
 * BLOCKED until backend ships POST /users/e2e/custom-token
 *
 * Required env (pass via maestro test -e ...):
 *   MAESTRO_E2E_SECRET   — shared secret (1Password)
 *   MAESTRO_EMAIL        — allowlisted test user email
 *   MAESTRO_E2E_TOKEN_URL — optional; defaults to preprod URL below
 *
 * Sets output:
 *   customToken   — JWT for signInWithCustomToken
 *   authDeepLink  — macadam.beta://e2e-auth?token=...
 */

const tokenUrl =
  MAESTRO_E2E_TOKEN_URL ||
  "https://macadam-core.preprod.macadam.app/users/e2e/custom-token";

if (!MAESTRO_E2E_SECRET) {
  throw new Error("Missing MAESTRO_E2E_SECRET (set via maestro -e)");
}
if (!MAESTRO_EMAIL) {
  throw new Error("Missing MAESTRO_EMAIL (set via maestro -e)");
}

const response = http.post(tokenUrl, {
  headers: {
    "Content-Type": "application/json",
    "X-E2E-Secret": MAESTRO_E2E_SECRET,
  },
  body: JSON.stringify({ email: MAESTRO_EMAIL }),
});

if (response.status !== 200) {
  throw new Error(
    "Failed to fetch custom token: " +
      response.status +
      " " +
      (response.body || ""),
  );
}

const data = JSON.parse(response.body);
if (!data.customToken) {
  throw new Error("Response missing customToken field");
}

output.customToken = data.customToken;
output.authDeepLink =
  "macadam.beta://e2e-auth?token=" + encodeURIComponent(data.customToken);

console.log("✅ Custom token fetched for " + MAESTRO_EMAIL);
