import Foundation
import Metal
import Darwin

public final class MemoryScavenger: @unchecked Sendable {
    public static let shared = MemoryScavenger()

    private init() {}

    /// Memory available to this process, straight from the kernel.
    ///
    /// Apple documents that this returns 0 when the process is not an app or has
    /// already passed its memory limit. Treating that 0 as a measurement made the
    /// post-load check compare a loaded multi-gigabyte model against zero bytes,
    /// so every load was freed again and reported as "not enough free memory" on
    /// an idle phone.
    ///
    /// Callers must therefore use `availableMemoryOrNil` when a zero means
    /// "unknown". This remains available for display and for relative comparisons,
    /// where the 0-returns-0 behaviour is harmless.
    public func getAvailableMemoryBytes() -> UInt64 {
        UInt64(os_proc_available_memory())
    }

    /// nil when the kernel reports 0, which means "cannot determine", never
    /// "nothing is free". Use this for any decision that blocks the user.
    public func availableMemoryOrNil() -> UInt64? {
        let value = getAvailableMemoryBytes()
        return value > 0 ? value : nil
    }

    /// Drops this process's own reclaimable memory: URL cache, then allocator
    /// free-list pages.
    ///
    /// - Parameter aggressive: also relieves the malloc zone. The Engine
    ///   Configuration toggle maps here.
    ///
    /// It cannot free memory held by other apps, and it cannot make the OS
    /// suspend anything. The previous wording overstated what this can do.
    @discardableResult
    public func purgeAndScavengeRAM(aggressive: Bool = true) -> UInt64 {
        // 1. Drain top-level caches
        URLCache.shared.removeAllCachedResponses()

        guard aggressive else { return getAvailableMemoryBytes() }

        // 2. Relieve allocator pressure. This is the call that actually does
        //    something: it makes the zone release free pages back to the system.
        //
        //    The removed "memory balloon" allocated 64 MB, madvised it away and
        //    freed it while claiming to signal Darwin compaction. That sequence
        //    reclaims nothing: a fresh anonymous block that is discarded straight
        //    away never leaves the allocator, and it spiked usage by 64 MB in a
        //    memory-critical path to do it.
        malloc_zone_pressure_relief(malloc_default_zone(), 0)

        let after = getAvailableMemoryBytes()
        print("[MemoryScavenger] Memory scavenged. Available unified RAM: \(after / (1024*1024)) MB")
        return after
    }

    public func lockMemoryRegion(pointer: UnsafeMutableRawPointer, size: Int) -> Bool {
        posix_madvise(pointer, size, POSIX_MADV_WILLNEED)
        let result = mlock(pointer, size)
        return result == 0
    }

    public func unlockMemoryRegion(pointer: UnsafeMutableRawPointer, size: Int) {
        munlock(pointer, size)
        posix_madvise(pointer, size, POSIX_MADV_DONTNEED)
    }
}
