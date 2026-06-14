import Foundation
import Compression

/// Decompresses gzip (RFC 1952) data.
///
/// itv.live serves `epgfull.xml.gz` as a raw file body with no
/// `Content-Encoding` header, so URLSession won't decompress it and Foundation's
/// `Data(.zlib)` won't strip the gzip wrapper. We parse the gzip framing
/// ourselves and inflate the raw DEFLATE payload via the Compression framework
/// (`COMPRESSION_ZLIB` decodes raw DEFLATE). No external dependency.
public enum Gunzip {
    public enum GunzipError: Error, Equatable { case notGzip, truncated, inflateFailed }

    public static func inflate(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 0x08 else {
            throw GunzipError.notGzip
        }
        let flg = bytes[3]
        var idx = 10 // fixed header

        if flg & 0x04 != 0 { // FEXTRA
            guard idx + 2 <= bytes.count else { throw GunzipError.truncated }
            let xlen = Int(bytes[idx]) | (Int(bytes[idx + 1]) << 8)
            idx += 2 + xlen
        }
        if flg & 0x08 != 0 { idx = skipCString(bytes, from: idx) } // FNAME
        if flg & 0x10 != 0 { idx = skipCString(bytes, from: idx) } // FCOMMENT
        if flg & 0x02 != 0 { idx += 2 }                            // FHCRC

        guard idx <= bytes.count - 8 else { throw GunzipError.truncated }
        let deflate = data.subdata(in: idx..<(data.count - 8))
        return try inflateRawDeflate(deflate)
    }

    private static func skipCString(_ bytes: [UInt8], from start: Int) -> Int {
        var i = start
        while i < bytes.count, bytes[i] != 0 { i += 1 }
        return i + 1
    }

    private static func inflateRawDeflate(_ input: Data) throws -> Data {
        let bufferSize = 64 * 1024
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { dst.deallocate() }

        // Placeholder pointers; compression_stream_init only sets `state`, and we
        // assign real src/dst pointers below before each process call.
        var stream = compression_stream(dst_ptr: dst, dst_size: bufferSize,
                                        src_ptr: UnsafePointer(dst), src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw GunzipError.inflateFailed
        }
        defer { compression_stream_destroy(&stream) }

        var output = Data()
        var thrownError: Error?

        input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else {
                thrownError = GunzipError.inflateFailed
                return
            }
            stream.src_ptr = base
            stream.src_size = raw.count
            let flags = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
            var status = COMPRESSION_STATUS_OK
            repeat {
                stream.dst_ptr = dst
                stream.dst_size = bufferSize
                status = compression_stream_process(&stream, flags)
                switch status {
                case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                    let produced = bufferSize - stream.dst_size
                    if produced > 0 { output.append(dst, count: produced) }
                default:
                    thrownError = GunzipError.inflateFailed
                    return
                }
            } while status == COMPRESSION_STATUS_OK
        }

        if let thrownError { throw thrownError }
        return output
    }
}
