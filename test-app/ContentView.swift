//
//  ContentView.swift
//  test-app
//
//  Created by Valentin  on 06/09/2022.
//

import SwiftUI
import analytics

func onClick () {
    let config = analytics.InitConfiguration(
        companyId: "foo",
        datasourceId: "bar"
    )
    let sdk = analytics.Analytics.init(configuration: config)
    let event = analytics.Event.page_view(labels: [:])
    sdk.send(event: event)
}

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading) {
            Button("Send page view") {
                onClick()
            }
        }
        .buttonStyle(.bordered)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
