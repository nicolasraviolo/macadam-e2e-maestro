/**
 * Verify the mock server is running (http://localhost:4010).
 * Run before E2E flows that depend on the mock API.
 */

const response = http.get("http://localhost:4010/test/health")

if (response.status !== 200) {
  throw new Error("Health check failed with status: " + response.status)
}

const data = JSON.parse(response.body)

if (!data.success) {
  throw new Error("Health check returned success: false")
}

console.log("✅ Mock server is healthy")
console.log("   Current scenario:", data.currentScenario)
