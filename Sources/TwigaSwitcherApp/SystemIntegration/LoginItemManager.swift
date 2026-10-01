import ServiceManagement

@MainActor
public protocol LoginItemManaging {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSettings()
}

@MainActor
public final class LoginItemManager: LoginItemManaging {
    public init() {}

    public var status: SMAppService.Status { SMAppService.mainApp.status }

    public func register() throws { try SMAppService.mainApp.register() }
    public func unregister() throws { try SMAppService.mainApp.unregister() }
    public func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
