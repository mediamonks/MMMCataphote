//
// MMMCataphote. Part of MMMTemple suite.
// Copyright (C) 2016-2021 MediaMonks. All rights reserved.
//

/// Limited reflection for `Decodable` types.
///
/// The main objective for this is to be able to automatically generate lists of object fields and child entities to be
/// included into responses when working with "JSONAPI" style responses.
///
/// Limitations:
/// 1) there is very limited support for enum fields (only the ones that can decode from a string "dummy");
/// 2) any dictionary is assumed to have `String` keys, could be resoved by parsing type names;
/// 3) it might not work well with `Decodable`s that use custom initializers.
public final class MMMCataphote {

	public init() {
	}

	public struct Reflection: Equatable, CustomStringConvertible, CustomDebugStringConvertible {

		/// The main description of the type being reflected.
		public let typeInfo: TypeInfo

		/// All non-primitive ("object") types used in `typeInfo`, indexed by their names.
		///
		/// Note that this could be built from typeInfo alone on demand, but we had one already.
		public private(set) var objects: [String: Object] = [:]

		internal init(typeInfo: TypeInfo, objects: [String: Object]) {
			self.typeInfo = typeInfo
			self.objects = objects
		}

		public var description: String {

			var result: String = ""

			print("\(typeInfo)", terminator: "", to: &result)

			if !objects.isEmpty {
				print(" where:\n", to: &result)
				for name in objects.keys.sorted() {
					let o = objects[name]!
					print("\(o)", to: &result)
				}
			}

			return result
		}

		public var debugDescription: String { description }
	}

	/// Describes a non-primitive object, i.e. the one different from "primitives" such as Int, String,
	/// arrays or dictionaries.
	public final class Object: Equatable, CustomStringConvertible {

		/// The name of the corresponding type.
		public let name: String

		/// All the fields of the object that would participate in decoding.
		public private(set) var fields: [String: Field] = [:]

		/// Internal for unit tests.
		internal init(name: String, fields: [Field] = []) {
			self.name = name
			self.setFields(fields)
		}

		// Have to use sort of a 2-stage init here because an object with the same name might be created when computing fields.
		fileprivate func setFields(_ fields: [Field]) {
			self.fields = .init(uniqueKeysWithValues: fields.map { ($0.name, $0) } )
		}

		public var description: String {
			var result: String = ""
			print("\(name):", to: &result)
			for name in fields.keys.sorted() {
				print(" - \(fields[name]!)", to: &result)
			}
			return result
		}

		// TODO: make compiler generate this
		public static func == (lhs: MMMCataphote.Object, rhs: MMMCataphote.Object) -> Bool {
			return lhs.name == rhs.name && lhs.fields == rhs.fields
		}
	}

	public struct Field: Equatable, CustomStringConvertible {

		public let name: String
		public let typeInfo: TypeInfo

		public var description: String {
			return "\(name): \(typeInfo)"
		}
	}

	public indirect enum TypeInfo: Equatable, CustomStringConvertible {

		/// Used when we cannot figure out the contents of a decodable, like when it's empty or has unsupported features.
		case unknown

		/// Simple type like Int, Double or String.
		case primitive(String)

		/// Another Decodable struct or class.
		case object(Object)

		case array(TypeInfo)
		case dictionary(TypeInfo, TypeInfo)

		/// An optional wrapping the given type.
		case optional(TypeInfo)

		/// Objects used in the description of this type (without recursing into fields of these objects).
		/// This to be able to see objects through optionals or arrays.
		public func objects() -> [Object] {
			switch self {
			case .unknown, .primitive:
				return []
			case .object(let object):
				return [ object ]
			case .optional(let typeInfo), .array(let typeInfo):
				return typeInfo.objects()
			case .dictionary(let keyType, let valueType):
				return keyType.objects() + valueType.objects()
			}
		}

		public var description: String {
			switch self {
			case .optional(let type):
				return "\(type)?"
			case .unknown:
				return "Unknown"
			case .primitive(let name):
				return name
			case .object(let object):
				return "Object(\(object.name))"
			case .array(let type):
				return "[\(type)]"
			case let .dictionary(key, value):
				return "[\(key): \(value)]"
			}
		}
	}

	/// This is to avoid duplicate descriptions for objects.
	fileprivate final class ObjectStore {

		public init() {
		}

		public private(set) var objects: [String: Object] = [:]

		public func object(name: String, fields: @autoclosure () -> [Field]) -> Object {
			if let o = objects[name] {
				return o
			} else {
				let o = Object(name: name)
				objects[name] = o
				o.setFields(fields())
				return o
			}
		}
	}

	/// Like ObjectStore, but to track our decoders.
	fileprivate final class DecoderStore {

		public init() {
		}

		private var decoders: [String: _Decoder] = [:]

		public func hasDecoder(name: String) -> Bool {
			return decoders[name] != nil
		}

		fileprivate func decoder(name: String) -> _Decoder {
			if let o = decoders[name] {
				return o
			} else {
				let o = _Decoder(name: name)
				o.store = self
				decoders[name] = o
				return o
			}
		}
	}

	/// Main method of the helper: you give a type and get its limited description if everything is supported.
	public static func reflect<T: Decodable>(_ type: T.Type) -> Reflection {

		do {
			let decoderStore = DecoderStore()

			let d = decoderStore.decoder(name: String(describing: type))

			let _ = try T.init(from: d)

			let objectStore = ObjectStore()

			return Reflection(
				typeInfo: d.typeInfo(objectStore),
				objects: objectStore.objects
			)
		} catch {
			return Reflection(typeInfo: .unknown, objects: [:])
		}
	}

	// MARK: -

	fileprivate final class _Decoder: Decoder, TypeInfoProviding {

		fileprivate unowned var store: DecoderStore!

		public let name: String

		/// When `true`, then all the keyed containers don't need to pretend they have all the keys.
		private let closed: Bool

		public init(name: String, closed: Bool = false) {
			self.name = name
			self.closed = closed
		}

		private var container: TypeInfoProviding? {
			willSet {
				assert(container == nil, "A Decoder is expected to provide only one container per instance")
			}
		}

		public func typeInfo(_ objectStore: ObjectStore) -> TypeInfo {
			guard let container = container else {
				// Potentially can happen for types having no decodable members.
				return .unknown
			}
			return container.typeInfo(objectStore)
		}

		// We don't need these two, though might support codingPath for eventual error reporting.
		public let codingPath: [CodingKey] = []
		public let userInfo: [CodingUserInfoKey: Any] = [:]

		public func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
			let container = _KeyedContainer<Key>(decoderStore: store, name: name, closed: closed)
			self.container = container
			return KeyedDecodingContainer(container)
		}

		public func singleValueContainer() throws -> SingleValueDecodingContainer {
			let container = _UnkeyedOrSingleContainer(decoderStore: store, singleValue: true, closed: closed)
			self.container = container
			return container
		}

		public func unkeyedContainer() -> UnkeyedDecodingContainer {
			let container = _UnkeyedOrSingleContainer(decoderStore: store, singleValue: false, closed: closed)
			self.container = container
			return container
		}
	}

	private final class _CodingKey: CodingKey {

		var stringValue: String
		var intValue: Int?

		required init?(stringValue: String) {
			self.stringValue = stringValue
		}

		required init?(intValue: Int) {
			self.intValue = intValue
			self.stringValue = "\(intValue)"
		}
	}

	private enum DeferredTypeInfo {

		case resolved(TypeInfo)
		case unresolved(TypeInfoProviding)

		func type(_ objectStore: ObjectStore) -> TypeInfo {
			switch self {
			case .resolved(let type):
				return type
			case .unresolved(let typeInfoProviding):
				return typeInfoProviding.typeInfo(objectStore)
			}
		}
	}

	private static func decode<T: Decodable>(_ type: T.Type, store: DecoderStore) throws -> (T, DeferredTypeInfo)  {

		// Exceptions. Cannot seem to make specialized versions of decode<> instead.
		do {
			// URLs have custom initializers, so we don't really support them, but it can be handy.
			if T.self == URL.self {
				return (URL(string: "dummy")! as! T, .resolved(.primitive("String")))
			}
		}

		let name = String(describing: type)

		let d: _Decoder
		if store.hasDecoder(name: name) {
			d = _Decoder(name: name, closed: true)
			d.store = store
		} else {
			d = store.decoder(name: name)
		}

		return (try T.init(from: d), .unresolved(store.decoder(name: name)))
	}

	private final class _KeyedContainer<T: CodingKey>: KeyedDecodingContainerProtocol, TypeInfoProviding {

		typealias Key = T

		private let decoderStore: DecoderStore

		private let name: String?

		/// When `true`, then don't need to pretend that we have all the keys.
		private let closed: Bool

		public init(decoderStore: DecoderStore, name: String?, closed: Bool) {
			self.decoderStore = decoderStore
			self.name = name
			self.closed = closed
		}

		// MARK: -

		public func typeInfo(_ objectStore: ObjectStore) -> TypeInfo {
			if askedForKeys {
				if let key = keyTypes.keys.first {
					return .dictionary(.primitive("String"), keyTypes[key]!.type(objectStore))
				} else {
					return .unknown
				}
			} else if let name = name {
				return .object(objectStore.object(name: name, fields: self.fields(objectStore)))
			} else {
				// TODO:
				return .unknown
			}
		}

		public func fields(_ objectStore: ObjectStore) -> [Field] {
			var result: [Field] = []
			for k in keyTypes.keys.sorted() {
				let type = keyTypes[k]!.type(objectStore)
				result.append(.init(
					name: k,
					typeInfo: optionalKeys.contains(k) ? .optional(type) : type
				))
			}
			return result
		}

		// MARK: -

		// Not used in our case, though might be good for reporting.
		public var codingPath: [CodingKey] = []

		private var askedForKeys: Bool = false

		public var allKeys: [Key] {
			askedForKeys = true
			return [ Key.init(stringValue: "fakeKey")! ]
		}

		public func contains(_ key: Key) -> Bool {
			if !closed {
				// Pretend we have all the keys, so we can peek at their types when asked for.
				return true
			} else {
				return false
			}
		}

		private lazy var optionalKeys: Set<String> = .init()

		public func decodeNil(forKey key: Key) throws -> Bool {
			optionalKeys.insert(key.stringValue)
			if !closed {
				// We need it to continue decoding the value for this key to find out its type.
				return false
			} else {
				// Alright, it's a closed container, nothing here.
				return true
			}
		}

		private lazy var keyTypes: [String: DeferredTypeInfo] = [:]

		private func processPrimitive<T>(_ type: T.Type, _ key: Key) {
			//~ print("\(type), \(key)")
			keyTypes[key.stringValue] = .resolved(.primitive(String(describing: type)))
		}

		// Too many methods below, compressing some spaces.
		public func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { processPrimitive(type, key); return false }
		public func decode(_ type: String.Type, forKey key: Key) throws -> String { processPrimitive(type, key); return "dummy" }
		public func decode(_ type: Double.Type, forKey key: Key) throws -> Double { processPrimitive(type, key); return 0 }
		public func decode(_ type: Float.Type, forKey key: Key) throws -> Float { processPrimitive(type, key); return 0 }
		public func decode(_ type: Int.Type, forKey key: Key) throws -> Int { processPrimitive(type, key); return 0 }
		public func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { processPrimitive(type, key); return 0 }
		public func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { processPrimitive(type, key); return 0 }
		public func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { processPrimitive(type, key); return 0 }
		public func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { processPrimitive(type, key); return 0 }
		public func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { processPrimitive(type, key); return 0 }
		public func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { processPrimitive(type, key); return 0 }
		public func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { processPrimitive(type, key); return 0 }
		public func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { processPrimitive(type, key); return 0 }
		public func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { processPrimitive(type, key); return 0 }

		public func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
			let (r, info) = try MMMCataphote.decode(type, store: decoderStore)
			keyTypes[key.stringValue] = info
			return r
		}

		public func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
			assertionFailure("Objects requiring \(#function) are not supported")
			return KeyedDecodingContainer(_KeyedContainer<NestedKey>(decoderStore: decoderStore, name: nil, closed: closed))
		}

		public func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
			assertionFailure("Objects requiring \(#function) are not supported")
			return _UnkeyedOrSingleContainer(decoderStore: decoderStore, singleValue: false, closed: closed)
		}

		public func superDecoder() throws -> Decoder {
			assertionFailure("Objects requiring \(#function) are not supported")
			return _Decoder(name: "super")
		}

		public func superDecoder(forKey key: Key) throws -> Decoder {
			assertionFailure("Objects requiring \(#function) are not supported")
			return _Decoder(name: "super")
		}
	}

	private final class _UnkeyedOrSingleContainer: UnkeyedDecodingContainer, SingleValueDecodingContainer, TypeInfoProviding {

		private let decoderStore: DecoderStore
		private let singleValue: Bool
		private let closed: Bool

		public init(decoderStore: DecoderStore, singleValue: Bool, closed: Bool) {
			self.decoderStore = decoderStore
			self.singleValue = singleValue
			self.closed = closed
			self.isAtEnd = closed
		}

		// MARK: -

		public func typeInfo(_ objectStore: ObjectStore) -> TypeInfo {
			switch deferredTypeInfo {
			case nil:
				// Can happen if the container was not used at all, so no asserts.
				return .unknown
			case .resolved(let type):
				return singleValue ? type : .array(type)
			case .unresolved(let typeInfo):
				let result = singleValue ? typeInfo.typeInfo(objectStore) : .array(typeInfo.typeInfo(objectStore))
				return isOptional ? .optional(result) : result
			}
		}

		private var isOptional: Bool = false

		private var deferredTypeInfo: DeferredTypeInfo? {
			willSet {
				assert((!isAtEnd || singleValue) && deferredTypeInfo == nil, "We expect to decode only one element from this container")
			}
			didSet {
				isAtEnd = true
			}
		}

		private func processPrimitive<T>(_ type: T.Type) {
			self.deferredTypeInfo = .resolved(
				isOptional ?
					.optional(.primitive(String(describing: type)))
					: .primitive(String(describing: type))
			)
		}

		private func processOptionalPrimitive<T>(_ type: T.Type) {
			assertionFailure("\(#function) does not seem to be used")
			isOptional = true
			processPrimitive(type)
		}

		// MARK: -

		public var codingPath: [CodingKey] = []

		// Keeping undefined. We're going to pretend we have only one element in this container.
		public var count: Int?

		// Starting with "not at end".
		public var isAtEnd: Bool = false

		public var currentIndex: Int = 0

		// SingleValueDecodingContainer has a no throwing version of this.
		public func decodeNil() -> Bool {
			isOptional = true
			if !closed {
				return false // Got that this is an optional, need to continue decoding to get the type of an element.
			} else {
				return true
			}
		}

		public func decode(_ type: Bool.Type) throws -> Bool { processPrimitive(type); return false }
		public func decode(_ type: String.Type) throws -> String { processPrimitive(type); return "dummy" }
		public func decode(_ type: Double.Type) throws -> Double { processPrimitive(type); return 0 }
		public func decode(_ type: Float.Type) throws -> Float { processPrimitive(type); return 0 }
		public func decode(_ type: Int.Type) throws -> Int { processPrimitive(type); return 0 }
		public func decode(_ type: Int8.Type) throws -> Int8 { processPrimitive(type); return 0 }
		public func decode(_ type: Int16.Type) throws -> Int16 { processPrimitive(type); return 0 }
		public func decode(_ type: Int32.Type) throws -> Int32 { processPrimitive(type); return 0 }
		public func decode(_ type: Int64.Type) throws -> Int64 { processPrimitive(type); return 0 }
		public func decode(_ type: UInt.Type) throws -> UInt { processPrimitive(type); return 0 }
		public func decode(_ type: UInt8.Type) throws -> UInt8 { processPrimitive(type); return 0 }
		public func decode(_ type: UInt16.Type) throws -> UInt16 { processPrimitive(type); return 0 }
		public func decode(_ type: UInt32.Type) throws -> UInt32 { processPrimitive(type); return 0 }
		public func decode(_ type: UInt64.Type) throws -> UInt64 { processPrimitive(type); return 0 }

		public func decode<T: Decodable>(_ type: T.Type) throws -> T {
			let (r, info) = try MMMCataphote.decode(type, store: decoderStore)
			self.deferredTypeInfo = info
			return r
		}

		func decodeIfPresent(_ type: Bool.Type) throws -> Bool? { processOptionalPrimitive(type); return nil }
		func decodeIfPresent(_ type: String.Type) throws -> String? { processOptionalPrimitive(type); return nil }
		func decodeIfPresent(_ type: Double.Type) throws -> Double? { processOptionalPrimitive(type); return nil }
		func decodeIfPresent(_ type: Float.Type) throws -> Float? { processOptionalPrimitive(type); return nil }
		func decodeIfPresent(_ type: Int.Type) throws -> Int? { processOptionalPrimitive(type); return nil }
		func decodeIfPresent(_ type: Int8.Type) throws -> Int8? { processOptionalPrimitive(type); return nil }
		func decodeIfPresent(_ type: Int16.Type) throws -> Int16? { processOptionalPrimitive(type); return nil }
		func decodeIfPresent(_ type: Int32.Type) throws -> Int32? { processOptionalPrimitive(type); return nil }
		func decodeIfPresent(_ type: Int64.Type) throws -> Int64? { processOptionalPrimitive(type); return nil }
		func decodeIfPresent(_ type: UInt.Type) throws -> UInt? { processOptionalPrimitive(type); return nil }
		func decodeIfPresent(_ type: UInt8.Type) throws -> UInt8? { processOptionalPrimitive(type); return nil }
		func decodeIfPresent(_ type: UInt16.Type) throws -> UInt16? { processOptionalPrimitive(type); return nil }
		func decodeIfPresent(_ type: UInt32.Type) throws -> UInt32? { processOptionalPrimitive(type); return nil }
		func decodeIfPresent(_ type: UInt64.Type) throws -> UInt64? { processOptionalPrimitive(type); return nil }

		func decodeIfPresent<T>(_ type: T.Type) throws -> T? where T : Decodable {
			// TODO:
			assertionFailure()
			return nil
		}

		func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
			// TODO:
			assertionFailure()
			return KeyedDecodingContainer(_KeyedContainer<NestedKey>(decoderStore: decoderStore, name: nil, closed: closed))
		}

		func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
			// TODO:
			assertionFailure()
			return _UnkeyedOrSingleContainer(decoderStore: decoderStore, singleValue: false, closed: closed)
		}

		func superDecoder() throws -> Decoder {
			assertionFailure("Objects requiring \(#function) are not supported")
			return _Decoder(name: "")
		}
	}
}

extension MMMCataphote {
	private typealias TypeInfoProviding = MMMCataphote_TypeInfoProviding
}

private protocol MMMCataphote_TypeInfoProviding: AnyObject {
	func typeInfo(_ objectStore: MMMCataphote.ObjectStore) -> MMMCataphote.TypeInfo
}
