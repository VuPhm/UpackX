import AppKit

let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.4.0"

#if arch(arm64)
let runtimeArch = "arm64 Apple Silicon"
#elseif arch(x86_64)
let runtimeArch = "x86_64 Intel"
#else
let runtimeArch = "Universal 2"
#endif

if CommandLine.arguments.contains("--version") || CommandLine.arguments.contains("-v") {
    print("UpackX version \(version) (\(runtimeArch) native)")
    exit(0)
}

if CommandLine.arguments.contains("--help") || CommandLine.arguments.contains("-h") {
    print("""
    UpackX — Lightweight macOS Archive Extractor & Compressor
    Version: \(version) (\(runtimeArch))

    Usage:
      UpackX                              Open minimalist drop window
      UpackX --quick <archive...>         Quick extract to containing folder
      UpackX --extract-to <archive...>    Open Extract To dialog
      UpackX --compress <item...>         Compress items to ZIP
      UpackX --compress-to <item...>      Open Compress To dialog
      UpackX --check-update               Check for new updates from GitHub
      UpackX --install-services           Refresh native Finder Services
      UpackX --version                    Show version
      UpackX --help                       Show help
    """)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
