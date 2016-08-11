extension Body {
    /**
     Converts the body's contents into a `Data` buffer.
     If the body is a reader or writer type,
     it will be drained.
     */
    public mutating func becomeBuffer(deadline: Double = .never) throws -> Data {
        switch self {
        case .buffer(let data):
            return data
        case .receiver(let reader):
            let data = Drain(for: reader, timingOut: deadline).data
            self = .buffer(data)
            return data
        case .sender(let writer):
            let drain = Drain()
            try writer(drain)
            let data = drain.data

            self = .buffer(data)
            return data
        default:
            throw BodyError.inconvertibleType
        }
    }

    /**
     Converts the body's contents into a `ReceivingStream`
     that can be received in chunks.
     */
    public mutating func becomeReceiver() throws -> ReceivingStream {
        switch self {
        case .receiver(let reader):
            return reader
        case .buffer(let buffer):
            let stream = Drain(for: buffer)
            self = .receiver(stream)
            return stream
        case .sender(let writer):
            let stream = Drain()
            try writer(stream)
            self = .receiver(stream)
            return stream
        default:
            throw BodyError.inconvertibleType
        }
    }

    /**
     Converts the body's contents into a closure
     that accepts a `C7.SendingStream`.
     */
    public mutating func becomeSender(deadline: Double = .never) throws -> ((C7.SendingStream) throws -> Void) {
        switch self {
        case .buffer(let data):
            let closure: ((C7.SendingStream) throws -> Void) = { writer in
                try writer.send(data, timingOut: deadline)
            }
            self = .sender(closure)
            return closure
        case .receiver(let reader):
            let closure: ((C7.SendingStream) throws -> Void) = { writer in
                let data = Drain(for: reader, timingOut: deadline).data
                try writer.send(data, timingOut: deadline)
            }
            self = .sender(closure)
            return closure
        case .sender(let writer):
            return writer
        default:
            throw BodyError.inconvertibleType
        }
    }
}

extension Body : Equatable {}

public func == (lhs: Body, rhs: Body) -> Bool {
    switch (lhs, rhs) {
        case let (.buffer(l), .buffer(r)) where l == r: return true
        default: return false
    }
}
