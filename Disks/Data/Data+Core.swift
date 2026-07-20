//
//  Data+Core.swift
//  Disks
//
//  Created by Kyle Erhabor on 7/19/26.
//

import Foundation
import GRDB
import OSLog

typealias RowID = Int64

extension URL {
  static let dataDirectory = Self.applicationSupportDirectory.appending(
    components: Bundle.appID,
    directoryHint: .isDirectory,
  )

  static let databaseFile = Self.dataDirectory
    .appending(components: "Database", "Data", directoryHint: .notDirectory)
    .appendingPathExtension("sqlite3")
}

extension Logger {
  static let data = Self(subsystem: Bundle.appID, category: "Data")
}

extension TableRecord {
  static var everyColumn: [any SQLSelectable] {
    [AllColumns(), Column.rowID]
  }
}

struct DiskImageRecord {
  var rowID: RowID?
  let id: UUID?
  let uuid: UUID?

  init(rowID: RowID? = nil, id: UUID?, uuid: UUID?) {
    self.rowID = rowID
    self.id = id
    self.uuid = uuid
  }
}

extension DiskImageRecord: Equatable, FetchableRecord {}

extension DiskImageRecord: Codable {
  enum CodingKeys: String, CodingKey {
    case rowID = "rowid",
         id, uuid
  }

  enum Columns {
    static let id = Column(CodingKeys.id)
    static let uuid = Column(CodingKeys.uuid)
  }
}

extension DiskImageRecord: MutablePersistableRecord {
  mutating func didInsert(_ inserted: InsertionSuccess) {
    self.rowID = inserted.rowID
  }
}

extension DiskImageRecord: TableRecord {
  static let databaseTableName = "disk_images"
  static var databaseSelection: [any SQLSelectable] {
    Self.everyColumn
  }
}

struct DiskRecord {
  var rowID: RowID?
  let id: UUID?
  let uuid: UUID?

  init(rowID: RowID? = nil, id: UUID?, uuid: UUID?) {
    self.rowID = rowID
    self.id = id
    self.uuid = uuid
  }
}

extension DiskRecord: Equatable, FetchableRecord {}

extension DiskRecord: Codable {
  enum CodingKeys: String, CodingKey {
    case rowID = "rowid",
         id, uuid
  }

  enum Columns {
    static let id = Column(CodingKeys.id)
    static let uuid = Column(CodingKeys.uuid)
  }
}

extension DiskRecord: MutablePersistableRecord {
  mutating func didInsert(_ inserted: InsertionSuccess) {
    self.rowID = inserted.rowID
  }
}

extension DiskRecord: TableRecord {
  static let databaseTableName = "disks"
  static var databaseSelection: [any SQLSelectable] {
    Self.everyColumn
  }
}


func createSchema(_ connection: some DatabaseWriter) async throws {
  var migrator = DatabaseMigrator()
  migrator.registerMigration("v1") { db in
    try db.create(table: DiskImageRecord.databaseTableName) { table in
      table.primaryKey(Column.rowID.name, .integer)
      table
        .column(DiskImageRecord.Columns.id.name, .blob)
        .notNull()
        .unique()

      table
        .column(DiskImageRecord.Columns.uuid.name, .blob)
        .notNull()
        .unique()
    }

    try db.create(table: DiskRecord.databaseTableName) { table in
      table.primaryKey(Column.rowID.name, .integer)
      table
        .column(DiskRecord.Columns.id.name, .blob)
        .notNull()
        .unique()

      table
        .column(DiskRecord.Columns.uuid.name, .blob)
        .notNull()
        .unique()
    }
  }

  #if DEBUG
  migrator.eraseDatabaseOnSchemaChange = true

  #endif

  try migrator.migrate(connection)
}

extension GRDB.Configuration {
  static var standard: Self {
    var configuration = Self()

    #if DEBUG
    configuration.publicStatementArguments = true

    #endif

    configuration.prepareDatabase { db in
      #if DEBUG
      db.trace(options: .profile) { trace in
        Logger.data.debug("SQL> \(trace)")
      }

      #endif

      guard !db.configuration.readonly else {
        return
      }

      // This will execute twice: once for creating the database connection, and another for schema migration.
      try db.execute(literal: "VACUUM")
    }

    return configuration
  }
}

func createDatabaseConnection(at url: URL, configuration: GRDB.Configuration) throws -> DatabasePool {
  let path = url.pathString

  do {
    return try DatabasePool(path: path, configuration: configuration)
  } catch let error as DatabaseError where error.resultCode == .SQLITE_CANTOPEN {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

    return try DatabasePool(path: path, configuration: configuration)
  }
}

let databaseConnection = Once {
  let url = URL.databaseFile
  let configuration = GRDB.Configuration.standard
  let connection = try createDatabaseConnection(at: url, configuration: configuration)
  try await createSchema(connection)

  return connection
}
