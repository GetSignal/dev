import SwiftUI

// Wraps onChange to support iOS 17+ two-parameter form while preserving compatibility.
struct CurrentIndexObserver: ViewModifier {
    @Binding var currentIndex: Int
    let handler: (_ oldValue: Int, _ newValue: Int) -> Void

    func body(content: Content) -> some View {
        content
            .background(ObserverView(currentIndex: $currentIndex, handler: handler))
    }

    private struct ObserverView: View {
        @Binding var currentIndex: Int
        let handler: (_ oldValue: Int, _ newValue: Int) -> Void

        var body: some View {
            Group {
                if #available(iOS 17.0, *) {
                    EmptyView()
                        .onChange(of: currentIndex) { oldValue, newValue in
                            handler(oldValue, newValue)
                        }
                } else {
                    EmptyView()
                        .onChange(of: currentIndex) { newValue in
                            // We don't have the old value pre-iOS 17; pass same twice
                            handler(newValue, newValue)
                        }
                }
            }
        }
    }
}

