//
//  focusApp.swift
//  focus
//
//  Created by 이동언 on 3/7/26.
//

import SwiftUI
import UIKit
import AVFoundation

@main
struct FocusApp: App {
    @UIApplicationDelegateAdaptor(FocusAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var loginViewModel = KakaoLoginViewModel()

    var body: some Scene {
        WindowGroup {
            ZStack {
                if loginViewModel.isAuthenticated && loginViewModel.isChzzkConnected {
                    ContentView()
                        .modifier(AppOrientationModifier(mask: .landscapeRight, rotateTo: .landscapeRight))
                        .transition(.opacity)
                } else if loginViewModel.isAuthenticated {
                    ChzzkConnectGateView(
                        onTapConnect: {
                            loginViewModel.connectChzzk()
                        },
                        onTapRefresh: {
                            loginViewModel.refreshChzzkConnectionStatusIfNeeded()
                        },
                        isLoading: loginViewModel.isCheckingChzzkStatus || loginViewModel.isOpeningChzzkConnect,
                        channelName: loginViewModel.chzzkChannelName,
                        watchURL: loginViewModel.chzzkWatchURL,
                        errorMessage: loginViewModel.errorMessage
                    )
                    .modifier(AppOrientationModifier(mask: .portrait, rotateTo: .portrait))
                    .transition(.opacity)
                } else {
                    StartView(
                        onTapPrepare: {
                            loginViewModel.loginWithKakao()
                        },
                        isLoading: loginViewModel.isBootstrapping || loginViewModel.isLoggingIn,
                        errorMessage: loginViewModel.errorMessage
                    )
                    .modifier(AppOrientationModifier(mask: .portrait, rotateTo: .portrait))
                    .transition(.opacity)
                }
            }
            .onAppear {
                ScreenWakeController.update(for: scenePhase)
                loginViewModel.bootstrapIfNeeded()
            }
            .onChange(of: scenePhase) { _, newPhase in
                ScreenWakeController.update(for: newPhase)
                if newPhase == .active {
                    loginViewModel.refreshChzzkConnectionStatusIfNeeded()
                }
            }
            .onOpenURL { url in
                loginViewModel.handleOpenURL(url)
            }
        }
    }
}

final class FocusAppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        KakaoSDKRuntime.initializeIfPossible(appKey: KakaoAuthConfiguration.nativeAppKey)
        configureBroadcastAudioSession()
        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.orientationLock
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        KakaoSDKRuntime.handleOpenURL(url)
    }

    private func configureBroadcastAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .videoRecording,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
            try audioSession.setPreferredSampleRate(FocusConstants.srtAudioSampleRate)
            try audioSession.setActive(true, options: [])

            if (audioSession.availableInputs?.isEmpty == false) {
                do {
                    try audioSession.setPreferredInputNumberOfChannels(
                        FocusConstants.srtAudioChannelCount
                    )
                } catch {
                    FocusLogger.warning(
                        "AVAudioSession 입력 채널 선호값 설정 실패(무시): \(error.localizedDescription)",
                        category: .streaming
                    )
                }
            }

            FocusLogger.info(
                "AVAudioSession 설정 완료: sampleRate=\(audioSession.sampleRate), inputChannels=\(audioSession.inputNumberOfChannels), outputChannels=\(audioSession.outputNumberOfChannels)",
                category: .streaming
            )
        } catch {
            FocusLogger.warning(
                "AVAudioSession 설정 실패: \(error.localizedDescription)",
                category: .streaming
            )
        }
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

private enum ScreenWakeController {
    static func update(for phase: ScenePhase) {
        UIApplication.shared.isIdleTimerDisabled = (phase == .active)
    }
}
