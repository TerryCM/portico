import Testing
@testable import PorticoCore

@Test func parsesLocalForwardFullForm() {
    let f = Forward.parse(flag: "-L", value: "5501:localhost:5501")
    #expect(f == Forward(kind: .local, bindAddress: nil, bindPort: 5501,
                         targetHost: "localhost", targetPort: 5501))
}

@Test func parsesLocalForwardWithBindAddress() {
    let f = Forward.parse(flag: "-L", value: "127.0.0.1:8100:terry:8100")
    #expect(f == Forward(kind: .local, bindAddress: "127.0.0.1", bindPort: 8100,
                         targetHost: "terry", targetPort: 8100))
}

@Test func parsesDynamicForward() {
    let f = Forward.parse(flag: "-D", value: "1080")
    #expect(f == Forward(kind: .dynamic, bindAddress: nil, bindPort: 1080,
                         targetHost: nil, targetPort: nil))
}

@Test func parsesDynamicForwardWithBindAddress() {
    let f = Forward.parse(flag: "-D", value: "127.0.0.1:1080")
    #expect(f == Forward(kind: .dynamic, bindAddress: "127.0.0.1", bindPort: 1080,
                         targetHost: nil, targetPort: nil))
}

@Test func parsesRemoteForward() {
    let f = Forward.parse(flag: "-R", value: "9000:localhost:3000")
    #expect(f == Forward(kind: .remote, bindAddress: nil, bindPort: 9000,
                         targetHost: "localhost", targetPort: 3000))
}

@Test func rejectsGarbage() {
    #expect(Forward.parse(flag: "-L", value: "notaport") == nil)
}

@Test func forwardIDIsStable() {
    let f = Forward(kind: .local, bindAddress: nil, bindPort: 5501,
                    targetHost: "localhost", targetPort: 5501)
    #expect(f.id == "local::5501:localhost:5501")
}
