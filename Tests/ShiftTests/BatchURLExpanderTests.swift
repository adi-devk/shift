import XCTest
@testable import Shift

final class BatchURLExpanderTests: XCTestCase {
    func testNumericalPatternExpansion() {
        let pattern = "https://example.com/episodes/ep_[1-5].mp4"
        let generated = expandPattern(pattern)
        XCTAssertEqual(generated.count, 5)
        XCTAssertEqual(generated[0], "https://example.com/episodes/ep_1.mp4")
        XCTAssertEqual(generated[4], "https://example.com/episodes/ep_5.mp4")
    }

    func testZeroPaddedPatternExpansion() {
        let pattern = "https://cdn.example.com/images/img_[001-005].jpg"
        let generated = expandPattern(pattern)
        XCTAssertEqual(generated.count, 5)
        XCTAssertEqual(generated[0], "https://cdn.example.com/images/img_001.jpg")
        XCTAssertEqual(generated[4], "https://cdn.example.com/images/img_005.jpg")
    }

    func testAlphabeticalPatternExpansion() {
        let pattern = "https://example.com/pages/page_[a-d].html"
        let generated = expandPattern(pattern)
        XCTAssertEqual(generated.count, 4)
        XCTAssertEqual(generated[0], "https://example.com/pages/page_a.html")
        XCTAssertEqual(generated[3], "https://example.com/pages/page_d.html")
    }

    private func expandPattern(_ pattern: String) -> [String] {
        guard let rangeMatch = pattern.range(of: "\\[([^\\]]+)\\]", options: .regularExpression) else {
            return []
        }
        let inside = String(pattern[rangeMatch]).replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
        let parts = inside.components(separatedBy: "-")
        guard parts.count == 2 else { return [] }

        var results: [String] = []
        if let startNum = Int(parts[0]), let endNum = Int(parts[1]), startNum <= endNum {
            let isPadded = parts[0].hasPrefix("0") && parts[0].count > 1
            let padLength = parts[0].count
            for num in startNum...endNum {
                let formattedNum = isPadded ? String(format: "%0\(padLength)d", num) : "\(num)"
                results.append(pattern.replacingCharacters(in: rangeMatch, with: formattedNum))
            }
        } else if let startChar = parts[0].first?.asciiValue, let endChar = parts[1].first?.asciiValue, startChar <= endChar {
            for ascii in startChar...endChar {
                let charStr = String(UnicodeScalar(ascii))
                results.append(pattern.replacingCharacters(in: rangeMatch, with: charStr))
            }
        }
        return results
    }
}
