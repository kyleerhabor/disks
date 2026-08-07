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

struct DiskRecord {
  var rowID: RowID?
  let id: UUID?
  let uuid: UUID?
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

struct Disk2Record {
  var rowID: RowID?

  // MARK: Media
  let mediaID: UUID?

  init(rowID: RowID? = nil, mediaID: UUID?) {
    self.rowID = rowID
    self.mediaID = mediaID
  }
}

extension Disk2Record: Equatable, FetchableRecord {}

extension Disk2Record: Codable {
  enum CodingKeys: String, CodingKey {
    case rowID = "rowid",
         mediaID = "media_id"
  }

  enum Columns {
    static let mediaID = Column(CodingKeys.mediaID)
  }
}

extension Disk2Record: MutablePersistableRecord {
  mutating func didInsert(_ inserted: InsertionSuccess) {
    self.rowID = inserted.rowID
  }
}

extension Disk2Record: TableRecord {
  static let databaseTableName = "disks2"
  static var databaseSelection: [any SQLSelectable] {
    Self.everyColumn
  }
}


struct DiskImageRecord {
  var rowID: RowID?
  let id: UUID?
  let uuid: UUID?
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

struct DiskImage2Record {
  var rowID: RowID?
  // This property shouldn't be used for identifying all disk images because it's only relevant to encrypted disk images,
  // and is only available while the disk image is not in use (via `hdiutil isencrypted`). A solution is to use URL
  // bookmarks, but that requires input from the user because the path from `hdiutil info` may not be up-to-date.
  let id: UUID?

  init(rowID: RowID? = nil, id: UUID?) {
    self.rowID = rowID
    self.id = id
  }
}

extension DiskImage2Record: Equatable, FetchableRecord {}

extension DiskImage2Record: Codable {
  enum CodingKeys: String, CodingKey {
    case rowID = "rowid",
         id
  }

  enum Columns {
    static let id = Column(CodingKeys.id)
  }
}

extension DiskImage2Record: MutablePersistableRecord {
  mutating func didInsert(_ inserted: InsertionSuccess) {
    self.rowID = inserted.rowID
  }
}

extension DiskImage2Record: TableRecord {
  static let databaseTableName = "disk_images2"
  static var databaseSelection: [any SQLSelectable] {
    Self.everyColumn
  }
}

struct DiskDriveRecord {
  var rowID: RowID?
  // This should probably be in its own table, but I can't be asked to move around the code.
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

struct DiskImageDriveRecord {
  // TODO: Implement support for renaming disk images
  //
  // This will support read-only disk image files, like platform simulators from Xcode. DiskImageRecord's ID is from
  // `hdiutil info`, which is for encrypted disk images only. I'm inclined to use URL bookmarks for this.

  var rowID: RowID?
  let id: UUID?
  let image: RowID?
  let hasKeychainPassword: Bool?
}

extension DiskImageDriveRecord: Equatable, FetchableRecord {}

extension DiskImageDriveRecord: Codable {
  enum CodingKeys: String, CodingKey {
    case rowID = "rowid",
         id, image,
         hasKeychainPassword = "has_keychain_password"
  }

  enum Columns {
    static let id = Column(CodingKeys.id)
    static let image = Column(CodingKeys.image)
    static let hasKeychainPassword = Column(CodingKeys.hasKeychainPassword)
  }
}

extension DiskImageDriveRecord: MutablePersistableRecord {
  mutating func didInsert(_ inserted: InsertionSuccess) {
    self.rowID = inserted.rowID
  }
}

extension DiskImageDriveRecord: TableRecord {
  static let databaseTableName = "disk_image_drives"
  static var databaseSelection: [any SQLSelectable] {
    Self.everyColumn
  }

  static var image: BelongsToAssociation<Self, DiskImage2Record> {
    Self.belongsTo(DiskImage2Record.self, using: ForeignKey([Columns.image]))
  }
}

struct DriveDiskRecord {
  var rowID: RowID?
  let id: UUID?
  let disk: RowID?
  let hasKeychainPassword: Bool?

  init(rowID: RowID? = nil, id: UUID?, disk: RowID?, hasKeychainPassword: Bool?) {
    self.rowID = rowID
    self.id = id
    self.disk = disk
    self.hasKeychainPassword = hasKeychainPassword
  }
}

extension DriveDiskRecord: Equatable, FetchableRecord {}

extension DriveDiskRecord: Codable {
  enum CodingKeys: String, CodingKey {
    case rowID = "rowid",
         id, disk,
         hasKeychainPassword = "has_keychain_password"
  }

  enum Columns {
    static let id = Column(CodingKeys.id)
    static let disk = Column(CodingKeys.disk)
    static let hasKeychainPassword = Column(CodingKeys.hasKeychainPassword)
  }
}

extension DriveDiskRecord: MutablePersistableRecord {
  mutating func didInsert(_ inserted: InsertionSuccess) {
    self.rowID = inserted.rowID
  }
}

extension DriveDiskRecord: TableRecord {
  static let databaseTableName = "drive_disks"
  static var databaseSelection: [any SQLSelectable] {
    Self.everyColumn
  }

  static var disk: BelongsToAssociation<Self, Disk2Record> {
    Self.belongsTo(Disk2Record.self, using: ForeignKey([Columns.disk]))
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

  migrator.registerMigration("v2") { db in
    try db.create(table: Disk2Record.databaseTableName) { table in
      table.primaryKey(Column.rowID.name, .integer)
      table
        .column(Disk2Record.Columns.mediaID.name, .blob)
        .notNull()
        .unique()
    }

    try db.create(table: DriveDiskRecord.databaseTableName) { table in
      table.primaryKey(Column.rowID.name, .integer)
      table
        .column(DriveDiskRecord.Columns.id.name, .blob)
        .notNull()
        .unique()

      table
        .column(DriveDiskRecord.Columns.disk.name, .integer)
        .notNull()
        .unique()
        .references(Disk2Record.databaseTableName, onDelete: .cascade)

      table
        .column(DriveDiskRecord.Columns.hasKeychainPassword.name, .boolean)
        .notNull()
    }

    try db.create(table: DiskImage2Record.databaseTableName) { table in
      table.primaryKey(Column.rowID.name, .integer)
      table
        .column(DiskImage2Record.Columns.id.name, .blob)
        .notNull()
        .unique()
    }

    try db.create(table: DiskImageDriveRecord.databaseTableName) { table in
      table.primaryKey(Column.rowID.name, .integer)
      table
        .column(DiskImageDriveRecord.Columns.id.name, .blob)
        .notNull()
        .unique()

      table
        .column(DiskImageDriveRecord.Columns.image.name, .integer)
        .notNull()
        .unique()
        .references(DiskImage2Record.databaseTableName, onDelete: .cascade)

      table
        .column(DiskImageDriveRecord.Columns.hasKeychainPassword.name, .boolean)
        .notNull()
    }

    try db.create(table: DiskDriveRecord.databaseTableName) { table in
      table.primaryKey(Column.rowID.name, .integer)
      table
        .column(DiskDriveRecord.Columns.serial.name, .text)
        .notNull()
        .unique()

      table.column(DiskDriveRecord.Columns.name.name, .text)
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
