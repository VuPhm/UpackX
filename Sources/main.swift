import AppKit

let version = "1.1.0"

if CommandLine.arguments.contains("--version") || CommandLine.arguments.contains("-v") {
    print("UpackX version \(version) (x86_64 native)")
    exit(0)
}

if CommandLine.arguments.contains("--help") || CommandLine.arguments.contains("-h") {
    print("""
    UpackX — Lightweight macOS Archive Extractor
    Version: \(version) (x86_64 Intel)

    Usage:
      UpackX                              Open minimalist drop window
      UpackX --quick <archive...>         Quick extract to containing folder
      UpackX --extract-to <archive...>    Open Extract To dialog
      UpackX --install-services           Install Finder Quick Actions to ~/Library/Services
      UpackX --version                    Show version
      UpackX --help                       Show help
    """)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
