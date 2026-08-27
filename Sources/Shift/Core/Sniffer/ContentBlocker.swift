import Foundation
import WebKit

public final class ContentBlocker {
    public static let shared = ContentBlocker()

    // WebKit content blocker rules: WebKit regex does not support disjunctions `(a|b)`,
    // so each domain filter is declared as an independent trigger rule.
    public static let adBlockRuleJSON: String = """
    [
        {
            "trigger": { "url-filter": ".*doubleclick\\\\.net.*" },
            "action": { "type": "block" }
        },
        {
            "trigger": { "url-filter": ".*googleadservices.*" },
            "action": { "type": "block" }
        },
        {
            "trigger": { "url-filter": ".*googlesyndication.*" },
            "action": { "type": "block" }
        },
        {
            "trigger": { "url-filter": ".*adservice\\\\.google.*" },
            "action": { "type": "block" }
        },
        {
            "trigger": { "url-filter": ".*adnxs\\\\.com.*" },
            "action": { "type": "block" }
        },
        {
            "trigger": { "url-filter": ".*popads\\\\.net.*" },
            "action": { "type": "block" }
        },
        {
            "trigger": { "url-filter": ".*propellerads\\\\.com.*" },
            "action": { "type": "block" }
        },
        {
            "trigger": { "url-filter": ".*adroll\\\\.com.*" },
            "action": { "type": "block" }
        },
        {
            "trigger": { "url-filter": ".*outbrain\\\\.com.*" },
            "action": { "type": "block" }
        },
        {
            "trigger": { "url-filter": ".*taboola\\\\.com.*" },
            "action": { "type": "block" }
        },
        {
            "trigger": { "url-filter": ".*", "resource-type": ["popup"] },
            "action": { "type": "block" }
        }
    ]
    """

    public func compileRuleList(completion: @escaping (WKContentRuleList?) -> Void) {
        WKContentRuleListStore.default()?.compileContentRuleList(
            forIdentifier: "ShiftContentBlockerList",
            encodedContentRuleList: Self.adBlockRuleJSON
        ) { ruleList, error in
            if let error = error {
                print("ContentBlocker compile note: \(error.localizedDescription)")
            }
            completion(ruleList)
        }
    }
}
