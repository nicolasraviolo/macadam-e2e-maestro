/**
 * Reset mock server state to defaults before a test run.
 */

const response = http.post("http://localhost:4010/test/reset", {
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ scenario: "default" }),
})

if (response.status !== 200) {
  throw new Error("Failed to reset scenario: " + response.status)
}

const data = JSON.parse(response.body)

if (!data.success) {
  throw new Error("Reset returned success: false")
}

console.log("✅ Reset to default scenario")
