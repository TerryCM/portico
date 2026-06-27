import Testing
import Foundation
@testable import PorticoCore

private let configFixture = """
Host terry
    HostName 100.64.0.1
    User terry
    LocalForward 5501 localhost:5501
    LocalForward 8100 localhost:8100

Host jump bastion
    HostName jump.example.com
    DynamicForward 1080

Host *
    ServerAliveInterval 60
"""

@Test func parsesHostsWithForwards() {
    let hosts = SSHConfigCatalog.parse(configText: configFixture)
    #expect(hosts.count == 3) // terry, jump, bastion ; wildcard excluded
    let terry = hosts.first { $0.alias == "terry" }!
    #expect(terry.hostName == "100.64.0.1")
    #expect(terry.user == "terry")
    #expect(terry.forwards.count == 2)
    #expect(terry.forwards[0] == Forward(kind: .local, bindAddress: nil, bindPort: 5501,
                                         targetHost: "localhost", targetPort: 5501))
}

@Test func expandsMultiAliasHostLine() {
    let hosts = SSHConfigCatalog.parse(configText: configFixture)
    let jump = hosts.first { $0.alias == "jump" }!
    let bastion = hosts.first { $0.alias == "bastion" }!
    #expect(jump.forwards == [Forward(kind: .dynamic, bindAddress: nil, bindPort: 1080,
                                      targetHost: nil, targetPort: nil)])
    #expect(bastion.hostName == "jump.example.com")
}

@Test func excludesWildcardOnlyHost() {
    let hosts = SSHConfigCatalog.parse(configText: configFixture)
    #expect(hosts.contains { $0.alias == "*" } == false)
}

@Test func loadReturnsEmptyForMissingFile() {
    let catalog = SSHConfigCatalog()
    #expect(catalog.load(path: "/nonexistent/ssh/config").isEmpty)
}
