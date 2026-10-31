package io.github.alokkr016.otpbridge.otp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class OTPExtractorTest {

    @Test
    fun extractsOnlyWhenTheCodeIsLabeled() {
        assertEquals("843921", OTPExtractor.extractOTP("HDFC", "Your OTP is 843921. Do not share.")?.otp)
        assertEquals("572134", OTPExtractor.extractOTP("ICICI", "Verification code: 572134")?.otp)
        assertEquals("123456", OTPExtractor.extractOTP("Bank", "Your code: 123456")?.otp)
    }

    @Test
    fun ignoresANumberThatMerelySitsNearTheWordCode() {
        assertNull(OTPExtractor.extractOTP("Shop", "Use code 123456 at checkout"))
        assertNull(OTPExtractor.extractOTP("Bank", "Your account balance is 50000"))
    }

    @Test
    fun bareTitleIsOptIn() {
        assertNull(OTPExtractor.extractOTP("706594", "SMS from Bigbasket", allowBareTitle = false))
        assertEquals("706594", OTPExtractor.extractOTP("706594", "SMS from Bigbasket", allowBareTitle = true)?.otp)
    }
}
