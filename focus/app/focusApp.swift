//
//  focusApp.swift
//  focus
//
//  Created by 이동언 on 3/7/26.
//

import SwiftUI
import UIKit

@main
struct FocusApp: App {
    @UIApplicationDelegateAdaptor(FocusAppDelegate.self) private var appDelegate
    @State private var showsMainPage = false
    // Temporary switch for previewing a generated design system without touching live screens.
    private let debugLaunchRoute: FocusLaunchRoute = .designSystemPreview

    var body: some Scene {
        WindowGroup {
            switch debugLaunchRoute {
            case .appFlow:
                ZStack {
                    if showsMainPage {
                        ContentView()
                            .modifier(AppOrientationModifier(mask: .landscapeRight, rotateTo: .landscapeRight))
                            .transition(.opacity)
                    } else {
                        StartView(onTapPrepare: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showsMainPage = true
                            }
                        })
                        .modifier(AppOrientationModifier(mask: .portrait, rotateTo: .portrait))
                        .transition(.opacity)
                    }
                }

            case .designSystemPreview:
                DesignSystemTestView()
                    .modifier(AppOrientationModifier(mask: .portrait, rotateTo: .portrait))
            }
        }
    }
}

private enum FocusLaunchRoute {
    case appFlow
    case designSystemPreview
}

final class FocusAppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.orientationLock
    }
}

private struct AppOrientationModifier: ViewModifier {
    let mask: UIInterfaceOrientationMask
    let rotateTo: UIInterfaceOrientation

    func body(content: Content) -> some View {
        content
            .onAppear {
                AppOrientationController.lock(mask, rotateTo: rotateTo)
            }
    }
}

private enum AppOrientationController {
    static func lock(_ mask: UIInterfaceOrientationMask, rotateTo orientation: UIInterfaceOrientation) {
        FocusAppDelegate.orientationLock = mask

        if #available(iOS 16.0, *) {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?
                .requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        } else {
            UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
        }

        UINavigationController.attemptRotationToDeviceOrientation()
    }
}
