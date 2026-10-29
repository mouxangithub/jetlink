import Foundation

/// Whether this machine has a way to the internet at all, without asking the
/// network: a default route, as Linux lists them in /proc. A Jetson in a car
/// has none until it joins a Wi-Fi network. Elsewhere, and where /proc is not
/// readable (an Android app's sandbox), yes: a phone or a Mac is online far
/// more often than not, and a download that fails says so soon enough.
enum Reachability {
  static func hasDefaultRoute(ipv4: String = "/proc/net/route", ipv6: String = "/proc/net/ipv6_route") -> Bool {
    #if os(Linux)
      let v4 = try? String(contentsOfFile: ipv4, encoding: .utf8)
      let v6 = try? String(contentsOfFile: ipv6, encoding: .utf8)
      if v4 == nil && v6 == nil { return true }
      return defaultRoute(ipv4: v4 ?? "", ipv6: v6 ?? "")
    #else
      return true
    #endif
  }

  /// A default route on an interface other than loopback, in /proc/net/route
  /// (`Iface Destination Gateway Flags ... Mask`, hex) or /proc/net/ipv6_route
  /// (destination, prefix length, ..., interface last). Loopback carries the
  /// kernel's unreachable IPv6 default, which is no way out.
  static func defaultRoute(ipv4: String, ipv6: String) -> Bool {
    for line in ipv4.split(separator: "\n").dropFirst() {
      let fields = line.split(whereSeparator: { $0 == "\t" || $0 == " " })
      if fields.count > 7, fields[0] != "lo", fields[1] == "00000000", fields[7] == "00000000" { return true }
    }
    for line in ipv6.split(separator: "\n") {
      let fields = line.split(separator: " ", omittingEmptySubsequences: true)
      if fields.count >= 10, fields[0] == String(repeating: "0", count: 32), fields[1] == "00", fields.last != "lo" { return true }
    }
    return false
  }
}
