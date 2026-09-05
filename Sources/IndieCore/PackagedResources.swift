import Foundation

public enum PackagedResources {
    /// SwiftPM's generated accessor searches the app root and the build tree,
    /// whereas signed macOS applications keep resource bundles in Resources.
    public static func bundle(
        named name: String,
        main: Bundle = .main,
        development: @autoclosure () -> Bundle
    ) -> Bundle? {
        if let url = main.resourceURL?.appendingPathComponent(name + ".bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        // Never evaluate SwiftPM's fatalError-based fallback in an installed app.
        guard main.bundleURL.pathExtension != "app" else { return nil }
        return development()
    }
}
