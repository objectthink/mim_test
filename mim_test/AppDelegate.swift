//
//  AppDelegate.swift
//  mim_test
//
//  Created by stephen eshelman on 6/6/17.
//  Copyright © 2017 stephen eshelman. All rights reserved.
//

import UIKit
import CocoaAsyncSocket

protocol InstrumentManagerDelegate
{
   func instrumentListUpdate(instruments:[Instrument])
}

protocol InstrumentDelegate
{
}

class Instrument
{
   var heartbeat:String? //instrument unique identifier
   var name:String?
   var serialnumber:String?
   
   var location:String?
   {
      willSet
      {
         if location != nil
         {
            //send change to instrument
            print("   send change to instrument")
            
            instrumentManager?.set(heartbeat: heartbeat!, payload: location!)
         }
      }
      
   }
   
   var instrumentType:String?
   
   var instrumentManager:InstrumentManager?
   
   init(instrumentManager:InstrumentManager)
   {
      self.instrumentManager = instrumentManager
   }
}

class InstrumentManager: NSObject, GCDAsyncSocketDelegate
{
   var _socket:GCDAsyncSocket?
   var _heartbeats:Dictionary<String, Instrument> = [:]
   var _requests:Dictionary<String, (String)->()> = [:] //[replyto : callback]
   
   var _msgIndex:Int = 0
   var _replytoIndex = 0
   
   var delegate:InstrumentManagerDelegate?
   
   var instruments:[Instrument]
   {
      get{return Array(_heartbeats.values)}
   }
   
   init(ip:String, port:Int)
   {
      super.init()
      
      _socket = GCDAsyncSocket.init(delegate: self, delegateQueue: DispatchQueue.main)
      
      do
      {
         //try _socket?.connect(toHost: "52.203.231.127", onPort: 4222)
         try _socket?.connect(toHost: ip, onPort: UInt16(port))
      }
      catch
      {
         print(error.localizedDescription)
      }
   }
   
   //implement gets/sets/actions
   //heartbeat is instrument advertisement is instrument unique identifier
   func get(heartbeat:String, payload:String)
   {
   }
   
   func set(heartbeat:String, payload:String)
   {
      request(subject: "\(heartbeat).set.location", payload: payload)
      {status in
         print("location set was a: \(status)")
      }
   }
   
   func action(heartbeat:String, payload:String)
   {
   }
   /////////////////////////////
   
   func request(subject:String, payload:String, callback:@escaping (String)->())
   {
      _replytoIndex += 1
      _msgIndex += 1
      
      let replyto = "REPLYTO\(_replytoIndex)"
      
      //add to requests dictionary
      _requests[replyto] = callback
      
      let s = "SUB \(replyto) \(_msgIndex)\r\n"
      let p = "PUB \(subject) \(replyto) \(payload.lengthOfBytes(using: .utf8))\r\n\(payload)\r\n"
      
      _socket?.write(Data(bytes: Array(s.utf8)), withTimeout: -1, tag: 9)
      _socket?.write(Data(bytes: Array(p.utf8)), withTimeout: -1, tag: 9)
      _socket?.readData(withTimeout: -1, tag: 8)
   }
   
   func processReply(replyto:String, payload:String)
   {
      _requests[replyto]!(payload)
   }
   
   func processMSG(msg:String)
   {
      //look for subject
      //4 tokens ( no reply-to )
      //5 tokens ( reply-to is present )
      var tokens = msg._split(separator: " ")
      var lines:[String] = []
      
      let subject = tokens[1]
      
      msg.enumerateLines{
         line, _ in
         lines.append(line)
      }
      
      let payload = lines[1]
      
      if(subject == "heartbeat")
      {
         //get heartbeat
         
         let heartbeatExists = _heartbeats[payload] != nil
         
         if(!heartbeatExists)
         {
            _heartbeats[payload] = Instrument(instrumentManager: self)
            _heartbeats[payload]?.heartbeat = payload
            
            print(payload)
            
            _msgIndex += 1
            
            //subscribe to something
            let error_sub = "SUB " + payload + ".error \(_msgIndex)\r\n"
            
            _socket?.write(Data(bytes: Array(error_sub.utf8)), withTimeout: -1, tag: 9)
            
            //request name
            request(subject: "\(payload).get", payload: "name")
            {name in
               print("\(payload):\(name)")
               
               self._heartbeats[payload]?.name = name
               
               self.delegate?.instrumentListUpdate(instruments: self.instruments)
            }
            
            //request serialnumber
            request(subject: "\(payload).get", payload: "serial number")
            {serialnumber in
               print("\(payload):\(serialnumber)")
               
               self._heartbeats[payload]?.serialnumber = serialnumber
            }

            //request location
            request(subject: "\(payload).get", payload: "location")
            {location in
               print("\(payload):\(location)")
               
               self._heartbeats[payload]?.location = location
            }
            
            //request location
            request(subject: "\(payload).get", payload: "instrument type")
            {instrumentType in
               print("\(payload):\(instrumentType)")
               
               self._heartbeats[payload]?.instrumentType = instrumentType
            }

         }
      }
      
      if(subject.hasSuffix(".error"))
      {
         print(payload)
      }
      
      //another way to determine that
      if(_requests.keys.contains(subject))
      {
         processReply(replyto: subject, payload: payload)
      }
   }
   
   func socket(_ sock: GCDAsyncSocket, didConnectToHost host: String, port: UInt16)
   {
      print("connected: \(host)")
      
      let heartbeat_sub = "SUB heartbeat 1\r\n"
      
      _socket?.write(Data(bytes: Array(heartbeat_sub.utf8)), withTimeout: -1, tag: 9)
      
      _socket?.readData(withTimeout: -1, tag: 7)
   }
   
   func socket(_ sock: GCDAsyncSocket, didRead data: Data, withTag tag: Int)
   {
      let s = String(data: data, encoding: .utf8)
      let pong = "PONG\r\n"
      
      //print("received data: \(String(describing: s))")
      
      //let end = "\r\n"
      
      if (s?.hasPrefix("PING"))!
      {
         _socket?.write(Data(bytes: Array(pong.utf8)), withTimeout: -1, tag: 9)
      }
      
      if(s?.hasPrefix("MSG"))!
      {
         processMSG(msg: s!)
      }
      
      //_socket?.readData(to: Data(bytes: Array(end.utf8)), withTimeout: -1, tag: 8)
      _socket?.readData(withTimeout: -1, tag: 8)
   }
   
   func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
      // Override point for customization after application launch.
      _socket = GCDAsyncSocket.init(delegate: self, delegateQueue: DispatchQueue.main)
      
      do
      {
         try _socket?.connect(toHost: "52.203.231.127", onPort: 4222)
      }
      catch
      {
         print(error.localizedDescription)
      }
      
      
      return true
   }
}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, GCDAsyncSocketDelegate, InstrumentManagerDelegate {

   var window: UIWindow?
   
   var _instrumentManager:InstrumentManager?
   
   func instrumentListUpdate(instruments: [Instrument])
   {
      for instrument in instruments
      {
         print("  \(instrument.name ?? "unknown")")
         
         if instrument.name == "Dio"
         {
            //print("   GOT DIO!")
            //instrument.location = "SOMEWHERE ELSE!"
         }
      }
   }
   
   func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
      // Override point for customization after application launch.
      
      _instrumentManager = InstrumentManager(ip: "52.203.231.127", port: 4222)
      _instrumentManager?.delegate = self
      
      return true
   }

   func applicationWillResignActive(_ application: UIApplication) {
      // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
      // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
   }

   func applicationDidEnterBackground(_ application: UIApplication) {
      // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
      // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
   }

   func applicationWillEnterForeground(_ application: UIApplication) {
      // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
   }

   func applicationDidBecomeActive(_ application: UIApplication) {
      // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
   }

   func applicationWillTerminate(_ application: UIApplication) {
      // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
   }


}

