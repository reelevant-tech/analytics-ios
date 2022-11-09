//
//  analyticsTests.swift
//  analyticsTests
//
//  Created by Valentin  on 06/09/2022.
//

import XCTest
@testable import ReelevantAnalytics
import Swifter

final class ReelevantAnalyticsTests: XCTestCase {

    override func setUpWithError() throws {
        // noop
    }

    override func tearDownWithError() throws {
        ReelevantAnalytics.ConfigurationKeys.allCases.forEach { key in
            UserDefaults.standard.removeObject(forKey: key.rawValue)
        }
    }

    func testSendPageViewAndProductPage() throws {
        // Init the SDK
        let config = ReelevantAnalytics.Configuration(companyId: "foo", datasourceId: "bar")
        config.endpoint = "http://localhost:9080/receive"
        let sdk = ReelevantAnalytics.SDK(configuration: config)
        let event = ReelevantAnalytics.Event.page_view(labels: [:])
        
        // Create a local HTTP server to receive events
        let server = HttpServer()
        
        var exp = expectation(description: "Receiving a request")
        var receivedRequest: HttpRequest? = nil
        server["/receive"] = { request in
            receivedRequest = request
            exp.fulfill()
            return .ok(.text("OK"))
        }
        try server.start(9080)
        
        // Send the page_view event
        sdk.send(event: event)
        
        // Wait for a request and then assert
        waitForExpectations(timeout: 3)
        
        var data = Data(receivedRequest!.body)
        var decoder = JSONDecoder()
        var receivedEvent = try decoder.decode(ReelevantAnalytics.BuiltEvent.self, from: data)
        XCTAssertEqual(receivedEvent.name, "page_view")
        XCTAssertEqual(receivedEvent.key, "foo")
        XCTAssertEqual(receivedEvent.url, "unknown")
        XCTAssertEqual(receivedEvent.v, 1)
        XCTAssertEqual(receivedEvent.data.count, 0)
        XCTAssertNil(receivedEvent.clientId)
        XCTAssertNotNil(receivedEvent.tmpId)
        let userTmpId = receivedEvent.tmpId
        XCTAssertNotNil(receivedEvent.eventId)
        let firstEventId = receivedEvent.eventId

        // Identify
        exp = expectation(description: "Receiving identify request")
        sdk.setUser(userId: "my-user")
        waitForExpectations(timeout: 3)
        // Ensure we doesn't send a 2nd req with the same user
        sdk.setUser(userId: "my-user")
        
        exp = expectation(description: "Receiving a second request")
        // Wait for a request and then assert
        let secondEvent = ReelevantAnalytics.Event.product_page(productId: "my-product-id", labels: ["lang": "en_US"])
        sdk.setCurrentURL(url: "https://reelevant.com/my-product-id")
        sdk.send(event: secondEvent)
        waitForExpectations(timeout: 3)
        
        data = Data(receivedRequest!.body)
        decoder = JSONDecoder()
        receivedEvent = try decoder.decode(ReelevantAnalytics.BuiltEvent.self, from: data)
        XCTAssertEqual(receivedEvent.name, "product_page")
        XCTAssertEqual(receivedEvent.key, "foo")
        XCTAssertEqual(receivedEvent.url, "https://reelevant.com/my-product-id")
        XCTAssertEqual(receivedEvent.v, 1)
        XCTAssertEqual(receivedEvent.data, [
            "lang": ReelevantAnalytics.DataValue.string("en_US"),
            "ids": ReelevantAnalytics.DataValue.array(["my-product-id"])
        ])
        XCTAssertEqual(receivedEvent.clientId, "my-user")
        XCTAssertEqual(receivedEvent.tmpId, userTmpId)
        XCTAssertNotNil(receivedEvent.eventId)
        XCTAssertNotEqual(receivedEvent.tmpId, firstEventId)
        
        server.stop()
    }
    
    func testRetry() throws {
        // Init the SDK
        let config = ReelevantAnalytics.Configuration(companyId: "foo", datasourceId: "bar")
        config.endpoint = "http://localhost:9080/receive"
        config.retry = 1 // retry after 1s
        let sdk = ReelevantAnalytics.SDK(configuration: config)
        let event = ReelevantAnalytics.Event.page_view(labels: [:])
        
        // Create a local HTTP server to receive events
        let server = HttpServer()
        
        let exp = expectation(description: "Receiving a retried request")
        var receivedRequest: HttpRequest? = nil
        server["/receive"] = { request in
            let isFirstReq = receivedRequest == nil
            receivedRequest = request
            if isFirstReq {
                return .internalServerError(.none)
            }
            exp.fulfill()
            return .ok(.text("OK"))
        }
        try server.start(9080)
        
        // Send the page_view event
        sdk.send(event: event)
        
        // Wait for a request and then assert
        waitForExpectations(timeout: 3)
        
        let data = Data(receivedRequest!.body)
        let decoder = JSONDecoder()
        let receivedEvent = try decoder.decode(ReelevantAnalytics.BuiltEvent.self, from: data)
        XCTAssertEqual(receivedEvent.name, "page_view")
        
        server.stop()
    }

}
