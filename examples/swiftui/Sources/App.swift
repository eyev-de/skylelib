import SwiftUI

@main
struct SkyleSwiftUIExampleApp: App {
    @StateObject private var viewModel = SkyleViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(vm: viewModel)
                .frame(minWidth: 520, minHeight: 480)
                .onDisappear { viewModel.shutdown() }
        }
    }
}
