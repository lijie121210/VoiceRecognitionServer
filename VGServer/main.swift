//
//  main.swift
//  VGServer
//
//  Created by jie on 2017/2/18.
//  Copyright © 2017年 HTIOT.Inc. All rights reserved.
//

import Foundation
import CocoaAsyncSocket


func logging(arg: String) {
    print("\(Date()): ", arg)
}

func startApp() { autoreleasepool { () -> () in
    
    let servApp = Server()
    
    logging(arg: "launching app server...")
    
    guard servApp.listen() else {
        
        logging(arg: "fail to start app server.")
        
        return
    }
    
    logging(arg: "running current runloop...")

    RunLoop.current.run()
}}

logging(arg: "launching app ...")

startApp()
