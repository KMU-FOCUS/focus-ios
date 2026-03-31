//
//  startView.swift
//  focus
//
//  Created by 이동언 on 3/27/26.
//

import SwiftUI

struct StartView: View {
    let onTapPrepare: () -> Void
    @State private var selectedSlide = 0

    private let slides: [HeroSlide] = [
        HeroSlide(
            title: "스트리머는 그대로, 배경 인물은 안전하게",
            subtitle: "초상권 걱정 없는 스마트 라이브 스트리밍"
        ),
        HeroSlide(
            title: "방송중 스쳐가는 사람까지",
            subtitle: "자동으로 감지해 아바타로 전환해요"
        ),
        HeroSlide(
            title: "복잡한 설정 없이 바로 시작하는",
            subtitle: "안전한 라이브 스트리밍"
        )
    ]

    var body: some View {
        ZStack {
            backgroundImageLayer
            dimLayer
            contentLayer
        }
        .ignoresSafeArea()
    }
}

private extension StartView {
    var backgroundImageLayer: some View {
        Image("background")
            .resizable()
            .scaledToFill()
            .ignoresSafeArea()
    }

    var dimLayer: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.15),
                Color.black.opacity(0.35),
                Color.black.opacity(0.7)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    var contentLayer: some View {
        VStack {
            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                titleSection
                prepareButton
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var titleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                Text("FOCUS")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)

                Spacer()

                pageIndicator
            }

            slideSection
        }
    }

    var slideSection: some View {
        TabView(selection: $selectedSlide) {
            ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                VStack(alignment: .leading, spacing: 8) {
                    Text(slide.title)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(slide.subtitle)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 84)
    }

    var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(slides.indices, id: \.self) { index in
                Capsule()
                    .fill(index == selectedSlide ? Color.white : Color.white.opacity(0.35))
                    .frame(width: index == selectedSlide ? 22 : 8, height: 8)
            }
        }
    }

    var prepareButton: some View {
        Button(action: onTapPrepare) {
            Text("방송 준비하기")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    LinearGradient(
                        colors: [
                            Color.purple,
                            Color.blue
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(.top, 8)
    }
}

#Preview {
    StartView(onTapPrepare: {})
}

private struct HeroSlide {
    let title: String
    let subtitle: String
}
