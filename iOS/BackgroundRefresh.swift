import Foundation
import BackgroundTasks

/// Controlli periodici in background (Background App Refresh): quando l'app è
/// chiusa o disconnessa per timeout, iOS ci concede ogni tanto qualche secondo
/// per connetterci al server, confrontare lo stato con l'ultimo noto e
/// notificare download completati e disconnessioni eD2k/Kad.
/// La cadenza reale la decide iOS (tipicamente 15+ minuti, dipende dall'uso).
enum BackgroundRefresh {
    static let taskID = "com.sdimambro.amule-remote-ios.refresh"

    /// Da chiamare PRIMA che l'app finisca il lancio (App.init).
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refresh)
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        // iOS impone un minimo pratico di ~15 minuti e decide la cadenza reale.
        request.earliestBeginDate = Date(timeIntervalSinceNow: BackgroundMonitor.backgroundInterval)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule()   // ogni esecuzione riprenota la successiva
        let work = Task {
            await BackgroundMonitor.checkDefaultServer()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
