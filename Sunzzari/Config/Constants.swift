import Foundation

enum Constants {

    enum Notion {
        static let token        = "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"
        static let dinosaursDBID = "6538fcf3-fb3e-42de-a04d-794883895ba3"
        static let memoriesDBID  = "ae560a63-ba2f-4c0d-91c4-dc9de9e8e271"
        static let bestOfDBID       = "8cb7077a-ba21-4c10-a565-c6150fd9295c"
        static let restaurantsDBID  = "9078462d-842a-4233-82d9-dbd07014782b"
        static let winesDBID        = "e412ba9c-46eb-40fe-8dbe-58763c4501e7"
        static let activitiesDBID   = "ca04eea9-94f9-4be5-a075-5e509d236ccb"
        static let cycleTrackerDBID = "c2c5b2ed-5407-45db-bf4a-f89bf5a69cba"
        static let creditsTrackerDBID = "1cb0f680-349c-4666-8e4e-bac5676f7676"
        static let thoughtActionDBID  = "f876fb04-dfe2-4945-81fe-f85f36b30bcb"
        static let sunzzariInfoDBID   = "34650319-3d6e-4b7f-96c2-b81efaf8a279"
        static let version          = "2022-06-28"
    }

    enum Cloudinary {
        static let cloudName    = "dhkw1tuq6"
        static let uploadPreset = "sunzzari_uploads"
    }

    enum Travel {
        static let mapURL = URL(string: "https://elisa-travel-map.vercel.app")!
    }

    enum Boop {
        /// Private shared topic — both phones use the same string.
        /// Change this to any unique string to reset the channel.
        static let topic = "sunzzari-boop-7f4a2e91bc3d"
    }

    enum Anthropic {
        static let model = "claude-sonnet-4-6"
    }

    enum Status {
        /// Separate ntfy topic for mood notifications (never share with boop topic)
        static let ntfyTopic = "sunzzari-status-9b2c4f81ae7d"
        /// Notion page IDs for the two Status rows — fill in after Step 0 (create DB)
        static let hummingbirdPageID = "322f3cdd-67a4-815e-8619-cef755d2098b"
        static let branchPageID      = "322f3cdd-67a4-8184-9594-f0bb9f5c100c"
        /// APNs push backend
        static let pushEndpoint = "https://sunzzari-backend.vercel.app/api/push"
        static let pushSecret   = "d9be2a5c20fd74f0df195d1140a2fe97a9e3bd8b967060a4"
    }
}
