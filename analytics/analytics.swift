//
//  analytics.swift
//  analytics
//
//  Created by Valentin  on 06/09/2022.
//

import Foundation
import UIKit
import OSLog

/**
    Defined events
 */
public enum Event {
    case page_view(labels: Dictionary<String, String>)
    case product_page(ids: Array<String>, labels: Dictionary<String, String>)
    case add_cart(ids: Array<String>, labels: Dictionary<String, String>)
    case purchase(ids: Array<String>, totalAmount: Float, labels: Dictionary<String, String>, transId: String?)
    case category_view(categoryId: String, labels: Dictionary<String, String>)
    case brand_view(brandId: String, labels: Dictionary<String, String>)
    case product_hover(productId: String, labels: Dictionary<String, String>)
    case custom(name: String, labels: Dictionary<String, String>)
}

/**
    Configuration for the SDK
 */
public struct InitConfiguration {
    public init (companyId: String, datasourceId: String) {
        self.companyId = companyId
        self.datasourceId = datasourceId
    }

    let companyId: String
    let datasourceId: String
    var currentUrl: String?
}

/**
    Private configuration keys stored on the device
 */
private struct ConfigurationKeys {
    static let userId = "user-id"
    static let tmpId = "tmp-id"
    static let queue = "queue"
}

/**
    Custom enum to be able to define array of string / string (optional) or number for `data` property
 */
private enum DataValue: Encodable {
    
    case array(Array<String>), string(String?), number(Float)
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch self {
        case .array(let array):
            try container.encode(array)
        case .string(let optional):
            if optional == nil {
                try container.encodeNil()
            } else {
                try container.encode(optional)
            }
        case .number(let float):
            try container.encode(float)
        }
    }
}

/**
    Convert dict labels to data labels
 */
private func convertLabelsToData (labels: Dictionary<String, String>) -> Dictionary<String, DataValue> {
    return labels.mapValues { value in
        return DataValue.string(value)
    }
}

/**
    Sent event schema
 */
private struct BuiltEvent: Encodable {
    let key: String
    let name: String
    let url: String
    let tmpId: String
    let clientId: String?
    let data: Dictionary<String, DataValue>
    let eventId: String
    let v: Int
    let timestamp: Int64
}

public class Analytics {
    private var configuration: InitConfiguration
    
    /**
        Create the SDK instance
     */
    public init(configuration: InitConfiguration) {
        self.configuration = configuration

        // Init tmp id
        let defaults = UserDefaults.standard
        if defaults.string(forKey: ConfigurationKeys.tmpId) == nil {
            defaults.set(
                UIDevice.current.identifierForVendor?.uuidString ?? self.randomIdentifier(),
                forKey: ConfigurationKeys.tmpId
            )
        }
        
        // Empty fail queue every 15s
        Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { (timer) in
            var queue = self.getFailQueue()
            if queue.count > 0 {
                // Remove element from queue
                let data = queue.removeFirst()
                let defaults = UserDefaults.standard
                defaults.set(queue, forKey: ConfigurationKeys.queue)

                self.send(body: data)
            }
        }
    }
    
    /**
        Use this method to trigger an event with the associated payload and labels
        You should build event with the `Event` enum:
        ```
        let event = Event.page_view(labels=[:])
        sdk.send(event)
        ```
     */
    public func send (event: Event) {
        switch event {
        case .page_view(let labels):
            self.publishEvent(name: "page_view", payload: convertLabelsToData(labels: labels))
        case .product_page(let ids, let labels):
            fallthrough
        case .add_cart(let ids, let labels):
            let payload = convertLabelsToData(labels: labels)
                .merging(["ids": DataValue.array(ids)]) { (current, _) in current }
            self.publishEvent(name: "product_page", payload: payload)
        case .purchase(let ids, let totalAmount, let labels, let transId):
            let payload = convertLabelsToData(labels: labels)
                .merging([
                    "ids": DataValue.array(ids),
                    "value": DataValue.number(totalAmount),
                    "transId": DataValue.string(transId)
                ]) { (current, _) in current }
            self.publishEvent(name: "product_page", payload: payload)
        case .category_view(let id, let labels):
            fallthrough
        case .brand_view(let id, let labels):
            fallthrough
        case .product_hover(let id, let labels):
            let payload = convertLabelsToData(labels: labels)
                .merging(["ids": DataValue.array([id])]) { (current, _) in current }
            self.publishEvent(name: "product_page", payload: payload)
        case .custom(let name, let labels):
            self.publishEvent(name: name, payload: convertLabelsToData(labels: labels))
        }
    }
    
    /**
        Set the current user (`clientId` property)
     */
    public func setUser (userId: String) {
        let defaults = UserDefaults.standard
        defaults.set(userId, forKey: ConfigurationKeys.userId)
        self.publishEvent(name: "identify", payload: [String: DataValue]())
    }
    
    /**
        Set the current URL
     */
    public func setCurrentURL (url: String) {
        self.configuration.currentUrl = url
    }
    
    /**
        Generate random identifier (used for `tmpId` when unable to get IOS uuid, or for eventId)
     */
    private func randomIdentifier () -> String {
      let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
      return String((0..<25).map{ _ in letters.randomElement()! })
    }
    
    /**
        Retrieve fail queue from device
     */
    private func getFailQueue () -> Array<Data> {
        let defaults = UserDefaults.standard
        return (defaults.array(forKey: ConfigurationKeys.queue) as? Array<Data>) ?? []
    }
    
    /**
        Add element to the current fail queue and save it on the local device
     */
    private func pushToFailQueue (data: Data) {
        let defaults = UserDefaults.standard
        var currentQueue = self.getFailQueue()
        currentQueue.append(data)
        defaults.set(currentQueue, forKey: ConfigurationKeys.queue)
    }

    /**
        Build and send the event to the network
     */
    private func publishEvent (name: String, payload: Dictionary<String, DataValue>) {
        do {
            let builtEvent = self.buildEventPayload(name: name, payload: payload)
            let encoder = JSONEncoder()
            let data = try encoder.encode(builtEvent)
            return self.send(body: data)
        } catch {
            os_log("Unable to build event from Reelevant analytics SDK: %@", log: OSLog.default, type: .error, error as CVarArg)
        }
    }
    
    /**
        Send built event to the network
     */
    private func send (body: Data) {
        let url = URL(string: "https://collector.reelevant.com/collect/\(self.configuration.datasourceId)/rlvt")!
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Avoid being considered as a bot
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/104.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.httpMethod = "POST"
        request.httpBody = body

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            let httpResponse = response as? HTTPURLResponse
            if error == nil || httpResponse?.statusCode ?? 500 >= 500 {
                if error != nil {
                    os_log("Unable to send event from Reelevant analytics SDK: %@", log: OSLog.default, type: .error, error! as CVarArg)
                } else {
                    os_log("Unable to send event from Reelevant analytics SDK: %@", log: OSLog.default, type: .error, "HTTP status code: \(httpResponse?.statusCode ?? 500)")
                }
                self.pushToFailQueue(data: body)
            }
        }

        task.resume()
    }
    
    /**
        Build the event payload
     */
    private func buildEventPayload (name: String, payload: Dictionary<String, DataValue>) -> BuiltEvent {
        let defaults = UserDefaults.standard
        let event = BuiltEvent(
            key: self.configuration.companyId,
            name: name,
            url: self.configuration.currentUrl ?? "unknown",
            tmpId: defaults.string(forKey: ConfigurationKeys.tmpId)!,
            clientId: defaults.string(forKey: ConfigurationKeys.userId),
            data: payload,
            eventId: self.randomIdentifier(),
            v: 1,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000)
        )
        return event
    }
}
