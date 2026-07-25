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

  // MARK: Volume
  let volumeID: UUID?

  init(rowID: RowID? = nil, id: UUID?, volumeID: UUID?) {
    self.rowID = rowID
    self.id = id
    self.volumeID = volumeID
  }
}

extension DiskRecord: Equatable, FetchableRecord {}

extension DiskRecord: Codable {
  enum CodingKeys: String, CodingKey {
    case rowID = "rowid",
         id,
         volumeID = "volume_id"
  }

  enum Columns {
    static let id = Column(CodingKeys.id)
    static let volumeID = Column(CodingKeys.volumeID)

    // MARK: v1
    static let uuidv1 = Column("uuid")
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

//struct DiskDiskDriveRecord {
//  var rowID: RowID?
//  let drive: RowID?
//  let disk: RowID?
//
//  init(rowID: RowID? = nil, drive: RowID?, disk: RowID?) {
//    self.rowID = rowID
//    self.drive = drive
//    self.disk = disk
//  }
//}
//
//extension DiskDiskDriveRecord: Equatable, FetchableRecord {}
//
//extension DiskDiskDriveRecord: Codable {
//  enum CodingKeys: String, CodingKey {
//    case rowID = "rowid",
//         drive, disk
//  }
//
//  enum Columns {
//    static let drive = Column(CodingKeys.drive)
//    static let disk = Column(CodingKeys.disk)
//  }
//}
//
//extension DiskDiskDriveRecord: MutablePersistableRecord {
//  mutating func didInsert(_ inserted: InsertionSuccess) {
//    self.rowID = inserted.rowID
//  }
//}
//
//extension DiskDiskDriveRecord: TableRecord {
//  static let databaseTableName = "disk_disk_drives"
//  static var databaseSelection: [any SQLSelectable] {
//    Self.everyColumn
//  }
//}

struct DiskDriveRecord {
  var rowID: RowID?
  let serial: String?
  let name: String?

  init(rowID: RowID? = nil, serial: String?, name: String?) {
    self.rowID = rowID
    self.serial = serial
    self.name = name
  }
}

extension DiskDriveRecord: Equatable, FetchableRecord {}

extension DiskDriveRecord: Codable {
  enum CodingKeys: String, CodingKey {
    case rowID = "rowid",
         serial, name
  }

  enum Columns {
    static let serial = Column(CodingKeys.serial)
    static let name = Column(CodingKeys.name)
  }
}

extension DiskDriveRecord: MutablePersistableRecord {
  mutating func didInsert(_ inserted: InsertionSuccess) {
    self.rowID = inserted.rowID
  }
}

extension DiskDriveRecord: TableRecord {
  static let databaseTableName = "disk_drives"
  static var databaseSelection: [any SQLSelectable] {
    Self.everyColumn
  }
}

//struct DiskImageDriveRecord {
//  var rowID: RowID?
//  let image: RowID?
//
//  init(rowID: RowID? = nil, image: RowID?) {
//    self.rowID = rowID
//    self.image = image
//  }
//}
//
//extension DiskImageDriveRecord: Equatable, FetchableRecord {}
//
//extension DiskImageDriveRecord: Codable {
//  enum CodingKeys: String, CodingKey {
//    case rowID = "rowid",
//         image
//  }
//
//  enum Columns {
//    static let image = Column(CodingKeys.image)
//  }
//}
//
//extension DiskImageDriveRecord: MutablePersistableRecord {
//  mutating func didInsert(_ inserted: InsertionSuccess) {
//    self.rowID = inserted.rowID
//  }
//}
//
//extension DiskImageDriveRecord: TableRecord {
//  static let databaseTableName = "disk_image_drives"
//  static var databaseSelection: [any SQLSelectable] {
//    Self.everyColumn
//  }
//}

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
        .column(DiskRecord.Columns.uuidv1.name, .blob)
        .notNull()
        .unique()
    }
  }

  migrator.registerMigration("v2") { db in
    let disksTemporaryTableName = "\(DiskRecord.databaseTableName)_v2"
    try db.create(table: disksTemporaryTableName) { table in
      table.primaryKey(Column.rowID.name, .integer)
      table
        .column(DiskRecord.Columns.id.name, .blob)
        .notNull()
        .unique()

      table
        .column(DiskRecord.Columns.volumeID.name, .blob)
        .unique()
    }

    try db.execute(
      literal: """
      INSERT INTO \(identifier: disksTemporaryTableName) \
      (\(Column.rowID), \(DiskRecord.Columns.id), \(DiskRecord.Columns.volumeID)) \
      SELECT \(Column.rowID), \(DiskRecord.Columns.id), \(DiskRecord.Columns.uuidv1) FROM \(DiskRecord.self)  
      """,
    )

    try db.drop(table: DiskRecord.databaseTableName)
    try db.rename(table: disksTemporaryTableName, to: DiskRecord.databaseTableName)
    try db.create(table: DiskDriveRecord.databaseTableName) { table in
      table.primaryKey(Column.rowID.name, .integer)
      table
        .column(DiskDriveRecord.Columns.serial.name, .text)
        .notNull()
        .unique()

      table.column(DiskDriveRecord.Columns.name.name, .text)
    }

//    try db.create(table: DiskDiskDriveRecord.databaseTableName) { table in
//      table.primaryKey(Column.rowID.name, .integer)
//      table
//        .column(DiskDiskDriveRecord.Columns.drive.name, .integer)
//        .notNull()
//        .references(DiskDriveRecord.databaseTableName)
//        .indexed()
//
//      table
//        .column(DiskDiskDriveRecord.Columns.disk.name, .integer)
//        .notNull()
//        .unique()
//        .references(DiskDiskDriveRecord.databaseTableName)
//    }
//
//    try db.create(table: DiskImageDriveRecord.databaseTableName) { table in
//      table.primaryKey(Column.rowID.name, .integer)
//      table
//        .column(DiskImageDriveRecord.Columns.image.name, .integer)
//        .notNull()
//        .unique()
//        .references(DiskImageRecord.databaseTableName)
//
//      table.column(DiskDriveRecord.Columns.name.name, .text)
//    }
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
