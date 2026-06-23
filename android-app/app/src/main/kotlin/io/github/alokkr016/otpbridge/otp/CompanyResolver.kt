package io.github.alokkr016.otpbridge.otp

/**
 * Resolves a human-readable company/brand name from an SMS sender header and/or
 * the message body.
 *
 * Indian SMS headers follow the TRAI format (e.g. "VM-FLPKRT", "AD-AMZN", "JD-SBIINB")
 * where the segment after the operator prefix carries the brand token. The message
 * body is usually a more reliable signal (it often spells the brand out), so we
 * check the body first, then fall back to the header token.
 */
object CompanyResolver {

    // Brand keywords looked up in the message body (lowercased substring match).
    // Order matters only for readability; matches are exact substring contains.
    private val BODY_BRANDS = linkedMapOf(
        "whatsapp" to "WhatsApp",
        "flipkart" to "Flipkart",
        "amazon" to "Amazon",
        "google" to "Google",
        "facebook" to "Facebook",
        "instagram" to "Instagram",
        "telegram" to "Telegram",
        "netflix" to "Netflix",
        "spotify" to "Spotify",
        "microsoft" to "Microsoft",
        "apple" to "Apple",
        "linkedin" to "LinkedIn",
        "twitter" to "Twitter",
        "uber" to "Uber",
        "ola" to "Ola",
        "swiggy" to "Swiggy",
        "zomato" to "Zomato",
        "paytm" to "Paytm",
        "phonepe" to "PhonePe",
        "gpay" to "Google Pay",
        "myntra" to "Myntra",
        "ajio" to "Ajio",
        "zepto" to "Zepto",
        "blinkit" to "Blinkit",
        "dunzo" to "Dunzo",
        "icici" to "ICICI Bank",
        "hdfc" to "HDFC Bank",
        "axis" to "Axis Bank",
        "kotak" to "Kotak Bank",
        "sbi" to "SBI",
        "paypal" to "PayPal",
        "binance" to "Binance",
        "coinbase" to "Coinbase",
        "discord" to "Discord",
        "github" to "GitHub",
        "openai" to "OpenAI",
        "chatgpt" to "OpenAI",
        "steam" to "Steam",
        "epic games" to "Epic Games",
        "razorpay" to "Razorpay",
        "cred" to "CRED"
    )

    // Header brand tokens (the middle segment of a TRAI header) -> display name.
    private val HEADER_TOKENS = mapOf(
        "FLPKRT" to "Flipkart",
        "FLIPKART" to "Flipkart",
        "AMZN" to "Amazon",
        "AMAZON" to "Amazon",
        "GOOGLE" to "Google",
        "GOOGL" to "Google",
        "FBOOK" to "Facebook",
        "FB" to "Facebook",
        "INSTA" to "Instagram",
        "NFLX" to "Netflix",
        "MSFT" to "Microsoft",
        "APPLE" to "Apple",
        "PAYTM" to "Paytm",
        "PHONPE" to "PhonePe",
        "PHNPE" to "PhonePe",
        "SWGY" to "Swiggy",
        "SWIGGY" to "Swiggy",
        "ZOMATO" to "Zomato",
        "MYNTRA" to "Myntra",
        "AJIO" to "Ajio",
        "ICICI" to "ICICI Bank",
        "ICICIB" to "ICICI Bank",
        "HDFCBK" to "HDFC Bank",
        "HDFC" to "HDFC Bank",
        "AXISBK" to "Axis Bank",
        "AXIS" to "Axis Bank",
        "KOTAK" to "Kotak Bank",
        "SBIINB" to "SBI",
        "SBI" to "SBI",
        "UBER" to "Uber",
        "OLACAB" to "Ola",
        "ZEPTO" to "Zepto",
        "BLNKIT" to "Blinkit",
        "CRED" to "CRED",
        "WHATSAPP" to "WhatsApp",
        "TELEGRAM" to "Telegram"
    )

    /**
     * Returns a friendly company name, or null if it can't be confidently resolved.
     */
    fun resolve(sender: String, body: String): String? {
        // 1. Body match — most reliable (brand is usually spelled out).
        val lowerBody = body.lowercase()
        for ((keyword, name) in BODY_BRANDS) {
            if (lowerBody.contains(keyword)) return name
        }

        // 2. Header token match.
        val token = brandToken(sender)
        if (token != null) {
            HEADER_TOKENS[token]?.let { return it }
            // Unknown but clearly alphabetic brand token — title-case it as a fallback.
            if (token.length in 3..10 && token.all { it.isLetter() }) {
                return token.lowercase().replaceFirstChar { it.uppercase() }
            }
        }

        return null
    }

    /**
     * Extracts the brand token from a TRAI-style header like "VM-FLPKRT-S" -> "FLPKRT".
     * For numeric senders (regular phone numbers) returns null.
     */
    private fun brandToken(sender: String): String? {
        val cleaned = sender.trim().uppercase()
        if (cleaned.isEmpty()) return null
        // Pure numeric (phone number) — no brand token.
        if (cleaned.all { it.isDigit() || it == '+' }) return null

        val parts = cleaned.split('-', '.', ' ').filter { it.isNotBlank() }
        if (parts.isEmpty()) return null

        // Typical TRAI header: <operator/circle>-<brand>-<suffix>. Brand is the longest
        // alphabetic segment after dropping a 2-char operator prefix when present.
        val candidates = when {
            parts.size >= 2 -> parts.drop(1) // drop operator prefix
            else -> parts
        }
        return candidates
            .filter { it.any { c -> c.isLetter() } }
            .maxByOrNull { it.length }
            ?: parts.maxByOrNull { it.length }
    }
}
