package io.github.alokkr016.otpbridge.otp

object OTPExtractor {

    // "code: 123456" and "password is 123456". A bare "code 123456" is not enough.
    private val LABELED_CODE = Regex(
        """(?:otp|code|pin|password|verification)\s*(?:is|:)\s*(\d{4,8})""",
        RegexOption.IGNORE_CASE
    )

    // "123456 is your OTP" and "847291 is the verification code".
    private val CODE_THEN_LABEL = Regex(
        """\b(\d{4,8})\b\s+is\s+(?:your\s+|the\s+)?(?:otp|pin|passcode|one[\s-]?time password|verification code|code)\b""",
        RegexOption.IGNORE_CASE
    )

    // Strong words only. "code" alone is handled by LABELED_CODE so "use code 123456" stays ignored.
    private val STRONG_LABEL = Regex(
        """\b(?:otp|pin|passcode|one[\s-]?time password|verification code)\b""",
        RegexOption.IGNORE_CASE
    )
    private val IS_DIGITS = Regex("""\bis\s+(\d{4,8})\b""", RegexOption.IGNORE_CASE)
    private val IMMEDIATE_DIGITS = Regex(
        """\b(?:otp|pin|passcode|one[\s-]?time password|verification code)\s*:?\s*(\d{4,8})\b""",
        RegexOption.IGNORE_CASE
    )
    private val PURE_OTP_TITLE = Regex("""^\d{4,8}$""")

    /**
     * [allowBareTitle] is only for the SMS path and known messaging apps.
     * A bare 4–8 digit title from any other notification is not treated as an OTP.
     */
    fun extractOTP(sender: String, text: String, allowBareTitle: Boolean = false): OTPMessage? {
        val otp = labeledCode(text) ?: if (allowBareTitle) bareTitle(sender) else null
        if (otp == null) return null
        val trimmedSender = sender.trim()
        val realSender = if (PURE_OTP_TITLE.matches(trimmedSender)) {
            text.replace(trimmedSender, "").trim().ifEmpty { sender }
        } else {
            sender
        }
        return OTPMessage(
            sender = realSender,
            otp = otp,
            company = CompanyResolver.resolve(realSender, text)
        )
    }

    private fun labeledCode(text: String): String? {
        LABELED_CODE.find(text)?.let { return it.groupValues[1] }
        CODE_THEN_LABEL.find(text)?.let { return it.groupValues[1] }

        val label = STRONG_LABEL.find(text) ?: return null
        val window = text.substring(label.range.first, minOf(text.length, label.range.last + 1 + 80))
        IS_DIGITS.find(window)?.let { return it.groupValues[1] }
        return IMMEDIATE_DIGITS.find(window)?.groupValues?.get(1)
    }

    private fun bareTitle(sender: String): String? {
        val trimmed = sender.trim()
        return trimmed.takeIf { PURE_OTP_TITLE.matches(it) }
    }
}
