import Foundation
import os

/// Loads, writes defaults on first run, and hot-reloads with a 250ms debounce. Re-opens the fd on rename/delete
/// because editors write-and-rename, which leaves the original descriptor stale.
@MainActor
final class ConfigStore {
    let url: URL
    private(set) var config = Config()
    var onChange: ((Config) -> Void)?
    var onError: ((String) -> Void)?
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var debounce: DispatchWorkItem?
    private let log = Logger(subsystem: "com.cohnesor.homerowless", category: "config")

    init(url: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/homerowless/config.json")) {
        self.url = url
        load(initial: true)
        watch()
    }

    private func load(initial: Bool) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            write(Config())
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let c = try JSONDecoder().decode(Config.self, from: data)
            if c != config || initial { config = c; if !initial { onChange?(c) } }
        } catch {
            log.error("config parse failed: \(String(describing: error), privacy: .public)")
            onError?("Config error: \(error.localizedDescription). Keeping previous config.")
        }
    }

    func write(_ c: Config) {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(c) { try? d.write(to: url, options: .atomic); config = c }
    }

    private func watch() {
        source?.cancel(); source = nil
        if fd >= 0 { close(fd); fd = -1 }
        fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        s.setEventHandler { [weak self] in
            guard let self else { return }
            let ev = s.data
            MainActor.assumeIsolated {
                self.debounce?.cancel()
                let w = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    MainActor.assumeIsolated {
                        if ev.contains(.rename) || ev.contains(.delete) { self.watch() }
                        self.load(initial: false)
                    }
                }
                self.debounce = w
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: w)
            }
        }
        s.setCancelHandler { [fd] in close(fd) }
        s.resume()
        source = s
    }
}
