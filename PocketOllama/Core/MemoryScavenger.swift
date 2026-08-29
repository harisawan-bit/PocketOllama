import Foundation
import MachO
import Metal
import Darwin

public final class MemoryScavenger: @unchecked Sendable {
    public static let shared = MemoryScavenger()

    private init() {}

    public func getAvailableMemoryBytes() -> UInt64 {
        if #available(iOS 13.0, *) {
            return os_proc_available_memory()
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

    @discardableResult
    public func purgeAndScavengeRAM() -> UInt64 {
        let before = getAvailableMemoryBytes()
        URLCache.shared.removeAllCachedResponses()
        malloc_zone_pressure_relief(malloc_default_zone(), 0)
        autoreleasepool {}
        let after = getAvailableMemoryBytes()
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
