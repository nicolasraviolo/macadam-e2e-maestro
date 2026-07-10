/**
 * Brief pause so the app can fetch /config from the mock server
 * before the login flow taps Next (avoids magic-link race).
 */
const seconds = parseInt(wait_seconds || "8", 10)
const until = Date.now() + seconds * 1000
while (Date.now() < until) {
  // busy wait — Maestro JS has no sleep()
}
console.log("Waited " + seconds + "s for app config")
