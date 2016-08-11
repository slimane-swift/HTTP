extension Response {
    public init(status: Status = .ok, headers: Headers = [:], body: Data = []) {
        self.init(
            version: Version(major: 1, minor: 1),
            status: status,
            headers: headers,
            cookieHeaders: [],
            body: .buffer(body)
        )

        self.headers["Content-Length"] = body.count.description
    }

    public init(status: Status = .ok, headers: Headers = [:], body: ReceivingStream) {
        self.init(
            version: Version(major: 1, minor: 1),
            status: status,
            headers: headers,
            cookieHeaders: [],
            body: .receiver(body)
        )

        self.headers["Transfer-Encoding"] = "chunked"
    }

    public init(status: Status = .ok, headers: Headers = [:], body: @escaping (C7.SendingStream) throws -> Void) {
        self.init(
            version: Version(major: 1, minor: 1),
            status: status,
            headers: headers,
            cookieHeaders: [],
            body: .sender(body)
        )

        self.headers["Transfer-Encoding"] = "chunked"
    }
}

extension Response {
    public init(status: Status = .ok, headers: Headers = [:], body: DataConvertible) {
        self.init(
            status: status,
            headers: headers,
            body: body.data
        )
    }
}

extension Response {
    public var statusCode: Int {
        return status.statusCode
    }

    public var reasonPhrase: String {
        return status.reasonPhrase
    }
}

extension Response {
    public var cookies: Set<AttributedCookie> {
        get {
            var cookies = Set<AttributedCookie>()

            for header in cookieHeaders {
                if let cookie = AttributedCookie(header) {
                    cookies.insert(cookie)
                }
            }

            return cookies
        }

        set(cookies) {
            var headers = Set<String>()

            for cookie in cookies {
                let header = String(describing: cookie)
                headers.insert(header)
            }

            cookieHeaders = headers
        }
    }
}

extension Response {
    public typealias UpgradeConnection = (Request, Stream) throws -> Void

    public var upgradeConnection: UpgradeConnection? {
        return storage["response-connection-upgrade"] as? UpgradeConnection
    }

    public mutating func upgradeConnection(_ upgrade: UpgradeConnection)  {
        storage["response-connection-upgrade"] = upgrade
    }
}

extension Response : CustomStringConvertible {
    public var statusLineDescription: String {
        return "HTTP/" + String(version.major) + "." + String(version.minor) + " " + String(statusCode) + " " + reasonPhrase + "\n"
    }

    public var description: String {
        return statusLineDescription +
            headers.description
    }
}

extension Response : CustomDebugStringConvertible {
    public var debugDescription: String {
        return description + "\n" + storageDescription
    }
}


extension Body {
    /**
     Converts the body's contents into a `Data` buffer asynchronously.
     If the body is a receiver, sender, asyncReceiver or asyncSender type,
     it will be drained.
     */
    public func asyncBecomeBuffer(timingOut deadline: Double = .never, completion: @escaping ((Void) throws -> (Body, Data)) -> Void) {
        switch self {
        case .asyncReceiver(let stream):
            _ = AsyncDrain(for: stream, timingOut: deadline) { closure in
                completion {
                    let drain = try closure ()
                    return (.buffer(drain.data), drain.data)
                }
            }
            
        case .asyncSender(let sender):
            let drain = AsyncDrain()
            sender(drain) { closure in
                completion {
                    try closure()
                    return (.buffer(drain.data), drain.data)
                }
            }
            
        default:
            completion {
                throw BodyError.inconvertibleType
            }
        }
    }
    
    /**
     Converts the body's contents into a `AsyncReceivingStream`
     that can be received in chunks.
     */
    public func becomeAsyncReceiver(completion: @escaping ((Void) throws -> (Body, AsyncReceivingStream)) -> Void) {
        switch self {
        case .asyncReceiver(let stream):
            completion {
                (self, stream)
            }
        case .buffer(let data):
            let stream = AsyncDrain(for: data)
            completion {
                (.asyncReceiver(stream), stream)
            }
        case .asyncSender(let sender):
            let stream = AsyncDrain()
            sender(stream) { closure in
                completion {
                    try closure()
                    return (.asyncReceiver(stream), stream)
                }
            }
        default:
            completion {
                throw BodyError.inconvertibleType
            }
        }
    }
    
    /**
     Converts the body's contents into a closure
     that accepts a `AsyncSendingStream`.
     */
    public func becomeAsyncSender(timingOut deadline: Double = .never, completion: @escaping ((Void) throws -> (Body, ((AsyncSendingStream, @escaping ((Void) throws -> Void) -> Void) -> Void))) -> Void) {
        
        switch self {
        case .buffer(let data):
            let closure: ((AsyncSendingStream, @escaping ((Void) throws -> Void) -> Void) -> Void) = { sender, result in
                sender.send(data, timingOut: deadline) { closure in
                    result {
                        try closure()
                    }
                }
            }
            completion {
                return (.asyncSender(closure), closure)
            }
        case .asyncReceiver(let receiver):
            let closure: ((AsyncSendingStream, @escaping ((Void) throws -> Void) -> Void) -> Void) = { sender, result in
                _ = AsyncDrain(for: receiver, timingOut: deadline) { getData in
                    do {
                        let drain = try getData()
                        sender.send(drain.data, timingOut: deadline, completion: result)
                    } catch {
                        result {
                            throw error
                        }
                    }
                }
            }
            completion {
                return (.asyncSender(closure), closure)
            }
        case .asyncSender(let closure):
            completion {
                (self, closure)
            }
        default:
            completion {
                throw BodyError.inconvertibleType
            }
        }
    }
}
