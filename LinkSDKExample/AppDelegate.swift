//
//  AppDelegate.swift
//  LinkSDKExample
//
//  Created by Mesh Connect, Inc
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let customNavBarAppearance = UINavigationBarAppearance()
        customNavBarAppearance.configureWithOpaqueBackground()
        customNavBarAppearance.backgroundColor = UIColor.white
        customNavBarAppearance.titleTextAttributes = [.foregroundColor: UIColor.black]
        
        let appearance = UINavigationBar.appearance()
        appearance.scrollEdgeAppearance = customNavBarAppearance
        appearance.compactAppearance = customNavBarAppearance
        appearance.standardAppearance = customNavBarAppearance
        
        return true
    }
    
    // MARK: UISceneSession Lifecycle
    
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        config.storyboard = UIStoryboard(name: "Main", bundle: nil)
        return config
    }
    
    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
}
