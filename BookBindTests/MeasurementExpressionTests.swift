import XCTest
@testable import BookBind

final class MeasurementExpressionTests: XCTestCase {
    private func mm(_ text: String, unit: MeasurementUnit = .millimeters, base: Double? = nil) -> Double? {
        MeasurementExpression.evaluateLength(text, defaultUnit: unit, baseMM: base)
    }

    func testBareNumbersUseTheFieldUnit() {
        XCTAssertEqual(mm("152"), 152)
        XCTAssertEqual(mm("6", unit: .inches) ?? 0, 152.4, accuracy: 0.0001)
        XCTAssertEqual(mm("5,5", unit: .inches) ?? 0, 139.7, accuracy: 0.0001, "comma decimal")
    }

    func testExplicitUnitsOverrideTheFieldUnit() {
        XCTAssertEqual(mm("6in") ?? 0, 152.4, accuracy: 0.0001)
        XCTAssertEqual(mm("6\"") ?? 0, 152.4, accuracy: 0.0001)
        XCTAssertEqual(mm("15.2cm") ?? 0, 152, accuracy: 0.0001)
        XCTAssertEqual(mm("152mm", unit: .inches) ?? 0, 152, accuracy: 0.0001)
        XCTAssertEqual(mm("72pt") ?? 0, 25.4, accuracy: 0.0001)
        XCTAssertEqual(mm("1pc") ?? 0, 25.4 / 6, accuracy: 0.0001)
    }

    func testPicaNotation() {
        XCTAssertEqual(mm("1p6") ?? 0, 18 * 25.4 / 72, accuracy: 0.0001)
        XCTAssertEqual(mm("p6") ?? 0, 6 * 25.4 / 72, accuracy: 0.0001)
        XCTAssertEqual(mm("2p") ?? 0, 2 * 25.4 / 6, accuracy: 0.0001)
    }

    func testArithmeticMixesUnits() {
        XCTAssertEqual(mm("229 - 2*3"), 223)
        XCTAssertEqual(mm("(6in - 3mm) / 2") ?? 0, (152.4 - 3) / 2, accuracy: 0.0001)
        XCTAssertEqual(mm("8.5in + 3mm") ?? 0, 215.9 + 3, accuracy: 0.0001)
        XCTAssertEqual(mm("2 * 6in") ?? 0, 304.8, accuracy: 0.0001)
        XCTAssertEqual(mm("-3"), -3)
        XCTAssertEqual(mm("11 / 2", unit: .inches) ?? 0, 139.7, accuracy: 0.0001)
    }

    func testPercentIsRelativeToTheCurrentValue() {
        XCTAssertEqual(mm("50%", base: 210), 105)
        XCTAssertEqual(mm("100% + 3mm", base: 210), 213)
        XCTAssertNil(mm("50%"), "no base to be a percent of")
    }

    func testInvalidInputIsRejected() {
        XCTAssertNil(mm(""))
        XCTAssertNil(mm("abc"))
        XCTAssertNil(mm("6 inches"))
        XCTAssertNil(mm("6in * 2in"), "area isn't a length")
        XCTAssertNil(mm("10 / 0"))
        XCTAssertNil(mm("(5 + 2"))
        XCTAssertNil(mm("5 +"))
    }

    func testPlainNumbersAllowArithmeticButNotUnits() {
        XCTAssertEqual(MeasurementExpression.evaluateNumber("16*4"), 64)
        XCTAssertEqual(MeasurementExpression.evaluateNumber("50%", base: 90), 45)
        XCTAssertNil(MeasurementExpression.evaluateNumber("80gsm"))
        XCTAssertNil(MeasurementExpression.evaluateNumber("6in"))
    }

    func testUnitConversionAndPrecision() {
        XCTAssertEqual(MeasurementUnit.inches.fromMillimeters(25.4), 1)
        XCTAssertEqual(MeasurementUnit.inches.fractionDigits(forMillimeterDigits: 1), 3)
        XCTAssertEqual(MeasurementUnit.millimeters.fractionDigits(forMillimeterDigits: 1), 1)
    }
}
