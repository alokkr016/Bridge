package io.github.alokkr016.otpbridge.otp

object OTPExtractor {

    private val OTP_KEYWORDS = listOf(
        "otp", "OTP", "code", "Code", "verification", "Verification",
        "pin", "PIN", "password", "Password", "authenticate", "Authenticate"
    )

    private val OTP_PATTERN = Regex("""\b(\d{4,8})\b""")
    private val OTP_WITH_CONTEXT = Regex("""(?:otp|code|pin|password|verification)\s*(?:is|:)\s*(\d{4,8})""", RegexOption.IGNORE_CASE)
    // Android SMS notifications often set the OTP itself as the notification title
    private val PURE_OTP_TITLE = Regex("""^\d{4,8}$""")

    fun extractOTP(sender: String, text: String): OTPMessage? {
        // Highest confidence: keyword + number pattern in text
        val contextMatch = OTP_WITH_CONTEXT.find(text)
        if (contextMatch != null) {
            return OTPMessage(
                sender = sender,
                otp = contextMatch.groupValues[1],
                company = CompanyResolver.resolve(sender, text)
            )
        }

        // Notification title IS the OTP (e.g. "706594" with body "SMS from Bigbasket")
        val trimmedSender = sender.trim()
        if (PURE_OTP_TITLE.matches(trimmedSender)) {
            val realSender = text.replace(trimmedSender, "").trim().ifEmpty { sender }
            return OTPMessage(
                sender = realSender,
                otp = trimmedSender,
                company = CompanyResolver.resolve(realSender, text)
            )
        }

        // Keyword present anywhere + numeric match
        val hasKeyword = OTP_KEYWORDS.any { text.contains(it, ignoreCase = true) }
        if (!hasKeyword) return null

        val matches = OTP_PATTERN.findAll(text).toList()
        if (matches.isEmpty()) return null

        val bestMatch = matches.maxByOrNull { it.groupValues[1].length } ?: return null
        return OTPMessage(
            sender = sender,
            otp = bestMatch.groupValues[1],
            company = CompanyResolver.resolve(sender, text)
        )
    }
}
