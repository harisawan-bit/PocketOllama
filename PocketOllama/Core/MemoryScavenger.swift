import Foundation
import Metal
import Darwin

public final class MemoryScavenger: @unchecked Sendable {
    public static let shared = MemoryScavenger()

    private init() {}

    /// Real memory pressure, straight from the kernel. The deployment target is
    /// 16.4, so the old pre-iOS-13 host_statistics64 fallback was unreachable.
    public func getAvailableMemoryBytes() -> UInt64 {
        UInt64(os_proc_available_memory())
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
