import Foundation
import AppKit

class UpdaterManager: ObservableObject {
    static let shared = UpdaterManager()
    
    static let currentVersion: String =
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    
    private let workerURL = URL(string: "https://bridge-updater.alokraj016.workers.dev")!
    
    @Published var statusMessage: String = ""
    @Published var isChecking: Bool = false
    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String = ""
    @Published var downloadURL: URL?
    @Published var isDownloading: Bool = false
    
    private init() {}
    
    func checkForUpdates(manually: Bool) {
        guard !isChecking else { return }
        
        DispatchQueue.main.async {
            self.isChecking = true
            if manually {
                self.statusMessage = "Checking for updates..."
            }
        }
        
        var request = URLRequest(url: workerURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer {
                DispatchQueue.main.async {
                    self.isChecking = false
                }
            }
            
            if let error = error {
                DispatchQueue.main.async {
                    if manually {
                        self.statusMessage = "Failed to check: \(error.localizedDescription)"
                    }
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    if manually {
                        self.statusMessage = "No response from server"
                    }
                }
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let err = json["error"] as? String {
                        DispatchQueue.main.async {
                            if manually {
                                self.statusMessage = "Update server error: \(err)"
                            }
                        }
                        return
                    }
                    
                    guard let version = json["version"] as? String,
                          let platforms = json["platforms"] as? [String: Any],
                          let darwinUniversal = platforms["darwin-universal"] as? [String: Any],
                          let urlStr = darwinUniversal["url"] as? String,
                          let url = URL(string: urlStr) else {
                        
                        DispatchQueue.main.async {
                            if manually {
                                self.statusMessage = "Invalid update response format"
                            }
                        }
                        return
                    }
                    
                    if self.isNewerVersion(latest: version, current: UpdaterManager.currentVersion) {
                        DispatchQueue.main.async {
                            self.updateAvailable = true
                            self.latestVersion = version
                            self.downloadURL = url
                            self.statusMessage = "New version \(version) available!"
                            
                            if !manually {
                                self.downloadAndInstallUpdate()
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.updateAvailable = false
                            if manually {
                                self.statusMessage = "Bridge is up to date! ✓"
                            }
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    if manually {
                        self.statusMessage = "Failed to parse update information"
                    }
                }
            }
        }.resume()
    }
    
    private func isNewerVersion(latest: String, current: String) -> Bool {
        let latestComponents = latest.split(separator: ".").compactMap { Int($0) }
        let currentComponents = current.split(separator: ".").compactMap { Int($0) }
        
        let count = max(latestComponents.count, currentComponents.count)
        for i in 0..<count {
            let latestVal = i < latestComponents.count ? latestComponents[i] : 0
            let currentVal = i < currentComponents.count ? currentComponents[i] : 0
            
            if latestVal > currentVal { return true }
            if latestVal < currentVal { return false }
        }
        return false
    }
    
    func downloadAndInstallUpdate() {
        guard let url = downloadURL, !isDownloading else { return }
        
        DispatchQueue.main.async {
            self.isDownloading = true
            self.statusMessage = "Downloading update..."
        }
        
        URLSession.shared.downloadTask(with: url) { localURL, response, error in
            defer {
                DispatchQueue.main.async {
                    self.isDownloading = false
                }
            }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.statusMessage = "Download failed: \(error.localizedDescription)"
                }
                return
            }
            
            guard let localURL = localURL else {
                DispatchQueue.main.async {
                    self.statusMessage = "Downloaded file not found"
                }
                return
            }
            
            let tempDir = FileManager.default.temporaryDirectory
            let destinationURL = tempDir.appendingPathComponent("Bridge-Installer.dmg")
            
            try? FileManager.default.removeItem(at: destinationURL)
            do {
                try FileManager.default.moveItem(at: localURL, to: destinationURL)
                
                DispatchQueue.main.async {
                    self.statusMessage = "Installing update..."
                }
                
                try self.installUpdate(dmgURL: destinationURL)
            } catch {
                DispatchQueue.main.async {
                    self.statusMessage = "Installation failed: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    private func installUpdate(dmgURL: URL) throws {
        let currentAppURL = URL(fileURLWithPath: Bundle.main.bundlePath)
        
        let script = """
        # Wait for the main app to terminate
        kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null
        while [ $? -eq 0 ]; do
            sleep 0.2
            kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null
        done
        
        # Mount the downloaded DMG to a unique mountpoint
        MOUNT_DIR=$(mktemp -d)
        hdiutil attach "\(dmgURL.path)" -mountpoint "$MOUNT_DIR" -nobrowse -quiet
        
        # Check if Bridge.app exists on the mount
        if [ -d "$MOUNT_DIR/Bridge.app" ]; then
            # Delete old app and copy new app
            rm -rf "\(currentAppURL.path)"
            cp -R "$MOUNT_DIR/Bridge.app" "\(currentAppURL.path)"
        fi
        
        # Unmount DMG and clean up
        hdiutil detach "$MOUNT_DIR" -quiet
        rm -rf "$MOUNT_DIR"
        
        # Relaunch application
        open "\(currentAppURL.path)"
        """
        
        let shProcess = Process()
        shProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
        shProcess.arguments = ["-c", script]
        try shProcess.run()
        
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }
}
