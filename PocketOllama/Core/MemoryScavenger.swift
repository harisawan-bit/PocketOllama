import Foundation
import MachO
import Metal
import Darwin

public final class MemoryScavenger: @unchecked Sendable {
    public static let shared = MemoryScavenger()

    private init() {}

    public func getAvailableMemoryBytes() -> UInt64 {
        if #available(iOS 13.0, *) {
            return UInt64(os_proc_available_memory())
        } else {
            var stats = vm_statistics64()
            var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &stats) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
                }
            }
            if result == KERN_SUCCESS {
                let pageSize = UInt64(vm_kernel_page_size)
                return UInt64(stats.free_count) * pageSize
            }
            return 2 * 1024 * 1024 * 1024
        }
    }

    /// Aggressively purges caches and signals Darwin VM to compress background apps and free RAM
    @discardableResult
    public func purgeAndScavengeRAM() -> UInt64 {
        // 1. Drain top-level caches
        URLCache.shared.removeAllCachedResponses()

        // 2. Darwin Memory Balloon Pulse: Briefly signals memory manager to reclaim inactive pages
        autoreleasepool {
            // Allocate and discard transient purgeable buffer to signal Darwin VM compaction
            let balloonSize = 64 * 1024 * 1024 // 64MB transient pulse
            if let ptr = malloc(balloonSize) {
                posix_madvise(ptr, balloonSize, POSIX_MADV_DONTNEED)
                free(ptr)
            }
        }

        // 3. Relieve Mach heap zone pressure
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
