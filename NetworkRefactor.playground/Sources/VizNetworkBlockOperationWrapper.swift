//
//  VizNetworkBlockOperationWrapper.swift
//  VizAINotify
//
//  Created by Ran Helfer on 22/06/2021.
//  Copyright © 2021 viz. All rights reserved.
//

import Foundation

enum VizNetworkOperationError: String, Error {
    case noResponseData
    case badMimeType
    case badStatusCode
}

class VizNetworkBlockOperationWrapper<Type: Decodable> {
    
    let vizHttpRequest: VizHTTPRequest
    var dataTask: URLSessionDataTask? = nil
    let completion: (Swift.Result<Type?, Error>) -> Void
    private let SuccessRangeOfStatusCodes: ClosedRange<Int> = (200...299)

    init(vizHttpRequest: VizHTTPRequest,
         startAction: Bool = true,
         completion: @escaping (Swift.Result<Type?, Error>) -> Void) {
        self.vizHttpRequest = vizHttpRequest
        self.completion = completion
        if startAction {
            start()
        }
    }
    
    func start() {
        let operation = BlockOperation()
        operation.addExecutionBlock { [unowned operation, weak self] in
            guard operation.isCancelled == false else {return}
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async {
                self?.addDataTask()
            }
            group.wait()
        }
    }
    
    func addDataTask() {
        dataTask = URLSession.shared.dataTask(with: vizHttpRequest.urlRequest) { [weak self] (data, response, error) in
            guard let weakSelf = self else {return}
            /* Accumulate errors so we can log all errors if needed */
            var errorsArray = [Error]()
            
            if let error = error {
                errorsArray.append(error)
            }
            
            if let response = response as? HTTPURLResponse, !weakSelf.SuccessRangeOfStatusCodes.contains(response.statusCode) {
                errorsArray.append(VizNetworkOperationError.badStatusCode)
            }

            if let response = response as? HTTPURLResponse,
                let mime = response.mimeType,
                mime == weakSelf.vizHttpRequest.expectedMimeType {
                errorsArray.append(VizNetworkOperationError.badMimeType)
            }
            
            if data == nil {
                errorsArray.append(VizNetworkOperationError.noResponseData)
            }
            
            /* Setting final handler according to errors accumulation or decoding status */
            var finalHandler:Swift.Result<Type?, Error>

            if errorsArray.count > 0,
               let err = errorsArray.first {
                finalHandler = .failure(err)
                weakSelf.logErrorsIfNeeded(logNeeded: weakSelf.vizHttpRequest.logToConsole, errors: errorsArray)
            } else {
                /* We are errors safe and we can try decode */
                do {
                    let concreteType = try JSONDecoder().decode(Type.self, from:data!)
                    finalHandler = .success(concreteType)
                } catch let err {
                    finalHandler = .failure(err)
                }
            }
            
            if let queue = weakSelf.vizHttpRequest.completionDispatchQueue {
                queue.async {
                    weakSelf.completion(finalHandler)
                }
            } else {
                weakSelf.completion(finalHandler)
            }
        }
        dataTask?.resume()
    }
    
    private func logErrorsIfNeeded(logNeeded: Bool, errors: [Error]) {
        guard logNeeded && errors.count > 0 else {
            return
        }
        for error in errors {
            print("VizNetworkOperation Error: \(error)")
        }
    }
}
