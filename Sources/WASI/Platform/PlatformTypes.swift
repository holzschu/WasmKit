import SystemPackage
import Foundation
import WasmTypes

extension WASIAbi.FileType {
    init(platformFileType: FileDescriptor.FileType) {
        switch platformFileType {
        case .directory: self = .DIRECTORY
        case .symlink: self = .SYMBOLIC_LINK
        case .regular: self = .REGULAR_FILE
        case .characterDevice: self = .CHARACTER_DEVICE
        case .blockDevice: self = .BLOCK_DEVICE
        case .socket: self = .SOCKET_STREAM
        case .unknown: self = .UNKNOWN
        }
    }
}

extension WASIAbi.Fdflags {
    init(platformOpenOptions: FileDescriptor.OpenOptions) {
        var fdFlags: WASIAbi.Fdflags = []
        if platformOpenOptions.contains(.append) { fdFlags.insert(.APPEND) }
        if platformOpenOptions.contains(.nonBlocking) { fdFlags.insert(.NONBLOCK) }
        if platformOpenOptions.contains(.dataSync) { fdFlags.insert(.DSYNC) }
        if platformOpenOptions.contains(.fileSync) { fdFlags.insert(.SYNC) }
        if platformOpenOptions.contains(.readSync) { fdFlags.insert(.RSYNC) }
        self = fdFlags
    }

    var platformOpenOptions: FileDescriptor.OpenOptions {
        var flags: FileDescriptor.OpenOptions = []
        if self.contains(.APPEND) { flags.insert(.append) }
        if self.contains(.NONBLOCK) { flags.insert(.nonBlocking) }
        if self.contains(.DSYNC) { flags.insert(.dataSync) }
        if self.contains(.SYNC) { flags.insert(.fileSync) }
        if self.contains(.RSYNC) { flags.insert(.readSync) }
        return flags
    }
}

extension WASIAbi.Timestamp {
    static func platformTimeSpec(
        atim: WASIAbi.Timestamp,
        mtim: WASIAbi.Timestamp,
        fstFlags: WASIAbi.FstFlags
    ) throws -> (access: FileTime, modification: FileTime) {
        return try (
            atim.platformTimeSpec(
                set: fstFlags.contains(.ATIM), now: fstFlags.contains(.ATIM_NOW)
            ),
            mtim.platformTimeSpec(
                set: fstFlags.contains(.MTIM), now: fstFlags.contains(.MTIM_NOW)
            )
        )
    }

    func platformTimeSpec(set: Bool, now: Bool) throws -> FileTime {
        switch (set, now) {
        case (true, true):
            throw WASIAbi.Errno.EINVAL
        case (true, false):
            return FileTime(
                seconds: Int(self / 1_000_000_000),
                nanoseconds: Int(self % 1_000_000_000)
            )
        case (false, true): return .now
        case (false, false): return .omit
        }
    }
}

extension WASIAbi.Filestat {
    init(stat: FileDescriptor.Attributes) {
        self = WASIAbi.Filestat(
            dev: WASIAbi.Device(stat.device),
            ino: WASIAbi.Inode(stat.inode),
            filetype: WASIAbi.FileType(platformFileType: stat.fileType),
            nlink: WASIAbi.LinkCount(stat.linkCount),
            size: WASIAbi.FileSize(stat.size),
            atim: WASIAbi.Timestamp(platformTimeSpec: stat.accessTime),
            mtim: WASIAbi.Timestamp(platformTimeSpec: stat.modificationTime),
            ctim: WASIAbi.Timestamp(platformTimeSpec: stat.creationTime)
        )
    }
}

extension WASIAbi.Timestamp {

    fileprivate init(seconds: UInt64, nanoseconds: UInt64) {
        self = nanoseconds + seconds * 1_000_000_000
    }

    init(platformTimeSpec timespec: FileTime) {
        // Clamp negative (pre-1970) times to 0 instead of trapping: WASI
        // timestamps are unsigned, and platforms can legitimately report
        // such values (e.g. zero-initialized FILETIME fields on Windows).
        self.init(
            seconds: UInt64(Swift.max(0, timespec.seconds)),
            nanoseconds: UInt64(Swift.max(0, timespec.nanoseconds)))
    }

    init(wallClockDuration duration: WallClock.Duration) {
        self.init(seconds: duration.seconds, nanoseconds: UInt64(duration.nanoseconds))
    }
}

extension WASIAbi.Errno {

    /// Looks through a cleanup failure so a failing close still reports the operation's own errno
    /// instead of trapping the guest.
    static func reportable(for error: any Error) -> WASIAbi.Errno? {
        switch error {
        case let errno as WASIAbi.Errno: return errno
        case let failure as CleanupFailure: return reportable(for: failure.underlying)
        default: return nil
        }
    }
    
    init(platformErrno: CInt) throws {
        try self.init(platformErrno: SystemPackage.Errno(rawValue: platformErrno))
    }

    init(platformErrno: Errno) throws {
        guard let error = WASIAbi.Errno(_platformErrno: platformErrno) else {
            throw WASIError(description: "Unknown underlying OS error: \(platformErrno)")
        }
        self = error
    }

    private init?(_platformErrno: SystemPackage.Errno) {
        switch _platformErrno {
        case .permissionDenied: self = .EPERM
        case .notPermitted: self = .EPERM
        case .noSuchFileOrDirectory: self = .ENOENT
        case .noSuchProcess: self = .ESRCH
        case .interrupted: self = .EINTR
        case .ioError: self = .EIO
        case .noSuchAddressOrDevice: self = .ENXIO
        case .argListTooLong: self = .E2BIG
        case .execFormatError: self = .ENOEXEC
        case .badFileDescriptor: self = .EBADF
        case .noChildProcess: self = .ECHILD
        case .deadlock: self = .EDEADLK
        case .noMemory: self = .ENOMEM
        case .permissionDenied: self = .EACCES
        case .badAddress: self = .EFAULT
        case .resourceBusy: self = .EBUSY
        case .fileExists: self = .EEXIST
        case .improperLink: self = .EXDEV
        case .operationNotSupportedByDevice: self = .ENODEV
        case .notDirectory: self = .ENOTDIR
        case .isDirectory: self = .EISDIR
        case .invalidArgument: self = .EINVAL
        case .tooManyOpenFilesInSystem: self = .ENFILE
        case .tooManyOpenFiles: self = .EMFILE
        #if !os(Windows)
            case .inappropriateIOCTLForDevice: self = .ENOTTY
            case .textFileBusy: self = .ETXTBSY
        #endif
        case .fileTooLarge: self = .EFBIG
        case .noSpace: self = .ENOSPC
        case .illegalSeek: self = .ESPIPE
        case .readOnlyFileSystem: self = .EROFS
        case .tooManyLinks: self = .EMLINK
        case .brokenPipe: self = .EPIPE
        case .outOfDomain: self = .EDOM
        case .outOfRange: self = .ERANGE
        case .resourceTemporarilyUnavailable: self = .EAGAIN
        case .nowInProgress: self = .EINPROGRESS
        case .alreadyInProcess: self = .EALREADY
        case .notSocket: self = .ENOTSOCK
        case .addressRequired: self = .EDESTADDRREQ
        case .messageTooLong: self = .EMSGSIZE
        case .protocolWrongTypeForSocket: self = .EPROTOTYPE
        case .protocolNotAvailable: self = .ENOPROTOOPT
        case .protocolNotSupported: self = .EPROTONOSUPPORT
        case .notSupported: self = .ENOTSUP
        case .addressFamilyNotSupported: self = .EAFNOSUPPORT
        case .addressInUse: self = .EADDRINUSE
        case .addressNotAvailable: self = .EADDRNOTAVAIL
        case .networkDown: self = .ENETDOWN
        case .networkUnreachable: self = .ENETUNREACH
        case .networkReset: self = .ENETRESET
        case .connectionAbort: self = .ECONNABORTED
        case .connectionReset: self = .ECONNRESET
        case .noBufferSpace: self = .ENOBUFS
        case .socketIsConnected: self = .EISCONN
        case .socketNotConnected: self = .ENOTCONN
        case .timedOut: self = .ETIMEDOUT
        case .connectionRefused: self = .ECONNREFUSED
        case .tooManySymbolicLinkLevels: self = .ELOOP
        case .fileNameTooLong: self = .ENAMETOOLONG
        case .noRouteToHost: self = .EHOSTUNREACH
        case .directoryNotEmpty: self = .ENOTEMPTY
        case .diskQuotaExceeded: self = .EDQUOT
        case .staleNFSFileHandle: self = .ESTALE
        case .noLocks: self = .ENOLCK
        case .noFunction: self = .ENOSYS
        #if !os(Windows)
            case .overflow: self = .EOVERFLOW
        #endif
        case .canceled: self = .ECANCELED
        #if !os(Windows)
            case .identifierRemoved: self = .EIDRM
            case .noMessage: self = .ENOMSG
        #endif
        case .illegalByteSequence: self = .EILSEQ
        #if !os(Windows)
            case .badMessage: self = .EBADMSG
            case .multiHop: self = .EMULTIHOP
            case .noLink: self = .ENOLINK
            case .protocolError: self = .EPROTO
            case .notRecoverable: self = .ENOTRECOVERABLE
            case .previousOwnerDied: self = .EOWNERDEAD
        #endif
        default: return nil
        }
    }

    
    func description() -> String {
        switch (self) {
        case .SUCCESS:
            return "No error occurred. System call completed successfully."
        case .E2BIG:
            return "Argument list too long."
        case .EACCES:
            return "Permission denied."
        case .EADDRINUSE:
            return "Address in use."
        case .EADDRNOTAVAIL:
            return "Address not available."
        case .EAFNOSUPPORT:
            return "Address family not supported."
        case .EAGAIN:
            return "Resource unavailable, or operation would block."
        case .EALREADY:
            return "Connection already in progress."
        case .EBADF:
            return "Bad file descriptor."
        case .EBADMSG:
            return "Bad message."
        case .EBUSY:
            return "Device or resource busy."
        case .ECANCELED:
            return "Operation canceled."
        case .ECHILD:
            return "No child processes."
        case .ECONNABORTED:
            return "Connection aborted."
        case .ECONNREFUSED:
            return "Connection refused."
        case .ECONNRESET:
            return "Connection reset."
        case .EDEADLK:
            return "Resource deadlock would occur."
        case .EDESTADDRREQ:
            return "Destination address required."
        case .EDOM:
            return "Mathematics argument out of domain of function."
        case .EDQUOT:
            return "Reserved (EDQUOT)."
        case .EEXIST:
            return "File exists."
        case .EFAULT:
            return "Bad address."
        case .EFBIG:
            return "File too large."
        case .EHOSTUNREACH:
            return "Host is unreachable."
        case .EIDRM:
            return "Identifier removed."
        case .EILSEQ:
            return "Illegal byte sequence."
        case .EINPROGRESS:
            return "Operation in progress."
        case .EINTR:
            return "Interrupted function."
        case .EINVAL:
            return "Invalid argument."
        case .EIO:
            return "I/O error."
        case .EISCONN:
            return "Socket is connected."
        case .EISDIR:
            return "Is a directory."
        case .ELOOP:
            return "Too many levels of symbolic links."
        case .EMFILE:
            return "File descriptor value too large."
        case .EMLINK:
            return "Too many links."
        case .EMSGSIZE:
            return "Message too large."
        case .EMULTIHOP:
            return "Reserved (EMULTIHOP)."
        case .ENAMETOOLONG:
            return "Filename too long."
        case .ENETDOWN:
            return "Network is down."
        case .ENETRESET:
            return "Connection aborted by network."
        case .ENETUNREACH:
            return "Network unreachable."
        case .ENFILE:
            return "Too many files open in system."
        case .ENOBUFS:
            return "No buffer space available."
        case .ENODEV:
            return "No such device."
        case .ENOENT:
            return "No such file or directory."
        case .ENOEXEC:
            return "Executable file format error."
        case .ENOLCK:
            return "No locks available."
        case .ENOLINK:
            return "Reserved (ENOLINK)."
        case .ENOMEM:
            return "Not enough space."
        case .ENOMSG:
            return "No message of the desired type."
        case .ENOPROTOOPT:
            return "Protocol not available."
        case .ENOSPC:
            return "No space left on device."
        case .ENOSYS:
            return "Function not supported."
        case .ENOTCONN:
            return "The socket is not connected."
        case .ENOTDIR:
            return "Not a directory or a symbolic link to a directory."
        case .ENOTEMPTY:
            return "Directory not empty."
        case .ENOTRECOVERABLE:
            return "State not recoverable."
        case .ENOTSOCK:
            return "Not a socket."
        case .ENOTSUP:
            return "Not supported, or operation not supported on socket."
        case .ENOTTY:
            return "Inappropriate I/O control operation."
        case .ENXIO:
            return "No such device or address."
        case .EOVERFLOW:
            return "Value too large to be stored in data type."
        case .EOWNERDEAD:
            return "Previous owner died."
        case .EPERM:
            return "Operation not permitted."
        case .EPIPE:
            return "Broken pipe."
        case .EPROTO:
            return "Protocol error."
        case .EPROTONOSUPPORT:
            return "Protocol not supported."
        case .EPROTOTYPE:
            return "Protocol wrong type for socket."
        case .ERANGE:
            return "Result too large."
        case .EROFS:
            return "Read-only file system."
        case .ESPIPE:
            return "Invalid seek."
        case .ESRCH:
            return "No such process."
        case .ESTALE:
            return "Reserved (ESTALE)."
        case .ETIMEDOUT:
            return "Connection timed out."
        case .ETXTBSY:
            return "Text file busy."
        case .EXDEV:
            return "Cross-device link."
        case .ENOTCAPABLE:
            return "Extension: Capabilities insufficient."
        default:
            return "unknown Error: \(self.rawValue)"
        }
        return "localized Description"
    }
}
