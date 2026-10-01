import Darwin
import Foundation

final class MappedFile: @unchecked Sendable {
    let bytes: UnsafeRawBufferPointer

    init(url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }

        var information = stat()
        guard fstat(descriptor, &information) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        guard information.st_size > 0,
              let size = Int(exactly: information.st_size) else {
            throw LexiconIndexError.invalidFormat
        }

        let pointer = mmap(nil, size, PROT_READ, MAP_PRIVATE, descriptor, 0)
        guard pointer != MAP_FAILED, let pointer else {
            throw POSIXError(.init(rawValue: errno) ?? .ENOMEM)
        }
        bytes = UnsafeRawBufferPointer(start: UnsafeRawPointer(pointer), count: size)
    }

    deinit {
        if let baseAddress = bytes.baseAddress {
            munmap(UnsafeMutableRawPointer(mutating: baseAddress), bytes.count)
        }
    }
}
