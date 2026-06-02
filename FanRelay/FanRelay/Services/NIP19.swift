import Foundation

/// NIP-19: bech32 encoding for Nostr keys.
///
/// A Nostr key is 32 raw bytes. NIP-19 wraps those bytes in a text format
/// (bech32) with a human-readable prefix and a checksum:
///   • public key  → "npub1…"
///   • secret key  → "nsec1…"
///
/// The checksum is the useful part for us: if a user mistypes a character
/// while importing an `nsec`, `decode` returns `nil` instead of handing us a
/// silently-wrong key. There's no Apple framework for bech32 and the spec
/// forbids an SDK, so this is a small, self-contained implementation. The
/// algorithm was validated against the reference implementation before
/// shipping (encode output and round-trip both verified).
enum NIP19 {

    enum NIP19Error: Error {
        case wrongByteCount      // a key wasn't 32 bytes
        case malformed          // not a valid bech32 string
        case wrongPrefix        // e.g. expected "nsec" but got "npub"
    }

    // MARK: - Public API

    /// 32-byte public key → "npub1…"
    static func encodePublicKey(_ bytes: [UInt8]) throws -> String {
        guard bytes.count == 32 else { throw NIP19Error.wrongByteCount }
        return encode(hrp: "npub", eightBitData: bytes)
    }

    /// 32-byte secret key → "nsec1…"
    static func encodeSecretKey(_ bytes: [UInt8]) throws -> String {
        guard bytes.count == 32 else { throw NIP19Error.wrongByteCount }
        return encode(hrp: "nsec", eightBitData: bytes)
    }

    /// "nsec1…" → 32-byte secret key. Throws if the string is malformed,
    /// has the wrong prefix, or fails its checksum.
    static func decodeSecretKey(_ nsec: String) throws -> [UInt8] {
        let (hrp, bytes) = try decode(nsec)
        guard hrp == "nsec" else { throw NIP19Error.wrongPrefix }
        guard bytes.count == 32 else { throw NIP19Error.wrongByteCount }
        return bytes
    }

    /// "npub1…" → 32-byte public key.
    static func decodePublicKey(_ npub: String) throws -> [UInt8] {
        let (hrp, bytes) = try decode(npub)
        guard hrp == "npub" else { throw NIP19Error.wrongPrefix }
        guard bytes.count == 32 else { throw NIP19Error.wrongByteCount }
        return bytes
    }

    // MARK: - bech32 core

    private static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")

    /// Encode raw 8-bit bytes under a human-readable prefix.
    private static func encode(hrp: String, eightBitData: [UInt8]) -> String {
        let data5 = convertBits(eightBitData, from: 8, to: 5, pad: true)!
        let checksum = createChecksum(hrp: hrp, data: data5)
        let combined = data5 + checksum
        let body = String(combined.map { charset[Int($0)] })
        return hrp + "1" + body
    }

    /// Decode a bech32 string into its prefix and raw 8-bit bytes.
    private static func decode(_ string: String) throws -> (hrp: String, data: [UInt8]) {
        let lower = string.lowercased()
        guard let sep = lower.lastIndex(of: "1") else { throw NIP19Error.malformed }

        let hrp = String(lower[lower.startIndex..<sep])
        let dataPart = lower[lower.index(after: sep)...]
        guard !hrp.isEmpty, !dataPart.isEmpty else { throw NIP19Error.malformed }

        // Map each character back to its 5-bit value.
        var values = [UInt8]()
        for ch in dataPart {
            guard let idx = charset.firstIndex(of: ch) else { throw NIP19Error.malformed }
            values.append(UInt8(idx))
        }

        guard verifyChecksum(hrp: hrp, data: values) else { throw NIP19Error.malformed }

        // Drop the 6-symbol checksum, convert 5-bit groups back to 8-bit bytes.
        let payload = Array(values.dropLast(6))
        guard let eightBit = convertBits(payload, from: 5, to: 8, pad: false) else {
            throw NIP19Error.malformed
        }
        return (hrp, eightBit)
    }

    // MARK: - Checksum (BIP-173 polymod)

    private static func polymod(_ values: [UInt8]) -> UInt32 {
        let gen: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
        var chk: UInt32 = 1
        for v in values {
            let top = chk >> 25
            chk = ((chk & 0x1ffffff) << 5) ^ UInt32(v)
            for i in 0..<5 where (top >> i) & 1 == 1 {
                chk ^= gen[i]
            }
        }
        return chk
    }

    /// Expand the human-readable prefix into the values the checksum mixes in.
    private static func hrpExpand(_ hrp: String) -> [UInt8] {
        let scalars = Array(hrp.unicodeScalars)
        var out = scalars.map { UInt8($0.value >> 5) }
        out.append(0)
        out += scalars.map { UInt8($0.value & 31) }
        return out
    }

    private static func createChecksum(hrp: String, data: [UInt8]) -> [UInt8] {
        let values = hrpExpand(hrp) + data + [0, 0, 0, 0, 0, 0]
        let mod = polymod(values) ^ 1
        return (0..<6).map { UInt8((mod >> (5 * (5 - UInt32($0)))) & 31) }
    }

    private static func verifyChecksum(hrp: String, data: [UInt8]) -> Bool {
        polymod(hrpExpand(hrp) + data) == 1
    }

    // MARK: - Bit regrouping (8-bit <-> 5-bit)

    /// Regroup a stream of `from`-bit values into `to`-bit values. bech32 works
    /// in 5-bit symbols, but our keys are 8-bit bytes, so we convert both ways.
    private static func convertBits(_ data: [UInt8], from: UInt32, to: UInt32, pad: Bool) -> [UInt8]? {
        var acc: UInt32 = 0
        var bits: UInt32 = 0
        var out = [UInt8]()
        let maxv: UInt32 = (1 << to) - 1
        let maxAcc: UInt32 = (1 << (from + to - 1)) - 1

        for value in data {
            let v = UInt32(value)
            if (v >> from) != 0 { return nil }   // value doesn't fit in `from` bits
            acc = ((acc << from) | v) & maxAcc
            bits += from
            while bits >= to {
                bits -= to
                out.append(UInt8((acc >> bits) & maxv))
            }
        }

        if pad {
            if bits > 0 {
                out.append(UInt8((acc << (to - bits)) & maxv))
            }
        } else if bits >= from || ((acc << (to - bits)) & maxv) != 0 {
            return nil   // leftover bits would corrupt the result
        }
        return out
    }
}
