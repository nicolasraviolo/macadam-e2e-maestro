/**
 * Push feature flags to the mock server (POST /test/feature-flags).
 *
 * Env:
 *   maestro_flags — JSON string, e.g.
 *     {"flags":{"magic_link_enabled":false,"pre_signup_enabled":true}}
 */

let parsedFlags = {}

if (maestro_flags) {
  try {
    const parsed = JSON.parse(maestro_flags)
    parsedFlags = parsed.flags || {}
    console.log("Setting feature flags:", parsedFlags)
  } catch (error) {
    console.error("Failed to parse maestro_flags:", error.message)
    throw new Error("Invalid maestro_flags format: " + error.message)
  }
} else {
  console.log("No maestro_flags provided, using default flags")
}

const response = http.post("http://localhost:4010/test/feature-flags", {
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ flags: parsedFlags }),
})

if (response.status !== 200) {
  throw new Error(
    "Failed to update local feature flags: " +
      response.status +
      " - " +
      (response.body || "No response body"),
  )
}

console.log(
  "✅ Successfully updated " + Object.keys(parsedFlags).length + " feature flags",
)
