//
//  AmazonS3RequestManager.swift
//  AmazonS3RequestManager
//
//  Copyright (c) 2015 Anthony Miller.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.


import Foundation

import Alamofire

/**
The possible Amazon Web Service regions for the client.

- USStandard:   N. Virginia or Pacific Northwest
- USWest1:      Oregon
- USWest2:      N. California
- EUWest1:      Ireland
- EUCentral1:   Frankfurt
- APSoutheast1: Singapore
- APSoutheast2: Sydney
- APNortheast1: Toyko
- SAEast1:      Sao Paulo
*/
public enum AmazonS3Region: String {
  case USStandard = "s3.amazonaws.com",
  USWest1 = "s3-us-west-1.amazonaws.com",
  USWest2 = "s3-us-west-2.amazonaws.com",
  EUWest1 = "s3-eu-west-1.amazonaws.com",
  EUCentral1 = "s3-eu-central-1.amazonaws.com",
  APSoutheast1 = "s3-ap-southeast-1.amazonaws.com",
  APSoutheast2 = "s3-ap-southeast-2.amazonaws.com",
  APNortheast1 = "s3-ap-northeast-1.amazonaws.com",
  SAEast1 = "s3-sa-east-1.amazonaws.com"
}

public class AmazonS3RequestManager: Alamofire.Manager {
  
  /**
  The Amazon S3 Bucket for the client
  */
  public var bucket: String?
  
  /**
  The AWS Bucket for the client
  */
  public var region: AmazonS3Region = .USStandard
  
  /**
  The Amazon S3 Access Key ID used to generate authorization headers and pre-signed queries
  
  :dicussion: This can be found on the AWS control panel: http://aws-portal.amazon.com/gp/aws/developer/account/index.html?action=access-key
  */
  public var accessKey: String?
  
  /**
  The Amazon S3 Secret used to generate authorization headers and pre-signed queries
  
  :dicussion: This can be found on the AWS control panel: http://aws-portal.amazon.com/gp/aws/developer/account/index.html?action=access-key
  */
  public var secret: String?
  
  
  public var sessionToken: String?
  
  /**
  Whether to connect over HTTPS. `true` by default.
  */
  public var useSSL: Bool = true
  
  /**
  A readonly endpoint URL created for the specified bucket, region, and SSL use preference. `AmazonS3RequestManager` uses this as the baseURL for all requests.
  */
  public var endpointURL: NSURL? {
    var URLString = ""
    
    let scheme = self.useSSL ? "https" : "http"
    
    if bucket != nil {
      URLString = "\(scheme)://\(bucket!).\(region.rawValue)"
      
    } else {
      URLString = "\(scheme)://\(region.rawValue)"
    }
    
    return NSURL(string: URLString)
  }

  /**
  MARK: Initialization
  */
  
  convenience public init(bucket: String, region: AmazonS3Region, accessKey: String?, secret: String?) {
    self.init(configuration: AmazonS3RequestManager.amazonConfiguration())
    
    self.bucket = bucket
    self.region = region
    self.accessKey = accessKey
    self.secret = secret
  }

  required public init(configuration: NSURLSessionConfiguration?) {
    self.bucket = ""
    self.region = AmazonS3Region.USStandard
    self.accessKey = ""
    self.secret = ""
    
    super.init(configuration: configuration)
  }
  
  public class func amazonConfiguration() -> NSURLSessionConfiguration {
    let configuration = NSURLSessionConfiguration.defaultSessionConfiguration()
    configuration.HTTPAdditionalHeaders = Alamofire.Manager.defaultHTTPHeaders()
    
    configuration.requestCachePolicy = NSURLRequestCachePolicy.ReloadIgnoringLocalCacheData
    
    return configuration
  }
  
  /**
  MARK: Request
  */
  
  public override func request(method: Alamofire.Method,
    _ URLString: Alamofire.URLStringConvertible,
    parameters: [String: AnyObject]? = nil,
    encoding: ParameterEncoding = .URL) -> Request {
      
    return request(encoding.encode(amazonURLRequest(method, URL: URLString), parameters: parameters).0)
      
  }
  
  private func amazonURLRequest(method: Alamofire.Method,
    URL: Alamofire.URLStringConvertible) -> NSURLRequest {
      
    let mutableURLRequest = NSMutableURLRequest(URL: NSURL(string: URL.URLString)!)
    mutableURLRequest.HTTPMethod = method.rawValue
    
    let amazonRequest = requestBySettingAuthorizationHeaders(forRequest: mutableURLRequest)
    
      //TODO: Error handling
    return amazonRequest.0!
  }
  
  private func requestBySettingAuthorizationHeaders(forRequest request: NSURLRequest) -> (NSURLRequest?, NSError?) {
    
    let mutableRequest = request.mutableCopy() as NSMutableURLRequest
    
    if accessKey != nil && secret != nil {
      
      if sessionToken != nil {
        mutableRequest.setValue(sessionToken!, forHTTPHeaderField: "x-amz-security-token")
      }
      
      let timestamp = currentTimeStamp()
      
      let signature = authorizationSignature(forRequest: mutableRequest, timestamp: timestamp)
      
      mutableRequest.setValue("AWS \(accessKey):\(signature)", forHTTPHeaderField: "Authorization")
      mutableRequest.setValue(timestamp ?? "", forHTTPHeaderField: "Date")
     
      return(mutableRequest, nil)
      
    } else {
      // TODO: Error Handling
      return (nil, nil)
    }
  }
  
  private func currentTimeStamp() -> String {
    return requestDateFormatter.stringFromDate(NSDate())
  }
  
  private lazy var requestDateFormatter: NSDateFormatter = {
    let dateFormatter = NSDateFormatter()
    dateFormatter.timeZone = NSTimeZone(name: "GMT")
    dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
    dateFormatter.locale = NSLocale(localeIdentifier: "en_US_POSIX")
    
    return dateFormatter
    }()
  
  private func authorizationSignature(forRequest request:NSURLRequest, timestamp: String) -> String {
    let method = request.HTTPMethod ?? ""
    let contentMD5 = request.valueForHTTPHeaderField("Content-MD5") ?? ""
    let contentType = request.valueForHTTPHeaderField("Content-Type") ?? ""
    let headerString = canonicalizedHeaderString(forRequest: request)
    let resource = canonicalizedResource(forRequest: request)
    
    var signature = ""
    signature += "\(method)\n"
    signature += "\(contentMD5)\n"
    signature += "\(contentType)\n"
    signature += "\(timestamp)\n"
    signature += "\(headerString)"
    signature += "\(resource)"
    
    return AmazonS3SignatureHelpers.encodedSignatureForSignature(signature, withSecret: secret)
  }
  
  private func canonicalizedHeaderString(forRequest request: NSURLRequest) -> String {
    var headerString = ""
    
    let AMZHeaderFields = amazonHeaderFields(forRequest: request)
    
    let sortedHeaderFields = sorted(AMZHeaderFields) { $0.0 < $1.0 }
    
    for field in sortedHeaderFields {
      headerString += "\(field.0):\(field.1)\n"
      
    }
    
    return headerString
  }
  
  private func amazonHeaderFields(forRequest request: NSURLRequest) -> [String: AnyObject] {
    var AMZHeaderFields = [String: AnyObject]()
    
    if let headers = request.allHTTPHeaderFields as? [String: AnyObject] {
      for header in headers {
        
        let fieldName = header.0.lowercaseString
        
        if fieldName.hasPrefix("x-amz") {
          
          if let existingValue: AnyObject = AMZHeaderFields[fieldName] {
            
            AMZHeaderFields[fieldName] = "\(existingValue),\(header.1)"
            
          } else {
            AMZHeaderFields[fieldName] = header.1
            
          }
        }
      }
    }
    
    return AMZHeaderFields
  }
  
  private func canonicalizedResource(forRequest request: NSURLRequest) -> String {
    var canonicalizedResource: String
    
    if bucket != nil {
      canonicalizedResource = "/\(bucket!)\(request.URL.path)"
      
    } else {
      canonicalizedResource = request.URL.path!
      
    }
    return canonicalizedResource
  }
  
}