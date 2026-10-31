import XCTest

final class OTPExtractorTests: XCTestCase {

    func testExtractOTPFromSMS() {
        let testCases: [(sender: String, text: String, expectedOTP: String?)] = [
            ("HDFC Bank", "Your OTP is 843921. Do not share.", "843921"),
            ("ICICI", "Verification code: 572134", "572134"),
            ("SBI", "Your OTP for transaction is 1234", "1234"),
            ("Google", "Your verification code is 987654", "987654"),
            ("Random App", "Hello world", nil),
            ("Bank", "Your code: 123456", "123456"),
            ("Auth", "PIN: 7890", "7890"),
            ("Shop", "Use code 123456 at checkout", nil),
        ]

        for testCase in testCases {
            let result = extractOTPFromText(sender: testCase.sender, text: testCase.text)
            XCTAssertEqual(result, testCase.expectedOTP, "Failed for: \(testCase.text)")
        }
    }

    func testExtractOTPWithContext() {
        let text = "Your OTP is 843921. Valid for 5 minutes."
        let result = extractOTPFromText(sender: "HDFC", text: text)
        XCTAssertEqual(result, "843921")
    }

    func testExtractOTPFromLongMessage() {
        let text = "Dear Customer, your OTP for adding beneficiary is 556677. Do not share this with anyone."
        let result = extractOTPFromText(sender: "Bank", text: text)
        XCTAssertEqual(result, "556677")
    }

    func testNoOTPInMessage() {
        let text = "Your account balance is ₹50,000"
        let result = extractOTPFromText(sender: "Bank", text: text)
        XCTAssertNil(result)
    }

    private func extractOTPFromText(sender: String, text: String) -> String? {
        let pattern = /(?i)(?:otp|code|pin|password|verification)\s*(?:is|:)\s*(\d{4,8})/
        if let match = text.firstMatch(of: pattern) {
            return String(match.1)
        }
        return nil
    }
}
