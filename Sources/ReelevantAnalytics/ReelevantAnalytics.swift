//
//  analytics.swift
//  analytics
//
//  Created by Valentin  on 06/09/2022.
//
import Foundation
import WebKit
#if canImport(UIKit)
import UIKit
#endif
import OSLog

public struct ReelevantAnalytics {
    /**
        Defined events
     */
    public enum Event {
        case page_view(labels: Dictionary<String, String>)
        case product_page(productId: String, labels: Dictionary<String, String>)
        case add_cart(ids: Array<String>, labels: Dictionary<String, String>)
        case purchase(ids: Array<String>, totalAmount: Float, labels: Dictionary<String, String>, transId: String?)
        case category_view(categoryId: String, labels: Dictionary<String, String>)
        case brand_view(brandId: String, labels: Dictionary<String, String>)
        case product_hover(productId: String, labels: Dictionary<String, String>)
        case custom(name: String, labels: Dictionary<String, String>)

        // source: https://gist.github.com/qmchenry/a3b317a8cc47bd06aeabc0ddf95ba113
        var caseName: String {
            return Mirror(reflecting: self).children.first?.label ?? String(describing: self)
        }
    }

    /**
        Configuration for the SDK
     */
    public struct Configuration {
        public init (companyId: String, datasourceId: String) {
            self.companyId = companyId
            self.datasourceId = datasourceId
            self.endpoint = "https://collector.reelevant.com/collect/\(datasourceId)/rlvt"
            self.retry = 60 // 1m
        }

        let companyId: String
        let datasourceId: String
        var currentUrl: String?
        var endpoint: String
        var retry: Double
    }

    /**
        Private configuration keys stored on the device
     */
    public enum ConfigurationKeys: String, CaseIterable {
        case userId
        case tmpId
        case queue
    }

    /**
        Custom enum to be able to define array of string / string (optional) or number for `data` property
     */
    public enum DataValue: Codable, Equatable {
        
        case array(Array<String>), string(String?), number(Float)
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            
            if let v = try? container.decode(Float.self) {
                self = .number(v)
                return
            } else if let v = try? container.decode(Array<String>.self) {
                self = .array(v)
                return
            }
            
            let v = try? container.decode(String?.self)
            self = .string(v)
        }
        
        public func encode(to encoder: Encoder) throws {
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
    static private func convertLabelsToData (labels: Dictionary<String, String>) -> Dictionary<String, DataValue> {
        return labels.mapValues { value in
            return DataValue.string(value)
        }
    }

    /**
        Sent event schema
     */
    public struct BuiltEvent: Codable {
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

    @available(macOS 10.12, iOS 10.0, *)
    public class SDK {
        private var configuration: Configuration
        
        /**
            Create the SDK instance
         */
        public init(configuration: Configuration) {
            self.configuration = configuration

            // Init tmp id
            let defaults = UserDefaults.standard
            if defaults.string(forKey: ConfigurationKeys.tmpId.rawValue) == nil {
                #if canImport(UIKit)
                let tmpId = UIDevice.current.identifierForVendor?.uuidString ?? self.randomIdentifier()
                #else
                let tmpId = self.randomIdentifier()
                #endif
                defaults.set(tmpId, forKey: ConfigurationKeys.tmpId.rawValue)
            }
            
            // Empty fail queue every 15s
            Timer.scheduledTimer(withTimeInterval: self.configuration.retry, repeats: true) { (timer) in
                var queue = self.getFailQueue()
                if queue.count > 0 {
                    // Remove element from queue
                    let data = queue.removeFirst()
                    let defaults = UserDefaults.standard
                    defaults.set(queue, forKey: ConfigurationKeys.queue.rawValue)

                    // We don't send the event if he is older than 15min
                    let decoder = JSONDecoder()
                    do {
                        let event = try decoder.decode(ReelevantAnalytics.BuiltEvent.self, from: data)
                        let timeSinceEvent = Int64(Date().timeIntervalSince1970 * 1000) - event.timestamp
                        if timeSinceEvent <= 15 * 60 * 1000 {
                            self.send(body: data)
                        }
                    } catch {
                         os_log("Unable to send queued event from Reelevant analytics SDK: %@", log: OSLog.default, type: .error, error as CVarArg)
                    }
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
            case .add_cart(let ids, let labels):
                let payload = convertLabelsToData(labels: labels)
                    .merging(["ids": DataValue.array(ids)]) { (current, _) in current }
                self.publishEvent(name: "add_cart", payload: payload)
            case .purchase(let ids, let totalAmount, let labels, let transId):
                let payload = convertLabelsToData(labels: labels)
                    .merging([
                        "ids": DataValue.array(ids),
                        "value": DataValue.number(totalAmount),
                        "transId": DataValue.string(transId)
                    ]) { (current, _) in current }
                self.publishEvent(name: "purchase", payload: payload)
            case .product_page(let id, let labels):
                fallthrough
            case .category_view(let id, let labels):
                fallthrough
            case .brand_view(let id, let labels):
                fallthrough
            case .product_hover(let id, let labels):
                let payload = convertLabelsToData(labels: labels)
                    .merging(["ids": DataValue.array([id])]) { (current, _) in current }
                self.publishEvent(name: event.caseName, payload: payload)
            case .custom(let name, let labels):
                self.publishEvent(name: name, payload: convertLabelsToData(labels: labels))
            }
        }
        
        /**
            Set the current user (`clientId` property)
         */
        public func setUser (userId: String) {
            let defaults = UserDefaults.standard
            let currentValue = defaults.string(forKey: ConfigurationKeys.userId.rawValue)
            if currentValue != userId {
                defaults.set(userId, forKey: ConfigurationKeys.userId.rawValue)
                self.publishEvent(name: "identify", payload: [String: DataValue]())
            }
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
            return (defaults.array(forKey: ConfigurationKeys.queue.rawValue) as? Array<Data>) ?? []
        }
        
        /**
            Add element to the current fail queue and save it on the local device
         */
        private func pushToFailQueue (data: Data) {
            let defaults = UserDefaults.standard
            var currentQueue = self.getFailQueue()
            currentQueue.append(data)
            defaults.set(currentQueue, forKey: ConfigurationKeys.queue.rawValue)
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
            let url = URL(string: self.configuration.endpoint)!
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            // Avoid being considered as a bot
            request.setValue(WKWebView().value(forKey: "userAgent") as? String ?? "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/104.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.httpMethod = "POST"
            request.httpBody = body

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                let httpResponse = response as? HTTPURLResponse
                if error != nil || httpResponse?.statusCode ?? 500 >= 500 {
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
                tmpId: defaults.string(forKey: ConfigurationKeys.tmpId.rawValue)!,
                clientId: defaults.string(forKey: ConfigurationKeys.userId.rawValue),
                data: payload,
                eventId: self.randomIdentifier(),
                v: 1,
                timestamp: Int64(Date().timeIntervalSince1970 * 1000)
            )
            return event
        }
    }
}
