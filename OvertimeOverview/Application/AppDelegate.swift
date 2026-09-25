//
//  AppDelegate.swift
//  OvertimeOverview
//
//  Created by Andras Olah on 2026. 09. 25..
//

import OSLog
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    private let logger = Logger(subsystem: "hu.paydogs.overtimeoverview", category: "app")

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        logger.debug("didFinishLaunching")
        return true
    }
}