// EC wire format: tags and packets.
//
// Tag on the wire (plain mode, all numbers big-endian):
//   u16 (name << 1 | hasChildren), u8 type, u32 tagLen,
//   [u16 childCount + children...] , value bytes
// tagLen = valueLen + Σ per child (7-byte header + 2 bytes if that child
// has children + child's own tagLen, recursively).
//
// Packet: u32 flags, u32 payloadLen, then payload = u8 opcode, u16 tagCount, tags.

import Foundation

struct ECError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct ECTag {
    var name: UInt16
    var type: ECTagType
    var value: Data
    var children: [ECTag] = []

    init(name: UInt16, type: ECTagType, value: Data, children: [ECTag] = []) {
        self.name = name
        self.type = type
        self.value = value
        self.children = children
    }

    init(_ name: ECTagName, type: ECTagType, value: Data, children: [ECTag] = []) {
        self.init(name: name.rawValue, type: type, value: value, children: children)
    }

    // MARK: convenience constructors

    static func string(_ name: ECTagName, _ s: String) -> ECTag {
        var d = Data(s.utf8)
        d.append(0) // EC strings are NUL-terminated
        return ECTag(name, type: .string, value: d)
    }

    static func uint8(_ name: ECTagName, _ v: UInt8) -> ECTag {
        ECTag(name, type: .uint8, value: Data([v]))
    }

    static func uint16(_ name: ECTagName, _ v: UInt16) -> ECTag {
        var be = v.bigEndian
        return ECTag(name, type: .uint16, value: Data(bytes: &be, count: 2))
    }

    static func uint32(_ name: ECTagName, _ v: UInt32) -> ECTag {
        var be = v.bigEndian
        return ECTag(name, type: .uint32, value: Data(bytes: &be, count: 4))
    }

    static func uint64(_ name: ECTagName, _ v: UInt64) -> ECTag {
        var be = v.bigEndian
        return ECTag(name, type: .uint64, value: Data(bytes: &be, count: 8))
    }

    /// Smallest-width unsigned int, like aMule's CECTag(name, uint64) constructor.
    static func number(_ name: ECTagName, _ v: UInt64) -> ECTag {
        if v <= UInt64(UInt8.max) { return uint8(name, UInt8(v)) }
        if v <= UInt64(UInt16.max) { return uint16(name, UInt16(v)) }
        if v <= UInt64(UInt32.max) { return uint32(name, UInt32(v)) }
        return uint64(name, v)
    }

    static func hash16(_ name: ECTagName, _ hash: Data) -> ECTag {
        ECTag(name, type: .hash16, value: hash.prefix(16))
    }

    static func ipv4(_ name: ECTagName, ip: UInt32, port: UInt16) -> ECTag {
        var d = Data()
        var ipBE = ip.bigEndian
        var portBE = port.bigEndian
        d.append(Data(bytes: &ipBE, count: 4))
        d.append(Data(bytes: &portBE, count: 2))
        return ECTag(name, type: .ipv4, value: d)
    }

    static func empty(_ name: ECTagName) -> ECTag {
        ECTag(name, type: .custom, value: Data())
    }

    // MARK: value accessors

    var stringValue: String? {
        guard type == .string || type == .custom else { return nil }
        var d = value
        if d.last == 0 { d = d.dropLast() }
        return String(data: d, encoding: .utf8)
    }

    /// Any unsigned integer type, regardless of declared width.
    var numberValue: UInt64? {
        switch type {
        case .uint8, .uint16, .uint32, .uint64:
            guard !value.isEmpty, value.count <= 8 else { return nil }
            return value.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        default:
            return nil
        }
    }

    var doubleValue: Double? {
        // EC doubles are transmitted as ASCII strings
        if type == .double {
            var d = value
            if d.last == 0 { d = d.dropLast() }
            if let s = String(data: d, encoding: .ascii) { return Double(s) }
            return nil
        }
        if let n = numberValue { return Double(n) }
        return nil
    }

    var hashValue16: Data? {
        guard type == .hash16, value.count == 16 else { return nil }
        return value
    }

    var ipv4Value: (ip: UInt32, port: UInt16)? {
        guard type == .ipv4, value.count >= 6 else { return nil }
        let ip = value.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let port = value.dropFirst(4).prefix(2).reduce(UInt16(0)) { ($0 << 8) | UInt16($1) }
        return (ip, port)
    }

    // MARK: child lookup

    func child(_ name: ECTagName) -> ECTag? {
        children.first { $0.name == name.rawValue }
    }

    func childString(_ name: ECTagName) -> String? { child(name)?.stringValue }
    func childNumber(_ name: ECTagName) -> UInt64? { child(name)?.numberValue }

    // MARK: encoding

    private var hasChildren: Bool { !children.isEmpty }

    /// tagLen field: value length + serialized size of all children.
    var tagLen: UInt32 {
        var len = UInt32(value.count)
        for c in children {
            len += 7 // child header: name(2) + type(1) + len(4)
            if !c.children.isEmpty { len += 2 } // child's own children-count field
            len += c.tagLen
        }
        return len
    }

    func encode(into data: inout Data) {
        var nameBE = ((name << 1) | (hasChildren ? 1 : 0)).bigEndian
        data.append(Data(bytes: &nameBE, count: 2))
        data.append(type.rawValue)
        var lenBE = tagLen.bigEndian
        data.append(Data(bytes: &lenBE, count: 4))
        if hasChildren {
            var countBE = UInt16(children.count).bigEndian
            data.append(Data(bytes: &countBE, count: 2))
            for c in children { c.encode(into: &data) }
        }
        data.append(value)
    }

    // MARK: decoding

    static func decode(from data: Data, offset: inout Int) throws -> ECTag {
        func need(_ n: Int) throws {
            guard offset + n <= data.count else {
                throw ECError(message: "Pacchetto EC troncato durante la lettura di un tag")
            }
        }
        try need(7)
        let rawName = UInt16(data[data.startIndex + offset]) << 8 | UInt16(data[data.startIndex + offset + 1])
        offset += 2
        let rawType = data[data.startIndex + offset]
        offset += 1
        var len: UInt32 = 0
        for i in 0..<4 { len = (len << 8) | UInt32(data[data.startIndex + offset + i]) }
        offset += 4

        let hasChildren = (rawName & 1) == 1
        let name = rawName >> 1
        let type = ECTagType(rawValue: rawType) ?? .unknown

        var children: [ECTag] = []
        var childrenBytes = 0
        if hasChildren {
            try need(2)
            let count = UInt16(data[data.startIndex + offset]) << 8 | UInt16(data[data.startIndex + offset + 1])
            offset += 2
            let mark = offset
            for _ in 0..<count {
                children.append(try decode(from: data, offset: &offset))
            }
            childrenBytes = offset - mark
        }

        let valueLen = Int(len) - childrenBytes
        guard valueLen >= 0 else {
            throw ECError(message: "Tag EC con lunghezza incoerente")
        }
        try need(valueLen)
        let start = data.startIndex + offset
        let value = Data(data[start..<(start + valueLen)])
        offset += valueLen

        return ECTag(name: name, type: type, value: value, children: children)
    }
}

struct ECPacket {
    var opcode: ECOp
    var tags: [ECTag] = []

    init(_ opcode: ECOp, tags: [ECTag] = []) {
        self.opcode = opcode
        self.tags = tags
    }

    func tag(_ name: ECTagName) -> ECTag? {
        tags.first { $0.name == name.rawValue }
    }

    func allTags(_ name: ECTagName) -> [ECTag] {
        tags.filter { $0.name == name.rawValue }
    }

    /// Serialize including the 8-byte transmission header.
    func serialize() -> Data {
        var payload = Data()
        payload.append(opcode.rawValue)
        var countBE = UInt16(tags.count).bigEndian
        payload.append(Data(bytes: &countBE, count: 2))
        for t in tags { t.encode(into: &payload) }

        var out = Data()
        var flagsBE = EC.flagBase.bigEndian
        out.append(Data(bytes: &flagsBE, count: 4))
        var lenBE = UInt32(payload.count).bigEndian
        out.append(Data(bytes: &lenBE, count: 4))
        out.append(payload)
        return out
    }

    static func parse(payload: Data, flags: UInt32) throws -> ECPacket {
        var body = payload
        if flags & EC.flagZlib != 0 {
            body = try zlibInflate(payload)
        }
        if flags & EC.flagUTF8Numbers != 0 {
            throw ECError(message: "Il server ha usato una codifica non supportata (UTF-8 numbers)")
        }
        guard body.count >= 3 else {
            throw ECError(message: "Pacchetto EC troppo corto")
        }
        var offset = 0
        let opRaw = body[body.startIndex]
        offset += 1
        let tagCount = UInt16(body[body.startIndex + 1]) << 8 | UInt16(body[body.startIndex + 2])
        offset += 2
        guard let op = ECOp(rawValue: opRaw) else {
            throw ECError(message: String(format: "Opcode EC sconosciuto: 0x%02X", opRaw))
        }
        var tags: [ECTag] = []
        for _ in 0..<tagCount {
            tags.append(try ECTag.decode(from: body, offset: &offset))
        }
        return ECPacket(op, tags: tags)
    }
}

// zlib-wrapped deflate (RFC 1950), as produced by zlib compress() in amuled.
private func zlibInflate(_ data: Data) throws -> Data {
    guard data.count > 2 else { throw ECError(message: "Dati zlib non validi") }
    // Skip the 2-byte zlib header; Compression's ZLIB is raw deflate.
    let raw = data.dropFirst(2)
    var out = Data()
    let bufSize = 1 << 20
    let dstBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
    defer { dstBuf.deallocate() }

    try raw.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
        guard let srcPtr = src.bindMemory(to: UInt8.self).baseAddress else {
            throw ECError(message: "Dati zlib non validi")
        }
        var stream = compression_stream(dst_ptr: dstBuf, dst_size: bufSize, src_ptr: srcPtr, src_size: raw.count, state: nil)
        var status = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        guard status == COMPRESSION_STATUS_OK else { throw ECError(message: "Inizializzazione zlib fallita") }
        defer { compression_stream_destroy(&stream) }

        stream.src_ptr = srcPtr
        stream.src_size = raw.count
        repeat {
            stream.dst_ptr = dstBuf
            stream.dst_size = bufSize
            status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
            if status == COMPRESSION_STATUS_ERROR {
                throw ECError(message: "Decompressione zlib fallita")
            }
            out.append(dstBuf, count: bufSize - stream.dst_size)
        } while status == COMPRESSION_STATUS_OK
    }
    return out
}

import Compression
