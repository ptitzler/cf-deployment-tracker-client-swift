/**
* Copyright IBM Corporation 2016, 2017
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
* http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
**/

import Foundation
import Configuration
import CloudFoundryEnv
import CloudFoundryConfig
import LoggerAPI
import KituraNet

public struct CloudFoundryDeploymentTracker {

  var configMgr: ConfigurationManager?
  var repositoryURL: String
  var codeVersion: String?

  public init(repositoryURL: String, codeVersion: String? = nil) {
    self.repositoryURL = repositoryURL
    self.codeVersion = codeVersion
    println("XXX")
    let configMgr = ConfigurationManager()
    println("YYY")
    configMgr.load(.environmentVariables)
    println("ZZZ")
  }

  public init(configMgr: ConfigurationManager, repositoryURL: String, codeVersion: String? = nil) {
    self.repositoryURL = repositoryURL
    self.codeVersion = codeVersion
    self.configMgr = configMgr
  }


  /// Sends off http post request to tracking service, simply logging errors on failure
  public func track() {
    if let configMgr = configMgr, let trackerJson = buildTrackerJson(configMgr: configMgr),
       let jsonData = try? JSONSerialization.data(withJSONObject: trackerJson) {

      var requestOptions: [ClientRequest.Options] = []
      requestOptions.append(.method("POST"))
      requestOptions.append(.schema("https://"))
      requestOptions.append(.hostname("deployment-tracker.mybluemix.net"))
      requestOptions.append(.port(443))
      requestOptions.append(.path("/api/v1/track"))
      let headers = ["Content-Type": "application/json"]
      requestOptions.append(.headers(headers))

      let req = HTTP.request(requestOptions) { response in
        if let response = response, response.statusCode == HTTPStatusCode.OK || response.statusCode == HTTPStatusCode.created {
          println("Uploaded stats \(response.status)")
          do {
            var body = Data()
            try response.readAllData(into: &body)
            let jsonResponse = try JSONSerialization.jsonObject(with: body, options: [])
            Log.info("Deployment Tracker response: \(jsonResponse)")
          } catch {
            Log.error("Bad JSON doc received from deployment tracker.")
          }
        } else {
          println("Failed to send tracking data with status code: \(String(describing: response?.status))")
        }
      }
      req.end(jsonData)
    } else {
      println("Failed to build valid JSON payload for deployment tracker... maybe running locally and not on the cloud?")
      return
    }
  }

  /// Helper method to build Json in a valid format for tracking service
  ///
  /// - parameter configMgr: application environment to pull Bluemix app data from
  ///
  /// - returns: JSON, assuming we have access to application info
  public func buildTrackerJson(configMgr: ConfigurationManager) -> [String:Any]? {
      var jsonEvent: [String:Any] = [:]
      guard let vcapApplication = configMgr.getApp() else {
        Log.error("Couldn't get Cloud Foundry App instance... maybe running locally and not on the cloud?")
        return nil
      }

      let dateFormatter = DateFormatter()
      #if os(OSX)
        //dateFormatter.calendar = Calendar(identifier: .iso8601)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
      #else
        //dateFormatter.calendar = Calendar(identifier: .iso8601)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(abbreviation: "GMT")
      #endif
      dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSX"
      jsonEvent["date_sent"] = dateFormatter.string(from: Date())

      if let codeVersion = self.codeVersion {
        jsonEvent["code_version"] = codeVersion
      }
      jsonEvent["repository_url"] = repositoryURL
      jsonEvent["runtime"] = "swift"
      jsonEvent["application_name"] = vcapApplication.name
      jsonEvent["space_id"] = vcapApplication.spaceId
      jsonEvent["application_id"] = vcapApplication.id
      jsonEvent["application_version"] = vcapApplication.version
      jsonEvent["application_uris"] = vcapApplication.uris
      jsonEvent["instance_index"] = vcapApplication.instanceIndex

      let services = configMgr.getServices()
      if services.count > 0 {
        var serviceDictionary = [String: Any]()
        for (_, service) in services {
            if var serviceStats = serviceDictionary[service.label] as? [String: Any] {
            if let count = serviceStats["count"] as? Int {
                serviceStats["count"] = count + 1
            }
            if var plans = serviceStats["plans"] as? [String] {
              if !plans.contains(service.plan) { plans.append(service.plan) }
              serviceStats["plans"] = plans
            }
            serviceDictionary[service.label] = serviceStats
          } else {
            var newService = [String: Any]()
            newService["count"] = 1
            newService["plans"] = service.plan.components(separatedBy: ", ")
            serviceDictionary[service.label] = newService
          }
        }
        jsonEvent["bound_vcap_services"] = serviceDictionary
      }
      return jsonEvent
  }

}
