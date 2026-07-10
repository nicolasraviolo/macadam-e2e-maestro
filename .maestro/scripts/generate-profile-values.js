/**
 * Random profile field values for edit-profile E2E (unique pseudo per run).
 */
const suffix = Date.now().toString().slice(-6)

output.PROFILE_FIRSTNAME = "Maestro" + suffix
output.PROFILE_LASTNAME = "Tester"
output.PROFILE_CITY = "Lyon"
output.PROFILE_PSEUDO = "mstr" + suffix

console.log(
  "Profile values: " +
    output.PROFILE_FIRSTNAME +
    " / @" +
    output.PROFILE_PSEUDO +
    " / " +
    output.PROFILE_CITY,
)
