//
//  EmptyFeedView.swift
//  signal
//
//  Friendly empty state with retry guidance for TikTok-style feed
//

import SwiftUI

struct EmptyFeedView: View {
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles.tv")
                .font(.system(size: 48, weight: .regular))
                .foregroundColor(.white)

            Text("No videos to show")
                .font(.title3).bold()
                .foregroundColor(.white)

            Text("Pull to refresh or tap Retry")
                .font(.subheadline)
                .foregroundColor(.gray)
                .accessibilityLabel("Pull to refresh or tap Retry")

            Button(action: retry) {
                Text("Retry")
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .cornerRadius(8)
            }
            .accessibilityLabel("Retry loading feed")
        }
        .padding()
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        EmptyFeedView(retry: {})
    }
}

