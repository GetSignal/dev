//
//  FeedView.swift
//  signal
//
//  Main feed view implementing vertical video scrolling
//

import SwiftUI
import UIKit

struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @State private var currentIndex: Int = 0
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
            } else if !viewModel.items.isEmpty {
                FullScreenFeedView(
                    items: viewModel.items,
                    playerPool: viewModel.playerPool,
                    eventBus: viewModel.eventBus
                )
                .ignoresSafeArea()
                .onChange(of: currentIndex) { newIndex in
                    viewModel.videoDidAppear(at: newIndex)
                }
            } else if viewModel.error == nil {
                // Empty-state (no items, not loading, no error)
                EmptyFeedView {
                    Task { await viewModel.loadInitialFeed() }
                }
            } else if let error = viewModel.error {
                ErrorView(error: error) {
                    Task {
                        await viewModel.loadInitialFeed()
                    }
                }
            }
        }
        .task {
            await viewModel.loadInitialFeed()
        }
        .refreshable {
            await viewModel.loadInitialFeed()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            viewModel.didEnterBackground()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await viewModel.willEnterForeground() }
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }
}

struct ErrorView: View {
    let error: Error
    let retry: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.white)
            
            Text("Failed to load feed")
                .font(.title2)
                .foregroundColor(.white)
            
            Text(error.localizedDescription)
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: retry) {
                Text("Tap to Retry")
                    .foregroundColor(.white)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(8)
            }
        }
        .padding()
    }
}

#Preview {
    FeedView()
}
