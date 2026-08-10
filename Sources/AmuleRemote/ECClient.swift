// TCP client for aMule External Connections (amuled, default port 4712).
import Foundation
import Network
import CryptoKit

actor ECClient {
    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private(set) var serverVersion: String = ""

    // EC has no request IDs: replies are matched to requests purely by order.
    // Swift actors are re-entrant at await points, so overlapping request()
    // calls would interleave their socket reads and corrupt the stream —
    // this gate keeps exactly one request/response cycle in flight (FIFO).
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var isConnected: Bool { connection != nil }

    // MARK: - Connection & auth

    func connect(host: String, port: UInt16, password: String) async throws {
        disconnectNow()

        let conn = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        connection = conn

        let queue = DispatchQueue(label: "ec-client")
        // Hard connection timeout: NWConnection sits in .waiting (retrying)
        // forever when the host is unreachable and never fails on its own —
        // without this the UI spinner would spin indefinitely.
        let timeout = DispatchWorkItem { conn.cancel() }
        queue.asyncAfter(deadline: .now() + 12, execute: timeout)

        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                var resumed = false
                conn.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        if !resumed { resumed = true; cont.resume() }
                    case .failed(let err):
                        if !resumed { resumed = true; cont.resume(throwing: err) }
                        conn.cancel()
                    case .waiting(let err):
                        // Host unreachable / connection refused: fail fast
                        // instead of letting Network.framework keep retrying.
                        if !resumed { resumed = true; cont.resume(throwing: err) }
                        conn.cancel()
                    case .cancelled:
                        if !resumed { resumed = true; cont.resume(throwing: ECError(message: "Timeout di connessione: server non raggiungibile")) }
                    default:
                        break
                    }
                }
                conn.start(queue: queue)
            }
            timeout.cancel()
        } catch {
            timeout.cancel()
            conn.stateUpdateHandler = nil
            disconnectNow()
            throw error
        }
        conn.stateUpdateHandler = nil

        do {
            try await authenticate(password: password)
        } catch {
            disconnectNow()
            throw error
        }
    }

    func disconnectNow() {
        connection?.cancel()
        connection = nil
        receiveBuffer.removeAll()
        serverVersion = ""
        // Wake queued requests: they will find connection == nil and fail cleanly.
        let queued = waiters
        waiters.removeAll()
        for w in queued { w.resume() }
    }

    private func authenticate(password: String) async throws {
        // 1) AUTH_REQ with client identity, no optional capabilities:
        //    the server will then talk plain (no zlib, no utf8 numbers).
        let authReq = ECPacket(.authReq, tags: [
            .string(.clientName, "aMule Remote (macOS)"),
            .string(.clientVersion, "1.0"),
            .uint16(.protocolVersion, EC.protocolVersion),
        ])
        let saltReply = try await request(authReq)

        switch saltReply.opcode {
        case .authSalt:
            break
        case .authFail:
            throw ECError(message: saltReply.tag(.string)?.stringValue ?? "Autenticazione rifiutata")
        default:
            throw ECError(message: "Risposta inattesa al login (\(saltReply.opcode))")
        }
        guard let salt = saltReply.tag(.passwdSalt)?.numberValue else {
            throw ECError(message: "Il server non ha inviato il salt di autenticazione")
        }

        // 2) hash = MD5( md5hex(password).lowercased + md5hex(format("%llX", salt)) )
        let passHex = md5Hex(Data(password.utf8)).lowercased()
        let saltStr = String(format: "%llX", salt)
        let saltHex = md5Hex(Data(saltStr.utf8))
        let final = Data(Insecure.MD5.hash(data: Data((passHex + saltHex).utf8)))

        let authPass = ECPacket(.authPasswd, tags: [.hash16(.passwdHash, final)])
        let okReply = try await request(authPass)

        switch okReply.opcode {
        case .authOK:
            serverVersion = okReply.tag(.serverVersion)?.stringValue ?? ""
        case .authFail:
            throw ECError(message: okReply.tag(.string)?.stringValue ?? "Password errata")
        default:
            throw ECError(message: "Risposta inattesa all'autenticazione (\(okReply.opcode))")
        }
    }

    private func md5Hex(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Request / response

    /// EC is strictly request/response on this connection (we never advertise
    /// notification support). Replies carry no request ID, so only one
    /// request/response cycle may be on the wire at a time.
    func request(_ packet: ECPacket) async throws -> ECPacket {
        while busy {
            await withCheckedContinuation { waiters.append($0) }
        }
        busy = true
        defer {
            busy = false
            if !waiters.isEmpty { waiters.removeFirst().resume() }
        }
        return try await performRequest(packet)
    }

    private func performRequest(_ packet: ECPacket) async throws -> ECPacket {
        guard let conn = connection else {
            throw ECError(message: "Non connesso")
        }
        try await send(conn, data: packet.serialize())

        let header = try await receiveExactly(conn, count: 8)
        let flags = header.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let length = header.dropFirst(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0, length < 256 * 1024 * 1024 else {
            throw ECError(message: "Pacchetto EC di dimensione non valida (\(length) byte)")
        }
        let payload = try await receiveExactly(conn, count: Int(length))
        return try ECPacket.parse(payload: payload, flags: flags)
    }

    private func send(_ conn: NWConnection, data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { err in
                if let err { cont.resume(throwing: err) } else { cont.resume() }
            })
        }
    }

    private func receiveExactly(_ conn: NWConnection, count: Int) async throws -> Data {
        while receiveBuffer.count < count {
            let chunk = try await receiveSome(conn)
            if chunk.isEmpty {
                throw ECError(message: "Connessione chiusa dal server")
            }
            receiveBuffer.append(chunk)
        }
        let out = Data(receiveBuffer.prefix(count))
        receiveBuffer.removeFirst(count)
        return out
    }

    private func receiveSome(_ conn: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { data, _, isComplete, error in
                if let error {
                    cont.resume(throwing: error)
                } else if let data, !data.isEmpty {
                    cont.resume(returning: data)
                } else if isComplete {
                    cont.resume(returning: Data())
                } else {
                    cont.resume(returning: Data())
                }
            }
        }
    }
}
