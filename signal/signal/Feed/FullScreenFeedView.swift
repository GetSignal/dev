import SwiftUI

struct FullScreenFeedView: UIViewControllerRepresentable {
    let items: [VideoItem]
    let playerPool: PlayerPool
    let eventBus: EventBusProtocol

    func makeUIViewController(context: Context) -> FullScreenFeedCollectionViewController {
        let vc = FullScreenFeedCollectionViewController(items: items, eventBus: eventBus, playerPool: playerPool)
        return vc
    }

    func updateUIViewController(_ uiViewController: FullScreenFeedCollectionViewController, context: Context) {
        uiViewController.updateItems(items)
    }
}

