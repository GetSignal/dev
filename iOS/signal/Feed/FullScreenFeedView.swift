import SwiftUI

struct FullScreenFeedView: UIViewControllerRepresentable {
    let items: [VideoItem]
    let playerPool: PlayerPool
    let eventBus: EventBusProtocol
    let manifestStore: ManifestStore

    func makeUIViewController(context: Context) -> FullScreenFeedCollectionViewController {
        let vc = FullScreenFeedCollectionViewController(items: items, eventBus: eventBus, playerPool: playerPool, manifestStore: manifestStore)
        return vc
    }

    func updateUIViewController(_ uiViewController: FullScreenFeedCollectionViewController, context: Context) {
        uiViewController.updateItems(items)
    }
}
