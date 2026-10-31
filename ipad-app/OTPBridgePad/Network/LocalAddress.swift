import Foundation

/// Best LAN IPv4 for QR pairing and beaconing.
/// Ported from the Mac app. On iPadOS the Wi-Fi interface is also `en0`, so the
/// same preference order applies: en0, then any other en*, skipping loopback and
/// (unless nothing else exists) link-local.
enum LocalAddress {
    static func ipv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var en0: String?
        var en0LinkLocal: String?
        var other: String?
        var otherLinkLocal: String?

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let iface = ptr.pointee
            guard iface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: iface.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(iface.ifa_addr, socklen_t(iface.ifa_addr.pointee.sa_len),
                        &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: host)
            if ip.hasPrefix("127.") { continue }
            let linkLocal = ip.hasPrefix("169.254.")
            if name == "en0" {
                if linkLocal { en0LinkLocal = ip } else { en0 = ip }
            } else {
                if linkLocal { otherLinkLocal = ip } else if other == nil { other = ip }
            }
        }
        return en0 ?? other ?? en0LinkLocal ?? otherLinkLocal
    }
}
