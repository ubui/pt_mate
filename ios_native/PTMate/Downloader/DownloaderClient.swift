import Foundation

protocol DownloaderClient {
    func testConnection() async throws

    func getTransferInfo() async throws -> TransferInfo

    func getServerState() async throws -> ServerState

    func getTasks(params: GetTasksParams?) async throws -> [DownloadTask]

    func addTask(_ params: AddTaskParams, siteConfig: SiteConfig?) async throws

    func pauseTasks(_ hashes: [String]) async throws

    func resumeTasks(_ hashes: [String]) async throws

    func deleteTasks(_ hashes: [String], deleteFiles: Bool) async throws

    func getCategories() async throws -> [String]

    func getTags() async throws -> [String]

    func getVersion() async throws -> String

    func getPaths() async throws -> [String]
}

extension DownloaderClient {
    func getTasks() async throws -> [DownloadTask] {
        try await getTasks(params: nil)
    }

    func addTask(_ params: AddTaskParams) async throws {
        try await addTask(params, siteConfig: nil)
    }

    func deleteTasks(_ hashes: [String]) async throws {
        try await deleteTasks(hashes, deleteFiles: false)
    }

    func pauseTask(_ hash: String) async throws {
        try await pauseTasks([hash])
    }

    func resumeTask(_ hash: String) async throws {
        try await resumeTasks([hash])
    }

    func deleteTask(_ hash: String, deleteFiles: Bool = false) async throws {
        try await deleteTasks([hash], deleteFiles: deleteFiles)
    }
}