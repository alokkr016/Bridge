package io.github.alokkr016.otpbridge.otp

object OTPExtractor {

    private val OTP_WITH_CONTEXT = Regex("""(?:otp|code|pin|password|verification)\s*(?:is|:)\s*(\d{4,8})""", RegexOption.IGNORE_CASE)
    // Android SMS notifications often set the OTP itself as the notification title
    private val PURE_OTP_TITLE = Regex("""^\d{4,8}$""")

    /**
     * [allowBareTitle] is only for the SMS path and known messaging apps.
     * A bare 4–8 digit title from any other notification is not treated as an OTP.
     */
    fun extractOTP(sender: String, text: String, allowBareTitle: Boolean = false): OTPMessage? {
        val contextMatch = OTP_WITH_CONTEXT.find(text)
        if (contextMatch != null) {
            return OTPMessage(
                sender = sender,
                otp = contextMatch.groupValues[1],
                company = CompanyResolver.resolve(sender, text)
            )
        }

        if (!allowBareTitle) return null

        val trimmedSender = sender.trim()
        if (PURE_OTP_TITLE.matches(trimmedSender)) {
            val realSender = text.replace(trimmedSender, "").trim().ifEmpty { sender }
            return OTPMessage(
                sender = realSender,
                otp = trimmedSender,
                company = CompanyResolver.resolve(realSender, text)
            )
        }
        return null
    }
}
