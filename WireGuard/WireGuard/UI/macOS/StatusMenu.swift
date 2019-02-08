// SPDX-License-Identifier: MIT
// Copyright © 2018-2019 WireGuard LLC. All Rights Reserved.

import Cocoa

protocol StatusMenuWindowDelegate: class {
    func manageTunnelsWindow() -> NSWindow
}

class StatusMenu: NSMenu {

    let tunnelsManager: TunnelsManager

    var statusMenuItem: NSMenuItem?
    var networksMenuItem: NSMenuItem?
    var firstTunnelMenuItemIndex = 0
    var numberOfTunnelMenuItems = 0

    var currentTunnel: TunnelContainer? {
        didSet {
            updateStatusMenuItems(with: currentTunnel)
        }
    }
    weak var windowDelegate: StatusMenuWindowDelegate?

    init(tunnelsManager: TunnelsManager) {
        self.tunnelsManager = tunnelsManager
        super.init(title: tr("macMenuTitle"))

        addStatusMenuItems()
        addItem(NSMenuItem.separator())

        firstTunnelMenuItemIndex = numberOfItems
        let isAdded = addTunnelMenuItems()
        if isAdded {
            addItem(NSMenuItem.separator())
        }
        addTunnelManagementItems()
        addItem(NSMenuItem.separator())
        addApplicationItems()
    }

    required init(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func addStatusMenuItems() {
        let statusTitle = tr(format: "macStatus (%@)", tr("tunnelStatusInactive"))
        let statusMenuItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        addItem(statusMenuItem)
        let networksMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        networksMenuItem.isEnabled = false
        networksMenuItem.isHidden = true
        addItem(networksMenuItem)
        self.statusMenuItem = statusMenuItem
        self.networksMenuItem = networksMenuItem
    }

    func updateStatusMenuItems(with tunnel: TunnelContainer?) {
        guard let statusMenuItem = statusMenuItem, let networksMenuItem = networksMenuItem else { return }
        guard let tunnel = tunnel else {
            statusMenuItem.title = tr(format: "macStatus (%@)", tr("tunnelStatusInactive"))
            networksMenuItem.title = ""
            networksMenuItem.isHidden = true
            return
        }
        var statusText: String

        switch tunnel.status {
        case .waiting:
            statusText = tr("tunnelStatusWaiting")
        case .inactive:
            statusText = tr("tunnelStatusInactive")
        case .activating:
            statusText = tr("tunnelStatusActivating")
        case .active:
            statusText = tr("tunnelStatusActive")
        case .deactivating:
            statusText = tr("tunnelStatusDeactivating")
        case .reasserting:
            statusText = tr("tunnelStatusReasserting")
        case .restarting:
            statusText = tr("tunnelStatusRestarting")
        }

        statusMenuItem.title = tr(format: "macStatus (%@)", statusText)

        if tunnel.status == .inactive {
            networksMenuItem.title = ""
            networksMenuItem.isHidden = true
        } else {
            let allowedIPs = tunnel.tunnelConfiguration?.peers.flatMap { $0.allowedIPs }.map { $0.stringRepresentation }.joined(separator: ", ") ?? ""
            if !allowedIPs.isEmpty {
                networksMenuItem.title = tr(format: "macMenuNetworks (%@)", allowedIPs)
            } else {
                networksMenuItem.title = tr("macMenuNetworksNone")
            }
            networksMenuItem.isHidden = false
        }
    }

    func addTunnelMenuItems() -> Bool {
        let numberOfTunnels = tunnelsManager.numberOfTunnels()
        for index in 0 ..< tunnelsManager.numberOfTunnels() {
            let tunnel = tunnelsManager.tunnel(at: index)
            insertTunnelMenuItem(for: tunnel, at: numberOfTunnelMenuItems)
        }
        return numberOfTunnels > 0
    }

    func addTunnelManagementItems() {
        let manageItem = NSMenuItem(title: tr("macMenuManageTunnels"), action: #selector(manageTunnelsClicked), keyEquivalent: "")
        manageItem.target = self
        addItem(manageItem)
        let importItem = NSMenuItem(title: tr("macMenuImportTunnels"), action: #selector(importTunnelsClicked), keyEquivalent: "")
        importItem.target = self
        addItem(importItem)
    }

    func addApplicationItems() {
        let aboutItem = NSMenuItem(title: tr("macMenuAbout"), action: #selector(aboutClicked), keyEquivalent: "")
        aboutItem.target = self
        addItem(aboutItem)
        let quitItem = NSMenuItem(title: tr("macMenuQuit"), action: #selector(NSApplication.terminate), keyEquivalent: "")
        quitItem.target = NSApp
        addItem(quitItem)
    }

    @objc func tunnelClicked(sender: AnyObject) {
        guard let tunnelMenuItem = sender as? TunnelMenuItem else { return }
        if tunnelMenuItem.state == .off {
            tunnelsManager.startActivation(of: tunnelMenuItem.tunnel)
        } else {
            tunnelsManager.startDeactivation(of: tunnelMenuItem.tunnel)
        }
    }

    @objc func manageTunnelsClicked() {
        NSApp.activate(ignoringOtherApps: true)
        guard let manageTunnelsWindow = windowDelegate?.manageTunnelsWindow() else { return }
        manageTunnelsWindow.makeKeyAndOrderFront(self)
    }

    @objc func importTunnelsClicked() {
        NSApp.activate(ignoringOtherApps: true)
        guard let manageTunnelsWindow = windowDelegate?.manageTunnelsWindow() else { return }
        manageTunnelsWindow.makeKeyAndOrderFront(self)
        ImportPanelPresenter.presentImportPanel(tunnelsManager: tunnelsManager, sourceVC: manageTunnelsWindow.contentViewController)
    }

    @objc func aboutClicked() {
        var appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        if let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            appVersion += " (\(appBuild))"
        }
        let appVersionString = [
            tr(format: "macAppVersion (%@)", appVersion),
            tr(format: "macGoBackendVersion (%@)", WIREGUARD_GO_VERSION)
        ].joined(separator: "\n")
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationVersion: appVersionString,
            .version: ""
        ])
    }
}

extension StatusMenu {
    func insertTunnelMenuItem(for tunnel: TunnelContainer, at tunnelIndex: Int) {
        let menuItem = TunnelMenuItem(tunnel: tunnel, action: #selector(tunnelClicked(sender:)))
        menuItem.target = self
        insertItem(menuItem, at: firstTunnelMenuItemIndex + tunnelIndex)
        if numberOfTunnelMenuItems == 0 {
            insertItem(NSMenuItem.separator(), at: firstTunnelMenuItemIndex + tunnelIndex + 1)
        }
        numberOfTunnelMenuItems += 1
    }

    func removeTunnelMenuItem(at tunnelIndex: Int) {
        removeItem(at: firstTunnelMenuItemIndex + tunnelIndex)
        numberOfTunnelMenuItems -= 1
        if numberOfTunnelMenuItems == 0 {
            if let firstItem = item(at: firstTunnelMenuItemIndex), firstItem.isSeparatorItem {
                removeItem(at: firstTunnelMenuItemIndex)
            }
        }
    }

    func moveTunnelMenuItem(from oldTunnelIndex: Int, to newTunnelIndex: Int) {
        guard let oldMenuItem = item(at: firstTunnelMenuItemIndex + oldTunnelIndex) as? TunnelMenuItem else { return }
        let oldMenuItemTunnel = oldMenuItem.tunnel
        removeItem(at: firstTunnelMenuItemIndex + oldTunnelIndex)
        let menuItem = TunnelMenuItem(tunnel: oldMenuItemTunnel, action: #selector(tunnelClicked(sender:)))
        menuItem.target = self
        insertItem(menuItem, at: firstTunnelMenuItemIndex + newTunnelIndex)

    }
}

class TunnelMenuItem: NSMenuItem {

    var tunnel: TunnelContainer

    private var statusObservationToken: AnyObject?
    private var nameObservationToken: AnyObject?

    init(tunnel: TunnelContainer, action selector: Selector?) {
        self.tunnel = tunnel
        super.init(title: tunnel.name, action: selector, keyEquivalent: "")
        updateStatus()
        let statusObservationToken = tunnel.observe(\.status) { [weak self] _, _ in
            self?.updateStatus()
        }
        updateTitle()
        let nameObservationToken = tunnel.observe(\TunnelContainer.name) { [weak self] _, _ in
            self?.updateTitle()
        }
        self.statusObservationToken = statusObservationToken
        self.nameObservationToken = nameObservationToken
    }

    required init(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateTitle() {
        title = tunnel.name
    }

    func updateStatus() {
        let shouldShowCheckmark = (tunnel.status != .inactive && tunnel.status != .deactivating)
        state = shouldShowCheckmark ? .on : .off
    }
}
