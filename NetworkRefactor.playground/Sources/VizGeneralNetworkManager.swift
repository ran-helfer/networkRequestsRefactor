//
//  VizGeneralNetworkManager.swift
//  VizAINotify
//
//  Created by Ran Helfer on 22/06/2021.
//  Copyright © 2021 viz. All rights reserved.
//
// A general networking manager unifying https network requests
//
// HttpMethod and Request structs are based upon:
// https://swiftwithmajid.com/2021/02/10/building-type-safe-networking-in-swift/

import Foundation

enum HttpMethod: Equatable {
    static func == (lhs: HttpMethod, rhs: HttpMethod) -> Bool {
        guard lhs.name == rhs.name else {
            return false
        }
        return true
    }
    
    case get([URLQueryItem])
    case put(Any?)
    case post(Any?)
    case delete
    case head

    var name: String {
        switch self {
        case .get: return "GET"
        case .put: return "PUT"
        case .post: return "POST"
        case .delete: return "DELETE"
        case .head: return "HEAD"
        }
    }
    
    func requestInputDataAsData() -> Data? {
        switch self {
        case .post(let input), .put(let input): do {
            if let input = input as? Decodable {
                return try? JSONSerialization.data(withJSONObject: input)
            }
            return nil
        }
        case .get: return nil
        case .delete: return nil
        case .head: return nil
        }
    }
}

struct VizHTTPRequest {
    var defaultTimeOut = TimeInterval(15)
    let url: URL
    let method: HttpMethod
    var headers: [String: String] = [:]
    let timeOut:TimeInterval?
    var expectedMimeType: String = "application/json"
    var completionDispatchQueue: DispatchQueue?
    var logToConsole: Bool = false

    var urlRequest: URLRequest {
        var request = URLRequest(url: url)

        switch method {
        case .post, .put:
            request.httpBody = method.requestInputDataAsData()
        case let .get(queryItems):
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = queryItems
            guard let url = components?.url else {
                preconditionFailure("Couldn't create a url from components...")
            }
            request = URLRequest(url: url)
        default:
            break
        }
        
        request.allHTTPHeaderFields = headers
        request.httpMethod = method.name
        request.timeoutInterval = timeOut ?? defaultTimeOut
        
        return request
    }
}

struct VizGeneralNetworkManager {
    
    private var operationQueue = OperationQueue()
    private static let min_URL_Length = 5
    private static let defaultQueueConcurrentOperations = 5
    
    init(maxConcurent: Int = Self.defaultQueueConcurrentOperations) {
        operationQueue.maxConcurrentOperationCount = maxConcurent
    }
    
    func sendRequest
            <Type: Codable>(vizHttpRequest: VizHTTPRequest,
                            logToConsole: Bool = false,
                            completion: @escaping (Swift.Result<Type?, Error>) -> Void) -> URLSessionDataTask? {

        guard vizHttpRequest.url.path.count > Self.min_URL_Length else {
            completion(.failure(VizGeneralNetworkManagerError.setupErrorURLIsTooShort))
            return nil
        }

        let operation = VizNetworkBlockOperationWrapper(vizHttpRequest: vizHttpRequest,
                                                        completion: completion)
        assert(operation.dataTask != nil, "VizNetworkOperation returned nil data task")
        return operation.dataTask
    }
    
    
    func cancelAllTasks() {
        operationQueue.cancelAllOperations()
    }
    
    func cancelDataTask(task: URLSessionDataTask) {
        let taskToCancel = operationQueue.operations.first(where: {$0 == task})
        taskToCancel?.cancel()
    }
}

enum VizGeneralNetworkManagerError: String, Error {
    case setupErrorURLIsTooShort
}

