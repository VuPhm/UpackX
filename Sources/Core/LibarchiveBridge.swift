import Foundation

// MARK: - Libarchive Low-level C Bridge

public typealias ArchivePtr = OpaquePointer
public typealias ArchiveEntryPtr = OpaquePointer

public let ARCHIVE_OK: Int32 = 0
public let ARCHIVE_EOF: Int32 = 1
public let ARCHIVE_RETRY: Int32 = -10
public let ARCHIVE_WARN: Int32 = -20
public let ARCHIVE_FAILED: Int32 = -25
public let ARCHIVE_FATAL: Int32 = -30

public let AE_IFMT: UInt16 = 0o170000
public let AE_IFREG: UInt16 = 0o100000
public let AE_IFLNK: UInt16 = 0o120000
public let AE_IFDIR: UInt16 = 0o040000

@_silgen_name("archive_read_new")
public func archive_read_new() -> ArchivePtr?

@_silgen_name("archive_read_support_filter_all")
public func archive_read_support_filter_all(_ a: ArchivePtr) -> Int32

@_silgen_name("archive_read_support_format_all")
public func archive_read_support_format_all(_ a: ArchivePtr) -> Int32

@_silgen_name("archive_read_open_filename")
public func archive_read_open_filename(_ a: ArchivePtr, _ filename: UnsafePointer<CChar>, _ blockSize: Int) -> Int32

@_silgen_name("archive_read_next_header")
public func archive_read_next_header(_ a: ArchivePtr, _ entry: UnsafeMutablePointer<ArchiveEntryPtr?>) -> Int32

@_silgen_name("archive_read_data_block")
public func archive_read_data_block(_ a: ArchivePtr, _ buff: UnsafeMutablePointer<UnsafeRawPointer?>, _ size: UnsafeMutablePointer<Int>, _ offset: UnsafeMutablePointer<Int64>) -> Int32

@_silgen_name("archive_read_has_encrypted_entries")
public func archive_read_has_encrypted_entries(_ a: ArchivePtr) -> Int32

@_silgen_name("archive_read_add_passphrase")
public func archive_read_add_passphrase(_ a: ArchivePtr, _ passphrase: UnsafePointer<CChar>) -> Int32

@_silgen_name("archive_read_close")
public func archive_read_close(_ a: ArchivePtr) -> Int32

@_silgen_name("archive_read_free")
public func archive_read_free(_ a: ArchivePtr) -> Int32

@_silgen_name("archive_error_string")
public func archive_error_string(_ a: ArchivePtr) -> UnsafePointer<CChar>?

@_silgen_name("archive_errno")
public func archive_errno(_ a: ArchivePtr) -> Int32

@_silgen_name("archive_entry_pathname")
public func archive_entry_pathname(_ entry: ArchiveEntryPtr) -> UnsafePointer<CChar>?

@_silgen_name("archive_entry_pathname_utf8")
public func archive_entry_pathname_utf8(_ entry: ArchiveEntryPtr) -> UnsafePointer<CChar>?

@_silgen_name("archive_entry_size")
public func archive_entry_size(_ entry: ArchiveEntryPtr) -> Int64

@_silgen_name("archive_entry_filetype")
public func archive_entry_filetype(_ entry: ArchiveEntryPtr) -> UInt16

@_silgen_name("archive_entry_mode")
public func archive_entry_mode(_ entry: ArchiveEntryPtr) -> UInt16

@_silgen_name("archive_entry_mtime")
public func archive_entry_mtime(_ entry: ArchiveEntryPtr) -> Int

@_silgen_name("archive_entry_is_encrypted")
public func archive_entry_is_encrypted(_ entry: ArchiveEntryPtr) -> Int32

@_silgen_name("archive_entry_symlink")
public func archive_entry_symlink(_ entry: ArchiveEntryPtr) -> UnsafePointer<CChar>?

// MARK: - Libarchive Write API

@_silgen_name("archive_write_new")
public func archive_write_new() -> ArchivePtr?

@_silgen_name("archive_write_set_format_zip")
public func archive_write_set_format_zip(_ a: ArchivePtr) -> Int32

@_silgen_name("archive_write_set_options")
public func archive_write_set_options(_ a: ArchivePtr, _ opts: UnsafePointer<CChar>) -> Int32

@_silgen_name("archive_write_open_filename")
public func archive_write_open_filename(_ a: ArchivePtr, _ filename: UnsafePointer<CChar>) -> Int32

@_silgen_name("archive_write_header")
public func archive_write_header(_ a: ArchivePtr, _ entry: ArchiveEntryPtr) -> Int32

@_silgen_name("archive_write_data")
public func archive_write_data(_ a: ArchivePtr, _ buff: UnsafeRawPointer, _ size: Int) -> Int

@_silgen_name("archive_write_close")
public func archive_write_close(_ a: ArchivePtr) -> Int32

@_silgen_name("archive_write_free")
public func archive_write_free(_ a: ArchivePtr) -> Int32

// MARK: - Archive Entry Setters

@_silgen_name("archive_entry_new")
public func archive_entry_new() -> ArchiveEntryPtr?

@_silgen_name("archive_entry_free")
public func archive_entry_free(_ entry: ArchiveEntryPtr)

@_silgen_name("archive_entry_set_pathname")
public func archive_entry_set_pathname(_ entry: ArchiveEntryPtr, _ path: UnsafePointer<CChar>)

@_silgen_name("archive_entry_set_pathname_utf8")
public func archive_entry_set_pathname_utf8(_ entry: ArchiveEntryPtr, _ path: UnsafePointer<CChar>)

@_silgen_name("archive_entry_set_size")
public func archive_entry_set_size(_ entry: ArchiveEntryPtr, _ size: Int64)

@_silgen_name("archive_entry_set_filetype")
public func archive_entry_set_filetype(_ entry: ArchiveEntryPtr, _ type: UInt16)

@_silgen_name("archive_entry_set_perm")
public func archive_entry_set_perm(_ entry: ArchiveEntryPtr, _ mode: UInt16)

@_silgen_name("archive_entry_set_mtime")
public func archive_entry_set_mtime(_ entry: ArchiveEntryPtr, _ mtime: Int, _ ns: Int)

@_silgen_name("archive_entry_set_symlink")
public func archive_entry_set_symlink(_ entry: ArchiveEntryPtr, _ link: UnsafePointer<CChar>)

