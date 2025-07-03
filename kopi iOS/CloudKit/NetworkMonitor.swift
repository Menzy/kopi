//
//  NetworkMonitor.swift
//  kopi iOS
//
//  Created by Wan Menzy on 20/06/2025.
//

import Foundation
import Network

@MainActor
class NetworkMonitor: ObservableObject {
    @Published var isConnected: Bool = false
    
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")
    private var connectionStateChangeHandler: (() -> Void)?
    
    init() {
        setupNetworkMonitoring()
    }
    
    func setConnectionStateChangeHandler(_ handler: @escaping () -> Void) {
        connectionStateChangeHandler = handler
    }
    
    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let wasConnected = self?.isConnected ?? false
                self?.isConnected = path.status == .satisfied
                
                if path.status == .satisfied {
                    print("🌐 [iOS CloudKit] Network connected")
                } else {
                    print("📵 [iOS CloudKit] Network disconnected")
                }
                
                // Notify about connection state change
                if wasConnected != (path.status == .satisfied) {
                    self?.connectionStateChangeHandler?()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }
    
    deinit {
        monitor.cancel()
    }
}
